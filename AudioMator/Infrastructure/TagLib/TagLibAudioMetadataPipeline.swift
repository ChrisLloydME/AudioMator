import Foundation
import TagLibAudioMetadata

struct TagLibAudioMetadataPipeline: AudioMetadataPipeline {
    nonisolated var requiresTransactionalDirectoryAccess: Bool { true }

    nonisolated init() {}

    /// Single validation and encoding policy for every semantic write entry
    /// point: unsupported advisory imports are rejected before a patch can be
    /// planned or committed. Preserve semantic intent exactly; package alias
    /// defects are not repaired by synthesizing writes to unedited date fields.
    nonisolated static func metadataPatchForWrite(from edit: MetadataEditPayload) throws -> MetadataPatch {
        if edit.unsupportedAdvisoryImport != nil {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "This content advisory code can't be assigned. Its existing value will be kept. To change it, choose a supported advisory option.")])
        }
        return MetadataPipelineSupport.metadataPatch(from: edit)
    }

    nonisolated static func interpretingWrite(
        _ operation: () throws -> TagLibMetadataManager.MetadataWriteResult
    ) throws -> AudioMetadataWriteResult {
        do {
            let result = try operation()
            let status: AudioMetadataCommitStatus = switch result.commitStatus {
            case .durable: .durable
            case .durabilityUncertain(let detail): .durabilityUncertain(detail)
            }
            return AudioMetadataWriteResult(warnings: result.warnings, commitStatus: status)
        } catch MetadataPatchValidationError.ambiguousNumberRecovery(let field, _) {
            let label: String = switch field {
            case "trackTotal": String(localized: "Total Tracks")
            case "discTotal": String(localized: "Total Discs")
            case "disc": String(localized: "Disc Number")
            default: String(localized: "Track Number")
            }
            throw NSError(domain: "AudioMator.Numbering", code: 1, userInfo: [NSLocalizedDescriptionKey:
                label + " — " + String(localized: "This numbering value couldn’t be determined. Enter the value you want to save.")])
        } catch TagLibManagerError.committedButDurabilityUncertain(let detail) {
            return AudioMetadataWriteResult(
                warnings: [],
                commitStatus: .durabilityUncertain(detail)
            )
        }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        do {
            return try await AudioFile(url: url, id: id)
        } catch TagLibManagerError.fileChanged {
            // A read is safe to retry once; a commit must never be retried this way.
            try Task.checkCancellation()
            return try await AudioFile(url: url, id: id)
        }
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try TagLibMetadataManager.readSnapshot(from: url, includingAudioContent: true)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try TagLibMetadataManager.fileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        let bridgeText = TagLibMetadataManager.bestEffortRawMetadataText(from: url)

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

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        let dump = try TagLibMetadataManager.rawMetadataResult(from: url)
        return dump.properties.reduce(into: RawMetadataValueMap()) { result, entry in
            let key = entry.key.uppercased()
            guard !key.isEmpty else { return }
            let values = entry.values.isEmpty ? [entry.value] : entry.values
            result[key, default: []].append(contentsOf: values)
        }
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyMetadataPatch(
                try Self.metadataPatchForWrite(from: edit),
                to: url,
                expectedVersion: expectedVersion
            )
        }
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
            )
        }
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyMetadataPatch(
                try Self.metadataPatchForWrite(from: edit),
                to: url,
                expectedVersion: expectedVersion, expectedAudioContent: expectedAudioContent
            )
        }
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyRawMetadataPatch(
                patch, to: url,
                expectedVersion: expectedVersion, expectedAudioContent: expectedAudioContent
            )
        }
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.eraseAllMetadataWithVerification(
                from: url,
                expectedVersion: expectedVersion
            )
        }
    }

    // MARK: - Reviewed (strict) writes

    nonisolated static func isWritableMetadataFileExtension(_ fileExtension: String) -> Bool {
        AudioFormatSupport.metadataWritableExtensions.contains(fileExtension.lowercased())
    }

    /// Applies the same deterministic encoder used by the eventual commit and the
    /// app's fail-closed capability policy. Plan-time truth only: the returned
    /// projection never authorizes a write by itself.
    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        let extensionIsWritable = Self.isWritableMetadataFileExtension(fileExtension)

        switch intent {
        case .semantic(let payload):
            let requested = payload.requestedFields
            if payload.unsupportedAdvisoryImport != nil {
                return MetadataWriteProjection(
                    requestedFields: requested,
                    validation: .rejected(String(localized: "This content advisory code can't be assigned. Its existing value will be kept. To change it, choose a supported advisory option."))
                )
            }
            if let message = payload.numberPairValidationMessage {
                return MetadataWriteProjection(
                    requestedFields: requested,
                    validation: .rejected(message)
                )
            }
            if requested.isEmpty {
                return MetadataWriteProjection(
                    requestedFields: [],
                    effectiveFields: [],
                    componentOperations: [],
                    validation: .executable,
                    isEncoderNoOp: true
                )
            }
            guard extensionIsWritable else {
                return MetadataWriteProjection(
                    requestedFields: requested,
                    unsupportedFields: requested,
                    validation: .unsupported(requested)
                )
            }
            // Missing capability information is unsupported for every requested
            // field; it is never treated as "the package will decide".
            guard let writableFields = AudioFormatSupport.writableMetadataFields(for: fileExtension) else {
                return MetadataWriteProjection(
                    requestedFields: requested,
                    unsupportedFields: requested,
                    validation: .unsupported(requested)
                )
            }
            let unsupported = requested.subtracting(writableFields)
            guard unsupported.isEmpty else {
                return MetadataWriteProjection(
                    requestedFields: requested,
                    unsupportedFields: unsupported,
                    validation: .unsupported(unsupported)
                )
            }
            let operations = MetadataPipelineSupport.semanticWriteOperations(from: payload)
            return MetadataWriteProjection(
                requestedFields: requested,
                effectiveFields: operations.effectiveFieldKeys,
                componentOperations: operations.componentOperations,
                validation: .executable,
                isEncoderNoOp: operations.effectiveFieldKeys.isEmpty
                    && operations.componentOperations.isEmpty
            )

        case .raw(let patch):
            guard extensionIsWritable else {
                return MetadataWriteProjection(
                    validation: .rejected(String(localized: "AudioMator doesn't support writing raw metadata values to this file format."))
                )
            }
            return MetadataWriteProjection(
                validation: .executable,
                isEncoderNoOp: patch.valuesToSet.isEmpty && patch.removingKeys.isEmpty
            )

        case .eraseAll:
            guard extensionIsWritable else {
                return MetadataWriteProjection(
                    validation: .rejected(String(localized: "AudioMator doesn't support clearing metadata in this file format."))
                )
            }
            return MetadataWriteProjection(validation: .executable)
        }
    }

    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyMetadataPatch(
                try Self.metadataPatchForWrite(from: edit),
                to: url,
                expectedVersion: expectedVersion
            )
        }
    }

    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.applyRawMetadataPatch(
                patch,
                to: url,
                expectedVersion: expectedVersion
            )
        }
    }

    nonisolated func eraseAllMetadataReviewed(
        at url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try Self.interpretingWrite {
            try TagLibMetadataManager.eraseAllMetadataWithVerification(
                from: url,
                expectedVersion: expectedVersion
            )
        }
    }
}

private enum MetadataPipelineSupport {
    nonisolated struct SemanticWriteOperations {
        var fields: [MetadataFieldKey: MetadataPatchValue]
        var explicitAdvisory: ExplicitAdvisory?
        var artwork: MetadataArtworkPatch
        var componentOperations: [MetadataNumberComponentOperation]

        /// Exact field identities the deterministic encoder will submit,
        /// including advisory and artwork when they changed.
        nonisolated var effectiveFieldKeys: Set<MetadataFieldKey> {
            var keys = Set(fields.keys)
            if explicitAdvisory != nil { keys.insert(.explicitContent) }
            if case .unchanged = artwork {} else { keys.insert(.artwork) }
            return keys
        }
    }

    /// Single deterministic semantic encoder shared by plan-time projection and
    /// the commit. Projection and commit must never diverge.
    nonisolated static func semanticWriteOperations(
        from edit: MetadataEditPayload
    ) -> SemanticWriteOperations {
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
            // YEAR is `.year`; the legacy `.date` alias is never submitted.
            .year: textValue(edit.year),
            // DATE is its own identity, not a YEAR projection.
            .standaloneDate: textValue(edit.date),
            .releaseDate: textValue(edit.releaseDate),
            .originalReleaseDate: textValue(edit.originalReleaseDate),
            .contentGroup: textValue(edit.contentGroup),
            .grouping: textValue(edit.grouping),
            .work: textValue(edit.work),
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
        var fields = candidateFields.filter { edit.changedFields.contains($0.key) }

        // Inspector/provider/CSV models keep identifier text for display, but
        // numeric semantic fields must follow the package's declared shape.
        // Convert only requested fields; malformed/overflow values stay invalid
        // and are rejected by package validation, never dropped or truncated.
        for (field, value) in fields {
            guard case .text(let text) = value,
                  MetadataFieldRegistry.schema(for: field)?.acceptedPatchValueKinds == [.integer],
                  let integer = Int(text) else { continue }
            fields[field] = .integer(integer)
        }

        // Number components are typed intents. Only a changed component is
        // submitted: a number-only edit never removes or rewrites its untouched
        // total, and a total-only edit preserves the number. A cleared
        // component is an explicit removal.
        var componentOperations: [MetadataNumberComponentOperation] = []
        if edit.trackNumberTextChanged {
            if edit.originalTrackNumber != edit.trackNumber {
                componentOperations.append(
                    MetadataNumberComponentOperation(
                        field: .track,
                        value: edit.trackNumber > 0 ? edit.trackNumber : nil
                    )
                )
            }
            if edit.originalTrackTotal != edit.trackTotal {
                componentOperations.append(
                    MetadataNumberComponentOperation(
                        field: .trackTotal,
                        value: edit.trackTotal > 0 ? edit.trackTotal : nil
                    )
                )
            }
        }
        if edit.discNumberTextChanged {
            if edit.originalDiscNumber != edit.discNumber {
                componentOperations.append(
                    MetadataNumberComponentOperation(
                        field: .disc,
                        value: edit.discNumber > 0 ? edit.discNumber : nil
                    )
                )
            }
            if edit.originalDiscTotal != edit.discTotal {
                componentOperations.append(
                    MetadataNumberComponentOperation(
                        field: .discTotal,
                        value: edit.discTotal > 0 ? edit.discTotal : nil
                    )
                )
            }
        }
        // Explicit scoped removals cover loaded raw text that projects to zero,
        // where numeric comparison alone cannot express component presence.
        for field in edit.explicitComponentRemovals where
            [MetadataFieldKey.track, .trackTotal, .disc, .discTotal].contains(field)
            && !componentOperations.contains(where: { $0.field == field }) {
            componentOperations.append(MetadataNumberComponentOperation(field: field, value: nil))
        }
        for operation in componentOperations {
            fields[operation.field] = operation.value.map { .integer($0) } ?? .remove
        }

        // Typed container-exclusive intents are already shape-validated. Never
        // route them through a legacy Basic replacement.
        for (key, value) in edit.containerFields {
            fields[key] = value
        }

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

        return SemanticWriteOperations(
            fields: fields,
            explicitAdvisory: advisory,
            artwork: artwork,
            componentOperations: componentOperations
        )
    }

    nonisolated static func metadataPatch(from operations: SemanticWriteOperations) -> MetadataPatch {
        MetadataPatch(
            fields: operations.fields,
            explicitAdvisory: operations.explicitAdvisory,
            artwork: operations.artwork
        )
    }

    nonisolated static func metadataPatch(from edit: MetadataEditPayload) -> MetadataPatch {
        metadataPatch(from: semanticWriteOperations(from: edit))
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

}

private struct LegacyTagComparisonField {
    let displayName: String
    let canonicalKeys: [String]
    let legacyKeys: [String]
}
