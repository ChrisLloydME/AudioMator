import Foundation

enum ToolbarButtonOption: String, CaseIterable, Identifiable {
    case addFiles
    case tagInspector
    case renumberTracks
    case onlineMetadataBrowser = "musicBrainzBrowser"
    case renameFiles
    case metadataEditor
    case clearList
    case cancelEdits
    case saveEdits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .addFiles:
            return L10n.string("Add Files")
        case .tagInspector:
            return L10n.string("Tag Inspector")
        case .renumberTracks:
            return L10n.string("Renumber Tracks")
        case .onlineMetadataBrowser:
            return L10n.string("Online Metadata")
        case .renameFiles:
            return L10n.string("Filename & Metadata")
        case .metadataEditor:
            return L10n.string("Metadata Editor")
        case .clearList:
            return L10n.string("Clear List")
        case .cancelEdits:
            return L10n.string("Cancel")
        case .saveEdits:
            return L10n.string("Save")
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
        case .onlineMetadataBrowser:
            return "globe"
        case .renameFiles:
            return "arrow.trianglehead.2.clockwise"
        case .metadataEditor:
            return "long.text.page.and.pencil"
        case .clearList:
            return "text.badge.minus"
        case .cancelEdits:
            return "xmark.circle"
        case .saveEdits:
            return "checkmark.circle"
        }
    }

    var settingsDescription: String {
        switch self {
        case .addFiles:
            return L10n.string("Choose audio files for one-off editing in Current Session.")
        case .tagInspector:
            return L10n.string("Inspect a complete, read-only view of raw tags and file properties for troubleshooting.")
        case .renumberTracks:
            return L10n.string("Automatically assign track numbers from the order shown in the center list.")
        case .onlineMetadataBrowser:
            return L10n.string("Access metadata and lyrics from MusicBrainz, iTunes, and LRCLIB.")
        case .renameFiles:
            return L10n.string("Generate filenames, text, or CSV from metadata, or extract metadata from them.")
        case .metadataEditor:
            return L10n.string("Add, remove, and edit all available metadata fields for the selected files.")
        case .clearList:
            return L10n.string("Unload every track from Current Session without deleting files from disk.")
        case .cancelEdits:
            return L10n.string("Revert unsaved changes made in the Inspector.")
        case .saveEdits:
            return L10n.string("Write pending Inspector changes to the selected files.")
        }
    }

    static let defaultVisibleButtons: [ToolbarButtonOption] = Self.allCases
}
