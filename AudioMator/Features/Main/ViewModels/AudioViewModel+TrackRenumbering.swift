import Foundation
import TagLibAudioMetadata

extension AudioViewModel {
    // MARK: - Reviewed track renumbering

    /// Builds the reviewed renumber plan from the supplied middle-list order.
    ///
    /// `orderedFiles` is the resolver output (manual order and column sort
    /// already applied). An empty selection continues to mean the whole current
    /// list. Recovery decisions currently recorded by the view model classify
    /// their files before numbering.
    func makeTrackRenumberPlan(
        orderedFiles: [AudioFile],
        selectedIDs: Set<AudioFile.ID>,
        direction: TrackRenumberDirection,
        startNumberText: String
    ) -> TrackRenumberPlan {
        let recoveryBlockedIDs = Set(
            orderedFiles.map(\.id).filter { hasRecoveryDecision(for: $0) }
        )
        return TrackRenumberPlanner.makePlan(
            orderedFiles: orderedFiles,
            selectedIDs: selectedIDs,
            direction: direction,
            startNumberText: startNumberText,
            recoveryBlockedIDs: recoveryBlockedIDs,
            projector: metadataPipeline
        )
    }

    /// Executes exactly the reviewed plan the preview showed.
    ///
    /// Eligibility, numbering, review authority and payloads were frozen by the
    /// planner. The shared strict executor rechecks current membership, recovery
    /// state, the captured fingerprint and the captured package revision under the
    /// path reservation before the package performs the guarded track-only write.
    ///
    /// Execution stays serial: a runtime failure keeps that row's reviewed number
    /// and leaves the other reviewed assignments untouched. Cancellation stops
    /// before starting the next row; an already committed row keeps its real
    /// outcome and bounded readback.
    func renumberTrackNumbers(using plan: TrackRenumberPlan) async -> TrackRenumberResult {
        var result = plan.resultBaseline()

        // An invalid start entry is explicit invalid state: Apply is disabled and a
        // stale direct call issues no write at all.
        guard plan.isStartValid else { return result }

        let executableRows = plan.executableRows
        guard !executableRows.isEmpty else { return result }

        guard canStartExternalFileMutation() else { return .empty }

        // Ask for the required directory access once, before the first write, using
        // only currently eligible reviewed URLs. Precondition failures and rows
        // already rejected by current eligibility never prompt.
        let prePromptURLs = prePromptDirectoryAccessURLs(
            for: executableRows.compactMap { $0.executableWrite?.reviewedWrite }
        )
        if !prePromptURLs.isEmpty,
           let accessFailure = ensureMetadataMutationDirectoryAccess(for: prePromptURLs) {
            for row in executableRows {
                let reason: String
                if let write = row.executableWrite?.reviewedWrite,
                   let eligibilityFailure = reviewedWriteEligibilityFailure(
                    for: write.target,
                    allowsChangedRevision: false
                   ) {
                    reason = eligibilityFailure
                } else {
                    reason = accessFailure
                }
                result.failed += 1
                result.failures.append(
                    TrackRenumberFailure(fileName: row.fileName, reason: reason)
                )
            }
            return result
        }

        var didRefreshFileModel = false
        for (index, row) in executableRows.enumerated() {
            if Task.isCancelled {
                let unprocessed = executableRows.dropFirst(index)
                result.cancelled.append(contentsOf: unprocessed.map {
                    TrackRenumberFailure(
                        fileName: $0.fileName,
                        reason: String(localized: "Cancelled before this file was processed. This file wasn't changed.")
                    )
                })
                break
            }

            guard let write = row.executableWrite else { continue }
            let outcome = await executeReviewedMetadataWrite(write.reviewedWrite, publication: .batched)
            switch outcome {
            case .success(let success):
                result.succeeded += 1
                didRefreshFileModel = didRefreshFileModel || success.didRefreshFileModel
                if !success.warnings.isEmpty {
                    result.warnings.append(
                        TrackRenumberWarning(fileName: row.fileName, messages: success.warnings)
                    )
                }
            case .failure(let reason):
                result.failed += 1
                result.failures.append(
                    TrackRenumberFailure(fileName: row.fileName, reason: reason)
                )
            case .cancelled:
                let remaining = executableRows.dropFirst(index)
                let message = (result.succeeded == 0 && result.failed == 0)
                    ? String(localized: "Track numbering was cancelled before it began. No track numbers were changed.")
                    : String(localized: "Cancelled before this file was processed. This file wasn't changed.")
                result.cancelled.append(contentsOf: remaining.map {
                    TrackRenumberFailure(fileName: $0.fileName, reason: message)
                })
                break
            }
            if !result.cancelled.isEmpty {
                break
            }
        }

        if didRefreshFileModel {
            refreshInspectorDraftAfterAcceptedPublication()
        }

        return result
    }
}
