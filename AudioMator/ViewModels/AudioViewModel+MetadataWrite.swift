import Foundation

private let supportedTagWriteExtensions = AudioFormatSupport.metadataWritableExtensions

private let supportedArtworkWriteExtensions = AudioFormatSupport.artworkWritableExtensions

private func formattedTrackNumberText(_ value: Int, padWidth: Int) -> String {
    guard padWidth > 0 else { return String(value) }
    return String(format: "%0*d", padWidth, value)
}

private func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    supportedTagWriteExtensions.contains(ext.lowercased())
}

func isArtworkWriteSupportedExtension(_ ext: String) -> Bool {
    supportedArtworkWriteExtensions.contains(ext.lowercased())
}

private struct MetadataWriteSuccessOutcome {
    let warnings: [String]
    let didRefreshFileModel: Bool
}

private enum MetadataWriteExecutionResult {
    case success(MetadataWriteSuccessOutcome)
    case failure(String)
}

private struct BatchMetadataWriteIssue {
    let fileName: String
    let messages: [String]
}

private struct BatchMetadataWriteSummary {
    let totalTargets: Int
    var succeeded: Int = 0
    var warningIssues: [BatchMetadataWriteIssue] = []
    var failureIssues: [BatchMetadataWriteIssue] = []
    var allSuccessfulFilesRefreshed = true

    var hudStyle: MetadataWriteHUDStyle {
        if failureIssues.isEmpty && warningIssues.isEmpty {
            return .success
        }

        if failureIssues.isEmpty {
            return .warning
        }

        return succeeded > 0 ? .warning : .failure
    }

    var hudTitle: String {
        if failureIssues.isEmpty && warningIssues.isEmpty {
            return "Saved to Disk"
        }

        if failureIssues.isEmpty {
            return "Saved with Issues"
        }

        return succeeded > 0 ? "Partially Saved" : "Save Failed"
    }

    var hudSubtitle: String {
        if failureIssues.isEmpty && warningIssues.isEmpty {
            return fileCountLabel(succeeded)
        }

        var lines: [String] = [summaryLine]

        if !warningIssues.isEmpty {
            lines.append("\(warningIssues.count) file(s) saved with issues")
        }

        if !failureIssues.isEmpty {
            lines.append("\(failureIssues.count) file(s) failed")
        }

        let detailSource = failureIssues.isEmpty ? warningIssues : failureIssues
        for issue in detailSource.prefix(2) {
            let detail = issue.messages.joined(separator: " ")
            lines.append("\(issue.fileName): \(detail)")
        }

        if detailSource.count > 2 {
            lines.append("...and \(detailSource.count - 2) more")
        }

        return lines.joined(separator: "\n")
    }

    private var summaryLine: String {
        switch succeeded {
        case totalTargets:
            return "\(totalTargets) of \(totalTargets) files saved"
        case 0:
            return "No files were saved"
        default:
            return "\(succeeded) of \(totalTargets) files saved"
        }
    }
}

private func fileCountLabel(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(count) files"
}

extension AudioViewModel {
    // MARK: - Inspector Writes (TagLib)

    func saveInspectorEdits() {
        if selectedAudioIDs.count > 1 {
            saveMultiFileEdits()
        } else {
            saveSingleEdits()
        }
    }

    /// Writes the current inspector edits back to the selected audio file through the TagLib bridge.
    func saveSingleEdits() {
        guard
            let edit = edit,
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id })
        else {
            return
        }

        Task(priority: .userInitiated) {
            let result = await self.persistMetadataEdit(edit, to: file)

            switch result {
            case .success(let success):
                if success.warnings.isEmpty {
                    self.presentMetadataWriteSuccess(for: file.url.lastPathComponent)
                } else {
                    self.presentMetadataWriteWarning(
                        title: "Saved with Issues",
                        subtitle: ([file.url.lastPathComponent] + success.warnings).joined(separator: "\n")
                    )
                }
            case .failure(let reason):
                self.presentMetadataWriteFailure(
                    for: file.url.lastPathComponent,
                    reason: reason
                )
            }
        }
    }

    /// Applies only the modified multi-file fields to each selected file, then reuses the existing write path.
    func saveMultiFileEdits() {
        guard selectedAudioIDs.count > 1, let multiEdit else {
            return
        }

        guard multiEdit.hasUnsavedChanges else {
            return
        }

        let targetFiles = files.filter { selectedAudioIDs.contains($0.id) }
        guard !targetFiles.isEmpty else { return }

        let editSnapshot = multiEdit

        Task(priority: .userInitiated) {
            var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

            for file in targetFiles {
                let effectiveEdit = editSnapshot.applyingChanges(to: file)
                let result = await self.persistMetadataEdit(
                    effectiveEdit,
                    to: file,
                    syncInspectorAfterReload: false
                )

                switch result {
                case .success(let success):
                    summary.succeeded += 1
                    summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                    if !success.warnings.isEmpty {
                        summary.warningIssues.append(
                            BatchMetadataWriteIssue(
                                fileName: file.url.lastPathComponent,
                                messages: success.warnings
                            )
                        )
                    }
                case .failure(let reason):
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: file.url.lastPathComponent,
                            messages: [reason]
                        )
                    )
                }
            }

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
                self.updateEditForSelection()
            }

            self.presentBatchMetadataWriteSummary(summary)
        }
    }

    /// Imports one text field value per target file and writes the chosen metadata field in order.
    func importMetadataFieldValues(
        _ values: [String],
        to field: MultiFileEditableTextField,
        for targetFiles: [AudioFile]
    ) async {
        guard !targetFiles.isEmpty else { return }

        guard values.count == targetFiles.count else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Import Failed",
                subtitle: "Imported \(values.count) values for \(targetFiles.count) selected files."
            )
            return
        }

        var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

        for (file, value) in zip(targetFiles, values) {
            var edit = SingleFileEditModel(from: file)
            edit[keyPath: field.keyPath] = value

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false
            )

            switch result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: file.url.lastPathComponent,
                            messages: success.warnings
                        )
                    )
                }
            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [reason]
                    )
                )
            }
        }

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }

    private func persistMetadataEdit(
        _ edit: SingleFileEditModel,
        to file: AudioFile,
        syncInspectorAfterReload: Bool = true
    ) async -> MetadataWriteExecutionResult {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported write format for: \(file.url.lastPathComponent)")
            return .failure("This format does not support metadata writing yet.")
        }

        let meta = makeTagLibMetadata(from: edit)
        logMetadataWrite(meta, edit: edit, file: file)

        do {
            try TagLibMetadataExtractor.writeMetadata(meta, to: file.url)
            var warnings: [String] = []

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

            let refreshWarning = await reloadEditedFile(
                file,
                syncInspectorAfterReload: syncInspectorAfterReload
            )
            if let refreshWarning {
                warnings.append(refreshWarning)
            }

            return .success(
                MetadataWriteSuccessOutcome(
                    warnings: warnings,
                    didRefreshFileModel: refreshWarning == nil
                )
            )
        } catch {
            print("Failed to write metadata via TagLib: \(error)")
            return .failure((error as NSError).localizedDescription)
        }
    }

    private func makeTagLibMetadata(from edit: SingleFileEditModel) -> TagLibAudioMetadata {
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
        meta.trackNumberText = edit.trackNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.discNumberText = edit.discNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.trackNumber = 0
        meta.totalTracks = 0
        meta.discNumber = 0
        meta.totalDiscs = 0

        return meta
    }

    private func logMetadataWrite(
        _ meta: TagLibAudioMetadata,
        edit: SingleFileEditModel,
        file: AudioFile
    ) {
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
    }

    private func presentBatchMetadataWriteSummary(_ summary: BatchMetadataWriteSummary) {
        guard summary.totalTargets > 0 else { return }

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
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
        meta.removeArtwork = true

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

    private func reloadEditedFile(
        _ file: AudioFile,
        syncInspectorAfterReload: Bool = true
    ) async -> String? {
        await reloadEditedFile(
            at: file.url,
            id: file.id,
            syncInspectorAfterReload: syncInspectorAfterReload
        )
    }

    private func reloadEditedFile(
        at url: URL,
        id: UUID,
        syncInspectorAfterReload: Bool = true
    ) async -> String? {
        do {
            let reloaded = try await AudioFile(url: url, id: id)
            replaceLoadedFile(reloaded)

            if syncInspectorAfterReload, selectedAudioIDs.contains(id) {
                updateEditForSelection()
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
        let writeTargets: [(id: UUID, url: URL)] = targetFiles.map { ($0.id, $0.url) }

        guard !writeTargets.isEmpty else {
            return .empty
        }

        // 3) Prepare numbering sequence.
        let count = writeTargets.count
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
        let padWidth = trackRenumberPadWidth(maxNumber: maxNumber, padWithZeros: options.padWithZeros)
        let writableExtensions = supportedTagWriteExtensions

        // 4) Execute writes off the main thread.
        let writeOutcome = await Task.detached(priority: .userInitiated) { [writeTargets, numbers, padWidth, writableExtensions] in
            var result = TrackRenumberResult(
                totalTargets: writeTargets.count,
                succeeded: 0,
                skippedUnsupported: 0,
                failed: 0,
                failures: []
            )
            var successfulTargets: [(id: UUID, url: URL)] = []

            for (idx, target) in writeTargets.enumerated() {
                let newNumber = numbers[idx]

                let ext = target.url.pathExtension.lowercased()
                guard writableExtensions.contains(ext) else {
                    result.skippedUnsupported += 1
                    continue
                }

                do {
                    _ = try TagLibMetadataExtractor.writeTrackNumberText(
                        formattedTrackNumberText(newNumber, padWidth: padWidth),
                        discNumberText: nil,
                        to: target.url
                    )
                    result.succeeded += 1
                    successfulTargets.append(target)
                } catch {
                    result.failed += 1
                    let reason = (error as NSError).localizedDescription
                    result.failures.append(TrackRenumberFailure(fileName: target.url.lastPathComponent, reason: reason))
                }
            }

            return (result, successfulTargets)
        }.value

        for target in writeOutcome.1 {
            if let refreshWarning = await reloadEditedFile(
                at: target.url,
                id: target.id,
                syncInspectorAfterReload: false
            ) {
                print("[AudioMator] Track renumber saved but refresh failed for \(target.url.lastPathComponent): \(refreshWarning)")
            }
        }

        if !writeOutcome.1.isEmpty {
            updateEditForSelection()
        }

        return writeOutcome.0
    }
}
