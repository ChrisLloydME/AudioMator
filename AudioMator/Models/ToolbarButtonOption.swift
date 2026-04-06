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

    static let defaultVisibleButtons: [ToolbarButtonOption] = Self.allCases
}
