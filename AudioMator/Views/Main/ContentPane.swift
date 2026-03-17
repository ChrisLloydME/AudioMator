import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    let selection: Binding<Set<AudioFile.ID>>
    let onAddFiles: () -> Void
    let onShowMetadataDump: () -> Void
    let onOpenTrackRenumber: () -> Void
    let onCancelEdits: () -> Void
    let onSaveEdits: () -> Void

    @FocusState private var tableFocused: Bool
    @State private var isEraseAllTagsConfirmPresented: Bool = false
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
        Group {
            if viewModel.files.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: emptyStateSymbol,
                    description: Text(emptyStateDescription)
                )
            } else {
                Table(orderedFiles, selection: selection) {
                    TableColumn("Filename") { file in
                        Text(file.url.lastPathComponent)
                            .onDrag {
                                // Ensure the order array is initialized before dragging
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
                    TableColumn("Title") { file in
                        Text(file.title)
                    }
                    TableColumn("Artist") { file in
                        Text(file.artist)
                    }
                    TableColumn("Album") { file in
                        Text(file.album)
                    }
                    TableColumn("Duration") { file in
                        Text(formatDuration(file.duration))
                    }
                }
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

                    Button("Erase All Tags…", role: .destructive) {
                        isEraseAllTagsConfirmPresented = true
                    }
                    .disabled(selectedFiles.isEmpty)
                }
                .confirmationDialog(
                    "Erase all tags?",
                    isPresented: $isEraseAllTagsConfirmPresented,
                    titleVisibility: .visible
                ) {
                    Button("Erase", role: .destructive) {
                        clearAllMetadataForSelectedFiles()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove metadata tags from the selected file(s). This action cannot be undone.")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onAddFiles) {
                    Image(systemName: "plus")
                }
                .help(isQuickImportMode ? "Add audio files to the current session" : "Switch to Current Session in the sidebar to add files")
                .disabled(!isQuickImportMode)

                Button(action: onShowMetadataDump) {
                    Label("Tag Inspector", systemImage: "doc.text.magnifyingglass")
                }
                .help("Show all metadata as text")
                .disabled(state.selectedAudioIDs.isEmpty)

                Button(action: onOpenTrackRenumber) {
                    Label("Renumber Tracks…", systemImage: "number")
                }
                .help("Rewrite Track Number (TRCK) by the middle list order")
                .disabled(viewModel.files.isEmpty)

                Button(role: .destructive) {
                    isClearListConfirmPresented = true
                } label: {
                    Label("Clear List", systemImage: "trash")
                }
                .help(isQuickImportMode ? "Remove all files from the current session list" : "Watched folder lists are managed from the sidebar")
                .disabled(!isQuickImportMode || viewModel.files.isEmpty)

                Button("Cancel", action: onCancelEdits)
                    .disabled(state.selectedAudioIDs.isEmpty)

                Button("Save", action: onSaveEdits)
                    .disabled(state.selectedAudioIDs.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear the current list?",
            isPresented: $isClearListConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Clear List", role: .destructive) {
                clearFileList()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes the loaded tracks from AudioMator. The original files on disk will not be deleted.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestClearListConfirmation)) { _ in
            guard isQuickImportMode, !viewModel.files.isEmpty else { return }
            isClearListConfirmPresented = true
        }
    }

    private var emptyStateTitle: String {
        switch currentSidebarSelection {
        case .quickImport:
            return "No Session Files"
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
            return "Add audio files for one-off edits. This list is cleared when AudioMator closes."
        case .watchedLibrary:
            if viewModel.watchedFolders.isEmpty {
                return "Add a folder from the sidebar to keep it available across launches and use it as a persistent file source."
            }
            return "AudioMator is watching the folders in the sidebar, but no supported audio files were found yet."
        case .watchedFolder(let folderID):
            if let folder = viewModel.watchedFolders.first(where: { $0.id == folderID }) {
                return "\(folder.displayName) does not contain any supported audio files yet."
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
