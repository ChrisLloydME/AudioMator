import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
internal import UIKit
#endif

struct ContentPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let selection: Binding<Set<AudioFile.ID>>
    let onAddFiles: () -> Void
    let onShowMetadataDump: () -> Void
    let onOpenMusicBrainzBrowser: () -> Void
    let onOpenMetadataFilenameTool: ([AudioFile.ID]) -> Void
    let onOpenMetadataEditor: ([AudioFile.ID]) -> Void
    let onFindSelectedFileInMusicBrainz: () -> Void
    let onOpenTrackRenumber: () -> Void
    let onCancelEdits: () -> Void
    let onSaveEdits: () -> Void
    let isInspectorVisible: Bool
    let onToggleInspector: () -> Void

    @State private var isEraseAllTagsConfirmPresented: Bool = false
    @State private var isClearListConfirmPresented: Bool = false
    @State private var isTextMetadataImportPresented: Bool = false
    @State private var textMetadataImportTargets: [AudioFile] = []
    @State private var isFileImporterPresented: Bool = false

    private var currentSidebarSelection: SidebarSelection {
        state.selectedSidebarItem ?? .quickImport
    }

    private var isQuickImportMode: Bool {
        state.currentFileSourceMode == .quickImport
    }

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
    }

    private var visibleToolbarButtons: Set<ToolbarButtonOption> {
        state.visibleToolbarButtons
    }

    private var orderedFiles: [AudioFile] {
        state.orderedMiddleListFiles(from: viewModel.files)
    }

    var body: some View {
        mainContent
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if visibleToolbarButtons.contains(.addFiles) {
                        Button(action: addFilesAction) {
                            Image(systemName: "plus")
                        }
                        .help(isQuickImportMode ? "Add files to this session" : "Select Current Session in the sidebar to add files")
                        .disabled(!isQuickImportMode)
                    }

                    if visibleToolbarButtons.contains(.clearList) {
                        Button(role: .destructive) {
                            isClearListConfirmPresented = true
                        } label: {
                            Label(ToolbarButtonOption.clearList.displayName, systemImage: ToolbarButtonOption.clearList.systemImage)
                        }
                        .help(isQuickImportMode ? "Clear this session list" : "Manage watched folders in the sidebar")
                        .disabled(!isQuickImportMode || viewModel.files.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.renumberTracks) {
                        Button(action: onOpenTrackRenumber) {
                            Label("Renumber Tracks…", systemImage: ToolbarButtonOption.renumberTracks.systemImage)
                        }
                        .help("Renumber tracks in list order")
                        .disabled(viewModel.files.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.renameFiles) {
                        #if os(macOS)
                        Button(action: openMetadataFilenameRenameSheet) {
                            Label("Filename & Metadata…", systemImage: ToolbarButtonOption.renameFiles.systemImage)
                        }
                        .help("Convert between filenames and metadata for the selected files")
                        .disabled(state.selectedAudioIDs.isEmpty)
                        #endif
                    }

                    if visibleToolbarButtons.contains(.metadataEditor) {
                        #if os(macOS)
                        Button(action: openMetadataEditorWindow) {
                            Label("Metadata Editor…", systemImage: ToolbarButtonOption.metadataEditor.systemImage)
                        }
                        .help("Edit the selected metadata fields in a separate window")
                        .disabled(state.selectedAudioIDs.isEmpty)
                        #endif
                    }

                    if visibleToolbarButtons.contains(.importField) {
                        #if os(macOS)
                        Button(action: openTextMetadataImportSheet) {
                            Label("Import Field…", systemImage: ToolbarButtonOption.importField.systemImage)
                        }
                        .help("Import one field from a text file")
                        .disabled(state.selectedAudioIDs.isEmpty)
                        #endif
                    }

                    if visibleToolbarButtons.contains(.tagInspector) {
                        #if os(macOS)
                        Button(action: onShowMetadataDump) {
                            Label(ToolbarButtonOption.tagInspector.displayName, systemImage: ToolbarButtonOption.tagInspector.systemImage)
                        }
                        .help("View raw metadata")
                        .disabled(state.selectedAudioIDs.isEmpty)
                        #endif
                    }

                    if visibleToolbarButtons.contains(.musicBrainzBrowser) {
                        #if os(macOS)
                        Button(action: onOpenMusicBrainzBrowser) {
                            Label(ToolbarButtonOption.musicBrainzBrowser.displayName, systemImage: ToolbarButtonOption.musicBrainzBrowser.systemImage)
                        }
                        .help("Open MusicBrainz Browser")
                        #endif
                    }

                    if visibleToolbarButtons.contains(.cancelEdits) {
                        Button("Cancel", action: onCancelEdits)
                            .disabled(state.selectedAudioIDs.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.saveEdits) {
                        Button("Save", action: onSaveEdits)
                            .disabled(state.selectedAudioIDs.isEmpty || viewModel.metadataSaveProgress != nil)
                    }

                    Button(action: onToggleInspector) {
                        Image(systemName: "sidebar.right")
                    }
                    .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
                }
            }
            .confirmationDialog(
                "Clear this list?",
                isPresented: $isClearListConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Clear List", role: .destructive) {
                    clearFileList()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the loaded tracks from AudioMator only. Files on disk stay unchanged.")
            }
            .sheet(isPresented: $isTextMetadataImportPresented) {
                TextMetadataImportSheet(
                    viewModel: viewModel,
                    targetFiles: textMetadataImportTargets,
                    isPresented: $isTextMetadataImportPresented
                )
            }
            #if !os(macOS)
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: AudioFormatSupport.openPanelContentTypes,
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                viewModel.importQuickFiles(from: urls)
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .requestClearListConfirmation)) { _ in
                guard isQuickImportMode, !viewModel.files.isEmpty else { return }
                isClearListConfirmPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMetadataFilenameRename)) { _ in
                guard !state.selectedAudioIDs.isEmpty else { return }
                openMetadataFilenameRenameSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMetadataEditor)) { _ in
                guard !state.selectedAudioIDs.isEmpty else { return }
                openMetadataEditorWindow()
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if viewModel.files.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: emptyStateSymbol,
                    description: Text(emptyStateDescription)
                )
            } else {
                #if os(macOS)
                MiddleListTable(
                    files: orderedFiles,
                    selection: selection,
                    visibleColumns: $state.visibleMiddleListColumns,
                    customOrder: $state.customOrder,
                    middleListSort: $state.middleListSort,
                    onOpenSelectedFiles: openSelectedFiles,
                    onRevealSelectedFilesInFinder: revealSelectedFilesInFinder,
                    onCopySelectedFilePaths: copySelectedFilePaths,
                    onCopySelectedFileNames: copySelectedFileNames,
                    onFindSelectedFileInMusicBrainz: onFindSelectedFileInMusicBrainz,
                    onRequestEraseAllTags: { isEraseAllTagsConfirmPresented = true }
                )
                .onChange(of: state.selectedAudioIDs) { _, newSelection in
                    viewModel.selectedAudioIDs = newSelection
                    viewModel.updateEditForSelection()
                }
                .onAppear {
                    syncSelectionWithFiles()
                    viewModel.selectedAudioIDs = state.selectedAudioIDs
                    viewModel.updateEditForSelection()
                    syncCustomOrderWithFiles()
                }
                .onChange(of: viewModel.files.map { $0.id }) {
                    syncSelectionWithFiles()
                    viewModel.selectedAudioIDs = state.selectedAudioIDs
                    viewModel.updateEditForSelection()
                    syncCustomOrderWithFiles()
                }
                .confirmationDialog(
                    "Erase all metadata tags?",
                    isPresented: $isEraseAllTagsConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("Erase", role: .destructive) {
                        clearAllMetadataForSelectedFiles()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes metadata from the selected files. This can't be undone.")
                }
                #else
                List(orderedFiles, selection: selection) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.title.isEmpty ? file.url.lastPathComponent : file.title)
                            .font(.body)
                            .lineLimit(1)
                        Text(file.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(file.id)
                }
                .onChange(of: state.selectedAudioIDs) { _, newSelection in
                    viewModel.selectedAudioIDs = newSelection
                    viewModel.updateEditForSelection()
                }
                .onAppear {
                    syncSelectionWithFiles()
                    viewModel.selectedAudioIDs = state.selectedAudioIDs
                    viewModel.updateEditForSelection()
                    syncCustomOrderWithFiles()
                }
                .onChange(of: viewModel.files.map { $0.id }) {
                    syncSelectionWithFiles()
                    viewModel.selectedAudioIDs = state.selectedAudioIDs
                    viewModel.updateEditForSelection()
                    syncCustomOrderWithFiles()
                }
                #endif
            }
        }
    }

    private func addFilesAction() {
        #if os(macOS)
        onAddFiles()
        #else
        guard isQuickImportMode else { return }
        isFileImporterPresented = true
        #endif
    }

    private var emptyStateTitle: String {
        switch currentSidebarSelection {
        case .quickImport:
            return "No Files in Session"
        case .watchedLibrary:
            return viewModel.watchedFolders.isEmpty ? "No Watched Folders" : "No Audio Files Found"
        case .watchedFolder:
            return "No Audio Files Found"
        }
    }

    private var emptyStateSymbol: String {
        switch currentSidebarSelection {
        case .quickImport:
            return "bolt.horizontal.circle"
        case .watchedLibrary where viewModel.watchedFolders.isEmpty:
            return "folder.badge.plus"
        case .watchedLibrary:
            return "folder.badge.gearshape"
        case .watchedFolder:
            return "folder"
        }
    }

    private var emptyStateDescription: String {
        switch currentSidebarSelection {
        case .quickImport:
            return "Add audio files for one-off edits. This list clears when AudioMator closes."
        case .watchedLibrary:
            if viewModel.watchedFolders.isEmpty {
                return "Add a watched folder from the sidebar to keep it available across launches."
            }
            return "AudioMator is watching these folders, but no supported audio files have appeared yet."
        case .watchedFolder(let folderID):
            if let folder = viewModel.watchedFolders.first(where: { $0.id == folderID }) {
                return "\(folder.displayName) doesn't contain any supported audio files yet."
            }
            return "Select a watched folder from the sidebar or add a new one."
        }
    }

    private func syncSelectionWithFiles() {
        let validIDs = Set(viewModel.files.map(\.id))
        let prunedSelection = state.selectedAudioIDs.intersection(validIDs)

        if prunedSelection != state.selectedAudioIDs {
            state.selectedAudioIDs = prunedSelection
        }
    }

    private func syncCustomOrderWithFiles() {
        let ids = viewModel.files.map { $0.id }
        let idSet = Set(ids)

        if state.customOrder.isEmpty {
            state.customOrder = ids
            return
        }

        // Remove ids that no longer exist
        state.customOrder.removeAll { !idSet.contains($0) }

        // Append newly added ids
        let existing = Set(state.customOrder)
        for id in ids where !existing.contains(id) {
            state.customOrder.append(id)
        }
    }

    private func openTextMetadataImportSheet() {
        textMetadataImportTargets = orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }

        guard !textMetadataImportTargets.isEmpty else { return }
        isTextMetadataImportPresented = true
    }

    private func openMetadataFilenameRenameSheet() {
        let targets = orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }

        guard !targets.isEmpty else { return }
        if let failure = viewModel.ensureRenameDirectoryAccess(for: targets.map(\.url)) {
            viewModel.presentMetadataWriteHUD(
                style: .warning,
                title: "Folder Access Needed",
                subtitle: failure
            )
            return
        }

        onOpenMetadataFilenameTool(targets.map(\.id))
    }

    private func openMetadataEditorWindow() {
        let targets = orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        onOpenMetadataEditor(targets.map(\.id))
    }

    private func openSelectedFiles() {
        #if os(macOS)
        for file in selectedFiles {
            NSWorkspace.shared.open(file.url)
        }
        #else
        guard let url = selectedFiles.first?.url else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func revealSelectedFilesInFinder() {
        #if os(macOS)
        let urls = selectedFiles.map { $0.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #else
        openSelectedFiles()
        #endif
    }

    private func copySelectedFilePaths() {
        let text = selectedFiles.map { $0.url.path }.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func copySelectedFileNames() {
        let text = selectedFiles.map { $0.url.lastPathComponent }.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func clearAllMetadataForSelectedFiles() {
        // Best-effort erase using TagLib bridge. This is a user-facing action.
        for file in selectedFiles {
            viewModel.eraseAllMetadata(file)
        }
    }

    private func clearFileList() {
        guard isQuickImportMode else { return }
        viewModel.clearList()
        state.selectedAudioIDs.removeAll()
        state.customOrder.removeAll()
    }
}
