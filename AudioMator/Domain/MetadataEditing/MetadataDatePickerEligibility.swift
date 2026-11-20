import Foundation
import TagLibAudioMetadata

/// Verified eligibility and exact destination format capabilities for a date or
/// timestamp picker session.
nonisolated struct MetadataDatePickerEligibility: Equatable, Hashable, Sendable {
    let fieldKey: MetadataFieldKey
    let destinationFormat: MetadataDateDestinationFormat
    let effectiveRawKey: String?

    init(
        fieldKey: MetadataFieldKey,
        destinationFormat: MetadataDateDestinationFormat,
        effectiveRawKey: String? = nil
    ) {
        self.fieldKey = fieldKey
        self.destinationFormat = destinationFormat
        self.effectiveRawKey = effectiveRawKey
    }
}

/// Resolves whether a field and concrete target selection qualify for native
/// macOS date/time picking, and intersects destination format capabilities across
/// multi-selections.
///
/// Inspector eligibility follows semantic write targets. Metadata Editor
/// eligibility follows the exact raw PropertyMap key written by the editor.
nonisolated enum MetadataDatePickerEligibilityResolver {
    private static let mp4Extensions: Set<String> = ["m4a", "mp4", "m4b", "m4r", "m4p", "m4v", "3g2"]
    private static let vorbisExtensions: Set<String> = ["flac", "ogg", "oga", "opus", "spx"]
    private static let apeExtensions: Set<String> = ["ape", "wv", "mpc"]
    private static let asfExtensions: Set<String> = ["wma", "asf"]
    private static let id3Extensions: Set<String> = ["mp3", "mp2", "aac", "aif", "aiff", "aifc", "afc", "tta", "dsf", "dff", "dsdiff"]

    /// Inspector eligibility for a semantic row across the current selection.
    @MainActor
    static func inspectorEligibility(
        for field: InspectorMetadataField,
        files: [AudioFile]
    ) -> MetadataDatePickerEligibility? {
        guard !files.isEmpty, let fieldKey = field.metadataFieldKey else { return nil }
        guard isInspectorEligibleFieldKey(fieldKey) else { return nil }

        var formats: [MetadataDateDestinationFormat] = []
        formats.reserveCapacity(files.count)

        for file in files {
            guard AudioViewModel.canWrite(fieldKey, to: file),
                  let format = destinationFormat(
                      for: fieldKey,
                      fileExtension: file.url.pathExtension,
                      structured: file.metadataConflictBaseline?.structured
                  ) else {
                return nil
            }
            formats.append(format)
        }

        guard let intersected = MetadataDateDestinationFormat.intersect(formats) else {
            return nil
        }

        return MetadataDatePickerEligibility(
            fieldKey: fieldKey,
            destinationFormat: intersected,
            effectiveRawKey: nil
        )
    }

    /// Metadata Editor eligibility for a raw PropertyMap key across the editor's
    /// target selection. Preserves the exact raw key and treats ambiguous aliases
    /// as text fields.
    static func metadataEditorEligibility(
        rawKey: String,
        targets: [MetadataEditorTarget]
    ) -> MetadataDatePickerEligibility? {
        guard !targets.isEmpty else { return nil }
        let normalizedKey = MetadataFieldRegistry.normalizePropertyMapKey(rawKey)
        guard !normalizedKey.isEmpty, !normalizedKey.contains(":") else { return nil }

        var resolvedKeys: Set<MetadataFieldKey> = []
        var formats: [MetadataDateDestinationFormat] = []
        formats.reserveCapacity(targets.count)

        for target in targets {
            let ext = target.url.pathExtension
            let structured = target.metadataConflictBaseline?.structured

            guard let resolved = resolveMetadataEditorKey(
                normalizedRawKey: normalizedKey,
                fileExtension: ext,
                structured: structured
            ) else {
                return nil
            }

            resolvedKeys.insert(resolved.fieldKey)
            // Mixed selections where the same raw key maps to different semantic
            // identities (for example raw `DATE` across FLAC and MP3) are
            // ambiguous and must remain text-only.
            guard resolvedKeys.count == 1 else { return nil }

            formats.append(resolved.format)
        }

        guard let fieldKey = resolvedKeys.first,
              let intersected = MetadataDateDestinationFormat.intersect(formats) else {
            return nil
        }

        return MetadataDatePickerEligibility(
            fieldKey: fieldKey,
            destinationFormat: intersected,
            effectiveRawKey: normalizedKey
        )
    }

    // MARK: - Resolution Details

    private static func isInspectorEligibleFieldKey(_ key: MetadataFieldKey) -> Bool {
        switch key {
        case .year, .standaloneDate, .releaseDate, .originalReleaseDate:
            return true
        default:
            return false
        }
    }

    private static func resolveMetadataEditorKey(
        normalizedRawKey: String,
        fileExtension: String,
        structured: StructuredMetadata?
    ) -> (fieldKey: MetadataFieldKey, format: MetadataDateDestinationFormat)? {
        guard let family = resolveNativeFamily(fileExtension: fileExtension, structured: structured) else {
            return nil
        }

        // These keys reach the same field through both the raw and semantic
        // writers for the listed tag families. Registry aliases alone are not
        // evidence of raw routing (e.g. YEAR in ID3 writes a user text frame).
        let fieldKey: MetadataFieldKey
        switch (normalizedRawKey, family) {
        case ("DATE", .vorbisComment), ("DATE", .apev2):
            fieldKey = .standaloneDate
        case ("RELEASEDATE", .id3v24), ("RELEASEDATE", .mp4),
             ("RELEASEDATE", .vorbisComment), ("RELEASEDATE", .apev2):
            fieldKey = .releaseDate
        case ("ORIGINALDATE", .id3v24), ("ORIGINALDATE", .mp4),
             ("ORIGINALDATE", .vorbisComment), ("ORIGINALDATE", .apev2):
            fieldKey = .originalReleaseDate
        default:
            return nil
        }

        guard let format = destinationFormat(
            for: fieldKey,
            fileExtension: fileExtension,
            structured: structured
        ) else {
            return nil
        }

        return (fieldKey, format)
    }

    /// Resolves the concrete `MetadataNativeFamily` for a file using its
    /// extension and loaded structured metadata.
    static func resolveNativeFamily(
        fileExtension: String,
        structured: StructuredMetadata?
    ) -> MetadataNativeFamily? {
        let ext = fileExtension.lowercased()

        if mp4Extensions.contains(ext) {
            return .mp4
        }
        if vorbisExtensions.contains(ext) {
            return .vorbisComment
        }
        if apeExtensions.contains(ext) {
            return .apev2
        }
        if asfExtensions.contains(ext) {
            return .asf
        }
        if id3Extensions.contains(ext) || ext == "wav" {
            guard let structured else { return nil }
            if let majorVersion = structured.id3v2MajorVersion {
                switch majorVersion {
                case 4: return .id3v24
                case 3: return .id3v23
                default: return nil
                }
            }
            // The writer can create ID3v2.4 when the snapshot has no ID3 tag.
            return .id3v24
        }
        return nil
    }

    private static func destinationFormat(
        for fieldKey: MetadataFieldKey,
        fileExtension: String,
        structured: StructuredMetadata?
    ) -> MetadataDateDestinationFormat? {
        let ext = fileExtension.lowercased()
        guard AudioFormatSupport.metadataWritableExtensions.contains(ext) else {
            return nil
        }
        guard let writableFields = AudioFormatSupport.writableMetadataFields(for: ext),
              writableFields.contains(fieldKey) else {
            return nil
        }
        guard let family = resolveNativeFamily(fileExtension: ext, structured: structured) else {
            return nil
        }

        // Existing ID3v2.3 independent dates are read-only/unverified.
        if family == .id3v23 {
            return nil
        }

        guard let schema = MetadataFieldRegistry.schema(for: fieldKey) else {
            return nil
        }

        let capability = schema.capability(for: family)
        guard capability == .native || capability == .conventionalExtension else {
            return nil
        }
        guard let target = schema.writeTarget(for: family) else {
            return nil
        }

        switch fieldKey {
        case .year:
            // Year keeps direct text entry everywhere except when the actual
            // writable target is a timestamp field such as ID3v2.4 TDRC.
            guard family == .id3v24, target.nativeIdentity == "TDRC" else {
                return nil
            }
            // For WAV without an existing ID3v2.4 tag, avoid claiming TDRC
            // timestamp support if only RIFF INFO could be present.
            if ext == "wav", structured?.id3v2MajorVersion != 4 {
                return nil
            }
            return .id3v24Timestamp

        case .releaseDate:
            switch family {
            case .id3v24 where target.nativeIdentity == "TDRL":
                return .id3v24Timestamp
            case .mp4 where target.storage == .mp4Freeform && target.nativeIdentity == "RELEASEDATE":
                return .isoDateOnly
            case .vorbisComment, .apev2:
                return target.nativeIdentity == "RELEASEDATE" ? .isoDateOnly : nil
            default:
                return nil
            }

        case .originalReleaseDate:
            switch family {
            case .id3v24 where target.nativeIdentity == "TDOR":
                return .id3v24Timestamp
            case .mp4 where target.storage == .mp4Freeform && target.nativeIdentity == "ORIGINALDATE":
                return .isoDateOnly
            case .vorbisComment, .apev2:
                return target.nativeIdentity == "ORIGINALDATE" ? .isoDateOnly : nil
            case .asf where target.nativeIdentity == "WM/OriginalReleaseYear":
                return .yearOnly
            default:
                return nil
            }

        case .standaloneDate:
            switch family {
            case .id3v24 where target.storage == .userTextFrame && target.nativeIdentity == "DATE":
                return .isoDateOnly
            case .mp4 where target.storage == .mp4Freeform && target.nativeIdentity == "DATE":
                return .isoDateOnly
            case .vorbisComment, .apev2:
                return target.nativeIdentity == "DATE" ? .isoDateOnly : nil
            case .asf where target.nativeIdentity == "DATE":
                return .isoDateOnly
            default:
                return nil
            }

        default:
            return nil
        }
    }
}
