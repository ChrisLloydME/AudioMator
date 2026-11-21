import SwiftUI
import UniformTypeIdentifiers

struct ContentPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let selection: Binding<Set<AudioFile.ID>>
    let onAddFiles: () -> Void
    let onShowMetadataDump: () -> Void
    let onOpenOnlineMetadataBrowser: () -> Void
    let onOpenMetadataFilenameTool: ([AudioFile.ID]) -> Void
    let onOpenMetadataEditor: ([AudioFile.ID]) -> Void
    let onFindSelectedFileInMusicBrainz: () -> Void
    let onOpenTrackRenumber: () -> Void

    @AppStorage(museAmpSupportEnabledDefaultsKey) private var isMuseAmpSupportEnabled: Bool = false

    @State private var pendingEraseAllCapture: ConfirmedSelectionActionCapture?
    @State private var pendingMuseAmpIDCapture: ConfirmedSelectionActionCapture?
    @State private var isClearListConfirmPresented: Bool = false
    @State private var isReloadDiscardConfirmPresented: Bool = false
    @State private var reloadDiscardToken: InspectorDiscardConfirmationToken?
    @State private var clearListDiscardToken: InspectorDiscardConfirmationToken?
    @State private var isReplacementFileAcceptConfirmPresented = false
    @State private var presentedReplacementReviews: [PendingReplacementFileReview] = []

    private var isEraseAllTagsConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingEraseAllCapture != nil },
            set: { if !$0 { pendingEraseAllCapture = nil } }
        )
    }

    private var isMuseAmpIDConfirmPresented: Binding<Bool> {
        Binding(
            get: { pendingMuseAmpIDCapture != nil },
            set: { if !$0 { pendingMuseAmpIDCapture = nil } }
        )
    }

    private func replacementFileReviewMessage(_ reviews: [PendingReplacementFileReview]) -> String {
        if reviews.count == 1, let review = reviews.first {
            let details = [review.title, review.artist]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            if details.isEmpty {
                return String(localized: "“\(review.fileName)” is now a different file on disk than the one AudioMator renamed. Accept this replacement file to resume editing it, or keep editing paused.")
            }
            return String(localized: "“\(review.fileName)” (\(details)) is now a different file on disk than the one AudioMator renamed. Accept this replacement file to resume editing it, or keep editing paused.")
        }
        let previewNames = reviews.prefix(3).map(\.fileName).joined(separator: ", ")
        return String(localized: "\(reviews.count) reloaded paths (\(previewNames)) now contain different files on disk than the ones AudioMator renamed. Accept these replacement files to resume editing them, or keep editing paused.")
    }

    private var currentSidebarSelection: SidebarSelection {
        state.selectedSidebarItem ?? .quickImport
    }

    private var isQuickImportMode: Bool {
        state.currentFileSourceMode == .quickImport
    }

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { viewModel.selectedAudioIDs.contains($0.id) }
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
            visibleToolbarButtons.contains(.onlineMetadataBrowser)
    }

    private var shouldShowMetadataToolsToolbarGroup: Bool {
        visibleToolbarButtons.contains(.tagInspector) ||
            visibleToolbarButtons.contains(.metadataEditor)
    }

    private var orderedFiles: [AudioFile] {
        middleListPresentation.files
    }

    private var middleListPresentation: MiddleListPresentation {
        state.middleListPresentation(from: viewModel.files, revision: viewModel.filesRevision)
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
            }
            .confirmationDialog(
                String(localized: "Discard edits and reload from disk?"),
                isPresented: $isReloadDiscardConfirmPresented,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Discard and Reload"), role: .destructive) {
                    let capturedToken = reloadDiscardToken
                    reloadDiscardToken = nil
                    guard let capturedToken, viewModel.isInspectorDiscardConfirmationCurrent(capturedToken) else {
                        if viewModel.hasUnsavedInspectorChanges {
                            reloadDiscardToken = viewModel.captureInspectorDiscardConfirmationToken()
                            isReloadDiscardConfirmPresented = true
                        }
                        return
                    }
                    viewModel.cancelEditing()
                    Task { await viewModel.reloadSelectedFilesFromDisk() }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    reloadDiscardToken = nil
                }
            } message: {
                Text(String(localized: "Unsaved inspector edits will be discarded. The files will be read again from disk."))
            }
            .confirmationDialog(
                "Clear this list?",
                isPresented: $isClearListConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Clear List", role: .destructive) {
                    let capturedToken = clearListDiscardToken
                    clearListDiscardToken = nil
                    guard let capturedToken, viewModel.isInspectorDiscardConfirmationCurrent(capturedToken) else {
                        clearListDiscardToken = viewModel.captureInspectorDiscardConfirmationToken()
                        isClearListConfirmPresented = true
                        return
                    }
                    if viewModel.hasUnsavedInspectorChanges {
                        viewModel.cancelEditing()
                    }
                    clearFileList()
                }
                Button("Cancel", role: .cancel) {
                    clearListDiscardToken = nil
                }
            } message: {
                if viewModel.hasUnsavedInspectorChanges {
                    Text(String(localized: "Unsaved inspector edits will be discarded, and the loaded tracks will be removed from AudioMator only. Files on disk stay unchanged."))
                } else {
                    Text("Removes the loaded tracks from AudioMator only. Files on disk stay unchanged.")
                }
            }
            .confirmationDialog(
                presentedReplacementReviews.count == 1
                    ? String(localized: "Accept replacement file?")
                    : String(localized: "Accept replacement files?"),
                isPresented: $isReplacementFileAcceptConfirmPresented,
                titleVisibility: .visible,
                presenting: presentedReplacementReviews
            ) { reviews in
                Button(String(localized: "Accept Replacement")) {
                    Task { await viewModel.acceptPendingReplacementFiles(reviews) }
                }
                Button(String(localized: "Keep Editing Paused"), role: .cancel) {
                    viewModel.dismissPendingReplacementFileReviews(reviews)
                }
            } message: { reviews in
                Text(replacementFileReviewMessage(reviews))
            }
            .onChange(of: viewModel.pendingReplacementFileReviews, initial: true) { _, reviews in
                if reviews.isEmpty {
                    isReplacementFileAcceptConfirmPresented = false
                } else if !isReplacementFileAcceptConfirmPresented {
                    presentedReplacementReviews = reviews
                    isReplacementFileAcceptConfirmPresented = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestClearListConfirmation)) { _ in
                guard isQuickImportMode, !viewModel.files.isEmpty else { return }
                clearListDiscardToken = viewModel.captureInspectorDiscardConfirmationToken()
                isClearListConfirmPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMetadataFilenameRename)) { _ in
                guard !viewModel.selectedAudioIDs.isEmpty else { return }
                openMetadataFilenameRenameSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMetadataEditor)) { _ in
                guard !viewModel.selectedAudioIDs.isEmpty else { return }
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
                let presentation = middleListPresentation
                MiddleListTable(
                    files: presentation.files,
                    filesRevision: presentation.revision,
                    selection: selection,
                    visibleColumns: $state.visibleMiddleListColumns,
                    customOrder: $state.customOrder,
                    middleListSort: $state.middleListSort,
                    onOpenSelectedFiles: openSelectedFiles,
                    onRevealSelectedFilesInFinder: revealSelectedFilesInFinder,
                    onCopySelectedFilePaths: copySelectedFilePaths,
                    onCopySelectedFileNames: copySelectedFileNames,
                    onFindSelectedFileInMusicBrainz: onFindSelectedFileInMusicBrainz,
                    onRequestCreateMuseAmpIDs: {
                        let capture = viewModel.captureConfirmedSelectionAction()
                        guard !capture.isEmpty else { return }
                        pendingMuseAmpIDCapture = capture
                    },
                    onRequestEraseAllTags: {
                        let capture = viewModel.captureConfirmedSelectionAction()
                        guard !capture.isEmpty else { return }
                        pendingEraseAllCapture = capture
                    },
                    onReloadSelectedFiles: {
                        if viewModel.hasUnsavedInspectorChanges {
                            reloadDiscardToken = viewModel.captureInspectorDiscardConfirmationToken()
                            isReloadDiscardConfirmPresented = true
                        } else {
                            Task { await viewModel.reloadSelectedFilesFromDisk() }
                        }
                    },
                    isFileReloadEnabled: viewModel.metadataSaveProgress == nil && !viewModel.isReloadingSelectedFiles,
                    isMuseAmpSupportEnabled: isMuseAmpSupportEnabled,
                    isMuseAmpIDCreationEnabled: viewModel.metadataSaveProgress == nil
                )
                .onAppear {
                    syncCustomOrderWithFiles()
                }
                .onChange(of: viewModel.filesRevision) {
                    syncCustomOrderWithFiles()
                }
                .confirmationDialog(
                    "Create MuseAmp IDs?",
                    isPresented: isMuseAmpIDConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("Create IDs", role: .destructive) {
                        guard let capture = pendingMuseAmpIDCapture else { return }
                        pendingMuseAmpIDCapture = nil
                        viewModel.executeConfirmedCreateMuseAmpIDs(capture)
                    }
                    Button("Cancel", role: .cancel) {
                        pendingMuseAmpIDCapture = nil
                    }
                } message: {
                    Text("This replaces the Comment field on the selected files with MuseAmp ID data, then saves the files.")
                }
                .confirmationDialog(
                    "Erase all metadata tags?",
                    isPresented: isEraseAllTagsConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("Erase", role: .destructive) {
                        guard let capture = pendingEraseAllCapture else { return }
                        pendingEraseAllCapture = nil
                        viewModel.executeConfirmedEraseAllMetadata(capture)
                    }
                    Button("Cancel", role: .cancel) {
                        pendingEraseAllCapture = nil
                    }
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
                    clearListDiscardToken = viewModel.captureInspectorDiscardConfirmationToken()
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
                .disabled(viewModel.selectedAudioIDs.isEmpty)
            }

            if visibleToolbarButtons.contains(.onlineMetadataBrowser) {
                Button(action: onOpenOnlineMetadataBrowser) {
                    toolbarIconLabel(ToolbarButtonOption.onlineMetadataBrowser.displayName, systemImage: ToolbarButtonOption.onlineMetadataBrowser.systemImage)
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
                .disabled(viewModel.selectedAudioIDs.isEmpty)
            }

            if visibleToolbarButtons.contains(.metadataEditor) {
                Button(action: openMetadataEditorWindow) {
                    toolbarIconLabel(ToolbarButtonOption.metadataEditor.displayName + "…", systemImage: ToolbarButtonOption.metadataEditor.systemImage)
                }
                .help("Edit the selected metadata fields in a separate window")
                .disabled(viewModel.selectedAudioIDs.isEmpty)
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
            return viewModel.watchedFolders.isEmpty ? "No Watched Folders" : String(localized: "No Audio Files to Show")
        case .watchedFolder:
            return L10n.string("No Audio Files to Show")
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

    private func syncCustomOrderWithFiles() {
        let ids = viewModel.files.map { $0.id }
        let idSet = Set(ids)

        if state.customOrder.isEmpty {
            state.customOrder = ids
            return
        }

        var order = state.customOrder.filter(idSet.contains)
        let existing = Set(order)
        for id in ids where !existing.contains(id) {
            order.append(id)
        }
        if order != state.customOrder {
            state.customOrder = order
        }
    }

    private func openMetadataFilenameRenameSheet() {
        let targets = orderedFiles.filter { viewModel.selectedAudioIDs.contains($0.id) }

        guard !targets.isEmpty else { return }
        // Opening the converter, typing a template and exporting text/CSV need
        // no mutation grant. The only scope request happens at Apply, for the
        // executable targets captured by that plan.
        onOpenMetadataFilenameTool(targets.map(\.id))
    }

    private func openMetadataEditorWindow() {
        let targets = orderedFiles.filter { viewModel.selectedAudioIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        onOpenMetadataEditor(targets.map(\.id))
    }

    private func openSelectedFiles() {
        for file in selectedFiles {
            MacWorkspace.open(file.url)
        }
    }

    private func revealSelectedFilesInFinder() {
        let urls = selectedFiles.map { $0.url }
        guard !urls.isEmpty else { return }
        MacWorkspace.reveal(urls)
    }

    private func copySelectedFilePaths() {
        let text = selectedFiles.map { $0.url.path }.joined(separator: "\n")
        MacPasteboard.copy(text)
    }

    private func copySelectedFileNames() {
        let text = selectedFiles.map { $0.url.lastPathComponent }.joined(separator: "\n")
        MacPasteboard.copy(text)
    }

    private func clearFileList() {
        guard isQuickImportMode else { return }
        viewModel.clearList()
        state.customOrder.removeAll()
    }
}

private extension View {
    @ViewBuilder
    func toolbarControlGroupCompatibilityStyle() -> some View {
        if #available(macOS 27.0, *) {
            controlGroupStyle(.navigation)
        } else {
            self
        }
    }
}
