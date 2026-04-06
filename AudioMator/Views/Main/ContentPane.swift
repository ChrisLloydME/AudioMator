import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let selection: Binding<Set<AudioFile.ID>>
    let onAddFiles: () -> Void
    let onShowMetadataDump: () -> Void
    let onOpenMusicBrainzBrowser: () -> Void
    let onFindSelectedFileInMusicBrainz: () -> Void
    let onOpenTrackRenumber: () -> Void
    let onCancelEdits: () -> Void
    let onSaveEdits: () -> Void

    @FocusState private var tableFocused: Bool
    @State private var isEraseAllTagsConfirmPresented: Bool = false
    @State private var isClearListConfirmPresented: Bool = false
    @State private var isTextMetadataImportPresented: Bool = false
    @State private var textMetadataImportTargets: [AudioFile] = []
    @State private var isMetadataFilenameRenamePresented: Bool = false
    @State private var metadataFilenameRenameTargetIDs: [AudioFile.ID] = []

    private var currentSidebarSelection: SidebarSelection {
        state.selectedSidebarItem ?? .quickImport
    }

    private var isQuickImportMode: Bool {
        state.currentFileSourceMode == .quickImport
    }

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
    }

    private var hasSelectedFiles: Bool {
        !selectedFiles.isEmpty
    }

    private var visibleColumns: Set<MiddleListColumn> {
        state.visibleMiddleListColumns
    }

    private var visibleToolbarButtons: Set<ToolbarButtonOption> {
        state.visibleToolbarButtons
    }

    private var orderedFiles: [AudioFile] {
        // If no custom order yet, fall back to the raw array order
        if state.customOrder.isEmpty {
            return viewModel.files
        }

        // Map ids -> file and emit in custom order
        let map = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        var result: [AudioFile] = []
        result.reserveCapacity(viewModel.files.count)

        for id in state.customOrder {
            if let file = map[id] {
                result.append(file)
            }
        }

        // Append any new files that are not in the order array yet (e.g. newly imported)
        let existing = Set(result.map { $0.id })
        for file in viewModel.files where !existing.contains(file.id) {
            result.append(file)
        }

        return result
    }

    var body: some View {
        mainContent
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if visibleToolbarButtons.contains(.addFiles) {
                        Button(action: onAddFiles) {
                            Image(systemName: "plus")
                        }
                        .help(isQuickImportMode ? "Add files to this session" : "Select Current Session in the sidebar to add files")
                        .disabled(!isQuickImportMode)
                    }

                    if visibleToolbarButtons.contains(.tagInspector) {
                        Button(action: onShowMetadataDump) {
                            Label("Tag Inspector", systemImage: "doc.text.magnifyingglass")
                        }
                        .help("View raw metadata")
                        .disabled(state.selectedAudioIDs.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.renumberTracks) {
                        Button(action: onOpenTrackRenumber) {
                            Label("Renumber Tracks…", systemImage: "number")
                        }
                        .help("Renumber tracks in list order")
                        .disabled(viewModel.files.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.musicBrainzBrowser) {
                        Button(action: onOpenMusicBrainzBrowser) {
                            Label("MusicBrainz Browser", systemImage: "network")
                        }
                        .help("Open MusicBrainz Browser")
                    }

                    if visibleToolbarButtons.contains(.renameFiles) {
                        Button(action: openMetadataFilenameRenameSheet) {
                            Label("Rename Files…", systemImage: "pencil.line")
                        }
                        .help("Rename selected files from metadata")
                        .disabled(state.selectedAudioIDs.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.importField) {
                        Button(action: openTextMetadataImportSheet) {
                            Label("Import Field…", systemImage: "square.and.arrow.down")
                        }
                        .help("Import one field from a text file")
                        .disabled(state.selectedAudioIDs.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.clearList) {
                        Button(role: .destructive) {
                            isClearListConfirmPresented = true
                        } label: {
                            Label("Clear List", systemImage: "trash")
                        }
                        .help(isQuickImportMode ? "Clear this session list" : "Manage watched folders in the sidebar")
                        .disabled(!isQuickImportMode || viewModel.files.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.cancelEdits) {
                        Button("Cancel", action: onCancelEdits)
                            .disabled(state.selectedAudioIDs.isEmpty)
                    }

                    if visibleToolbarButtons.contains(.saveEdits) {
                        Button("Save", action: onSaveEdits)
                            .disabled(state.selectedAudioIDs.isEmpty)
                    }
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
            .sheet(isPresented: $isMetadataFilenameRenamePresented) {
                MetadataFilenameRenameSheet(
                    viewModel: viewModel,
                    targetFileIDs: metadataFilenameRenameTargetIDs,
                    isPresented: $isMetadataFilenameRenamePresented
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestClearListConfirmation)) { _ in
                guard isQuickImportMode, !viewModel.files.isEmpty else { return }
                isClearListConfirmPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestMetadataFilenameRename)) { _ in
                guard !state.selectedAudioIDs.isEmpty else { return }
                openMetadataFilenameRenameSheet()
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
                Table(orderedFiles, selection: selection) {
                    primaryMetadataColumns
                    secondaryMetadataColumns
                    auxiliaryMetadataColumns
                    technicalMetadataColumns
                }
                .background(
                    MiddleListHeaderContextMenuInstaller(
                        visibleColumns: $state.visibleMiddleListColumns
                    )
                )
                .focused($tableFocused)
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
                .contextMenu {
                    Button("Open") {
                        openSelectedFiles()
                    }
                    .disabled(selectedFiles.isEmpty)

                    Button("Reveal in Finder") {
                        revealSelectedFilesInFinder()
                    }
                    .disabled(selectedFiles.isEmpty)

                    Divider()

                    Button("Copy Path") {
                        copySelectedFilePaths()
                    }
                    .disabled(selectedFiles.isEmpty)

                    Button("Copy Filename") {
                        copySelectedFileNames()
                    }
                    .disabled(selectedFiles.isEmpty)

                    Divider()

                    Button("Find in MusicBrainz") {
                        onFindSelectedFileInMusicBrainz()
                    }
                    .disabled(!hasSelectedFiles)

                    Divider()

                    Button("Erase All Tags…", role: .destructive) {
                        isEraseAllTagsConfirmPresented = true
                    }
                    .disabled(selectedFiles.isEmpty)
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

    @TableColumnBuilder<AudioFile, Never>
    private var primaryMetadataColumns: some TableColumnContent<AudioFile, Never> {
        if visibleColumns.contains(.filename) {
            TableColumn(MiddleListColumn.filename.displayName) { file in
                middleListCell(for: file, column: .filename)
            }
        }
        if visibleColumns.contains(.title) {
            TableColumn(MiddleListColumn.title.displayName) { file in
                middleListCell(for: file, column: .title)
            }
        }
        if visibleColumns.contains(.artist) {
            TableColumn(MiddleListColumn.artist.displayName) { file in
                middleListCell(for: file, column: .artist)
            }
        }
        if visibleColumns.contains(.album) {
            TableColumn(MiddleListColumn.album.displayName) { file in
                middleListCell(for: file, column: .album)
            }
        }
        if visibleColumns.contains(.albumArtist) {
            TableColumn(MiddleListColumn.albumArtist.displayName) { file in
                middleListCell(for: file, column: .albumArtist)
            }
        }
        if visibleColumns.contains(.composer) {
            TableColumn(MiddleListColumn.composer.displayName) { file in
                middleListCell(for: file, column: .composer)
            }
        }
    }

    @TableColumnBuilder<AudioFile, Never>
    private var secondaryMetadataColumns: some TableColumnContent<AudioFile, Never> {
        if visibleColumns.contains(.genre) {
            TableColumn(MiddleListColumn.genre.displayName) { file in
                middleListCell(for: file, column: .genre)
            }
        }
        if visibleColumns.contains(.year) {
            TableColumn(MiddleListColumn.year.displayName) { file in
                middleListCell(for: file, column: .year)
            }
        }
        if visibleColumns.contains(.track) {
            TableColumn(MiddleListColumn.track.displayName) { file in
                middleListCell(for: file, column: .track)
            }
        }
        if visibleColumns.contains(.disc) {
            TableColumn(MiddleListColumn.disc.displayName) { file in
                middleListCell(for: file, column: .disc)
            }
        }
        if visibleColumns.contains(.comment) {
            TableColumn(MiddleListColumn.comment.displayName) { file in
                middleListCell(for: file, column: .comment)
            }
        }
    }

    @TableColumnBuilder<AudioFile, Never>
    private var auxiliaryMetadataColumns: some TableColumnContent<AudioFile, Never> {
        if visibleColumns.contains(.releaseDate) {
            TableColumn(MiddleListColumn.releaseDate.displayName) { file in
                middleListCell(for: file, column: .releaseDate)
            }
        }
        if visibleColumns.contains(.publisher) {
            TableColumn(MiddleListColumn.publisher.displayName) { file in
                middleListCell(for: file, column: .publisher)
            }
        }
        if visibleColumns.contains(.copyright) {
            TableColumn(MiddleListColumn.copyright.displayName) { file in
                middleListCell(for: file, column: .copyright)
            }
        }
        if visibleColumns.contains(.credits) {
            TableColumn(MiddleListColumn.credits.displayName) { file in
                middleListCell(for: file, column: .credits)
            }
        }
        if visibleColumns.contains(.explicit) {
            TableColumn(MiddleListColumn.explicit.displayName) { file in
                middleListCell(for: file, column: .explicit)
            }
        }
    }

    @TableColumnBuilder<AudioFile, Never>
    private var technicalMetadataColumns: some TableColumnContent<AudioFile, Never> {
        if visibleColumns.contains(.duration) {
            TableColumn(MiddleListColumn.duration.displayName) { file in
                middleListCell(for: file, column: .duration)
            }
        }
        if visibleColumns.contains(.bitrate) {
            TableColumn(MiddleListColumn.bitrate.displayName) { file in
                middleListCell(for: file, column: .bitrate)
            }
        }
        if visibleColumns.contains(.sampleRate) {
            TableColumn(MiddleListColumn.sampleRate.displayName) { file in
                middleListCell(for: file, column: .sampleRate)
            }
        }
        if visibleColumns.contains(.channels) {
            TableColumn(MiddleListColumn.channels.displayName) { file in
                middleListCell(for: file, column: .channels)
            }
        }
        if visibleColumns.contains(.format) {
            TableColumn(MiddleListColumn.format.displayName) { file in
                middleListCell(for: file, column: .format)
            }
        }
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

    @ViewBuilder
    private func middleListCell(for file: AudioFile, column: MiddleListColumn) -> some View {
        Text(column.text(for: file))
            .lineLimit(1)
            .truncationMode(.tail)
            .onDrag {
                if state.customOrder.isEmpty {
                    state.customOrder = viewModel.files.map { $0.id }
                }
                state.draggingAudioID = file.id
                return NSItemProvider(object: file.id.uuidString as NSString)
            }
            .onDrop(
                of: [.text],
                delegate: FileReorderDropDelegate(
                    targetID: file.id,
                    customOrder: $state.customOrder,
                    draggingID: $state.draggingAudioID
                )
            )
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

        metadataFilenameRenameTargetIDs = targets.map(\.id)
        isMetadataFilenameRenamePresented = true
    }

    private func openSelectedFiles() {
        for file in selectedFiles {
            NSWorkspace.shared.open(file.url)
        }
    }

    private func revealSelectedFilesInFinder() {
        let urls = selectedFiles.map { $0.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func copySelectedFilePaths() {
        let text = selectedFiles.map { $0.url.path }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copySelectedFileNames() {
        let text = selectedFiles.map { $0.url.lastPathComponent }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        state.draggingAudioID = nil
    }
}

private struct FileReorderDropDelegate: DropDelegate {
    let targetID: AudioFile.ID
    @Binding var customOrder: [AudioFile.ID]
    @Binding var draggingID: AudioFile.ID?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        guard let fromIndex = customOrder.firstIndex(of: draggingID),
              let toIndex = customOrder.firstIndex(of: targetID) else { return }

        // Reorder immediately on hover for a responsive UX
        if fromIndex != toIndex {
            withAnimation(.default) {
                let from = IndexSet(integer: fromIndex)
                customOrder.move(fromOffsets: from, toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // no-op
    }
}
