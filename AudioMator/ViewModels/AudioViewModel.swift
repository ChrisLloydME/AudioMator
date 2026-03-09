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

// MARK: - Track Renumbering

enum TrackRenumberDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
}

struct TrackRenumberOptions: Equatable {
    var direction: TrackRenumberDirection = .ascending
    var startNumber: Int = 1
    var padWithZeros: Bool = true
}

struct TrackRenumberFailure: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let reason: String
}

struct TrackRenumberResult: Equatable {
    var totalTargets: Int
    var succeeded: Int
    var skippedUnsupported: Int
    var failed: Int
    var failures: [TrackRenumberFailure]

    static let empty = TrackRenumberResult(
        totalTargets: 0,
        succeeded: 0,
        skippedUnsupported: 0,
        failed: 0,
        failures: []
    )
}

private func digitCount(_ value: Int) -> Int {
    let v = abs(value)
    return String(v).count
}

private func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    let lower = ext.lowercased()
    return lower == "mp3" || lower == "m4a" || lower == "m4b" || lower == "m4p" || lower == "mp4"
}

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
    var trackNumberText: String   // e.g. "1" / "01" / "01/10" (TRCK)
    var discNumberText: String    // e.g. "1" / "1/2" (TPOS)
    var albumArtist: String
    var releaseDate: String
    var publisher: String
    var copyright: String
    var isExplicit: Bool

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
        trackNumberText: String = "",
        discNumberText: String = "",
        albumArtist: String = "",
        releaseDate: String = "",
        publisher: String = "",
        copyright: String = "",
        isExplicit: Bool = false
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
        self.trackNumberText = trackNumberText
        self.discNumberText = discNumberText
        self.albumArtist = albumArtist
        self.releaseDate = releaseDate
        self.publisher = publisher
        self.copyright = copyright
        self.isExplicit = isExplicit
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
            trackNumberText: file.track > 0 ? (file.trackTotal > 0 ? "\(file.track)/\(file.trackTotal)" : "\(file.track)") : "",
            discNumberText: file.disc > 0 ? (file.discTotal > 0 ? "\(file.disc)/\(file.discTotal)" : "\(file.disc)") : "",
            albumArtist: file.albumArtist,
            releaseDate: file.releaseDate,
            publisher: file.publisher,
            copyright: file.copyright,
            isExplicit: file.isExplicit
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

    /// 将当前 Inspector 中的编辑结果写回到选中的音频文件（直接调用 TagLib 桥接）
    func saveSingleEdits() {
        guard
            let edit = edit,
            let id = selectedAudioIDs.first,
            let index = files.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let file = files[index]

        // 当前支持 MP3 和 MP4/M4A 家族写标签
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported write format for: \(file.url.lastPathComponent)")
            return
        }

        // 构造 TagLibAudioMetadata（桥接对象）
        let meta = TagLibAudioMetadata()

        // 去掉首尾空格，避免无意写入带空格的标签
        meta.title       = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.artist      = edit.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.album       = edit.album.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.composer    = edit.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.genre       = edit.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.comment     = edit.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.albumArtist = edit.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.year        = edit.year.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.releaseDate = edit.releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.label       = edit.publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.copyright   = edit.copyright.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.explicitContent = edit.isExplicit

        // Track/Disc are written via `writeTrackNumberText(...)` below so the UI can accept
        // formats like "01" or "01/10" (and so we can omit the "/total" part when desired).
        meta.trackNumber = 0
        meta.totalTracks = 0
        meta.discNumber  = 0
        meta.totalDiscs  = 0

        print("""
        [AudioMator] Will write metadata for \(file.url.lastPathComponent)
          title       = \(meta.title ?? "<nil>")
          artist      = \(meta.artist ?? "<nil>")
          album       = \(meta.album ?? "<nil>")
          composer    = \(meta.composer ?? "<nil>")
          genre       = \(meta.genre ?? "<nil>")
          comment     = \(meta.comment ?? "<nil>")
          albumArtist = \(meta.albumArtist ?? "<nil>")
          releaseDate = \(meta.releaseDate ?? "<nil>")
          publisher   = \(meta.label ?? "<nil>")
          copyright   = \(meta.copyright ?? "<nil>")
          explicit    = \(meta.explicitContent ? "YES" : "NO")
          year        = \(meta.year ?? "<nil>")
          trackText   = \(edit.trackNumberText.isEmpty ? "<empty>" : edit.trackNumberText)
          discText    = \(edit.discNumberText.isEmpty ? "<empty>" : edit.discNumberText)
        """)

        Task(priority: .userInitiated) {
            do {
                try TagLibMetadataExtractor.writeMetadata(meta, to: file.url)

                // Write Track/Disc number text using the same Save button flow as other fields.
                // Note: ObjC NSError-style API is imported as `throws` in Swift.
                do {
                    let trackText = edit.trackNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let discText = edit.discNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try TagLibMetadataExtractor.writeTrackNumberText(
                        trackText,
                        discNumberText: discText,
                        to: file.url
                    )
                } catch {
                    print("Failed to write Track/Disc numbers: \(error)")
                }

                // 写完重新从磁盘读一遍，刷新 UI（并保持选中项不丢）
                if let reloaded = try? await AudioFile(url: file.url) {
                    self.files[index] = reloaded
                    self.selectedAudioIDs = [reloaded.id]
                    self.edit = SingleFileEditModel(from: reloaded)
                }
            } catch {
                print("Failed to write metadata via TagLib: \(error)")
            }
        }
    }

    // MARK: - 右键菜单动作（中间列表）

    func openWithDefaultApp(_ file: AudioFile) {
        NSWorkspace.shared.open(file.url)
    }

    func revealInFinder(_ file: AudioFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func copyFilePath(_ file: AudioFile) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(file.url.path, forType: .string)
    }

    func removeFromList(_ file: AudioFile) {
        files.removeAll { $0.id == file.id }
        selectedAudioIDs.remove(file.id)
        if selectedAudioIDs.isEmpty {
            edit = nil
        }
    }

    /// 尝试抹掉文件的所有元数据（当前对 MP3 和 MP4/M4A 生效；实现为“写入空标签并覆盖”）
    func eraseAllMetadata(_ file: AudioFile) {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported erase format for: \(file.url.lastPathComponent)")
            return
        }

        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }

        let meta = TagLibAudioMetadata()
        meta.title = ""
        meta.artist = ""
        meta.album = ""
        meta.composer = ""
        meta.genre = ""
        meta.comment = ""
        meta.albumArtist = ""
        meta.year = ""
        meta.releaseDate = ""
        meta.label = ""
        meta.copyright = ""
        meta.trackNumber = 0
        meta.totalTracks = 0
        meta.discNumber = 0
        meta.totalDiscs = 0
        meta.explicitContent = false

        Task(priority: .userInitiated) {
            do {
                try TagLibMetadataExtractor.writeMetadata(meta, to: file.url)

                if let reloaded = try? await AudioFile(url: file.url) {
                    self.files[index] = reloaded
                    self.selectedAudioIDs = [reloaded.id]
                    self.edit = SingleFileEditModel(from: reloaded)
                }
            } catch {
                print("Failed to erase metadata via TagLib: \(error)")
            }
        }
    }

    // MARK: - 批量按列表顺序重写 Track Number

    /// 根据中间栏列表的排序顺序批量重写 Track Number（TRCK）。
    ///
    /// - Parameters:
    ///   - orderedIDs: 列表排序来源（通常传 `SharedState.customOrder`；若为空则传当前 `files.map(\.id)`）。
    ///   - selectedIDs: 当前选中项；若非空，则只对选中项（按 orderedIDs 的出现顺序）执行重写。
    ///   - options: 重写配置（顺序/倒序、起始号、是否补零）。
    ///
    /// - Returns: 可用于 UI 展示的汇总结果。
    func renumberTrackNumbers(orderedIDs: [UUID], selectedIDs: Set<UUID>, options: TrackRenumberOptions) async -> TrackRenumberResult {
        // 1) Build the target list by ordered appearance.
        let targetsInOrder: [UUID] = {
            let base = orderedIDs
            if selectedIDs.isEmpty { return base }
            return base.filter { selectedIDs.contains($0) }
        }()

        guard !targetsInOrder.isEmpty else {
            return .empty
        }

        // 2) Resolve UUIDs to current files (and keep order).
        //    NOTE: We intentionally skip IDs that are no longer present.
        let filesByID: [UUID: AudioFile] = Dictionary(uniqueKeysWithValues: self.files.map { ($0.id, $0) })
        let targetFiles: [AudioFile] = targetsInOrder.compactMap { filesByID[$0] }

        guard !targetFiles.isEmpty else {
            return .empty
        }

        // 3) Prepare numbering sequence.
        let count = targetFiles.count
        let start = max(0, options.startNumber)

        let numbers: [Int] = {
            switch options.direction {
            case .ascending:
                return (0..<count).map { start + $0 }
            case .descending:
                // “倒序分配”的直觉定义：列表第一首拿到最大号，最后一首拿到最小号。
                return (0..<count).map { start + (count - 1 - $0) }
            }
        }()

        let maxNumber = numbers.max() ?? start
        let padWidth = options.padWithZeros ? digitCount(maxNumber) : 0

        // 4) Execute writes off the main thread.
        return await Task.detached(priority: .userInitiated) { [targetFiles, numbers, padWidth] in
            let supportedExtensions: Set<String> = ["mp3", "m4a", "m4b", "m4p", "mp4"]
            var result = TrackRenumberResult(
                totalTargets: targetFiles.count,
                succeeded: 0,
                skippedUnsupported: 0,
                failed: 0,
                failures: []
            )

            for (idx, file) in targetFiles.enumerated() {
                let newNumber = numbers[idx]

                let ext = file.url.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else {
                    result.skippedUnsupported += 1
                    continue
                }

                do {
                    _ = try TagLibMetadataExtractor.writeTrackNumber(
                        newNumber,
                        totalTracks: 0,
                        padWidth: padWidth,
                        to: file.url
                    )
                    result.succeeded += 1
                } catch {
                    result.failed += 1
                    let reason = (error as NSError).localizedDescription
                    result.failures.append(TrackRenumberFailure(fileName: file.url.lastPathComponent, reason: reason))
                }
            }

            return result
        }.value
    }
}
