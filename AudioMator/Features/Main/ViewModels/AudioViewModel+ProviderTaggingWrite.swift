import Foundation

extension AudioViewModel {
    func applyMusicBrainzTaggingPlan(_ entries: [MusicBrainzTaggingWriteEntry]) async {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return }
        guard canStartExternalFileMutation() else { return }

        guard prepareMetadataMutationDirectoryAccess(for: entries.compactMap { $0.reviewedWrite?.target.url }) else { return }
        var summary = BatchMetadataOperationSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: "Applying MusicBrainz Tags",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            guard let write = entry.reviewedWrite else {
                return (entry.fileName, .failure(Self.unreviewedProviderEntryFailureMessage))
            }
            let result = await self.executeReviewedMetadataWrite(write, publication: .batched)
            return (entry.fileName, result)
        }
        for (index, entry) in entries.enumerated() {
            guard let outcome = outcomes[index] else {
                summary.recordCancelledFiles([entry.fileName])
                continue
            }
            switch outcome.result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: outcome.fileName,
                            messages: success.warnings
                        )
                    )
                }
            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: outcome.fileName,
                        messages: [reason]
                    )
                )
            case .cancelled:
                summary.recordCancelledFiles([outcome.fileName])
            }
        }

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: entries.count
        )

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            refreshInspectorDraftAfterAcceptedPublication()
        }

        presentBatchMetadataOperationSummary(summary)
    }

    func applyiTunesTaggingPlan(_ entries: [iTunesTaggingWriteEntry]) async {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return }
        guard canStartExternalFileMutation() else { return }

        guard prepareMetadataMutationDirectoryAccess(for: entries.compactMap { $0.reviewedWrite?.target.url }) else { return }
        var summary = BatchMetadataOperationSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: "Applying iTunes Tags",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            guard let write = entry.reviewedWrite else {
                return (entry.fileName, .failure(Self.unreviewedProviderEntryFailureMessage))
            }
            let result = await self.executeReviewedMetadataWrite(write, publication: .batched)
            return (entry.fileName, result)
        }
        for (index, entry) in entries.enumerated() {
            guard let outcome = outcomes[index] else {
                summary.recordCancelledFiles([entry.fileName])
                continue
            }
            switch outcome.result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: outcome.fileName,
                            messages: success.warnings
                        )
                    )
                }
            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: outcome.fileName,
                        messages: [reason]
                    )
                )
            case .cancelled:
                summary.recordCancelledFiles([outcome.fileName])
            }
        }

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: entries.count
        )

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            refreshInspectorDraftAfterAcceptedPublication()
        }

        presentBatchMetadataOperationSummary(summary)
    }

    private static var unreviewedProviderEntryFailureMessage: String {
        String(localized: "This preview wasn’t built from a reviewed file revision. Close and reopen the tool, then review the current values before applying changes.")
    }
}
