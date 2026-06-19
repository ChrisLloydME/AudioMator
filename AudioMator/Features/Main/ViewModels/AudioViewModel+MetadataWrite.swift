import Foundation

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

    func persistMetadataEdit(
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

    func presentBatchMetadataWriteSummary(_ summary: BatchMetadataWriteSummary) {
        guard summary.totalTargets > 0 else { return }

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
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
