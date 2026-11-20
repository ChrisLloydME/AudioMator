import Foundation

extension AudioViewModel {
    @discardableResult
    func applyFilenameMetadataPlan(
        _ entries: [FilenameMetadataWriteEntry],
        skippedIssues: [BatchMetadataWriteIssue] = []
    ) async -> BatchMetadataOperationSummary? {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return nil }

        guard !hasUnsavedInspectorChanges else {
            presentUnsavedMetadataPlanFailure()
            return nil
        }

        guard Set(entries.map(\.fileID)).count == entries.count else {
            presentDuplicateMetadataPlanFailure()
            return nil
        }

        let targetURLs = prePromptDirectoryAccessURLs(for: entries.map(\.write))
        if !targetURLs.isEmpty {
            guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return nil }
        }
        var summary = BatchMetadataOperationSummary(totalTargets: entries.count + skippedIssues.count)

        let progressToken = beginMetadataSaveProgress(
            title: String(localized: "Writing Filename Metadata"),
            subtitle: String(localized: "Preparing \(entries.count) files..."),
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress(token: progressToken) }

        // Each entry carries the frozen reviewed write captured from the reviewed
        // file. The strict executor revalidates the captured target/revision inside
        // the reservation; no draft field is read at Apply.
        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            let result = await self.executeReviewedMetadataWrite(
                entry.write,
                publication: .batched
            )
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

        summary.skippedIssues.append(contentsOf: skippedIssues)

        updateMetadataSaveProgress(
            token: progressToken,
            subtitle: String(localized: "Finishing..."),
            completedUnitCount: entries.count
        )
        endMetadataSaveProgress(token: progressToken)

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            refreshInspectorDraftAfterPlanWrite(capturedTargetIDs: Set(entries.map(\.fileID)))
        }

        presentBatchMetadataOperationSummary(summary)
        return summary
    }

    @discardableResult
    func applyMetadataExchangeWriteEntries(
        _ entries: [MetadataExchangeWriteEntry],
        skippedIssues: [BatchMetadataWriteIssue] = [],
        progressTitle: String = String(localized: "Importing Metadata")
    ) async -> BatchMetadataOperationSummary? {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return nil }

        guard !hasUnsavedInspectorChanges else {
            presentUnsavedMetadataPlanFailure()
            return nil
        }

        guard Set(entries.map(\.fileID)).count == entries.count else {
            presentDuplicateMetadataPlanFailure()
            return nil
        }

        let targetURLs = prePromptDirectoryAccessURLs(for: entries.map(\.write))
        if !targetURLs.isEmpty {
            guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return nil }
        }
        var summary = BatchMetadataOperationSummary(totalTargets: entries.count + skippedIssues.count)

        let progressToken = beginMetadataSaveProgress(
            title: progressTitle,
            subtitle: String(localized: "Preparing \(entries.count) files..."),
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress(token: progressToken) }

        // Exchange text/CSV and field-transfer entries both carry a frozen
        // ReviewedMetadataWrite. The strict executor validates the captured target
        // and revision inside the coordinator and reports per-row outcomes.
        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            let result = await self.executeReviewedMetadataWrite(
                entry.write,
                publication: .batched
            )
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

        summary.skippedIssues.append(contentsOf: skippedIssues)

        updateMetadataSaveProgress(
            token: progressToken,
            subtitle: String(localized: "Finishing..."),
            completedUnitCount: entries.count
        )
        endMetadataSaveProgress(token: progressToken)

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            refreshInspectorDraftAfterPlanWrite(capturedTargetIDs: Set(entries.map(\.fileID)))
        }

        presentBatchMetadataOperationSummary(summary)
        return summary
    }

    /// Completion-side draft publication for a plan batch.
    ///
    /// A batch may write files the Inspector does not currently show, and an
    /// Inspector draft can be created or edited while it runs. Only the captured
    /// batch targets may trigger the F3 clean-refresh path; a dirty, pending-review
    /// or different live draft is left untouched. The F3 operation itself also
    /// refuses to replace a dirty draft.
    private func refreshInspectorDraftAfterPlanWrite(capturedTargetIDs: Set<AudioFile.ID>) {
        guard !capturedTargetIDs.isEmpty else { return }
        let liveDraftTargetIDs = Set(inspectorDraftIdentity?.targetIDs ?? [])
        guard !liveDraftTargetIDs.isEmpty,
              liveDraftTargetIDs.isSubset(of: capturedTargetIDs),
              selectedAudioIDs == liveDraftTargetIDs else { return }
        refreshInspectorDraftAfterAcceptedPublication()
    }

    private func presentDuplicateMetadataPlanFailure() {
        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Changes Couldn’t Be Applied"),
            subtitle: String(localized: "The same file is included more than once in this preview. Close and reopen this tool before applying changes.")
        )
    }

    private func presentUnsavedMetadataPlanFailure() {
        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Unsaved Changes"),
            subtitle: String(localized: "Save or discard the pending inspector edits before writing a metadata exchange plan.")
        )
    }
}
