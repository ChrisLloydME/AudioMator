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
            VStack(alignment: .leading, spacing: 0) {
                metadataRow(label: "标题", value: file.title)
                Divider()
                metadataRow(label: "艺术家", value: file.artist)
                Divider()
                metadataRow(label: "专辑", value: file.album)
                Divider()
                metadataRow(label: "作曲", value: file.composer)
                Divider()
                metadataRow(label: "风格", value: file.genre)
                Divider()
                metadataRow(label: "年份", value: file.year.map(String.init))
                Divider()
                metadataRow(label: "曲目", value: file.trackNumber.map(String.init))
                Divider()
                metadataRow(label: "碟号", value: file.discNumber.map(String.init))
                Divider()
                metadataRow(label: "备注", value: file.comments)
            }
            .padding(.vertical, 4)
        }
        .groupBoxStyle(.automatic)
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func technicalSection(_ file: AudioFile) -> some View {
        GroupBox("技术") {
            VStack(alignment: .leading, spacing: 0) {
                technicalRow(label: "时长", value: formatDuration(file.duration))
                Divider()
                technicalRow(label: "比特率", value: file.bitrate.map { "\($0) kbps" })
                Divider()
                technicalRow(label: "采样率", value: file.sampleRate.map { String(format: "%.0f Hz", $0) })
                Divider()
                technicalRow(label: "声道", value: file.channels.map(String.init))
                Divider()
                technicalRow(label: "格式", value: file.fileFormat)
            }
            .padding(.vertical, 4)
        }
        .groupBoxStyle(.automatic)
    }

    @ViewBuilder
    private func technicalRow(label: String, value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
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
