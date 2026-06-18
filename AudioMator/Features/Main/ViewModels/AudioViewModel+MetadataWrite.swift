import Foundation

private let supportedTagWriteExtensions = AudioFormatSupport.metadataWritableExtensions

private let supportedArtworkWriteExtensions = AudioFormatSupport.artworkWritableExtensions

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

func fileCountLabel(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(count) files"
}

extension AudioViewModel {
    // MARK: - Inspector Writes (TagLib)

    func saveInspectorEdits() {
        guard metadataSaveProgress == nil else { return }

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

        beginMetadataSaveProgress(
            title: "Saving Metadata",
            subtitle: file.url.lastPathComponent,
            totalUnitCount: 1
        )

        Task(priority: .userInitiated) {
            let result = await self.persistMetadataEdit(edit, to: file)
            self.updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            self.endMetadataSaveProgress()

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

        beginMetadataSaveProgress(
            title: "Saving Album Artwork",
            subtitle: "Preparing \(targetFiles.count) files…",
            totalUnitCount: targetFiles.count
        )

        Task(priority: .userInitiated) {
            var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

            for (index, file) in targetFiles.enumerated() {
                self.updateMetadataSaveProgress(
                    subtitle: file.url.lastPathComponent,
                    completedUnitCount: index
                )

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

            self.updateMetadataSaveProgress(
                subtitle: "Finishing…",
                completedUnitCount: targetFiles.count
            )
            self.endMetadataSaveProgress()

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
                self.updateEditForSelection()
            }

            self.presentBatchMetadataWriteSummary(summary)
        }
    }

    func applyMusicBrainzTaggingPlan(_ entries: [MusicBrainzTaggingWriteEntry]) async {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: "Applying MusicBrainz Tags",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )

        for (index, entry) in entries.enumerated() {
            updateMetadataSaveProgress(
                subtitle: entry.fileName,
                completedUnitCount: index
            )

            guard let file = filesByID[entry.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values.sorted(by: { lhs, rhs in
                lhs.key.writeOrderIndex < rhs.key.writeOrderIndex
            }) {
                field.apply(value, to: &edit)
            }

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

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: entries.count
        )
        endMetadataSaveProgress()

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }

    func applyITunesTaggingPlan(_ entries: [ITunesTaggingWriteEntry]) async {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: "Applying iTunes Tags",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )

        for (index, entry) in entries.enumerated() {
            updateMetadataSaveProgress(
                subtitle: entry.fileName,
                completedUnitCount: index
            )

            guard let file = filesByID[entry.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values.sorted(by: { lhs, rhs in
                lhs.key.writeOrderIndex < rhs.key.writeOrderIndex
            }) {
                field.apply(value, to: &edit)
            }

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

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: entries.count
        )
        endMetadataSaveProgress()

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }

    func applyFilenameMetadataPlan(_ entries: [FilenameMetadataWriteEntry]) async {
        guard !entries.isEmpty else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        for entry in entries {
            guard let file = filesByID[entry.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values {
                field.applyExtractedValue(value, to: &edit)
            }

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

    func applyMetadataExchangeWriteEntries(_ entries: [MetadataExchangeWriteEntry]) async {
        guard !entries.isEmpty else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        for entry in entries {
            guard let file = filesByID[entry.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values {
                field.applyImportedValue(value, to: &edit)
            }

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

    func applyLRCLIBSyncedLyrics(_ syncedLyrics: String, to fileID: AudioFile.ID) async -> Bool {
        guard metadataSaveProgress == nil else { return false }
        let normalizedLyrics = syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLyrics.isEmpty else { return false }

        guard let file = files.first(where: { $0.id == fileID }) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Apply Lyrics Failed",
                subtitle: "The file is no longer loaded in AudioMator."
            )
            return false
        }

        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Apply Lyrics Failed",
                subtitle: "This format does not support metadata writing yet."
            )
            return false
        }

        beginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: file.url.lastPathComponent,
            totalUnitCount: 1
        )

        do {
            var propertyMap = try await rawMetadataPropertyMapOffMainActor(for: file.url)
            propertyMap["LYRICS"] = normalizedLyrics

            let writeResult = try await writeRawMetadataPropertyMapOffMainActor(propertyMap, to: file.url)
            var warnings = writeResult.warnings
            let refreshWarning = await reloadEditedFile(file, syncInspectorAfterReload: true)
            if let refreshWarning {
                warnings.append(refreshWarning)
            }

            updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            endMetadataSaveProgress()

            if warnings.isEmpty {
                presentMetadataWriteHUD(
                    style: .success,
                    title: "LRCLIB Lyrics Applied",
                    subtitle: file.url.lastPathComponent
                )
            } else {
                presentMetadataWriteWarning(
                    title: "Lyrics Applied with Issues",
                    subtitle: ([file.url.lastPathComponent] + warnings).joined(separator: "\n")
                )
            }

            return true
        } catch {
            updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            endMetadataSaveProgress()
            presentMetadataWriteHUD(
                style: .failure,
                title: "Apply Lyrics Failed",
                subtitle: [file.url.lastPathComponent, (error as NSError).localizedDescription]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
            return false
        }
    }

    func applyLRCLIBSyncedLyricsAutoMatches(_ matches: [LRCLIBSyncedLyricsAutoMatch]) async -> Set<AudioFile.ID> {
        guard metadataSaveProgress == nil else { return [] }
        guard !matches.isEmpty else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "No Synced Lyrics Found",
                subtitle: "LRCLIB did not return synced lyrics for the selected files."
            )
            return []
        }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: matches.count)
        var appliedFileIDs = Set<AudioFile.ID>()

        beginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: "Preparing \(matches.count) files...",
            totalUnitCount: matches.count
        )

        for (index, match) in matches.enumerated() {
            updateMetadataSaveProgress(
                subtitle: match.fileName,
                completedUnitCount: index
            )

            let normalizedLyrics = match.syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedLyrics.isEmpty else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: match.fileName,
                        messages: ["LRCLIB returned empty synced lyrics."]
                    )
                )
                continue
            }

            guard let file = filesByID[match.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: match.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            guard isTagWriteSupportedExtension(file.url.pathExtension) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: ["This format does not support metadata writing yet."]
                    )
                )
                continue
            }

            do {
                var propertyMap = try await rawMetadataPropertyMapOffMainActor(for: file.url)
                propertyMap["LYRICS"] = normalizedLyrics

                let writeResult = try await writeRawMetadataPropertyMapOffMainActor(propertyMap, to: file.url)
                var warningMessages = writeResult.warnings
                let refreshWarning = await reloadEditedFile(file, syncInspectorAfterReload: false)

                if let refreshWarning {
                    warningMessages.append(refreshWarning)
                    summary.allSuccessfulFilesRefreshed = false
                }

                summary.succeeded += 1
                appliedFileIDs.insert(file.id)

                if !warningMessages.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: file.url.lastPathComponent,
                            messages: warningMessages
                        )
                    )
                }
            } catch {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [(error as NSError).localizedDescription]
                    )
                )
            }
        }

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: matches.count
        )
        endMetadataSaveProgress()

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
        return appliedFileIDs
    }

    func applyRawMetadataPropertyMaps(
        _ propertyMaps: [AudioFile.ID: [String: String]],
        to targets: [MetadataEditorTarget]
    ) async {
        guard !targets.isEmpty else { return }

        var summary = BatchMetadataWriteSummary(totalTargets: targets.count)

        for target in targets {
            guard isTagWriteSupportedExtension(target.url.pathExtension) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: ["This format does not support metadata writing yet."]
                    )
                )
                continue
            }

            do {
                let writeResult = try await writeRawMetadataPropertyMapOffMainActor(
                    propertyMaps[target.id] ?? [:],
                    to: target.url
                )

                summary.succeeded += 1
                var warningMessages = writeResult.warnings

                let refreshWarning = await reloadEditedFile(
                    at: target.url,
                    id: target.id,
                    syncInspectorAfterReload: false
                )

                if let refreshWarning {
                    warningMessages.append(refreshWarning)
                    summary.allSuccessfulFilesRefreshed = false
                }

                if !warningMessages.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: target.fileName,
                            messages: warningMessages
                        )
                    )
                }
            } catch {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [(error as NSError).localizedDescription]
                    )
                )
            }
        }

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
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
            field.apply(value, to: &edit)

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

        let editPayload = MetadataEditPayload(edit)

        do {
            let writeResult = try await writeMetadataOffMainActor(editPayload, to: file.url)
            var warnings: [String] = writeResult.warnings

            let refreshWarning = await reloadEditedFile(
                file,
                syncInspectorAfterReload: syncInspectorAfterReload
            )
            if let refreshWarning {
                warnings.append(refreshWarning)
            }

            if !warnings.isEmpty {
                print("""
                [AudioMator] Metadata write completed with warning(s) for \(file.url.lastPathComponent)
                \(warnings.map { "  - \($0)" }.joined(separator: "\n"))
                """)
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

    private func presentBatchMetadataWriteSummary(_ summary: BatchMetadataWriteSummary) {
        guard summary.totalTargets > 0 else { return }

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
    }

    func createMuseAmpIDs(for targetFiles: [AudioFile]) {
        guard metadataSaveProgress == nil else { return }

        let targetFiles = targetFiles
        guard !targetFiles.isEmpty else { return }

        let assignments = MuseAmpCommentIDGenerator.assignments(
            for: targetFiles.map { file in
                MuseAmpTrackIdentity(
                    album: file.album,
                    albumArtist: file.albumArtist,
                    trackKey: file.url.path
                )
            }
        )

        beginMetadataSaveProgress(
            title: "Creating MuseAmp IDs",
            subtitle: "Preparing \(targetFiles.count) files...",
            totalUnitCount: targetFiles.count
        )

        Task(priority: .userInitiated) {
            var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

            for (index, pair) in zip(targetFiles, assignments).enumerated() {
                let file = pair.0
                let museAmpID = pair.1

                self.updateMetadataSaveProgress(
                    subtitle: file.url.lastPathComponent,
                    completedUnitCount: index
                )

                var edit = SingleFileEditModel(from: file)
                edit.comment = museAmpID.commentText

                let result = await self.persistMetadataEdit(
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

            self.updateMetadataSaveProgress(
                subtitle: "Finishing...",
                completedUnitCount: targetFiles.count
            )
            self.endMetadataSaveProgress()

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
                self.updateEditForSelection()
            }

            self.presentBatchMetadataWriteSummary(summary)
        }
    }

    private func beginMetadataSaveProgress(
        title: String,
        subtitle: String,
        totalUnitCount: Int
    ) {
        metadataSaveProgress = MetadataSaveProgress(
            title: title,
            subtitle: subtitle,
            completedUnitCount: 0,
            totalUnitCount: max(totalUnitCount, 1)
        )
    }

    private func updateMetadataSaveProgress(
        subtitle: String,
        completedUnitCount: Int
    ) {
        guard let current = metadataSaveProgress else { return }
        metadataSaveProgress = MetadataSaveProgress(
            title: current.title,
            subtitle: subtitle,
            completedUnitCount: min(max(completedUnitCount, 0), current.totalUnitCount),
            totalUnitCount: current.totalUnitCount
        )
    }

    private func endMetadataSaveProgress() {
        metadataSaveProgress = nil
    }

    /// Attempts to erase all metadata from a file by writing empty tags over the existing values.
    func eraseAllMetadata(_ file: AudioFile) {
        guard metadataSaveProgress == nil else { return }

        beginMetadataSaveProgress(
            title: "Clearing Metadata",
            subtitle: file.url.lastPathComponent,
            totalUnitCount: 1
        )

        Task(priority: .userInitiated) {
            let result = await self.persistMetadataErase(file, syncInspectorAfterReload: true)
            self.updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            self.endMetadataSaveProgress()

            switch result {
            case .success(let success):
                if success.warnings.isEmpty {
                    self.presentMetadataWriteHUD(
                        style: .success,
                        title: "Metadata Cleared",
                        subtitle: file.url.lastPathComponent
                    )
                } else {
                    self.presentMetadataWriteWarning(
                        title: "Cleared with Issues",
                        subtitle: ([file.url.lastPathComponent] + success.warnings).joined(separator: "\n")
                    )
                }
            case .failure(let reason):
                self.presentMetadataWriteHUD(
                    style: .failure,
                    title: "Clear Failed",
                    subtitle: [file.url.lastPathComponent, reason]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                )
            }
        }
    }

    /// Attempts to erase all metadata from a batch of files with the same progress UI used by batch saves.
    func eraseAllMetadata(_ targetFiles: [AudioFile]) {
        guard metadataSaveProgress == nil else { return }

        let targetFiles = targetFiles
        guard !targetFiles.isEmpty else { return }

        if targetFiles.count == 1, let file = targetFiles.first {
            eraseAllMetadata(file)
            return
        }

        beginMetadataSaveProgress(
            title: "Clearing Metadata",
            subtitle: "Preparing \(targetFiles.count) files...",
            totalUnitCount: targetFiles.count
        )

        Task(priority: .userInitiated) {
            var summary = BatchMetadataOperationSummary(totalTargets: targetFiles.count, operation: .clear)

            for (index, file) in targetFiles.enumerated() {
                self.updateMetadataSaveProgress(
                    subtitle: file.url.lastPathComponent,
                    completedUnitCount: index
                )

                let result = await self.persistMetadataErase(
                    file,
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

            self.updateMetadataSaveProgress(
                subtitle: "Finishing...",
                completedUnitCount: targetFiles.count
            )
            self.endMetadataSaveProgress()

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
                self.updateEditForSelection()
            }

            self.presentBatchMetadataClearSummary(summary)
        }
    }

    private func persistMetadataErase(
        _ file: AudioFile,
        syncInspectorAfterReload: Bool
    ) async -> MetadataWriteExecutionResult {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported erase format for: \(file.url.lastPathComponent)")
            return .failure("This format does not support metadata writing yet.")
        }

        do {
            let writeResult = try await eraseAllMetadataOffMainActor(at: file.url)
            var warnings: [String] = writeResult.warnings

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
            print("Failed to erase metadata via TagLib: \(error)")
            return .failure((error as NSError).localizedDescription)
        }
    }

    private func presentBatchMetadataClearSummary(_ summary: BatchMetadataOperationSummary) {
        guard summary.totalTargets > 0 else { return }

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
    }

    private func writeMetadataOffMainActor(
        _ edit: MetadataEditPayload,
        to url: URL
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.writeMetadata(edit, to: url)
        }.value
    }

    private func rawMetadataPropertyMapOffMainActor(for url: URL) async throws -> [String: String] {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.rawMetadataPropertyMap(for: url)
        }.value
    }

    private func writeRawMetadataPropertyMapOffMainActor(
        _ propertyMap: [String: String],
        to url: URL
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
        }.value
    }

    private func eraseAllMetadataOffMainActor(at url: URL) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.eraseAllMetadata(at: url)
        }.value
    }

    func reloadEditedFile(
        _ file: AudioFile,
        syncInspectorAfterReload: Bool = true
    ) async -> String? {
        await reloadEditedFile(
            at: file.url,
            id: file.id,
            syncInspectorAfterReload: syncInspectorAfterReload
        )
    }

    func reloadEditedFile(
        at url: URL,
        id: UUID,
        syncInspectorAfterReload: Bool = true
    ) async -> String? {
        do {
            let reloaded = try await metadataPipeline.loadAudioFile(at: url, id: id)
            replaceLoadedFile(reloaded)

            if syncInspectorAfterReload, selectedAudioIDs.contains(id) {
                updateEditForSelection()
            }

            return nil
        } catch {
            return "Saved to disk, but the inspector could not refresh: \((error as NSError).localizedDescription)"
        }
    }

}
