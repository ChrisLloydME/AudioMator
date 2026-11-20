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
        guard let progressToken = tryBeginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: intent.fileName,
            totalUnitCount: 1
        ) else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: anotherSaveInProgressMessage
            )
            return .rejected(anotherSaveInProgressMessage)
        }
        defer { endMetadataSaveProgress(token: progressToken) }

        let result = await executeReviewedMetadataWrite(write, publication: .immediate)
        updateMetadataSaveProgress(
            token: progressToken,
            subtitle: intent.fileName,
            completedUnitCount: 1
        )
        endMetadataSaveProgress(token: progressToken)

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
        guard let progressToken = tryBeginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        ) else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: anotherSaveInProgressMessage
            )
            return outcome(cancelledBeforeAnyStart: false)
        }
        defer { endMetadataSaveProgress(token: progressToken) }

        // Pre-authorize the captured target folders once, only for currently
        // eligible executable writes, and only after a cancellation checkpoint
        // so a session that ended before the handoff never asks for folder access.
        let reviewedWrites = entries.compactMap { $0.write }
        if !reviewedWrites.isEmpty {
            if Task.isCancelled {
                didCancel = true
                summary.recordCancelledFiles(entries.map(\.fileName))
                endMetadataSaveProgress(token: progressToken)
                return outcome(cancelledBeforeAnyStart: true)
            }
            if !prepareMetadataMutationDirectoryAccess(for: reviewedWrites) {
                for entry in entries {
                    let message: String
                    if let rejection = entry.rejection {
                        message = rejection.message
                    } else if let write = entry.write,
                              let eligibilityFailure = reviewedWriteEligibilityFailure(
                                for: write.target,
                                allowsChangedRevision: false
                              ) {
                        message = eligibilityFailure
                    } else if entry.write == nil {
                        message = unreviewedLyricsEntryMessage
                    } else {
                        message = String(localized: "Access to the file’s folder wasn’t granted, so this file wasn’t changed.")
                    }
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: entry.fileName,
                            messages: [message]
                        )
                    )
                }
                endMetadataSaveProgress(token: progressToken)
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
            updateMetadataSaveProgress(token: progressToken, subtitle: entry.fileName, completedUnitCount: index)

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
            token: progressToken,
            subtitle: "Finishing...",
            completedUnitCount: didCancel ? max(index, 0) : entries.count
        )
        endMetadataSaveProgress(token: progressToken)

        // Report the real outcome whenever anything committed or genuinely failed.
        // A session that ended before any write started stays silent: the user has
        // left the tool and there is no started commit to report.
        let outcomeValue = outcome(
            cancelledBeforeAnyStart: didCancel && succeededCount == 0 && summary.failureIssues.isEmpty
        )
        if shouldPresentBulkOutcome(outcomeValue) {
            presentBatchMetadataOperationSummary(summary)
        }

        if !appliedEntries.isEmpty,
           selectedAudioIDs.contains(where: { id in appliedEntries.contains { $0.fileID == id } }) {
            refreshInspectorDraftAfterAcceptedPublication()
        }

        return outcomeValue
    }

    private func shouldPresentBulkOutcome(_ outcome: LRCLIBLyricsAutoWriteOutcome) -> Bool {
        if outcome.didCommitAnything || outcome.realFailureCount > 0 {
            return true
        }
        return !outcome.didCancel
    }

    private func presentPostCommitInspectorRefreshIfClean(
        targetID: AudioFile.ID,
        refreshedFileModel: Bool
    ) {
        guard refreshedFileModel,
              selectedAudioIDs.contains(targetID) else {
            return
        }
        refreshInspectorDraftAfterAcceptedPublication()
    }
}
