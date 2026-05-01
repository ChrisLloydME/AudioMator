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
    let onOpenSettings: () -> Void
    let onCancelEdits: () -> Void
    let onSaveEdits: () -> Void

    @State private var isSelectionMode: Bool = false
    @State private var isClearListConfirmPresented: Bool = false
    @State private var isEraseAllTagsConfirmPresented: Bool = false
    @State private var isTextMetadataImportPresented: Bool = false
    @State private var textMetadataImportTargets: [AudioFile] = []

    private let inspectorWidthRatio: CGFloat = 0.42
    private let minimumInspectorWidth: CGFloat = 360
    private let maximumInspectorWidth: CGFloat = 520
    private let horizontalLayoutMinimumWidth: CGFloat = 860

    private var orderedFiles: [AudioFile] {
        state.orderedMiddleListFiles(from: viewModel.files)
    }

    private var selectedFiles: [AudioFile] {
        orderedFiles.filter { state.selectedAudioIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                workspaceContent(for: geometry.size)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(platformColor: .audiomatorWindowBackground))
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: onAddFiles) {
                        Label("Add Files", systemImage: "plus")
                    }
                    .help("Add audio files to this session")

                    Button(isSelectionMode ? "Done" : "Select") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isSelectionMode.toggle()
                        }
                    }
                    .disabled(orderedFiles.isEmpty)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu

                    Menu {
                        Button("MusicBrainz Browser", action: onOpenMusicBrainzBrowser)
                        Button("Tag Inspector", action: onShowMetadataDump)
                            .disabled(state.selectedAudioIDs.isEmpty)
                        Button("Filename & Metadata...", action: openMetadataFilenameRenameSheet)
                            .disabled(state.selectedAudioIDs.isEmpty)
                        Button("Metadata Editor...", action: openMetadataEditorWindow)
                            .disabled(state.selectedAudioIDs.isEmpty)
                        Button("Import Field...", action: openTextMetadataImportSheet)
                            .disabled(state.selectedAudioIDs.isEmpty)
                        Button("Renumber Tracks...", action: onOpenTrackRenumber)
                            .disabled(orderedFiles.isEmpty)
                        Divider()
                        Button {
                            onOpenSettings()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Divider()
                        Button("Clear List", role: .destructive) {
                            isClearListConfirmPresented = true
                        }
                        .disabled(orderedFiles.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isTextMetadataImportPresented) {
            IPadDismissibleSheet(title: "Import Metadata Field") {
                TextMetadataImportSheet(
                    viewModel: viewModel,
                    targetFiles: textMetadataImportTargets,
                    isPresented: $isTextMetadataImportPresented
                )
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
    private func workspaceContent(for size: CGSize) -> some View {
        if orderedFiles.isEmpty {
            emptySessionView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size.width >= horizontalLayoutMinimumWidth {
            HStack(spacing: 0) {
                primaryColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                inspectorColumn
                    .frame(width: inspectorWidth(for: size.width))
                    .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                primaryColumn
                    .frame(maxWidth: .infinity, maxHeight: max(320, size.height * 0.48))

                inspectorColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            leftColumnTitle

            IPadFileBrowserView(
                files: orderedFiles,
                selection: selection,
                customOrder: $state.customOrder,
                middleListSort: $state.middleListSort,
                metadataFields: state.iPadLeftListMetadataFields,
                isSelectionMode: $isSelectionMode,
                onOpenSelectedFiles: openSelectedFiles,
                onCopySelectedFilePaths: copySelectedFilePaths,
                onCopySelectedFileNames: copySelectedFileNames,
                onFindSelectedFileInMusicBrainz: onFindSelectedFileInMusicBrainz,
                onRequestEraseAllTags: { isEraseAllTagsConfirmPresented = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(platformColor: .audiomatorWindowBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectedFiles.isEmpty {
                selectionActionBar
            }
        }
    }

    private var inspectorColumn: some View {
        IPadInspectorView(
            viewModel: viewModel,
            state: state,
            onCancelEdits: onCancelEdits,
            onSaveEdits: onSaveEdits
        )
    }

    private var leftColumnTitle: some View {
        Text("AudioMator")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color(platformColor: .audiomatorWindowBackground))
    }

    private var emptySessionView: some View {
        ContentUnavailableView {
            Label("No Files in Session", systemImage: "music.note.list")
        } description: {
            Text("Add audio files for one-off metadata edits.")
        } actions: {
            Button(action: onAddFiles) {
                Label("Add Files", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func inspectorWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(totalWidth * inspectorWidthRatio, minimumInspectorWidth), maximumInspectorWidth)
    }

    private var sortMenu: some View {
        Menu {
            Button {
                state.middleListSort = nil
            } label: {
                if state.middleListSort == nil {
                    Label("Manual Order", systemImage: "checkmark")
                } else {
                    Text("Manual Order")
                }
            }
            .disabled(state.middleListSort == nil)

            Divider()

            ForEach(MiddleListColumn.allCases) { column in
                Menu(column.displayName) {
                    sortButton(for: column, ascending: true)
                    sortButton(for: column, ascending: false)
                }
            }
        } label: {
            Label(sortButtonTitle, systemImage: "arrow.up.arrow.down")
        }
        .disabled(orderedFiles.isEmpty)
    }

    private func sortButton(for column: MiddleListColumn, ascending: Bool) -> some View {
        Button {
            state.middleListSort = MiddleListSort(column: column, ascending: ascending)
        } label: {
            let title = ascending ? "Ascending" : "Descending"
            if state.middleListSort == MiddleListSort(column: column, ascending: ascending) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var sortButtonTitle: String {
        guard let middleListSort = state.middleListSort else {
            return "Sort by Manual Order"
        }

        let direction = middleListSort.ascending ? "Ascending" : "Descending"
        return "Sort by \(middleListSort.column.displayName), \(direction)"
    }

    private var selectionActionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedFiles.count) Selected")
                    .font(.subheadline.weight(.semibold))
                Text(selectedFiles.first?.url.lastPathComponent ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
        }
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
        viewModel.eraseAllMetadata(selectedFiles)
    }

    func clearFileList() {
        viewModel.clearList()
        state.selectedAudioIDs.removeAll()
        state.customOrder.removeAll()
    }
}
#endif
