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
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.addFiles) {
                    Image(systemName: "plus")
                }
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
    
    @State private var editingMetadata = AudioMetadataEditor()

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
                .onAppear {
                    if let file = selectedFiles.first {
                        editingMetadata.title = file.title
                        editingMetadata.artist = file.artist
                        editingMetadata.album = file.album
                        editingMetadata.composer = file.composer
                        editingMetadata.genre = file.genre
                        editingMetadata.year = file.year
                        editingMetadata.comment = file.comment
                    }
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
                editableRow(label: "Title", text: $editingMetadata.title)
                Divider()
                editableRow(label: "Artist", text: $editingMetadata.artist)
                Divider()
                editableRow(label: "Album", text: $editingMetadata.album)
                Divider()
                editableRow(label: "Composer", text: $editingMetadata.composer)
                Divider()
                editableRow(label: "Genre", text: $editingMetadata.genre)
                Divider()
                editableRow(label: "Year", text: $editingMetadata.year)
                Divider()
                editableRow(label: "Comment", text: $editingMetadata.comment)
                Divider()
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
        }
        .padding(.vertical, 14)    // balanced vertical centering between dividers
    }

    @ViewBuilder
    private func editableRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.headline)
            Spacer()
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(.vertical, 14)
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct AudioMetadataEditor {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var composer: String = ""
    var genre: String = ""
    var year: String = ""
    var comment: String = ""
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
