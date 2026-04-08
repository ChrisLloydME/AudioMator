import Foundation

enum ToolbarButtonOption: String, CaseIterable, Identifiable {
    case addFiles
    case tagInspector
    case renumberTracks
    case musicBrainzBrowser
    case renameFiles
    case importField
    case clearList
    case cancelEdits
    case saveEdits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .addFiles:
            return "Add Files"
        case .tagInspector:
            return "Tag Inspector"
        case .renumberTracks:
            return "Renumber Tracks"
        case .musicBrainzBrowser:
            return "MusicBrainz Browser"
        case .renameFiles:
            return "Rename Files"
        case .importField:
            return "Import Field"
        case .clearList:
            return "Clear List"
        case .cancelEdits:
            return "Cancel"
        case .saveEdits:
            return "Save"
        }
    }

    var systemImage: String {
        switch self {
        case .addFiles:
            return "plus"
        case .tagInspector:
            return "doc.text.magnifyingglass"
        case .renumberTracks:
            return "list.number.badge.ellipsis"
        case .musicBrainzBrowser:
            return "icloud.and.arrow.down"
        case .renameFiles:
            return "character.textbox"
        case .importField:
            return "arrow.down.doc"
        case .clearList:
            return "trash"
        case .cancelEdits:
            return "xmark.circle"
        case .saveEdits:
            return "square.and.arrow.down"
        }
    }

    static let defaultVisibleButtons: [ToolbarButtonOption] = Self.allCases
}
