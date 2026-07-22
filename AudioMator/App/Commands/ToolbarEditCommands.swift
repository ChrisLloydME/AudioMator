#if os(macOS)
import SwiftUI

struct ToolbarEditCommands: Commands {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var sharedState: SharedState

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Select All") {
                NotificationCenter.default.post(name: .requestSelectAllTracks, object: nil)
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button {
                viewModel.addFiles()
            } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(sharedState.currentFileSourceMode != .quickImport)

            Button {
                Self.performAddWatchedFolders(using: viewModel.addWatchedFolders)
            } label: {
                Label("Add Watched Folder…", systemImage: "folder.badge.plus")
            }

            Button {
                NotificationCenter.default.post(name: .requestMetadataDump, object: nil)
            } label: {
                Label(ToolbarButtonOption.tagInspector.displayName, systemImage: ToolbarButtonOption.tagInspector.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestTrackRenumber, object: nil)
            } label: {
                Label("Renumber Tracks…", systemImage: ToolbarButtonOption.renumberTracks.systemImage)
            }
            .disabled(viewModel.files.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMetadataFilenameRename, object: nil)
            } label: {
                Label(ToolbarButtonOption.renameFiles.displayName + "…", systemImage: ToolbarButtonOption.renameFiles.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestMetadataEditor, object: nil)
            } label: {
                Label(ToolbarButtonOption.metadataEditor.displayName + "…", systemImage: ToolbarButtonOption.metadataEditor.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                NotificationCenter.default.post(name: .requestOnlineMetadataBrowser, object: nil)
            } label: {
                Label(ToolbarButtonOption.onlineMetadataBrowser.displayName, systemImage: ToolbarButtonOption.onlineMetadataBrowser.systemImage)
            }

            Button(role: .destructive) {
                NotificationCenter.default.post(name: .requestClearListConfirmation, object: nil)
            } label: {
                Label(ToolbarButtonOption.clearList.displayName, systemImage: ToolbarButtonOption.clearList.systemImage)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(sharedState.currentFileSourceMode != .quickImport || viewModel.files.isEmpty)

            Divider()

            Button {
                viewModel.cancelEditing()
            } label: {
                Label("Cancel Edits", systemImage: ToolbarButtonOption.cancelEdits.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)

            Button {
                viewModel.saveSingleEdits()
            } label: {
                Label("Save Edits", systemImage: ToolbarButtonOption.saveEdits.systemImage)
            }
            .disabled(sharedState.selectedAudioIDs.isEmpty)
        }
    }

    static func performAddWatchedFolders(
        using addWatchedFolders: () -> SidebarSelection?,
        notificationCenter: NotificationCenter = .default
    ) {
        guard let selection = addWatchedFolders() else { return }
        notificationCenter.post(name: .requestSidebarSelectionChange, object: selection)
    }
}
#endif
