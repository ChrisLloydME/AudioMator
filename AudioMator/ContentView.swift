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
                Text("所有音频")
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
                    "没有音频文件",
                    systemImage: "music.note.list",
                    description: Text("点击右上角添加按钮导入音频文件")
                )
            } else {
                Table(
                    viewModel.files,
                    selection: Binding(
                        get: { state.selectedAudioID },
                        set: { state.selectedAudioID = $0 }
                    )
                ) {
                    TableColumn("文件名") { file in
                        Text(file.url.lastPathComponent)
                    }
                    TableColumn("标题") { file in
                        Text(file.title ?? "—")
                    }
                    TableColumn("艺术家") { file in
                        Text(file.artist ?? "—")
                    }
                    TableColumn("专辑") { file in
                        Text(file.album ?? "—")
                    }
                    TableColumn("时长") { file in
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
                        metadataSection(file)
                        technicalSection(file)
                        artworkSection(file)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "选择一个音频文件",
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
        GroupBox("文件") {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                Text(file.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let size = file.fileSize {
                    Text(fileSizeString(bytes: size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func metadataSection(_ file: AudioFile) -> some View {
        GroupBox("元数据") {
            LabeledContent("标题") { Text(file.title ?? "—") }
            LabeledContent("艺术家") { Text(file.artist ?? "—") }
            LabeledContent("专辑") { Text(file.album ?? "—") }
            LabeledContent("作曲") { Text(file.composer ?? "—") }
            LabeledContent("风格") { Text(file.genre ?? "—") }
            LabeledContent("年份") { Text(file.year.map(String.init) ?? "—") }
            LabeledContent("曲目") { Text(file.trackNumber.map(String.init) ?? "—") }
            LabeledContent("碟号") { Text(file.discNumber.map(String.init) ?? "—") }
            LabeledContent("备注") { Text(file.comments ?? "—") }
        }
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox("技术") {
            LabeledContent("时长") { Text(formatDuration(file.duration)) }
            LabeledContent("比特率") { Text(file.bitrate.map { "\($0) kbps" } ?? "—") }
            LabeledContent("采样率") { Text(file.sampleRate.map { String(format: "%.0f Hz", $0) } ?? "—") }
            LabeledContent("声道") { Text(file.channels.map(String.init) ?? "—") }
            LabeledContent("格式") { Text(file.fileFormat ?? "—") }
        }
    }

    @ViewBuilder
    private func artworkSection(_ file: AudioFile) -> some View {
        GroupBox("封面") {
            if let artwork = file.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .cornerRadius(12)
                    .shadow(radius: 6)
            } else {
                ContentUnavailableView("无封面", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func formatDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func fileSizeString(bytes: Int?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    ContentView()
}
