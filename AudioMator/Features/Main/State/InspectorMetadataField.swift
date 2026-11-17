import Foundation
import TagLibAudioMetadata

enum InspectorMetadataField: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case composer
    case genre
    case year
    case date
    case releaseDate
    case originalReleaseDate
    case trackNumber
    case totalTracks
    case discNumber
    case totalDiscs
    case comment
    case albumArtist
    case contentGroup
    case grouping
    case work
    case publisher
    case copyright
    case explicit
    case credits

    var id: String { rawValue }

    var displayName: String {
        if let key = metadataFieldKey {
            return MetadataFieldGuide.displayName(for: key)
        }
        return MetadataFieldGuide.displayName(forReadOnlyField: "credits")
    }

    // This is the product's curated quick-edit catalog, not the package registry.
    // New enum cases require an explicit decision about availability and defaults.
    static let configurableFields: [InspectorMetadataField] = [
        .title, .artist, .album, .composer, .genre, .year, .date,
        .releaseDate, .originalReleaseDate, .trackNumber, .totalTracks,
        .discNumber, .totalDiscs, .comment, .albumArtist, .contentGroup,
        .grouping, .work, .publisher, .copyright, .explicit, .credits,
    ]

    static let defaultVisibleFields: [InspectorMetadataField] = [
        .title, .artist, .album, .composer, .genre, .year,
        .trackNumber, .totalTracks, .discNumber, .totalDiscs,
        .comment, .albumArtist, .releaseDate, .publisher, .copyright,
        .explicit, .credits,
    ]

    /// The semantic identity this row edits. `nil` means display-only.
    var metadataFieldKey: MetadataFieldKey? {
        switch self {
        case .title: .title
        case .artist: .artist
        case .album: .album
        case .composer: .composer
        case .genre: .genre
        case .year: .year
        case .date: .standaloneDate
        case .releaseDate: .releaseDate
        case .originalReleaseDate: .originalReleaseDate
        case .trackNumber: .track
        case .totalTracks: .trackTotal
        case .discNumber: .disc
        case .totalDiscs: .discTotal
        case .comment: .comment
        case .albumArtist: .albumArtist
        case .contentGroup: .contentGroup
        case .grouping: .grouping
        case .work: .work
        case .publisher: .publisher
        case .copyright: .copyright
        case .explicit: .explicitContent
        case .credits: nil
        }
    }
}
