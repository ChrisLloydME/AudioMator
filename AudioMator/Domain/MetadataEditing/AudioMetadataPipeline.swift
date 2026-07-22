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
    var itunesAlbumID: String
    var itunesArtistID: String
    var itunesCatalogID: String
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
    var contentAdvisory: ContentAdvisory?
    nonisolated var isExplicit: Bool { contentAdvisory?.isExplicit ?? false }
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

    nonisolated static func metadataForWrite(
        from edit: MetadataEditPayload,
        sourceURL: URL
    ) throws -> TagLibAudioMetadata {
        try MetadataPipelineSupport.makeTagLibMetadata(from: edit, url: sourceURL)
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        try await AudioFile(url: url, id: id)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        let bridgeText = TagLibMetadataManager.rawMetadataText(from: url)

        if let dump = try? TagLibMetadataManager.rawMetadataResult(from: url) {
            let rawText = MetadataPipelineSupport.rawMetadataDumpText(
                from: dump,
                url: url,
                preservingSectionsFrom: bridgeText
            )
            return MetadataPipelineSupport.rawMetadataDumpTextWithCompatibilityNotes(rawText)
        }

        return bridgeText.map(MetadataPipelineSupport.rawMetadataDumpTextWithCompatibilityNotes)
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
        let metadata = try Self.metadataForWrite(from: edit, sourceURL: url)

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

        var warnings = writeResult.warnings
        warnings.append(contentsOf: MetadataPipelineSupport.writeContentAdvisory(
            edit.contentAdvisory,
            to: url
        ))
        let clearedKeys = MetadataPipelineSupport.clearedPropertyMapKeys(from: edit)
        if !clearedKeys.isEmpty {
            warnings.append(contentsOf: MetadataPipelineSupport.cleanupRemovedPropertyMapKeys(
                clearedKeys,
                from: url
            ))
        }

        return AudioMetadataWriteResult(warnings: warnings)
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        let originalPropertyMap = try rawMetadataPropertyMap(for: url)
        let removedKeys = MetadataPipelineSupport.removedPropertyMapKeys(
            original: originalPropertyMap,
            replacement: propertyMap
        )
        let valueMap = MetadataPipelineSupport.rawPropertyMapValues(from: propertyMap)
        let writeResult = try TagLibMetadataManager.writeRawMetadataPropertyMapValuesWithVerification(valueMap, to: url)
        var warnings = writeResult.warnings

        if !removedKeys.isEmpty {
            if url.pathExtension.localizedCaseInsensitiveCompare("m4a") == .orderedSame ||
                url.pathExtension.localizedCaseInsensitiveCompare("mp4") == .orderedSame ||
                url.pathExtension.localizedCaseInsensitiveCompare("m4b") == .orderedSame {
                warnings.append(contentsOf: MetadataPipelineSupport.removeMP4Atoms(
                    matching: removedKeys,
                    from: url
                ))
            }

            warnings.append(contentsOf: MetadataPipelineSupport.rawPropertyRemovalWarnings(
                removedKeys: removedKeys,
                for: url
            ))
        }

        return AudioMetadataWriteResult(warnings: warnings)
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
        let warnings = MetadataPipelineSupport.numberTextWriteWarnings(
            writeResult.warnings,
            expectedTrackNumberText: trackNumberText,
            expectedDiscNumberText: discNumberText,
            for: url
        )
        return AudioMetadataWriteResult(warnings: warnings)
    }
}

private enum MetadataPipelineSupport {
    nonisolated static func rawMetadataDumpText(
        from dump: RawMetadataDump,
        url: URL,
        preservingSectionsFrom bridgeText: String?
    ) -> String {
        var lines: [String] = [
            "File: \(url.lastPathComponent)",
            "Path: \(url.path)",
            "",
            "[TagLib Properties]"
        ]

        if dump.properties.isEmpty {
            lines.append("(none)")
        } else {
            for property in dump.properties {
                let values = property.values.isEmpty ? [property.value] : property.values
                let value = values
                    .map(normalizedFieldComponent)
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")

                if value.isEmpty {
                    lines.append("\(property.key) =")
                } else {
                    lines.append("\(property.key) = \(value)")
                }
            }
        }

        if let preservedSections = metadataDumpSectionsAfterTagLibProperties(from: bridgeText) {
            return (lines + [""] + preservedSections).joined(separator: "\n")
        }

        lines.append("")
        lines.append("[ID3v2 Frames]")

        if dump.id3v2Frames.isEmpty {
            lines.append("(none)")
        } else {
            for frame in dump.id3v2Frames {
                let value = frame.value.trimmingCharacters(in: .whitespacesAndNewlines)
                var label = frame.frameID

                if let language = frame.language, !language.isEmpty {
                    label += " [\(language)]"
                }

                if let description = frame.description, !description.isEmpty {
                    label += " (\(description))"
                }

                lines.append("\(label) = \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    nonisolated private static func metadataDumpSectionsAfterTagLibProperties(from rawText: String?) -> [String]? {
        guard let rawText else { return nil }

        let lines = rawText.components(separatedBy: .newlines)
        guard let propertyHeaderIndex = lines.firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines) == "[TagLib Properties]"
        }) else {
            return nil
        }

        let sectionStartIndex = lines[(propertyHeaderIndex + 1)...].firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        })

        guard let sectionStartIndex else { return nil }
        return Array(lines[sectionStartIndex...])
    }

    nonisolated static func rawMetadataDumpTextWithCompatibilityNotes(_ rawText: String) -> String {
        let notes = legacyTagCompatibilityNotes(for: rawText)
        guard !notes.isEmpty else { return rawText }

        let noteText = (["[AudioMator Compatibility Notes]"] + notes.map { "- \($0)" })
            .joined(separator: "\n")
        return [rawText, noteText].joined(separator: "\n\n")
    }

    nonisolated static func numberTextWriteWarnings(
        _ warnings: [String],
        expectedTrackNumberText: String,
        expectedDiscNumberText: String?,
        for url: URL
    ) -> [String] {
        guard !warnings.isEmpty else { return warnings }
        guard let readBack = try? TagLibMetadataManager.readMetadataResult(from: url) else {
            return warnings
        }

        return warnings.compactMap { warning in
            if warning.hasPrefix("Track number text differs after save") {
                return normalizedNumberTextWarning(
                    warning,
                    label: "Track number",
                    expectedText: expectedTrackNumberText,
                    actualText: readBack.trackNumberText,
                    actualNumber: readBack.track,
                    actualTotal: readBack.trackTotal
                )
            }

            if warning.hasPrefix("Disc number text differs after save") {
                return normalizedNumberTextWarning(
                    warning,
                    label: "Disc number",
                    expectedText: expectedDiscNumberText ?? "",
                    actualText: readBack.discNumberText,
                    actualNumber: readBack.disc,
                    actualTotal: readBack.discTotal
                )
            }

            return warning
        }
    }

    nonisolated private static func normalizedNumberTextWarning(
        _ warning: String,
        label: String,
        expectedText: String,
        actualText: String,
        actualNumber: Int,
        actualTotal: Int
    ) -> String? {
        let normalizedExpected = normalizedFieldComponent(expectedText)
        guard !normalizedExpected.isEmpty else { return warning }

        guard AudioTagNumberText.writeExpectationMatches(
            expectedText: normalizedExpected,
            actualNumber: actualNumber,
            actualTotal: actualTotal
        ) else {
            return warning
        }

        if AudioTagNumberText.components(from: normalizedExpected).total == nil, actualTotal > 0 {
            return nil
        }

        return "\(label) formatting was normalized by the container (\(normalizedExpected) -> \(actualText))."
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

    nonisolated static func writeContentAdvisory(
        _ advisory: ContentAdvisory?,
        to url: URL
    ) -> [String] {
        let key = "ITUNESADVISORY"
        var warnings: [String] = []

        do {
            let writeResult = try TagLibMetadataManager.writeRawMetadataPropertyMapWithVerification(
                [key: advisory.map { String($0.rawValue) } ?? ""],
                to: url,
                mode: .merge,
                verifyAfterWrite: false
            )
            warnings.append(contentsOf: writeResult.warnings)
        } catch {
            warnings.append("Could not write iTunes advisory metadata after save: \((error as NSError).localizedDescription)")
        }

        if advisory == nil {
            warnings.append(contentsOf: removeMP4Atoms(matching: propertyMapKeyAliases(key), from: url))
            warnings.append(contentsOf: rawPropertyRemovalWarnings(removedKeys: propertyMapKeyAliases(key), for: url))
        }

        return warnings
    }

    nonisolated static func removedPropertyMapKeys(
        original: [String: String],
        replacement: [String: String]
    ) -> Set<String> {
        let replacementKeys = Set(replacement.keys.flatMap(propertyMapKeyAliases))
        return Set(original.keys.flatMap(propertyMapKeyAliases)).subtracting(replacementKeys)
    }

    nonisolated static func rawPropertyRemovalWarnings(
        removedKeys: Set<String>,
        for url: URL
    ) -> [String] {
        guard !removedKeys.isEmpty else { return [] }

        let persistedPropertyMap: [String: String]
        do {
            persistedPropertyMap = try TagLibAudioMetadataPipeline().rawMetadataPropertyMap(for: url)
        } catch {
            return ["Could not verify raw metadata removal after save: \((error as NSError).localizedDescription)"]
        }
        let persistedKeys = Set(persistedPropertyMap.keys.flatMap(propertyMapKeyAliases))

        let remainingKeys = removedKeys.intersection(persistedKeys)
        guard !remainingKeys.isEmpty else { return [] }

        return remainingKeys
            .sorted()
            .map { "Raw key \"\($0)\" was expected to be removed after save." }
    }

    nonisolated static func cleanupRemovedPropertyMapKeys(
        _ removedKeys: Set<String>,
        from url: URL
    ) -> [String] {
        guard !removedKeys.isEmpty else { return [] }

        var warnings: [String] = []
        if isMP4Like(url) {
            warnings.append(contentsOf: removeMP4Atoms(matching: removedKeys, from: url))
        }

        let currentPropertyMap: [String: String]
        do {
            currentPropertyMap = try TagLibAudioMetadataPipeline().rawMetadataPropertyMap(for: url)
        } catch {
            warnings.append("Could not read raw metadata for cleared-field cleanup: \((error as NSError).localizedDescription)")
            return warnings
        }
        let filteredPropertyMap = currentPropertyMap.filter { entry in
            removedKeys.intersection(propertyMapKeyAliases(entry.key)).isEmpty
        }

        if filteredPropertyMap.count != currentPropertyMap.count {
            do {
                let valueMap = rawPropertyMapValues(from: filteredPropertyMap)
                let writeResult = try TagLibMetadataManager.writeRawMetadataPropertyMapValuesWithVerification(valueMap, to: url)
                warnings.append(contentsOf: writeResult.warnings)
            } catch {
                warnings.append("Could not remove cleared raw metadata after save: \((error as NSError).localizedDescription)")
            }
        }

        warnings.append(contentsOf: rawPropertyRemovalWarnings(removedKeys: removedKeys, for: url))
        return warnings
    }

    nonisolated static func removeMP4Atoms(
        matching removedKeys: Set<String>,
        from url: URL
    ) -> [String] {
        do {
            let structured = try TagLibMetadataManager.readStructuredMetadataResult(from: url)
            let atomsToRemove = structured.mp4Atoms
                .filter { atom in
                    !removedKeys.intersection(normalizedMP4AtomKeys(atom)).isEmpty
                }
                .map { atom in
                    StructuredMP4Atom(
                        key: atom.key,
                        type: "stringList",
                        values: [],
                        freeformDescription: atom.freeformDescription
                    )
                }

            guard !atomsToRemove.isEmpty else { return [] }

            let removalPayload = StructuredMetadata(mp4Atoms: atomsToRemove)
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(
                removalPayload,
                to: url,
                includeProperties: false,
                verifyAfterWrite: false
            )
            return []
        } catch {
            return ["Could not remove MP4 atom metadata after raw save: \((error as NSError).localizedDescription)"]
        }
    }

    nonisolated static func clearedPropertyMapKeys(from edit: MetadataEditPayload) -> Set<String> {
        var cleared: Set<MetadataFieldKey> = []
        var populated: Set<MetadataFieldKey> = []

        func record(_ key: MetadataFieldKey, isPopulated: Bool) {
            if isPopulated {
                populated.insert(key)
            } else {
                cleared.insert(key)
            }
        }

        record(.title, isPopulated: !normalizedFieldComponent(edit.title).isEmpty)
        record(.artist, isPopulated: !normalizedFieldComponent(edit.artist).isEmpty)
        record(.album, isPopulated: !normalizedFieldComponent(edit.album).isEmpty)
        record(.composer, isPopulated: !normalizedFieldComponent(edit.composer).isEmpty)
        record(.genre, isPopulated: !normalizedFieldComponent(edit.genre).isEmpty)
        record(.comment, isPopulated: !normalizedFieldComponent(edit.comment).isEmpty)
        record(.albumArtist, isPopulated: !normalizedFieldComponent(edit.albumArtist).isEmpty)
        record(.publisher, isPopulated: !normalizedFieldComponent(edit.publisher).isEmpty)
        record(.isrc, isPopulated: !normalizedFieldComponent(edit.isrc).isEmpty)
        record(.barcode, isPopulated: !normalizedFieldComponent(edit.barcode).isEmpty)
        record(.musicBrainzAlbumID, isPopulated: !normalizedFieldComponent(edit.musicBrainzAlbumID).isEmpty)
        record(.musicBrainzTrackID, isPopulated: !normalizedFieldComponent(edit.musicBrainzTrackID).isEmpty)
        record(.musicBrainzReleaseGroupID, isPopulated: !normalizedFieldComponent(edit.musicBrainzReleaseGroupID).isEmpty)
        record(.lyricist, isPopulated: !normalizedFieldComponent(edit.lyricist).isEmpty)
        record(.remixer, isPopulated: !normalizedFieldComponent(edit.remixer).isEmpty)
        record(.producer, isPopulated: !normalizedFieldComponent(edit.producer).isEmpty)
        record(.engineer, isPopulated: !normalizedFieldComponent(edit.engineer).isEmpty)
        record(.language, isPopulated: !normalizedFieldComponent(edit.language).isEmpty)
        record(.mediaType, isPopulated: !normalizedFieldComponent(edit.mediaType).isEmpty)
        record(.releaseType, isPopulated: !normalizedFieldComponent(edit.releaseType).isEmpty)
        record(.catalogNumber, isPopulated: !normalizedFieldComponent(edit.catalogNumber).isEmpty)
        record(.releaseCountry, isPopulated: !normalizedFieldComponent(edit.releaseCountry).isEmpty)
        record(.copyright, isPopulated: !normalizedFieldComponent(edit.copyright).isEmpty)
        record(.itunesAlbumID, isPopulated: !normalizedFieldComponent(edit.itunesAlbumID).isEmpty)
        record(.itunesArtistID, isPopulated: !normalizedFieldComponent(edit.itunesArtistID).isEmpty)
        record(.itunesCatalogID, isPopulated: !normalizedFieldComponent(edit.itunesCatalogID).isEmpty)

        let trackText = normalizedFieldComponent(edit.trackNumberText)
        let discText = normalizedFieldComponent(edit.discNumberText)
        let parsedTrack = parseNumberTextForMetadataWrite(trackText)
        let parsedDisc = parseNumberTextForMetadataWrite(discText)
        record(.track, isPopulated: max(edit.trackNumber, parsedTrack.number) > 0 || !trackText.isEmpty)
        record(.trackTotal, isPopulated: max(edit.trackTotal, parsedTrack.total) > 0)
        record(.disc, isPopulated: max(edit.discNumber, parsedDisc.number) > 0 || !discText.isEmpty)
        record(.discTotal, isPopulated: max(edit.discTotal, parsedDisc.total) > 0)

        let clearedKeys = cleared.flatMap(propertyMapKeyAliases)
        let populatedKeys = populated.flatMap(propertyMapKeyAliases)
        return Set(clearedKeys).subtracting(populatedKeys)
    }

    nonisolated private static func isMP4Like(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "m4a", "m4b", "m4p", "m4r", "mp4", "aac":
            return true
        default:
            return false
        }
    }

    nonisolated private static func propertyMapKeyAliases(_ key: String) -> Set<String> {
        let normalized = normalizedPropertyMapKey(key)
        guard !normalized.isEmpty else { return [] }

        var aliases: Set<String> = [normalized]
        if let schema = MetadataFieldRegistry.schema(forPropertyMapKey: normalized) {
            aliases.formUnion(schema.propertyMapKeys.map(normalizedPropertyMapKey))
        }

        return aliases
    }

    nonisolated private static func propertyMapKeyAliases(_ key: MetadataFieldKey) -> Set<String> {
        guard let schema = MetadataFieldRegistry.schema(for: key) else { return [] }
        return Set(schema.propertyMapKeys.flatMap(propertyMapKeyAliases))
    }

    nonisolated private static func normalizedMP4AtomKeys(_ atom: StructuredMP4Atom) -> Set<String> {
        let prefix = "----:COM.APPLE.ITUNES:"
        let rawKeys = [
            atom.key,
            atom.freeformDescription ?? ""
        ]

        return rawKeys.reduce(into: Set<String>()) { keys, rawKey in
            for key in propertyMapKeyAliases(rawKey) {
                keys.insert(key)
                if key.hasPrefix(prefix) {
                    keys.formUnion(propertyMapKeyAliases(String(key.dropFirst(prefix.count))))
                }
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
        AudioTagNumberText.parsedPair(from: rawText)
    }

    nonisolated static func makeTagLibMetadata(
        from edit: MetadataEditPayload,
        url: URL
    ) throws -> TagLibAudioMetadata {
        let metadata = try TagLibMetadataExtractor.extractMetadata(from: url)

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
        metadata.itunesAlbumId = normalizedFieldComponent(edit.itunesAlbumID)
        metadata.itunesArtistId = normalizedFieldComponent(edit.itunesArtistID)
        metadata.itunesCatalogId = normalizedFieldComponent(edit.itunesCatalogID)
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

}

private struct LegacyTagComparisonField {
    let displayName: String
    let canonicalKeys: [String]
    let legacyKeys: [String]
}
