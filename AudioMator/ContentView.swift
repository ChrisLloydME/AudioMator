//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI
import AppKit
import Combine

final class SharedState: ObservableObject {
    @Published var selectedSidebarItem: String? = "all"
    @Published var selectedAudioIDs: Set<AudioFile.ID> = []
}

struct ContentView: View {
    @StateObject private var viewModel = AudioViewModel()
    @StateObject private var state = SharedState()

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
                    viewModel.files,
                    selection: $state.selectedAudioIDs
                ) {
                    TableColumn("Filename") { file in
                        Text(file.url.lastPathComponent)
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
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
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

                // Read-only fields – still来自当前文件的合并视图
                metadataRow(label: "Album Artist", value: file.albumArtist)
                Divider()
                metadataRow(label: "Release Date", value: file.releasingTime)
                Divider()
                metadataRow(label: "Publisher", value: file.publisher)
                Divider()
                metadataRow(label: "Copyright", value: file.copyright)
                Divider()
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

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
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
        releaseDate = merge(files.map { $0.releasingTime })
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
