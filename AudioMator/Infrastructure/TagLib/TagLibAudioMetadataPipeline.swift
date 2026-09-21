import Foundation
import TagLibAudioMetadata

struct TagLibAudioMetadataPipeline: AudioMetadataPipeline {
    nonisolated var requiresTransactionalDirectoryAccess: Bool { true }

    nonisolated init() {}

    nonisolated static func metadataPatchForWrite(from edit: MetadataEditPayload) -> MetadataPatch {
        MetadataPipelineSupport.metadataPatch(from: edit)
    }

    nonisolated static func interpretingWrite(
        _ operation: () throws -> [String]
    ) throws -> AudioMetadataWriteResult {
        do {
            return AudioMetadataWriteResult(warnings: try operation())
        } catch TagLibManagerError.committedButDurabilityUncertain(let detail) {
            return AudioMetadataWriteResult(
                warnings: [],
                commitStatus: .durabilityUncertain(detail)
            )
        }
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

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        let dump = try TagLibMetadataManager.rawMetadataResult(from: url)
        return dump.properties.reduce(into: RawMetadataValueMap()) { result, entry in
            let key = entry.key.uppercased()
            guard !key.isEmpty else { return }
            let values = entry.values.isEmpty ? [entry.value] : entry.values
            result[key, default: []].append(contentsOf: values)
        }
    }

    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        try writeMetadata(edit, to: url, expectedVersion: nil)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyMetadataPatch(
                Self.metadataPatchForWrite(from: edit),
                to: url,
                expectedVersion: expectedVersion,
                failurePolicy: .throw
            ).warnings
        }
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        try writeRawMetadataValueMap(propertyMap.mapValues { [$0] }, to: url, expectedVersion: nil)
    }

    nonisolated func writeRawMetadataValueMap(
        _ valueMap: RawMetadataValueMap,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        let original = try rawMetadataValueMap(for: url)
        let originalKeys = Set(original.keys)
        let replacementKeys = Set(valueMap.keys)
        let changedValues = valueMap.filter { original[$0.key] != $0.value }
        let patch = RawMetadataPatch(
            valuesToSet: changedValues,
            removingKeys: originalKeys.subtracting(replacementKeys)
        )
        return try writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyRawMetadataPatch(
                patch,
                to: url,
                expectedVersion: expectedVersion
            ).warnings
        }
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        try eraseAllMetadata(at: url, expectedVersion: nil)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.eraseAllMetadataWithVerification(
                from: url,
                expectedVersion: expectedVersion
            ).warnings
        }
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        try writeTrackNumberText(
            trackNumberText,
            discNumberText: discNumberText,
            to: url,
            verifyAfterWrite: verifyAfterWrite,
            expectedVersion: nil
        )
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            let writeResult = try TagLibMetadataManager.writeTrackNumberText(
                trackNumberText,
                discNumberText: discNumberText,
                to: url,
                verifyAfterWrite: verifyAfterWrite,
                expectedVersion: expectedVersion
            )
            return MetadataPipelineSupport.numberTextWriteWarnings(
                writeResult.warnings,
                expectedTrackNumberText: trackNumberText,
                expectedDiscNumberText: discNumberText,
                for: url
            )
        }
    }
}

private enum MetadataPipelineSupport {
    nonisolated static func metadataPatch(from edit: MetadataEditPayload) -> MetadataPatch {
        func textValue(_ value: String) -> MetadataPatchValue {
            let trimmed = normalizedFieldComponent(value)
            return trimmed.isEmpty ? .remove : .text(trimmed)
        }

        let candidateFields: [MetadataFieldKey: MetadataPatchValue] = [
            .title: textValue(edit.title),
            .artist: textValue(edit.artist),
            .album: textValue(edit.album),
            .composer: textValue(edit.composer),
            .genre: textValue(edit.genre),
            .comment: textValue(edit.comment),
            .date: textValue(edit.year),
            .releaseDate: textValue(edit.releaseDate),
            .albumArtist: textValue(edit.albumArtist),
            .publisher: textValue(edit.publisher),
            .isrc: textValue(edit.isrc),
            .barcode: textValue(edit.barcode),
            .itunesAlbumID: textValue(edit.itunesAlbumID),
            .itunesArtistID: textValue(edit.itunesArtistID),
            .itunesCatalogID: textValue(edit.itunesCatalogID),
            .musicBrainzAlbumID: textValue(edit.musicBrainzAlbumID),
            .musicBrainzTrackID: textValue(edit.musicBrainzTrackID),
            .musicBrainzReleaseGroupID: textValue(edit.musicBrainzReleaseGroupID),
            .lyricist: textValue(edit.lyricist),
            .remixer: textValue(edit.remixer),
            .producer: textValue(edit.producer),
            .engineer: textValue(edit.engineer),
            .language: textValue(edit.language),
            .mediaType: textValue(edit.mediaType),
            .releaseType: textValue(edit.releaseType),
            .catalogNumber: textValue(edit.catalogNumber),
            .releaseCountry: textValue(edit.releaseCountry),
            .copyright: textValue(edit.copyright),
        ]
        let fields = candidateFields.filter { edit.changedFields.contains($0.key) }

        let trackText = normalizedNumberText(
            edit.trackNumberText,
            number: edit.trackNumber,
            total: edit.trackTotal
        )
        let discText = normalizedNumberText(
            edit.discNumberText,
            number: edit.discNumber,
            total: edit.discTotal
        )
        let advisory: ExplicitAdvisory? = if edit.contentAdvisoryChanged {
            switch edit.contentAdvisory {
            case nil: .unspecified
            case .notExplicit: .notExplicit
            case .clean: .clean
            case .explicit: .explicit
            }
        } else {
            nil
        }
        let artwork: MetadataArtworkPatch = switch edit.artwork {
        case .unchanged:
            .unchanged
        case .replace(let data, let mimeType):
            .replace([StructuredArtwork(mimeType: mimeType, data: data)])
        case .remove:
            .removeAll
        }

        let numberText: MetadataNumberTextPatch? = if edit.trackNumberTextChanged || edit.discNumberTextChanged {
            MetadataNumberTextPatch(
                trackNumberText: trackText,
                discNumberText: edit.discNumberTextChanged ? discText : nil
            )
        } else {
            nil
        }

        return MetadataPatch(
            fields: fields,
            explicitAdvisory: advisory,
            artwork: artwork,
            numberText: numberText
        )
    }

    nonisolated private static func normalizedNumberText(
        _ rawText: String,
        number: Int,
        total: Int
    ) -> String {
        let trimmed = normalizedFieldComponent(rawText)
        guard trimmed.isEmpty else { return trimmed }
        guard number > 0 else { return "" }
        return total > 0 ? "\(number)/\(total)" : String(number)
    }

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

}

private struct LegacyTagComparisonField {
    let displayName: String
    let canonicalKeys: [String]
    let legacyKeys: [String]
}
