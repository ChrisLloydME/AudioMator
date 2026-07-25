import Foundation

enum InspectorMetadataField: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case composer
    case genre
    case year
    case trackNumber
    case totalTracks
    case discNumber
    case totalDiscs
    case comment
    case albumArtist
    case releaseDate
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
        case .releaseDate:
            return L10n.string("Release Date")
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
}
