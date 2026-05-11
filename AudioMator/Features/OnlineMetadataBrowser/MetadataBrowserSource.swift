import Foundation

enum MetadataBrowserSource: String, CaseIterable, Identifiable {
    case musicBrainz
    case iTunes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .musicBrainz: return "MusicBrainz"
        case .iTunes: return "iTunes"
        }
    }

    var subtitle: String {
        switch self {
        case .musicBrainz:
            return "Search rich community metadata, release relationships, credits, and MusicBrainz IDs."
        case .iTunes:
            return "Search Apple iTunes catalog text metadata from tags, filenames, UPCs, links, and store IDs."
        }
    }

    var symbolName: String {
        switch self {
        case .musicBrainz: return "brain.head.profile"
        case .iTunes: return "music.note.list"
        }
    }
}
