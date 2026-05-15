import Foundation

enum MetadataBrowserSource: String, CaseIterable, Identifiable {
    case musicBrainz
    case iTunes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .musicBrainz: return L10n.string("MusicBrainz")
        case .iTunes: return L10n.string("iTunes")
        }
    }

    var subtitle: String {
        switch self {
        case .musicBrainz:
            return L10n.string("Search MusicBrainz metadata, release relationships, credits, and MusicBrainz IDs.")
        case .iTunes:
            return L10n.string("Search iTunes catalog metadata from tags, filenames, UPCs, links, and store IDs.")
        }
    }

    var symbolName: String {
        switch self {
        case .musicBrainz: return "brain.head.profile"
        case .iTunes: return "music.note.list"
        }
    }
}
