import Foundation
import TagLibAudioMetadata

/// A typed value for a container-exclusive semantic field. Presence is carried
/// by the containing dictionary: `false` and `0` are present values, not
/// absence. The shape comes from the package registry; AudioMator does not
/// duplicate the native mapping table.
nonisolated enum ContainerFieldValue: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case boolean(Bool)

    nonisolated var displayText: String {
        switch self {
        case .text(let value):
            return value
        case .integer(let value):
            return String(value)
        case .boolean(let value):
            return value ? "1" : "0"
        }
    }

    nonisolated var patchValue: MetadataPatchValue {
        switch self {
        case .text(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .remove : .text(trimmed)
        case .integer(let value):
            return .integer(value)
        case .boolean(let value):
            return .boolean(value)
        }
    }

    /// Parses typed editor text against the shape the registry advertises for
    /// this field and destination. Empty text means an explicit removal.
    nonisolated static func parse(
        _ text: String,
        acceptedKinds: Set<MetadataPatchValueKind>
    ) -> ContainerFieldValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .text("") }

        if acceptedKinds.contains(.integer), !acceptedKinds.contains(.text),
           let value = Int(trimmed) {
            return .integer(value)
        }
        if acceptedKinds.contains(.boolean), !acceptedKinds.contains(.integer),
           let value = parsedBoolean(trimmed) {
            return .boolean(value)
        }
        if acceptedKinds.contains(.text) || acceptedKinds.contains(.values) {
            return .text(trimmed)
        }
        return nil
    }

    nonisolated private static func parsedBoolean(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}

/// Deliberate application classification of the MP4-exclusive fields in
/// `AM-TLAM-MAPPING-2.2` section 8.1. Fields that already have a dedicated
/// AudioMator property (album/artist/catalog store IDs, WORK and
/// the number totals) are listed here so every registered exclusive identity has
/// an explicit UI/capability decision, while their editing stays on the
/// dedicated control.
nonisolated enum ContainerMetadataFieldCatalog {
    nonisolated enum Presentation: Sendable {
        /// Exposed in the container-fields editor with a typed shape.
        case editable
        /// Dedicated inspector or semantic control elsewhere.
        case dedicated
        /// Readable but typed writes are withheld by the registry.
        case readOnly
        /// Registered for a format that AudioMator does not advertise as writable.
        case unsupported
    }

    nonisolated struct Field: Sendable {
        let key: MetadataFieldKey
        let presentation: Presentation
        let isMP4Exclusive: Bool
    }

    nonisolated static let fields: [Field] = [
        Field(key: .director, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesAccount, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesComposerID, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesCountryID, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesGapless, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesHDVideo, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesOwner, presentation: .editable, isMP4Exclusive: true),
        Field(key: .rate, presentation: .readOnly, isMP4Exclusive: true),
        Field(key: .showMovement, presentation: .editable, isMP4Exclusive: true),
        Field(key: .storeDescription, presentation: .editable, isMP4Exclusive: true),
        Field(key: .tvEpisode, presentation: .editable, isMP4Exclusive: true),
        Field(key: .tvEpisodeID, presentation: .editable, isMP4Exclusive: true),
        Field(key: .tvNetwork, presentation: .editable, isMP4Exclusive: true),
        Field(key: .tvSeason, presentation: .editable, isMP4Exclusive: true),
        Field(key: .tvShow, presentation: .editable, isMP4Exclusive: true),
        Field(key: .tvShowSort, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesGenreID, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesMediaType, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesPurchaseDate, presentation: .editable, isMP4Exclusive: true),
        Field(key: .itunesAlbumID, presentation: .dedicated, isMP4Exclusive: true),
        Field(key: .itunesArtistID, presentation: .dedicated, isMP4Exclusive: true),
        Field(key: .itunesCatalogID, presentation: .dedicated, isMP4Exclusive: true),
        Field(key: .explicitContent, presentation: .dedicated, isMP4Exclusive: true),
        Field(key: .work, presentation: .dedicated, isMP4Exclusive: true),
        Field(key: .trackTotal, presentation: .dedicated, isMP4Exclusive: true),
        Field(key: .discTotal, presentation: .dedicated, isMP4Exclusive: true)
    ]

    /// Fields shown in the container editor, including readable-only values.
    nonisolated static let visibleKeys: [MetadataFieldKey] = fields
        .filter { $0.presentation == .editable || $0.presentation == .readOnly }
        .map(\.key)

    /// Keys edited through the generic container-fields editor.
    nonisolated static let editableKeys: [MetadataFieldKey] = fields
        .filter { $0.presentation == .editable }
        .map(\.key)

    /// Keys with typed container storage read into `AudioFile.containerValues`.
    nonisolated static let readKeys: [MetadataFieldKey] = fields
        .filter { $0.presentation == .editable || $0.presentation == .readOnly }
        .map(\.key)

    nonisolated static func presentation(for key: MetadataFieldKey) -> Presentation? {
        fields.first { $0.key == key }?.presentation
    }

    nonisolated static func isContainerExclusive(_ key: MetadataFieldKey) -> Bool {
        fields.contains { $0.key == key }
    }

    nonisolated static func schema(for key: MetadataFieldKey) -> MetadataFieldSchema? {
        MetadataFieldRegistry.schema(for: key)
    }

    nonisolated static func acceptedKinds(for key: MetadataFieldKey) -> Set<MetadataPatchValueKind> {
        schema(for: key)?.acceptedPatchValueKinds ?? [.text]
    }

    nonisolated static func displayName(for key: MetadataFieldKey) -> String {
        schema(for: key)?.displayName ?? key.rawValue
    }

    nonisolated static func isReadOnly(_ key: MetadataFieldKey) -> Bool {
        guard let schema = schema(for: key) else { return false }
        return schema.writeUnsupportedReason != nil
    }

    /// MP4 atom keys for typed container values, declared once here instead of
    /// duplicating the registry's native table. The registry remains the
    /// authority for write support; these names are used only to read the
    /// already-typed structured projection.
    nonisolated static func atomKey(for key: MetadataFieldKey) -> String? {
        let targets = schema(for: key)?.targets(for: .mp4) ?? []
        return (targets.first(where: \.preferredWrite) ?? targets.first)?.nativeIdentity
    }
}
