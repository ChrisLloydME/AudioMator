import Foundation

private let supportedTagWriteExtensions: Set<String> = [
    "mp3", "mp2", "aac",
    "m4a", "m4b", "m4p", "mp4",
    "flac", "wav", "aiff", "aif"
]

private func digitCount(_ value: Int) -> Int {
    let v = abs(value)
    return String(v).count
}

private func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    supportedTagWriteExtensions.contains(ext.lowercased())
}

extension AudioViewModel {
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

        // 当前支持 MPEG、MP4/M4A、FLAC、WAV、AIFF 写标签
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported write format for: \(file.url.lastPathComponent)")
            return
        }

        let meta = TagLibAudioMetadata()

        // 去掉首尾空格，避免无意写入带空格的标签
        meta.title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.artist = edit.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.album = edit.album.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.composer = edit.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.genre = edit.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.comment = edit.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.albumArtist = edit.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.year = edit.year.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.releaseDate = edit.releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.label = edit.publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.copyright = edit.copyright.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.explicitContent = edit.isExplicit

        // Track/Disc are written via `writeTrackNumberText(...)` below so the UI can accept
        // formats like "01" or "01/10" (and so we can omit the "/total" part when desired).
        meta.trackNumber = 0
        meta.totalTracks = 0
        meta.discNumber = 0
        meta.totalDiscs = 0

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

                self.presentMetadataWriteSuccess(for: file.url.lastPathComponent)

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

    /// 尝试抹掉文件的所有元数据（当前对 MPEG、MP4/M4A、FLAC、WAV、AIFF 生效；实现为“写入空标签并覆盖”）
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
                self.presentMetadataWriteSuccess(for: file.url.lastPathComponent)

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
    func renumberTrackNumbers(
        orderedIDs: [UUID],
        selectedIDs: Set<UUID>,
        options: TrackRenumberOptions
    ) async -> TrackRenumberResult {
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
        let writableExtensions = supportedTagWriteExtensions

        // 4) Execute writes off the main thread.
        return await Task.detached(priority: .userInitiated) { [targetFiles, numbers, padWidth, writableExtensions] in
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
                guard writableExtensions.contains(ext) else {
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
