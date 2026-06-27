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

        guard editSourceFileID == id else {
            updateEditForSelection()
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

    func persistMetadataEdit(
        _ edit: SingleFileEditModel,
        to file: AudioFile,
        syncInspectorAfterReload: Bool = true,
        expectedFileFingerprint: AudioFileFingerprint? = nil
    ) async -> MetadataWriteExecutionResult {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            print("Skip unsupported write format for: \(file.url.lastPathComponent)")
            return .failure("This format does not support metadata writing yet.")
        }

        let editPayload = MetadataEditPayload(edit)

        do {
            let writeResult = try await writeMetadataOffMainActor(
                editPayload,
                to: file.url,
                expectedFileFingerprint: expectedFileFingerprint
            )
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
            print("Failed to write metadata via TagLib: \(error)")
            return .failure((error as NSError).localizedDescription)
        }
    }

    func presentBatchMetadataWriteSummary(_ summary: BatchMetadataWriteSummary) {
        guard summary.totalTargets > 0 else { return }

        saveIssueLogStore.record(summary: summary)

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
