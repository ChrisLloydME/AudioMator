#if os(iOS)
import SwiftUI

struct IPadWorkspaceView: View {
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

    @State private var isSelectionMode: Bool = false
    @State private var isClearListConfirmPresented: Bool = false
    @State private var isEraseAllTagsConfirmPresented: Bool = false
    @State private var isTextMetadataImportPresented: Bool = false
    @State private var textMetadataImportTargets: [AudioFile] = []

    private var orderedFiles: [AudioFile] {
        state.orderedMiddleListFiles(from: viewModel.files)
    }

    private var selectedFiles: [AudioFile] {
        orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }
    }

    var body: some View {
        NavigationSplitView {
            primaryColumn
        } detail: {
            IPadInspectorView(
                viewModel: viewModel,
                state: state,
                onCancelEdits: onCancelEdits,
                onSaveEdits: onSaveEdits
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: onAddFiles) {
                    Image(systemName: "plus")
                }
                .help("Add files")

                Button(isSelectionMode ? "Done" : "Select") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isSelectionMode.toggle()
                    }
                }
                .disabled(orderedFiles.isEmpty)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("MusicBrainz Browser", action: onOpenMusicBrainzBrowser)
                    Button("Tag Inspector", action: onShowMetadataDump)
                        .disabled(state.selectedAudioIDs.isEmpty)
                    Button("Filename & Metadata…", action: openMetadataFilenameRenameSheet)
                        .disabled(state.selectedAudioIDs.isEmpty)
                    Button("Metadata Editor…", action: openMetadataEditorWindow)
                        .disabled(state.selectedAudioIDs.isEmpty)
                    Button("Import Field…", action: openTextMetadataImportSheet)
                        .disabled(state.selectedAudioIDs.isEmpty)
                    Button("Renumber Tracks…", action: onOpenTrackRenumber)
                        .disabled(orderedFiles.isEmpty)
                    Divider()
                    Button("Clear List", role: .destructive) {
                        isClearListConfirmPresented = true
                    }
                    .disabled(orderedFiles.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isTextMetadataImportPresented) {
            TextMetadataImportSheet(
                viewModel: viewModel,
                targetFiles: textMetadataImportTargets,
                isPresented: $isTextMetadataImportPresented
            )
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
        .onAppear {
            syncSelectionWithFiles()
            syncViewModelSelection()
            syncCustomOrderWithFiles()
        }
        .onChange(of: state.selectedAudioIDs) { _, _ in
            syncViewModelSelection()
        }
        .onChange(of: viewModel.files.map(\.id)) { _, _ in
            syncSelectionWithFiles()
            syncViewModelSelection()
            syncCustomOrderWithFiles()
        }
    }

    @ViewBuilder
    private var primaryColumn: some View {
        Group {
            if orderedFiles.isEmpty {
                ContentUnavailableView(
                    "No Files in Session",
                    systemImage: "music.note.list",
                    description: Text("Add audio files for one-off edits. iPadOS keeps AudioMator in session mode only.")
                )
            } else {
                IPadFileBrowserView(
                    files: orderedFiles,
                    selection: selection,
                    customOrder: $state.customOrder,
                    middleListSort: $state.middleListSort,
                    isSelectionMode: $isSelectionMode,
                    onOpenSelectedFiles: openSelectedFiles,
                    onCopySelectedFilePaths: copySelectedFilePaths,
                    onCopySelectedFileNames: copySelectedFileNames,
                    onFindSelectedFileInMusicBrainz: onFindSelectedFileInMusicBrainz,
                    onRequestEraseAllTags: { isEraseAllTagsConfirmPresented = true }
                )
            }
        }
        .navigationTitle("Current Session")
        .background(Color(platformColor: .audiomatorWindowBackground))
        .safeAreaInset(edge: .bottom) {
            if !selectedFiles.isEmpty {
                selectionActionBar
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedFiles.count) Selected")
                    .font(.subheadline.weight(.semibold))
                Text(selectedFiles.first?.url.lastPathComponent ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("MusicBrainz", action: onFindSelectedFileInMusicBrainz)
                .buttonStyle(.bordered)

            Button("Rename", action: openMetadataFilenameRenameSheet)
                .buttonStyle(.bordered)

            Menu {
                Button("Metadata Editor…", action: openMetadataEditorWindow)
                Button("Import Field…", action: openTextMetadataImportSheet)
                Button("Raw Metadata", action: onShowMetadataDump)
                Divider()
                Button("Erase All Tags", role: .destructive) {
                    isEraseAllTagsConfirmPresented = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private extension IPadWorkspaceView {
    func syncViewModelSelection() {
        viewModel.selectedAudioIDs = state.selectedAudioIDs
        viewModel.updateEditForSelection()
    }

    func syncSelectionWithFiles() {
        let validIDs = Set(viewModel.files.map(\.id))
        let prunedSelection = state.selectedAudioIDs.intersection(validIDs)
        if prunedSelection != state.selectedAudioIDs {
            state.selectedAudioIDs = prunedSelection
        }
    }

    func syncCustomOrderWithFiles() {
        let ids = viewModel.files.map(\.id)
        let idSet = Set(ids)

        if state.customOrder.isEmpty {
            state.customOrder = ids
            return
        }

        state.customOrder.removeAll { !idSet.contains($0) }

        let existing = Set(state.customOrder)
        for id in ids where !existing.contains(id) {
            state.customOrder.append(id)
        }
    }

    func openTextMetadataImportSheet() {
        textMetadataImportTargets = orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }
        guard !textMetadataImportTargets.isEmpty else { return }
        isTextMetadataImportPresented = true
    }

    func openMetadataFilenameRenameSheet() {
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

    func openMetadataEditorWindow() {
        let targets = orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        onOpenMetadataEditor(targets.map(\.id))
    }

    func openSelectedFiles() {
        for file in selectedFiles {
            PlatformWorkspace.open(file.url)
        }
    }

    func copySelectedFilePaths() {
        PlatformPasteboard.copy(selectedFiles.map { $0.url.path }.joined(separator: "\n"))
    }

    func copySelectedFileNames() {
        PlatformPasteboard.copy(selectedFiles.map { $0.url.lastPathComponent }.joined(separator: "\n"))
    }

    func clearAllMetadataForSelectedFiles() {
        for file in selectedFiles {
            viewModel.eraseAllMetadata(file)
        }
    }

    func clearFileList() {
        viewModel.clearList()
        state.selectedAudioIDs.removeAll()
        state.customOrder.removeAll()
    }
}
#endif
