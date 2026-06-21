import SwiftUI
import UniformTypeIdentifiers

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

    @AppStorage(museAmpSupportEnabledDefaultsKey) private var isMuseAmpSupportEnabled: Bool = false

    @State private var isEraseAllTagsConfirmPresented: Bool = false
    @State private var isMuseAmpIDConfirmPresented: Bool = false
    @State private var isClearListConfirmPresented: Bool = false

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

    private var shouldShowFileListToolbarGroup: Bool {
        isQuickImportMode &&
            (visibleToolbarButtons.contains(.addFiles) || visibleToolbarButtons.contains(.clearList))
    }

    private var shouldShowMetadataWorkflowToolbarGroup: Bool {
        visibleToolbarButtons.contains(.renumberTracks) ||
            visibleToolbarButtons.contains(.renameFiles) ||
            visibleToolbarButtons.contains(.musicBrainzBrowser)
    }

    private var shouldShowMetadataToolsToolbarGroup: Bool {
        visibleToolbarButtons.contains(.tagInspector) ||
            visibleToolbarButtons.contains(.metadataEditor)
    }

    private var orderedFiles: [AudioFile] {
        state.orderedMiddleListFiles(from: viewModel.files)
    }

    var body: some View {
        mainContent
            .toolbar {
                if shouldShowFileListToolbarGroup {
                    ToolbarItem(placement: .primaryAction) {
                        fileListToolbarGroup
                    }
                }

                if shouldShowMetadataWorkflowToolbarGroup {
                    ToolbarItem(placement: .primaryAction) {
                        metadataWorkflowToolbarGroup
                    }
                }

                if shouldShowMetadataToolsToolbarGroup {
                    ToolbarItem(placement: .primaryAction) {
                        metadataToolsToolbarGroup
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    trailingToolbarButtons
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
    private var trailingToolbarButtons: some View {
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
                    onRequestCreateMuseAmpIDs: { isMuseAmpIDConfirmPresented = true },
                    onRequestEraseAllTags: { isEraseAllTagsConfirmPresented = true },
                    isMuseAmpSupportEnabled: isMuseAmpSupportEnabled,
                    isMuseAmpIDCreationEnabled: viewModel.metadataSaveProgress == nil
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
                    "Create MuseAmp IDs?",
                    isPresented: $isMuseAmpIDConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("Create IDs", role: .destructive) {
                        createMuseAmpIDsForSelectedFiles()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This replaces the Comment field on the selected files with MuseAmp ID data, then saves the files.")
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
            }
        }
    }

    @ViewBuilder
    private var fileListToolbarGroup: some View {
        ControlGroup {
            if visibleToolbarButtons.contains(.addFiles) {
                Button(action: onAddFiles) {
                    toolbarIconLabel(ToolbarButtonOption.addFiles.displayName, systemImage: ToolbarButtonOption.addFiles.systemImage)
                }
                .help("Add files to this session")
            }

            if visibleToolbarButtons.contains(.clearList) {
                Button(role: .destructive) {
                    isClearListConfirmPresented = true
                } label: {
                    toolbarIconLabel(ToolbarButtonOption.clearList.displayName, systemImage: ToolbarButtonOption.clearList.systemImage)
                }
                .help("Clear this session list")
                .disabled(viewModel.files.isEmpty)
            }
        } label: {
            Label("File List", systemImage: ToolbarButtonOption.addFiles.systemImage)
        }
        .toolbarControlGroupCompatibilityStyle()
    }

    @ViewBuilder
    private var metadataWorkflowToolbarGroup: some View {
        ControlGroup {
            if visibleToolbarButtons.contains(.renumberTracks) {
                Button(action: onOpenTrackRenumber) {
                    toolbarIconLabel("Renumber Tracks…", systemImage: ToolbarButtonOption.renumberTracks.systemImage)
                }
                .help("Renumber tracks in list order")
                .disabled(viewModel.files.isEmpty)
            }

            if visibleToolbarButtons.contains(.renameFiles) {
                Button(action: openMetadataFilenameRenameSheet) {
                    toolbarIconLabel(ToolbarButtonOption.renameFiles.displayName + "…", systemImage: ToolbarButtonOption.renameFiles.systemImage)
                }
                .help("Convert between filenames and metadata for the selected files")
                .disabled(state.selectedAudioIDs.isEmpty)
            }

            if visibleToolbarButtons.contains(.musicBrainzBrowser) {
                Button(action: onOpenMusicBrainzBrowser) {
                    toolbarIconLabel(ToolbarButtonOption.musicBrainzBrowser.displayName, systemImage: ToolbarButtonOption.musicBrainzBrowser.systemImage)
                }
                .help(L10n.string("Open Online Metadata"))
            }
        } label: {
            Label("Metadata Tools", systemImage: ToolbarButtonOption.renameFiles.systemImage)
        }
        .toolbarControlGroupCompatibilityStyle()
    }

    @ViewBuilder
    private var metadataToolsToolbarGroup: some View {
        ControlGroup {
            if visibleToolbarButtons.contains(.tagInspector) {
                Button(action: onShowMetadataDump) {
                    toolbarIconLabel(ToolbarButtonOption.tagInspector.displayName, systemImage: ToolbarButtonOption.tagInspector.systemImage)
                }
                .help("View raw metadata")
                .disabled(state.selectedAudioIDs.isEmpty)
            }

            if visibleToolbarButtons.contains(.metadataEditor) {
                Button(action: openMetadataEditorWindow) {
                    toolbarIconLabel(ToolbarButtonOption.metadataEditor.displayName + "…", systemImage: ToolbarButtonOption.metadataEditor.systemImage)
                }
                .help("Edit the selected metadata fields in a separate window")
                .disabled(state.selectedAudioIDs.isEmpty)
            }
        } label: {
            Label("Metadata Inspectors", systemImage: ToolbarButtonOption.tagInspector.systemImage)
        }
        .toolbarControlGroupCompatibilityStyle()
    }

    private func toolbarIconLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private var emptyStateTitle: String {
        switch currentSidebarSelection {
        case .quickImport:
            return L10n.string("No Files in Session")
        case .watchedLibrary:
            return viewModel.watchedFolders.isEmpty ? "No Watched Folders" : "No Audio Files Found"
        case .watchedFolder:
            return L10n.string("No Audio Files Found")
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
        for file in selectedFiles {
            PlatformWorkspace.open(file.url)
        }
    }

    private func revealSelectedFilesInFinder() {
        let urls = selectedFiles.map { $0.url }
        guard !urls.isEmpty else { return }
        PlatformWorkspace.reveal(urls)
    }

    private func copySelectedFilePaths() {
        let text = selectedFiles.map { $0.url.path }.joined(separator: "\n")
        PlatformPasteboard.copy(text)
    }

    private func copySelectedFileNames() {
        let text = selectedFiles.map { $0.url.lastPathComponent }.joined(separator: "\n")
        PlatformPasteboard.copy(text)
    }

    private func clearAllMetadataForSelectedFiles() {
        viewModel.eraseAllMetadata(selectedFiles)
    }

    private func createMuseAmpIDsForSelectedFiles() {
        viewModel.createMuseAmpIDs(for: selectedFiles)
    }

    private func clearFileList() {
        guard isQuickImportMode else { return }
        viewModel.clearList()
        state.selectedAudioIDs.removeAll()
        state.customOrder.removeAll()
    }
}

private extension View {
    @ViewBuilder
    func toolbarControlGroupCompatibilityStyle() -> some View {
        #if os(macOS)
        if #available(macOS 27.0, *) {
            controlGroupStyle(.navigation)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
