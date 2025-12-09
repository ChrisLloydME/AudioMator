//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

// 单文件编辑模型：右侧 Inspector 绑定的数据载体
struct SingleFileEditModel {
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var comment: String
    var track: Int
    var trackTotal: Int
    var disc: Int
    var discTotal: Int
    var year: String
    var albumArtist: String

    init(
        title: String = "",
        artist: String = "",
        album: String = "",
        composer: String = "",
        genre: String = "",
        comment: String = "",
        track: Int = 0,
        trackTotal: Int = 0,
        disc: Int = 0,
        discTotal: Int = 0,
        year: String = "",
        albumArtist: String = ""
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.composer = composer
        self.genre = genre
        self.comment = comment
        self.track = track
        self.trackTotal = trackTotal
        self.disc = disc
        self.discTotal = discTotal
        self.year = year
        self.albumArtist = albumArtist
    }

    init(from file: AudioFile) {
        self.init(
            title: file.title,
            artist: file.artist,
            album: file.album,
            composer: file.composer,
            genre: file.genre,
            comment: file.comment,
            track: file.track,
            trackTotal: file.trackTotal,
            disc: file.disc,
            discTotal: file.discTotal,
            year: file.year,
            albumArtist: file.albumArtist
        )
    }
}

@MainActor
final class AudioViewModel: ObservableObject {
    // 当前加载到中间列表里的所有音频文件
    @Published private(set) var files: [AudioFile] = []
    // 中间列表的选中项（支持多选，但目前单文件编辑只用第一个）
    @Published var selectedAudioIDs: Set<UUID> = []
    // 右侧 Inspector 绑定的单文件编辑模型
    @Published var edit: SingleFileEditModel?

    // MARK: - 文件导入

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.aiff,
        ]
        panel.title = "选择音频文件"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls

        Task {
            var loaded: [AudioFile] = []
            for url in urls {
                if let file = try? await AudioFile(url: url) {
                    loaded.append(file)
                }
            }

            await MainActor.run {
                self.files.append(contentsOf: loaded)
            }
        }
    }

    // MARK: - 选中与编辑同步

    /// 当中间列表的选中项变化时调用，保持右侧 Inspector 内容与当前文件同步
    func updateEditForSelection() {
        guard
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id })
        else {
            edit = nil
            return
        }

        edit = SingleFileEditModel(from: file)
    }

    /// 放弃当前编辑，恢复为磁盘上的最新标签
    func cancelEditing() {
        updateEditForSelection()
    }

    // MARK: - 单文件写入（使用 TagLib）

    /// 将当前 Inspector 中的编辑结果写回到选中的 mp3 文件（直接调用 TagLib 桥接）
    func saveSingleEdits() {
        guard
            let edit = edit,
            let id = selectedAudioIDs.first,
            let index = files.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let file = files[index]

        // 当前只对 mp3 执行写入，其它格式直接跳过
        guard file.url.pathExtension.lowercased() == "mp3" else {
            print("Skip non-mp3 write for: \(file.url.lastPathComponent)")
            return
        }

        // 构造 TagLibAudioMetadata（桥接到 TagLib 的对象）
        let meta = TagLibAudioMetadata()
        meta.title       = edit.title
        meta.artist      = edit.artist
        meta.album       = edit.album
        meta.composer    = edit.composer
        meta.genre       = edit.genre
        meta.comment     = edit.comment
        meta.albumArtist = edit.albumArtist
        meta.year        = edit.year
        meta.trackNumber = edit.track
        meta.totalTracks = edit.trackTotal
        meta.discNumber  = edit.disc
        meta.totalDiscs  = edit.discTotal
        // 如果之后在 SingleFileEditModel 里加了 releaseDate / copyright / label，
        // 也可以在这里一并赋值给 meta.*

        do {
            // 1. 使用 TagLib 写入 mp3 标签
            try TagLibMetadataExtractor.writeMetadata(meta, to: file.url)

            // 2. 从磁盘重新读取一遍，刷新 UI 和 Inspector
            Task {
                if let reloaded = try? await AudioFile(url: file.url) {
                    await MainActor.run {
                        self.files[index] = reloaded
                        self.edit = SingleFileEditModel(from: reloaded)
                    }
                }
            }
        } catch {
            print("Failed to write metadata via TagLib: \(error)")
        }
    }
}
