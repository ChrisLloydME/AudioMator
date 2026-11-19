import Foundation
import TagLibAudioMetadata

/// LRCLIB lyrics application. Both entry points accept only the frozen intents
/// built by `LRCLIBLyricsWriteIntentBuilder`; there is deliberately no
/// `apply…(_ lyrics: String, to id: AudioFile.ID)` surface left.
///
/// Every disk mutation flows through `executeReviewedMetadataWrite`, i.e. the
/// shared strict route with its reservation, live-target recheck and commit
/// permit. The permit's first transition is the single ordering point between
/// cancellation and accepted work: a pending write is cancelled, and an admitted
/// one is never interrupted and reports its real outcome.
extension AudioViewModel {
    private var unreviewedLyricsEntryMessage: String {
        String(localized: "This lyrics result wasn’t built from a reviewed copy of this file. Close and reopen LRCLIB, then review the current lyrics before applying them.")
    }

    private var anotherSaveInProgressMessage: String {
        String(localized: "Another save is still in progress. Wait for it to finish, then try applying lyrics again.")
    }

    // MARK: - Manual (single file)

    func applyLRCLIBLyrics(_ intent: LRCLIBLyricsManualWriteIntent) async -> LRCLIBLyricsManualWriteOutcome {
        guard !Task.isCancelled else { return .cancelled }

        guard let write = intent.write else {
            let message = intent.rejection?.message ?? unreviewedLyricsEntryMessage
            presentMetadataWriteFailure(
                for: intent.fileName,
                reason: message,
                title: String(localized: "Lyrics Couldn’t Be Applied")
            )
            return .rejected(message)
        }
        guard intent.rejection == nil else {
            let message = intent.rejection?.message ?? unreviewedLyricsEntryMessage
            presentMetadataWriteFailure(
                for: intent.fileName,
                reason: message,
                title: String(localized: "Lyrics Couldn’t Be Applied")
            )
            return .rejected(message)
        }

        guard canStartExternalFileMutation() else {
            return .rejected(String(localized: "Save or discard the pending inspector edits before changing files from another tool."))
        }
        guard metadataSaveProgress == nil else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: anotherSaveInProgressMessage
            )
            return .rejected(anotherSaveInProgressMessage)
        }

        beginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: intent.fileName,
            totalUnitCount: 1
        )
        let result = await executeReviewedMetadataWrite(write, publication: .immediate)
        updateMetadataSaveProgress(subtitle: intent.fileName, completedUnitCount: 1)
        endMetadataSaveProgress()

        switch result {
        case .success(let success):
            if success.warnings.isEmpty {
                presentMetadataWriteHUD(
                    style: .success,
                    title: String(localized: "LRCLIB Lyrics Applied"),
                    subtitle: intent.fileName,
                    summary: intent.fileName,
                    details: ""
                )
            } else {
                presentMetadataWriteWarning(
                    title: String(localized: "Lyrics Saved with Warnings"),
                    fileName: intent.fileName,
                    warnings: success.warnings
                )
            }
            presentPostCommitInspectorRefreshIfClean(
                targetID: intent.fileID,
                refreshedFileModel: success.didRefreshFileModel
            )
            return .applied(warnings: success.warnings, refreshedFileModel: success.didRefreshFileModel)

        case .failure(let reason):
            presentMetadataWriteFailure(
                for: intent.fileName,
                reason: reason,
                title: String(localized: "Lyrics Couldn’t Be Applied")
            )
            return .rejected(reason)

        case .cancelled:
            // The session ended before this write crossed the commit boundary.
            // A started commit returns success/failure above, never this case.
            return .cancelled
        }
    }

    // MARK: - Bulk (auto-apply)

    func applyLRCLIBLyricsAutoMatches(
        _ intent: LRCLIBLyricsAutoWriteIntent
    ) async -> LRCLIBLyricsAutoWriteOutcome {
        let entries = intent.entries
        var summary = BatchMetadataOperationSummary(totalTargets: entries.count)
        var appliedEntries: [LRCLIBLyricsAppliedEntry] = []
        var succeededCount = 0
        var didCancel = false

        func outcome(cancelledBeforeAnyStart: Bool) -> LRCLIBLyricsAutoWriteOutcome {
            LRCLIBLyricsAutoWriteOutcome(
                appliedEntries: appliedEntries,
                summary: summary,
                succeededCount: succeededCount,
                didCancel: didCancel,
                cancelledBeforeAnyStart: cancelledBeforeAnyStart
            )
        }

        guard !Task.isCancelled else {
            didCancel = true
            summary.recordCancelledFiles(entries.map(\.fileName))
            return outcome(cancelledBeforeAnyStart: true)
        }

        guard !entries.isEmpty else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "No Synced Lyrics Available"),
                subtitle: String(localized: "LRCLIB didn't find synced lyrics for these files. Try different search details or choose another result.")
            )
            return outcome(cancelledBeforeAnyStart: false)
        }

        guard canStartExternalFileMutation() else {
            return outcome(cancelledBeforeAnyStart: false)
        }
        guard metadataSaveProgress == nil else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: anotherSaveInProgressMessage
            )
            return outcome(cancelledBeforeAnyStart: false)
        }

        beginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )

        // Pre-authorize the captured target folders once, like the previous bulk
        // path, but only after a cancellation checkpoint so a session that ended
        // before the handoff never asks for folder access.
        let targetURLs = entries.compactMap { $0.write?.target.url }
        if !targetURLs.isEmpty {
            if Task.isCancelled {
                didCancel = true
                summary.recordCancelledFiles(entries.map(\.fileName))
                endMetadataSaveProgress()
                return outcome(cancelledBeforeAnyStart: true)
            }
            if !prepareMetadataMutationDirectoryAccess(for: targetURLs) {
                for entry in entries {
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: entry.fileName,
                            messages: [String(localized: "Access to the file’s folder wasn’t granted, so this file wasn’t changed.")]
                        )
                    )
                }
                endMetadataSaveProgress()
                presentBatchMetadataOperationSummary(summary)
                return outcome(cancelledBeforeAnyStart: false)
            }
        }

        var index = 0
        while index < entries.count {
            if Task.isCancelled {
                summary.recordCancelledFiles(entries[index...].map(\.fileName))
                didCancel = true
                break
            }

            let entry = entries[index]
            updateMetadataSaveProgress(subtitle: entry.fileName, completedUnitCount: index)

            guard let write = entry.write else {
                let message = entry.rejection?.message ?? unreviewedLyricsEntryMessage
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(fileName: entry.fileName, messages: [message])
                )
                index += 1
                continue
            }

            let result = await executeReviewedMetadataWrite(write, publication: .batched)
            switch result {
            case .success(let success):
                succeededCount += 1
                summary.succeeded += 1
                appliedEntries.append(
                    LRCLIBLyricsAppliedEntry(fileID: entry.fileID, candidateID: entry.candidateID)
                )
                if !success.didRefreshFileModel {
                    summary.allSuccessfulFilesRefreshed = false
                }
                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(fileName: entry.fileName, messages: success.warnings)
                    )
                }
            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(fileName: entry.fileName, messages: [reason])
                )
            case .cancelled:
                // This file never crossed admission. It and everything after it
                // are recorded cancelled exactly once.
                summary.recordCancelledFiles([entry.fileName])
                summary.recordCancelledFiles(entries[(index + 1)...].map(\.fileName))
                didCancel = true
                index = entries.count
                continue
            }
            index += 1
        }

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: didCancel ? max(index, 0) : entries.count
        )
        endMetadataSaveProgress()

        // Report the real outcome whenever anything committed or genuinely failed.
        // A session that ended before any write started stays silent: the user has
        // left the tool and there is no started commit to report.
        let outcomeValue = outcome(cancelledBeforeAnyStart: false)
        if shouldPresentBulkOutcome(outcomeValue) {
            presentBatchMetadataOperationSummary(summary)
        }

        if summary.failureIssues.isEmpty,
           summary.allSuccessfulFilesRefreshed,
           !hasUnsavedInspectorChanges,
           selectedAudioIDs.contains(where: { id in appliedEntries.contains { $0.fileID == id } }) {
            updateEditForSelection()
        }

        return outcomeValue
    }

    private func shouldPresentBulkOutcome(_ outcome: LRCLIBLyricsAutoWriteOutcome) -> Bool {
        if outcome.didCommitAnything || outcome.realFailureCount > 0 {
            return true
        }
        return !outcome.didCancel
    }

    /// Interim AM-06/F3-b handoff: only refresh a clean, selected draft after this
    /// file's committed reload. The provider/MuseAmp/erase routes use the same
    /// conditional clean-refresh shape until the shared draft-session handoff lands.
    private func presentPostCommitInspectorRefreshIfClean(
        targetID: AudioFile.ID,
        refreshedFileModel: Bool
    ) {
        guard refreshedFileModel,
              selectedAudioIDs.contains(targetID),
              !hasUnsavedInspectorChanges else {
            return
        }
        updateEditForSelection()
    }
}
