import Foundation
import TagLibAudioMetadata

enum MetadataArtworkChange: Sendable {
    case unchanged
    case replace(data: Data, mimeType: String)
    case remove
}

struct MetadataEditPayload: Sendable {
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var comment: String
    var year: String
    var trackNumber: Int
    var trackTotal: Int
    var discNumber: Int
    var discTotal: Int
    var trackNumberText: String
    var discNumberText: String
    var albumArtist: String
    var releaseDate: String
    var publisher: String
    var isrc: String
    var barcode: String
    var musicBrainzAlbumID: String
    var musicBrainzTrackID: String
    var musicBrainzReleaseGroupID: String
    var lyricist: String
    var remixer: String
    var producer: String
    var engineer: String
    var language: String
    var mediaType: String
    var releaseType: String
    var catalogNumber: String
    var releaseCountry: String
    var copyright: String
    var isExplicit: Bool
    var artwork: MetadataArtworkChange
}

struct AudioMetadataWriteResult: Sendable {
    let warnings: [String]
}

protocol AudioMetadataPipeline: Sendable {
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile
    nonisolated func rawMetadataDumpText(for url: URL) -> String?
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String]
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult
    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult
    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult
    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult
}

struct TagLibAudioMetadataPipeline: AudioMetadataPipeline {
    nonisolated init() {}

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        try await AudioFile(url: url, id: id)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        guard let rawText = TagLibMetadataManager.rawMetadataText(from: url) else {
            return nil
        }

        return MetadataPipelineSupport.rawMetadataDumpTextWithCompatibilityNotes(rawText)
    }

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        let dump = try TagLibMetadataManager.rawMetadataResult(from: url)
        var propertyMap: [String: String] = [:]

        for entry in dump.properties {
            let key = MetadataPipelineSupport.normalizedPropertyMapKey(entry.key)
            let values = entry.values.isEmpty ? [entry.value] : entry.values
            let valueSource = values
                .map(MetadataPipelineSupport.normalizedFieldComponent)
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
            let value = MetadataPipelineSupport.normalizedFieldComponent(valueSource)

            guard !key.isEmpty, !value.isEmpty else { continue }
            propertyMap[key] = MetadataPipelineSupport.mergedPropertyMapValue(
                existing: propertyMap[key],
                incoming: value
            )
        }

        return MetadataPipelineSupport.propertyMapWithSeparatedNumberTotals(propertyMap)
    }

    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        let metadata = MetadataPipelineSupport.makeTagLibMetadata(from: edit, url: url)
        MetadataPipelineSupport.logMetadataWrite(metadata, edit: edit, url: url)

        let writeResult = try TagLibMetadataManager.writeTagMetadata(
            metadata,
            to: url,
            verification: TagLibMetadataManager.MetadataWriteVerificationContext(
                expectedTrackNumber: edit.trackNumber,
                expectedTrackTotal: edit.trackTotal,
                expectedTrackNumberText: edit.trackNumberText,
                expectedDiscNumber: edit.discNumber,
                expectedDiscTotal: edit.discTotal,
                expectedDiscNumberText: edit.discNumberText,
                expectedExplicitContent: edit.isExplicit,
                artworkExpectation: {
                    switch edit.artwork {
                    case .unchanged:
                        return .unchanged
                    case .replace:
                        return .present
                    case .remove:
                        return .absent
                    }
                }(),
                customFieldKeys: Array((metadata.customFields ?? [:]).keys)
            )
        )

        return AudioMetadataWriteResult(warnings: writeResult.warnings)
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        let valueMap = MetadataPipelineSupport.rawPropertyMapValues(from: propertyMap)
        let writeResult = try TagLibMetadataManager.writeRawMetadataPropertyMapValuesWithVerification(valueMap, to: url)
        return AudioMetadataWriteResult(warnings: writeResult.warnings)
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        let writeResult = try TagLibMetadataManager.eraseAllMetadataWithVerification(from: url)
        return AudioMetadataWriteResult(warnings: writeResult.warnings)
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        let writeResult = try TagLibMetadataManager.writeTrackNumberText(
            trackNumberText,
            discNumberText: discNumberText,
            to: url,
            verifyAfterWrite: verifyAfterWrite
        )
        return AudioMetadataWriteResult(warnings: writeResult.warnings)
    }
}

private enum MetadataPipelineSupport {
    nonisolated static func rawMetadataDumpTextWithCompatibilityNotes(_ rawText: String) -> String {
        let notes = legacyTagCompatibilityNotes(for: rawText)
        guard !notes.isEmpty else { return rawText }

        let noteText = (["[AudioMator Compatibility Notes]"] + notes.map { "- \($0)" })
            .joined(separator: "\n")
        return [rawText, noteText].joined(separator: "\n\n")
    }

    nonisolated private static func legacyTagCompatibilityNotes(for rawText: String) -> [String] {
        let sections = metadataDumpSections(from: rawText)
        let properties = sections["TagLib Properties"] ?? [:]
        let id3v1 = sections["ID3v1 Tag"] ?? [:]

        var notes: [String] = []

        for field in id3v1ComparisonFields {
            guard
                let canonicalValue = firstNonEmptyValue(for: field.canonicalKeys, in: properties),
                let legacyValue = firstNonEmptyValue(for: field.legacyKeys, in: id3v1),
                legacyValue != canonicalValue
            else {
                continue
            }

            if canonicalValue.hasPrefix(legacyValue) {
                notes.append(
                    "\(field.displayName) also exists in the ID3v1 tag as a shorter value. AudioMator treats the TagLib property value as authoritative because ID3v1 fields are length-limited."
                )
            } else {
                notes.append(
                    "\(field.displayName) differs between TagLib properties and the ID3v1 tag. AudioMator treats the TagLib property value as authoritative."
                )
            }
        }

        if !id3v1.isEmpty && !notes.isEmpty {
            notes.append("Saving metadata through AudioMator writes the modern TagLib-backed fields; the legacy ID3v1 copy may still be constrained by the file format or TagLib writer.")
        }

        return notes
    }

    nonisolated private static var id3v1ComparisonFields: [LegacyTagComparisonField] {
        [
            LegacyTagComparisonField(
                displayName: "Title",
                canonicalKeys: ["TITLE"],
                legacyKeys: ["Title"]
            ),
            LegacyTagComparisonField(
                displayName: "Artist",
                canonicalKeys: ["ARTIST"],
                legacyKeys: ["Artist"]
            ),
            LegacyTagComparisonField(
                displayName: "Album",
                canonicalKeys: ["ALBUM"],
                legacyKeys: ["Album"]
            ),
            LegacyTagComparisonField(
                displayName: "Year",
                canonicalKeys: ["DATE", "YEAR", "RELEASEDATE"],
                legacyKeys: ["Year"]
            ),
            LegacyTagComparisonField(
                displayName: "Track",
                canonicalKeys: ["TRACKNUMBER", "TRACK"],
                legacyKeys: ["Track"]
            )
        ]
    }

    nonisolated private static func firstNonEmptyValue(
        for keys: [String],
        in valuesByKey: [String: String]
    ) -> String? {
        for key in keys {
            if let value = valuesByKey[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        return nil
    }

    nonisolated private static func metadataDumpSections(from rawText: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var currentSection: String?

        for line in rawText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                if let currentSection {
                    sections[currentSection, default: [:]] = [:]
                }
                continue
            }

            guard
                let currentSection,
                trimmed != "(none)",
                let separatorRange = trimmed.range(of: " = ")
            else {
                continue
            }

            let key = String(trimmed[..<separatorRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[separatorRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty, !value.isEmpty else { continue }
            sections[currentSection, default: [:]][key] = value
        }

        return sections
    }

    nonisolated static func normalizedFieldComponent(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedPropertyMapKey(_ key: String) -> String {
        MetadataFieldRegistry.normalizePropertyMapKey(key)
    }

    nonisolated static func mergedPropertyMapValue(existing: String?, incoming: String) -> String {
        guard let existing = existing, !existing.isEmpty else { return incoming }

        var parts: [String] = []
        var seen = Set<String>()

        for value in (existing + "; " + incoming).components(separatedBy: "; ") {
            let trimmed = normalizedFieldComponent(value)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            parts.append(trimmed)
        }

        return parts.joined(separator: "; ")
    }

    nonisolated static func rawPropertyMapValues(from propertyMap: [String: String]) -> [String: [String]] {
        propertyMap.reduce(into: [String: [String]]()) { result, entry in
            let key = normalizedPropertyMapKey(entry.key)
            let value = normalizedFieldComponent(entry.value)
            guard !key.isEmpty else { return }

            if value.isEmpty {
                result[key] = []
                return
            }

            if MetadataFieldRegistry.shouldDisplayRawPropertyAsMultiValue(key) {
                result[key] = value
                    .components(separatedBy: "; ")
                    .map(normalizedFieldComponent)
                    .filter { !$0.isEmpty }
            } else {
                result[key] = [value]
            }
        }
    }

    nonisolated static func propertyMapWithSeparatedNumberTotals(_ propertyMap: [String: String]) -> [String: String] {
        var separated = propertyMap
        separateNumberTotal(
            numberKeys: ["TRACKNUMBER", "TRACK"],
            preferredNumberKey: "TRACKNUMBER",
            totalKeys: ["TRACKTOTAL", "TOTALTRACKS"],
            preferredTotalKey: "TRACKTOTAL",
            in: &separated
        )
        separateNumberTotal(
            numberKeys: ["DISCNUMBER", "DISC"],
            preferredNumberKey: "DISCNUMBER",
            totalKeys: ["DISCTOTAL", "TOTALDISCS"],
            preferredTotalKey: "DISCTOTAL",
            in: &separated
        )
        return separated
    }

    nonisolated private static func separateNumberTotal(
        numberKeys: [String],
        preferredNumberKey: String,
        totalKeys: [String],
        preferredTotalKey: String,
        in propertyMap: inout [String: String]
    ) {
        guard
            let existingNumberKey = numberKeys.first(where: { key in
                propertyMap[key]?.contains("/") == true
            }),
            let value = propertyMap[existingNumberKey]
        else {
            return
        }

        let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return }

        let number = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let total = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !number.isEmpty else { return }

        propertyMap.removeValue(forKey: existingNumberKey)
        propertyMap[preferredNumberKey] = number

        if !total.isEmpty && !totalKeys.contains(where: { propertyMap[$0]?.isEmpty == false }) {
            propertyMap[preferredTotalKey] = total
        }
    }

    nonisolated static func parseNumberTextForMetadataWrite(_ rawText: String) -> (number: Int, total: Int) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }

        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let number = parts.first.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let total = parts.count > 1
            ? Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            : 0

        return (max(0, number), max(0, total))
    }

    nonisolated static func makeTagLibMetadata(from edit: MetadataEditPayload, url: URL) -> TagLibAudioMetadata {
        let metadata = (try? TagLibMetadataExtractor.extractMetadata(from: url)) ?? TagLibAudioMetadata()

        metadata.title = normalizedFieldComponent(edit.title)
        metadata.artist = normalizedFieldComponent(edit.artist)
        metadata.album = normalizedFieldComponent(edit.album)
        metadata.composer = normalizedFieldComponent(edit.composer)
        metadata.genre = normalizedFieldComponent(edit.genre)
        metadata.comment = normalizedFieldComponent(edit.comment)
        metadata.albumArtist = normalizedFieldComponent(edit.albumArtist)
        metadata.year = normalizedFieldComponent(edit.year)
        metadata.releaseDate = normalizedFieldComponent(edit.releaseDate)
        metadata.label = normalizedFieldComponent(edit.publisher)
        metadata.isrc = normalizedFieldComponent(edit.isrc)
        metadata.barcode = normalizedFieldComponent(edit.barcode)
        metadata.musicBrainzAlbumId = normalizedFieldComponent(edit.musicBrainzAlbumID)
        metadata.musicBrainzTrackId = normalizedFieldComponent(edit.musicBrainzTrackID)
        metadata.musicBrainzReleaseGroupId = normalizedFieldComponent(edit.musicBrainzReleaseGroupID)
        metadata.lyricist = normalizedFieldComponent(edit.lyricist)
        metadata.remixer = normalizedFieldComponent(edit.remixer)
        metadata.producer = normalizedFieldComponent(edit.producer)
        metadata.engineer = normalizedFieldComponent(edit.engineer)
        metadata.language = normalizedFieldComponent(edit.language)
        metadata.mediaType = normalizedFieldComponent(edit.mediaType)
        metadata.releaseType = normalizedFieldComponent(edit.releaseType)
        metadata.catalogNumber = normalizedFieldComponent(edit.catalogNumber)
        metadata.releaseCountry = normalizedFieldComponent(edit.releaseCountry)
        metadata.copyright = normalizedFieldComponent(edit.copyright)
        metadata.explicitContent = edit.isExplicit

        switch edit.artwork {
        case .unchanged:
            metadata.artworkData = nil
            metadata.artworkMimeType = nil
            metadata.removeArtwork = false
        case .replace(let data, let mimeType):
            metadata.artworkData = data
            metadata.artworkMimeType = mimeType
            metadata.removeArtwork = false
        case .remove:
            metadata.removeArtwork = true
        }

        let trackText = normalizedFieldComponent(edit.trackNumberText)
        let discText = normalizedFieldComponent(edit.discNumberText)
        let parsedTrack = parseNumberTextForMetadataWrite(trackText)
        let parsedDisc = parseNumberTextForMetadataWrite(discText)

        metadata.trackNumberText = trackText
        metadata.discNumberText = discText
        metadata.trackNumber = max(edit.trackNumber, parsedTrack.number)
        metadata.totalTracks = max(edit.trackTotal, parsedTrack.total)
        metadata.discNumber = max(edit.discNumber, parsedDisc.number)
        metadata.totalDiscs = max(edit.discTotal, parsedDisc.total)

        return metadata
    }

    nonisolated static func logMetadataWrite(
        _ metadata: TagLibAudioMetadata,
        edit: MetadataEditPayload,
        url: URL
    ) {
        print("""
        [AudioMator] Will write metadata for \(url.lastPathComponent)
          title       = \(metadata.title ?? "<nil>")
          artist      = \(metadata.artist ?? "<nil>")
          album       = \(metadata.album ?? "<nil>")
          composer    = \(metadata.composer ?? "<nil>")
          genre       = \(metadata.genre ?? "<nil>")
          comment     = \(metadata.comment ?? "<nil>")
          albumArtist = \(metadata.albumArtist ?? "<nil>")
          releaseDate = \(metadata.releaseDate ?? "<nil>")
          publisher   = \(metadata.label ?? "<nil>")
          isrc        = \(metadata.isrc ?? "<nil>")
          barcode     = \(metadata.barcode ?? "<nil>")
          mbAlbumID   = \(metadata.musicBrainzAlbumId ?? "<nil>")
          mbTrackID   = \(metadata.musicBrainzTrackId ?? "<nil>")
          mbRGID      = \(metadata.musicBrainzReleaseGroupId ?? "<nil>")
          lyricist    = \(metadata.lyricist ?? "<nil>")
          remixer     = \(metadata.remixer ?? "<nil>")
          producer    = \(metadata.producer ?? "<nil>")
          engineer    = \(metadata.engineer ?? "<nil>")
          language    = \(metadata.language ?? "<nil>")
          mediaType   = \(metadata.mediaType ?? "<nil>")
          releaseType = \(metadata.releaseType ?? "<nil>")
          catalogNo   = \(metadata.catalogNumber ?? "<nil>")
          relCountry  = \(metadata.releaseCountry ?? "<nil>")
          copyright   = \(metadata.copyright ?? "<nil>")
          explicit    = \(metadata.explicitContent ? "YES" : "NO")
          year        = \(metadata.year ?? "<nil>")
          trackText   = \(edit.trackNumberText.isEmpty ? "<empty>" : edit.trackNumberText)
          discText    = \(edit.discNumberText.isEmpty ? "<empty>" : edit.discNumberText)
        """)
    }
}

private struct LegacyTagComparisonField {
    let displayName: String
    let canonicalKeys: [String]
    let legacyKeys: [String]
}
