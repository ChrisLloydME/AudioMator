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
    @Published var selectedAudioID: AudioFile.ID?
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
                    selection: Binding(
                        get: { state.selectedAudioID },
                        set: { state.selectedAudioID = $0 }
                    )
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

    var body: some View {
        Group {
            if let file = selectedFile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileSection(file)
                        artworkSection(file)
                        metadataSection(file)
                        technicalSection(file)
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

    private var selectedFile: AudioFile? {
        guard let id = state.selectedAudioID else { return nil }
        return viewModel.files.first { $0.id == id }
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
                metadataRow(label: "Title", value: file.title)
                Divider()
                metadataRow(label: "Artist", value: file.artist)
                Divider()
                metadataRow(label: "Album", value: file.album)
                Divider()
                metadataRow(label: "Composer", value: file.composer)
                Divider()
                metadataRow(label: "Genre", value: file.genre)
                Divider()
                metadataRow(label: "Year", value: file.year)
                Divider()
                metadataRow(label: "Track", value: "\(file.track) / \(file.trackTotal)")
                Divider()
                metadataRow(label: "Disc", value: "\(file.disc) / \(file.discTotal)")
                Divider()
                metadataRow(label: "Comment", value: file.comment)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.body)
            Spacer()
            Text(value ?? "—")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
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
