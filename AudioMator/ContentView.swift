//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//


import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Helpers
fileprivate func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

// MARK: - Read-only monospaced text view (AppKit-backed)
struct ReadOnlyMonospacedTextView: NSViewRepresentable {
    var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        // Seed initial content (SwiftUI may not call update before first draw in some sheet transitions)
        textView.string = text

        // Allow horizontal scrolling for very long lines
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Important: give the container an effectively unbounded width so the scroll view can scroll horizontally
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Give the document view a non-zero frame so it actually renders inside the scroll view
        textView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Avoid resetting selection/scroll if the text didn't actually change
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }
}

final class SharedState: ObservableObject {
    @Published var selectedSidebarItem: String? = "all"
    @Published var selectedAudioIDs: Set<AudioFile.ID> = []

    // Custom ordering for the middle list (session-only)
    @Published var customOrder: [AudioFile.ID] = []

    // Drag source tracking for row reordering
    @Published var draggingAudioID: AudioFile.ID? = nil
}

struct ContentView: View {
    @StateObject private var viewModel = AudioViewModel()
    @StateObject private var state = SharedState()

    // Full metadata dump (user-facing feature)
    @State private var isMetadataDumpPresented: Bool = false
    @State private var metadataDumpText: String = ""

    var body: some View {
        NavigationSplitView {
            SidebarPane(state: state)
        } content: {
            ContentPane(viewModel: viewModel, state: state)
        } detail: {
            InspectorPane(viewModel: viewModel, state: state)
                .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            // 导入文件按钮
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.addFiles) {
                    Image(systemName: "plus")
                }
            }

            // Print / Show all metadata (user-facing)
            ToolbarItem(placement: .automatic) {
                Button {
                    presentMetadataDump()
                } label: {
                    Label("Tag Inspector", systemImage: "doc.text.magnifyingglass")
                }
                .help("Show all metadata as text")
                .disabled(state.selectedAudioIDs.isEmpty)
            }

            // 取消 / 保存（单文件编辑）
            ToolbarItemGroup(placement: .automatic) {
                Button("Cancel") {
                    viewModel.cancelEditing()
                }
                .disabled(state.selectedAudioIDs.isEmpty)

                Button("Save") {
                    viewModel.saveSingleEdits()
                }
                .disabled(state.selectedAudioIDs.isEmpty)
            }
        }
        .sheet(isPresented: $isMetadataDumpPresented) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tag Inspector")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(metadataDumpText, forType: .string)
                    }
                }

                Text("Shows a raw TagLib metadata dump (properties + frames) for the selected file(s).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ReadOnlyMonospacedTextView(text: metadataDumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                           ? "(No TagLib metadata to display)"
                                           : metadataDumpText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.08))
                    )

                HStack {
                    Spacer()
                    Button("Close") {
                        isMetadataDumpPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(16)
            .frame(width: 760, height: 560)
        }
    }
}

struct SidebarPane: View {
    @ObservedObject var state: SharedState

    var body: some View {
        List(selection: $state.selectedSidebarItem) {
            Section("Library") {
                Text("All Audio")
                    .tag("all" as String?)
            }
        }
        .listStyle(.sidebar)
    }
}

struct ContentPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState
    @FocusState private var tableFocused: Bool
    @State private var isEraseAllTagsConfirmPresented: Bool = false

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
            if let f = map[id] {
                result.append(f)
            }
        }

        // Append any new files that are not in the order array yet (e.g. newly imported)
        let existing = Set(result.map { $0.id })
        for f in viewModel.files where !existing.contains(f.id) {
            result.append(f)
        }

        return result
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

    var body: some View {
        Group {
            if viewModel.files.isEmpty {
                ContentUnavailableView(
                    "No Audio Files",
                    systemImage: "music.note.list",
                    description: Text("Click the add button in the toolbar to import audio files")
                )
            } else {
                Table(
                    orderedFiles,
                    selection: $state.selectedAudioIDs
                ) {
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
                .onChange(of: state.selectedAudioIDs) { newSelection in
                    // 将中间列表的选中同步到 ViewModel，并刷新右侧 Inspector 的编辑模型
                    viewModel.selectedAudioIDs = newSelection
                    viewModel.updateEditForSelection()
                }
                .onAppear {
                    // 初次出现时也同步一次，以防已有选中状态
                    viewModel.selectedAudioIDs = state.selectedAudioIDs
                    viewModel.updateEditForSelection()
                    syncCustomOrderWithFiles()
                }
                .onChange(of: viewModel.files.map { $0.id }) { _ in
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
    }


}

struct InspectorPane: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    @State private var inspectorQuickLabel: String = ""
    @State private var inspectorQuickText: String = ""
    @State private var inspectorQuickBinding: Binding<String>? = nil
    @State private var isInspectorQuickPresented: Bool = false

    private var inspectorQuickPreview: String {
        let text = inspectorQuickText
        if text.isEmpty {
            return " "
        }
        return text.replacingOccurrences(of: " ", with: "·")
    }

    private func binding(for file: AudioFile,
                         keyPath: WritableKeyPath<SingleFileEditModel, String>) -> Binding<String> {
        Binding<String>(
            get: {
                viewModel.edit?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                if var current = viewModel.edit {
                    current[keyPath: keyPath] = newValue
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model[keyPath: keyPath] = newValue
                    viewModel.edit = model
                }
            }
        )
    }
    
    private func boolBinding(for file: AudioFile,
                             keyPath: WritableKeyPath<SingleFileEditModel, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                viewModel.edit?[keyPath: keyPath] ?? false
            },
            set: { newValue in
                if var current = viewModel.edit {
                    current[keyPath: keyPath] = newValue
                    viewModel.edit = current
                } else {
                    var model = SingleFileEditModel(from: file)
                    model[keyPath: keyPath] = newValue
                    viewModel.edit = model
                }
            }
        )
    }

    var body: some View {
        Group {
            if selectedFiles.count == 1, let file = selectedFiles.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileSection(file)
                        artworkSection(file)
                        metadataSection(file)
                        technicalSection(file)
                    }
                    .padding()
                }
            } else if selectedFiles.count > 1 {
                let merged = MergedAudioFile(files: selectedFiles)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        mergedMetadataSection(merged)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select an Audio File",
                    systemImage: "music.quarternote.3"
                )
            }
        }
        .sheet(isPresented: $isInspectorQuickPresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit \(inspectorQuickLabel)")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Main editable area – monospaced like an editor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inspectorQuickText)
                        .font(.system(.body, design: .monospaced))
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .frame(minHeight: 80, idealHeight: 140)

                    // Hint text when empty
                    if inspectorQuickText.isEmpty {
                        Text("Enter text…")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }

                // Preview area with label
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(inspectorQuickPreview)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isInspectorQuickPresented = false
                    }
                    Button("Save") {
                        inspectorQuickBinding?.wrappedValue = inspectorQuickText
                        isInspectorQuickPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 480)
        }
    }

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
    }

    @ViewBuilder
    private func fileSection(_ file: AudioFile) -> some View {
        GroupBox("File") {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func artworkSection(_ file: AudioFile) -> some View {
        GroupBox("Artwork") {
            VStack {
                if let image = file.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200)
                        .cornerRadius(8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 200, height: 200)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func metadataSection(_ file: AudioFile) -> some View {
        GroupBox("Metadata") {
            VStack(spacing: 6) {
                // Editable fields – bound directly into viewModel.edit
                editableRow(label: "Title", text: binding(for: file, keyPath: \.title))
                Divider()
                editableRow(label: "Artist", text: binding(for: file, keyPath: \.artist))
                Divider()
                editableRow(label: "Album", text: binding(for: file, keyPath: \.album))
                Divider()
                editableRow(label: "Composer", text: binding(for: file, keyPath: \.composer))
                Divider()
                editableRow(label: "Genre", text: binding(for: file, keyPath: \.genre))
                Divider()
                editableRow(label: "Year", text: binding(for: file, keyPath: \.year))
                Divider()
                editableRow(label: "Comment", text: binding(for: file, keyPath: \.comment))
                Divider()

                // Additional editable fields
                editableRow(label: "Album Artist", text: binding(for: file, keyPath: \.albumArtist))
                Divider()
                editableRow(label: "Release Date", text: binding(for: file, keyPath: \.releaseDate))
                Divider()
                editableRow(label: "Publisher", text: binding(for: file, keyPath: \.publisher))
                Divider()
                editableRow(label: "Copyright", text: binding(for: file, keyPath: \.copyright))
                Divider()
                explicitRow(label: "Explicit", isOn: boolBinding(for: file, keyPath: \.isExplicit))
                Divider()

                // Still read-only (not yet editable via TagLib bridge)
                metadataRow(label: "Credits", value: file.credits)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox("Technical Info") {
            VStack(spacing: 0) {
                metadataRow(label: "Duration", value: formatDuration(file.duration))
                Divider()
                metadataRow(label: "Bitrate", value: "\(file.bitrate) kbps")
                Divider()
                metadataRow(label: "Sample Rate", value: "\(Int(file.sampleRate)) Hz")
                Divider()
                metadataRow(label: "Channels", value: "\(file.channels)")
                Divider()
                metadataRow(label: "Format", value: file.format)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.headline)   // bold
            Spacer()
            Text(value ?? "—")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .trailing)
        }
        .padding(.vertical, 14)    // balanced vertical centering between dividers
    }

    @ViewBuilder
    private func editableRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 220, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            inspectorQuickLabel = label
            inspectorQuickText = text.wrappedValue
            inspectorQuickBinding = text
            isInspectorQuickPresented = true
        }
        .padding(.vertical, 14)
    }
    
    @ViewBuilder
    private func explicitRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.headline)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
        .padding(.vertical, 14)
    }

}

#Preview {
    ContentView()
}

struct MergedAudioFile {
    let title: String
    let artist: String
    let album: String
    let composer: String
    let genre: String
    let year: String
    let track: String
    let disc: String
    let comment: String
    let albumArtist: String
    let releaseDate: String
    let publisher: String
    let copyright: String
    let credits: String

    init(files: [AudioFile]) {
        func merge(_ values: [String]) -> String {
            guard let first = values.first else { return "—" }
            return values.allSatisfy { $0 == first } ? first : "—"
        }

        title = merge(files.map { $0.title })
        artist = merge(files.map { $0.artist })
        album = merge(files.map { $0.album })
        composer = merge(files.map { $0.composer })
        genre = merge(files.map { $0.genre })
        year = merge(files.map { $0.year })
        track = merge(files.map { "\($0.track) / \($0.trackTotal)" })
        disc = merge(files.map { "\($0.disc) / \($0.discTotal)" })
        comment = merge(files.map { $0.comment })
        albumArtist = merge(files.map { $0.albumArtist })
        releaseDate = merge(files.map { $0.releaseDate })
        publisher = merge(files.map { $0.publisher })
        copyright = merge(files.map { $0.copyright })
        credits = merge(files.map { $0.credits })
    }
}

@ViewBuilder
private func metadataRow(label: String, value: String?) -> some View {
    HStack(alignment: .center, spacing: 12) {
        Text(label)
            .font(.headline)
        Spacer()
        Text(value ?? "—")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 220, alignment: .trailing)
    }
    .padding(.vertical, 14)
}

@ViewBuilder
private func mergedMetadataSection(_ m: MergedAudioFile) -> some View {
    GroupBox("Metadata (Multiple Files)") {
        VStack(spacing: 6) {
            metadataRow(label: "Title", value: m.title)
            Divider()
            metadataRow(label: "Artist", value: m.artist)
            Divider()
            metadataRow(label: "Album", value: m.album)
            Divider()
            metadataRow(label: "Composer", value: m.composer)
            Divider()
            metadataRow(label: "Genre", value: m.genre)
            Divider()
            metadataRow(label: "Year", value: m.year)
            Divider()
            metadataRow(label: "Track", value: m.track)
            Divider()
            metadataRow(label: "Disc", value: m.disc)
            Divider()
            metadataRow(label: "Comment", value: m.comment)
            Divider()
            metadataRow(label: "Album Artist", value: m.albumArtist)
            Divider()
            metadataRow(label: "Release Date", value: m.releaseDate)
            Divider()
            metadataRow(label: "Publisher", value: m.publisher)
            Divider()
            metadataRow(label: "Copyright", value: m.copyright)
            Divider()
            metadataRow(label: "Credits", value: m.credits)
        }
        .padding(.vertical, 4)
    }
}



// MARK: - Full metadata dump (user-facing)
extension ContentView {
    private func presentMetadataDump() {
        let selected = viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
        metadataDumpText = buildTagLibDump(for: selected)
        isMetadataDumpPresented = true
    }

    /// Produces a best-effort *raw* metadata dump using the TagLib bridge.
    ///
    /// This intentionally does **not** re-print the already-normalized fields shown in the right inspector.
    private func buildTagLibDump(for files: [AudioFile]) -> String {
        guard !files.isEmpty else { return "(No selection)" }

        // Single selection: show only the raw dump.
        if files.count == 1, let file = files.first {
            return buildTagLibDump(for: file.url)
        }

        // Multiple selection: concatenate per-file dumps.
        return files.map { buildTagLibDump(for: $0.url) }
            .joined(separator: "\n\n")
    }

    /// Produces a best-effort *raw* metadata dump using the TagLib bridge.
    private func buildTagLibDump(for url: URL) -> String {
        if let text = TagLibMetadataManager.rawMetadataText(from: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        return [
            "File: \(url.lastPathComponent)",
            "Path: \(url.path)",
            "",
            "(No TagLib metadata to display. The file may contain no readable tags, or the TagLib bridge returned an empty result.)"
        ].joined(separator: "\n")
    }
}
