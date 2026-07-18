import Foundation

extension AudioViewModel {
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
                        subtitle: ([file.url.lastPathComponent] + success.warnings).joined(separator: "\n"),
                        operation: .clear
                    )
                }
            case .failure(let reason):
                self.saveIssueLogStore.recordSingleIssue(
                    title: "Clear Failed",
                    subtitle: [file.url.lastPathComponent, reason]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n"),
                    fileName: file.url.lastPathComponent,
                    messages: [reason],
                    severity: .failure,
                    operation: .clear
                )
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

    func persistMetadataErase(
        _ file: AudioFile,
        syncInspectorAfterReload: Bool
    ) async -> MetadataWriteExecutionResult {
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            return .failure("This format does not support metadata writing yet.")
        }

        do {
            let writeResult = try await eraseAllMetadataOffMainActor(
                at: file.url,
                expectedFileFingerprint: file.fileFingerprint
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
            return .failure((error as NSError).localizedDescription)
        }
    }

    func presentBatchMetadataClearSummary(_ summary: BatchMetadataOperationSummary) {
        guard summary.totalTargets > 0 else { return }

        saveIssueLogStore.record(summary: summary)

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
    }
}
