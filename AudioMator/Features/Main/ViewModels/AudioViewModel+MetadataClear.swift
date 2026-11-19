import Foundation

extension AudioViewModel {
    /// Attempts to erase all metadata from a file through the reviewed strict route.
    func eraseAllMetadata(_ file: AudioFile) {
        guard metadataSaveProgress == nil else { return }
        guard canStartExternalFileMutation() else { return }

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
                if self.selectedAudioIDs.contains(file.id), success.didRefreshFileModel {
                    self.updateEditForSelection()
                }
                if success.warnings.isEmpty {
                    self.presentMetadataWriteHUD(
                        style: .success,
                        title: "Metadata Cleared",
                        subtitle: file.url.lastPathComponent,
                        summary: file.url.lastPathComponent,
                        details: ""
                    )
                } else {
                    self.presentMetadataWriteWarning(
                        title: String(localized: "Metadata Cleared with Warnings"),
                        fileName: file.url.lastPathComponent,
                        warnings: success.warnings,
                        operation: .clear
                    )
                }
            case .failure(let reason):
                self.presentMetadataWriteFailure(
                    for: file.url.lastPathComponent, reason: reason,
                    title: String(localized: "Metadata Couldn’t Be Cleared"), operation: .clear
                )
            case .cancelled:
                self.presentMetadataWriteCancellation(
                    for: file.url.lastPathComponent,
                    operation: .clear
                )
            }
        }
    }

    /// Attempts to erase all metadata from a batch of files with the same progress UI used by batch saves.
    func eraseAllMetadata(_ targetFiles: [AudioFile]) {
        guard metadataSaveProgress == nil else { return }

        let targetFiles = targetFiles
        guard !targetFiles.isEmpty else { return }
        guard canStartExternalFileMutation() else { return }

        if targetFiles.count == 1, let file = targetFiles.first {
            eraseAllMetadata(file)
            return
        }

        // Freeze one reviewed erase intent per confirmed target before suspending.
        let plannedTargets = targetFiles.map {
            ReviewedMetadataWriteFactory.eraseAllWrite(for: $0)
        }
        guard prepareMetadataMutationDirectoryAccess(for: plannedTargets.compactMap { $0?.target.url }) else { return }

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

                guard let write = plannedTargets[index] else {
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: file.url.lastPathComponent,
                            messages: [Self.unreviewedEraseFailureMessage]
                        )
                    )
                    continue
                }

                let result = await self.executeReviewedMetadataWrite(write, publication: .batched)
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
                case .cancelled:
                    summary.recordCancelledFiles([file.url.lastPathComponent])
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

            self.presentBatchMetadataOperationSummary(summary)
        }
    }

    func persistMetadataErase(
        _ file: AudioFile,
        syncInspectorAfterReload: Bool
    ) async -> MetadataWriteExecutionResult {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            return .failure(String(localized: "AudioMator doesn't support saving metadata to this file format."))
        }
        guard let write = ReviewedMetadataWriteFactory.eraseAllWrite(for: file) else {
            return .failure(Self.unreviewedEraseFailureMessage)
        }
        return await executeReviewedMetadataWrite(
            write,
            publication: syncInspectorAfterReload ? .immediate : .batched
        )
    }

    private static var unreviewedEraseFailureMessage: String {
        String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before clearing metadata.")
    }
}
