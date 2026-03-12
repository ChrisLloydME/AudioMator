import Foundation

private let supportedTagWriteExtensions: Set<String> = [
    "mp3", "mp2", "aac",
    "m4a", "m4b", "m4p", "mp4",
    "flac", "wav", "aiff", "aif"
]

private let supportedArtworkWriteExtensions: Set<String> = [
    "mp3", "mp2", "aac",
    "m4a", "m4b", "m4p", "mp4",
    "flac"
]

private func digitCount(_ value: Int) -> Int {
    let v = abs(value)
    return String(v).count
}

private func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    supportedTagWriteExtensions.contains(ext.lowercased())
}

func isArtworkWriteSupportedExtension(_ ext: String) -> Bool {
    supportedArtworkWriteExtensions.contains(ext.lowercased())
}

extension AudioViewModel {
    // MARK: - Single-File Writes (TagLib)

    /// Writes the current inspector edits back to the selected audio file through the TagLib bridge.
    func saveSingleEdits() {
        guard
            let edit = edit,
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id })
        else {
            return
        }

        // Tag writing is currently supported for MPEG, MP4/M4A, FLAC, WAV, and AIFF.
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported write format for: \(file.url.lastPathComponent)")
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: "This format does not support metadata writing yet."
            )
            return
        }

        let meta = TagLibAudioMetadata()

        // Trim surrounding whitespace to avoid writing accidental padded tags.
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
        switch edit.artworkEditAction {
        case .unchanged:
            meta.removeArtwork = false
        case .replace(let artwork):
            meta.artworkData = artwork.data
            meta.artworkMimeType = artwork.mimeType
            meta.removeArtwork = false
        case .remove:
            meta.removeArtwork = true
        }

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
                var warnings: [String] = []

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
                    warnings.append("Track/Disc numbers were not fully saved: \((error as NSError).localizedDescription)")
                }

                if let refreshWarning = await self.reloadEditedFile(file) {
                    warnings.append(refreshWarning)
                }

                if warnings.isEmpty {
                    self.presentMetadataWriteSuccess(for: file.url.lastPathComponent)
                } else {
                    self.presentMetadataWriteWarning(
                        title: "Saved with Issues",
                        subtitle: ([file.url.lastPathComponent] + warnings).joined(separator: "\n")
                    )
                }
            } catch {
                print("Failed to write metadata via TagLib: \(error)")
                self.presentMetadataWriteFailure(
                    for: file.url.lastPathComponent,
                    reason: (error as NSError).localizedDescription
                )
            }
        }
    }

    /// Attempts to erase all metadata from a file by writing empty tags over the existing values.
    func eraseAllMetadata(_ file: AudioFile) {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported erase format for: \(file.url.lastPathComponent)")
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent,
                reason: "This format does not support metadata writing yet."
            )
            return
        }

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

                if let refreshWarning = await self.reloadEditedFile(file) {
                    self.presentMetadataWriteWarning(
                        title: "Saved, Refresh Failed",
                        subtitle: [file.url.lastPathComponent, refreshWarning].joined(separator: "\n")
                    )
                } else {
                    self.presentMetadataWriteSuccess(for: file.url.lastPathComponent)
                }
            } catch {
                print("Failed to erase metadata via TagLib: \(error)")
                self.presentMetadataWriteFailure(
                    for: file.url.lastPathComponent,
                    reason: (error as NSError).localizedDescription
                )
            }
        }
    }

    private func reloadEditedFile(_ file: AudioFile) async -> String? {
        do {
            let reloaded = try await AudioFile(url: file.url, id: file.id)

            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index] = reloaded
            }

            if selectedAudioIDs.contains(file.id) {
                edit = SingleFileEditModel(from: reloaded)
            }

            return nil
        } catch {
            return "Saved to disk, but the inspector could not refresh: \((error as NSError).localizedDescription)"
        }
    }

    // MARK: - Batch Track Renumbering by List Order

    /// Batch-rewrites Track Number (`TRCK`) using the current ordering of the middle list.
    ///
    /// - Parameters:
    ///   - orderedIDs: Source list order, usually `SharedState.customOrder`; use `files.map(\.id)` when empty.
    ///   - selectedIDs: Current selection. When non-empty, only selected items are rewritten in `orderedIDs` order.
    ///   - options: Rewrite options including direction, start value, and zero padding.
    ///
    /// - Returns: A summary result suitable for UI presentation.
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
                // Descending means the first item gets the highest number and the last item gets the lowest.
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
