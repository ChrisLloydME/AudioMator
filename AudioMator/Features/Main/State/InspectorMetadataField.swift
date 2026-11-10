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
        switch self {
        case .title:
            return L10n.string("Title")
        case .artist:
            return L10n.string("Artist")
        case .album:
            return L10n.string("Album")
        case .composer:
            return L10n.string("Composer")
        case .genre:
            return L10n.string("Genre")
        case .year:
            return L10n.string("Year")
        case .date:
            return L10n.string("Date")
        case .releaseDate:
            return L10n.string("Release Date")
        case .originalReleaseDate:
            return L10n.string("Original Release Date")
        case .trackNumber:
            return L10n.string("Track Number")
        case .totalTracks:
            return L10n.string("Total Tracks")
        case .discNumber:
            return L10n.string("Disc Number")
        case .totalDiscs:
            return L10n.string("Total Discs")
        case .comment:
            return L10n.string("Comment")
        case .albumArtist:
            return L10n.string("Album Artist")
        case .contentGroup:
            return L10n.string("Content Group")
        case .grouping:
            return L10n.string("Grouping")
        case .work:
            return L10n.string("Work")
        case .publisher:
            return L10n.string("Publisher")
        case .copyright:
            return L10n.string("Copyright")
        case .explicit:
            return L10n.string("Explicit")
        case .credits:
            return L10n.string("Credits")
        }
    }

    static let defaultVisibleFields: [InspectorMetadataField] = Self.allCases

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
