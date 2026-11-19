import Foundation
import TagLibAudioMetadata

struct RawMetadataApplyResult {
    let succeededTargetIDs: Set<AudioFile.ID>
    let failedTargetIDs: Set<AudioFile.ID>

    var didApplyAllChanges: Bool {
        failedTargetIDs.isEmpty
    }
}

/// One captured raw-editor target. The reviewed target and exact per-key delta are
/// frozen from the editor's reviewed original map before any suspension; the model
/// loaded at Apply is never consulted for revision authority or baseline content.
private struct RawMetadataWritePlan: Sendable {
    let targetID: AudioFile.ID
    let fileName: String
    let url: URL
    let route: Route

    enum Route: Sendable {
        case draft(ReviewedMetadataDraft)
        case strict(ReviewedMetadataWrite)
        case unchanged
        case rejected(String)
    }
}

extension AudioViewModel {
    /// Applies one captured raw-editor session through the F3 apply/request/outcome
    /// API. Every target is planned before authorization; targets without a
    /// coherent reviewed observation or captured original map fail closed.
    ///
    /// The raw editor keeps its low-level exception from semantic field preflight,
    /// but revision authority is required: there is no unversioned fallback.
    func applyRawMetadataApplyRequest(
        _ request: MetadataEditorApplyRequest
    ) async -> MetadataEditorApplyOutcome {
        let targets = request.pendingTargets
        guard !targets.isEmpty else {
            return MetadataEditorApplyOutcome(
                presentationID: request.presentationID,
                applyID: request.applyID,
                succeededTargetIDs: [],
                failedTargetIDs: [],
                didApplyAllChanges: true
            )
        }
        guard canStartExternalFileMutation() else {
            return Self.rawApplyOutcome(
                request,
                failed: Set(targets.map(\.id)),
                succeeded: []
            )
        }

        let policy = MetadataConflictPolicy.load(from: conflictPolicyDefaults)
        var plans: [RawMetadataWritePlan] = []
        for target in targets {
            plans.append(
                makeRawMetadataWritePlan(
                    target: target,
                    request: request,
                    policy: policy
                )
            )
        }

        let writableURLs = plans.compactMap { plan -> URL? in
            switch plan.route {
            case .unchanged, .rejected:
                return nil
            case .draft, .strict:
                return plan.url
            }
        }
        guard prepareMetadataMutationDirectoryAccess(for: writableURLs) else {
            return Self.rawApplyOutcome(
                request,
                failed: Set(targets.map(\.id)),
                succeeded: []
            )
        }

        var summary = BatchMetadataOperationSummary(totalTargets: plans.count)
        var succeededTargetIDs = Set<AudioFile.ID>()
        var failedTargetIDs = Set<AudioFile.ID>()
        var didCancelUnprocessed = false

        for (index, plan) in plans.enumerated() {
            if Task.isCancelled {
                let unprocessed = plans.dropFirst(index)
                failedTargetIDs.formUnion(unprocessed.map(\.targetID))
                summary.recordCancelledFiles(unprocessed.map(\.fileName))
                didCancelUnprocessed = true
                break
            }

            let result: MetadataWriteExecutionResult
            switch plan.route {
            case .rejected(let reason):
                result = .failure(reason)
            case .unchanged:
                result = .success(
                    MetadataWriteSuccessOutcome(warnings: [], didRefreshFileModel: true)
                )
            case .strict(let write):
                result = await executeReviewedMetadataWrite(write, publication: .batched)
            case .draft(let draft):
                result = await executeReviewedDraftMetadataWrite(draft, publication: .batched)
            }

            switch result {
            case .success(let success):
                summary.succeeded += 1
                succeededTargetIDs.insert(plan.targetID)
                if !success.didRefreshFileModel {
                    summary.allSuccessfulFilesRefreshed = false
                }
                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: plan.fileName,
                            messages: success.warnings
                        )
                    )
                }

            case .failure(let reason):
                failedTargetIDs.insert(plan.targetID)
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: plan.fileName,
                        messages: [reason]
                    )
                )

            case .cancelled:
                failedTargetIDs.insert(plan.targetID)
                summary.recordCancelledFiles([plan.fileName])
            }
        }

        presentBatchMetadataOperationSummary(summary)

        return MetadataEditorApplyOutcome(
            presentationID: request.presentationID,
            applyID: request.applyID,
            succeededTargetIDs: succeededTargetIDs,
            failedTargetIDs: failedTargetIDs,
            didApplyAllChanges: failedTargetIDs.isEmpty,
            wasCancelled: didCancelUnprocessed
        )
    }

    /// Compatibility seam for direct callers and existing integration tests.
    ///
    /// It captures the same reviewed targets/deltas as the window route and
    /// returns the same per-target accounting; it must not be used to bypass the
    /// session-scoped API from the editor window.
    @discardableResult
    func applyRawMetadataPropertyMaps(
        _ propertyMaps: [AudioFile.ID: RawMetadataValueMap],
        to targets: [MetadataEditorTarget]
    ) async -> RawMetadataApplyResult {
        let request = MetadataEditorApplyRequest(
            presentationID: MetadataEditorPresentationID(),
            applyID: MetadataEditorApplyID(),
            targets: targets,
            pendingTargets: targets,
            submittedPropertyMaps: propertyMaps,
            draftGeneration: 0
        )
        let outcome = await applyRawMetadataApplyRequest(request)
        return RawMetadataApplyResult(
            succeededTargetIDs: outcome.succeededTargetIDs,
            failedTargetIDs: outcome.failedTargetIDs
        )
    }

    // MARK: - Captured raw plan construction

    private func makeRawMetadataWritePlan(
        target: MetadataEditorTarget,
        request: MetadataEditorApplyRequest,
        policy: MetadataConflictPolicy
    ) -> RawMetadataWritePlan {
        func plan(_ route: RawMetadataWritePlan.Route) -> RawMetadataWritePlan {
            RawMetadataWritePlan(
                targetID: target.id,
                fileName: target.fileName,
                url: target.url,
                route: route
            )
        }

        guard let reviewedTarget = target.reviewedTarget else {
            return plan(.rejected(Self.rawReviewedTargetUnavailableMessage))
        }
        guard let baseline = target.metadataConflictBaseline else {
            return plan(.rejected(Self.rawReviewedTargetUnavailableMessage))
        }
        guard let submitted = request.submittedPropertyMaps[target.id] else {
            return plan(.rejected(String(localized: "Metadata wasn’t loaded for this file. Close and reopen the Metadata Editor. No changes were saved.")))
        }
        guard isTagWriteSupportedExtension(target.url.pathExtension) else {
            return plan(.rejected(String(localized: "AudioMator doesn't support saving metadata to this file format.")))
        }

        // Capture the exact key-level delta. The production route consumes the
        // editor's captured per-file/key changes and proves every before/after
        // array against the captured original map, so the intent can never be
        // rebuilt from current disk. The compatibility seam (direct callers) has
        // no captured changes and derives the delta from the reviewed baseline.
        let original = baseline.values
        let patch: RawMetadataPatch
        if request.hasCapturedChanges {
            let changes = request.changes(for: target.id)
            guard !changes.isEmpty else { return plan(.unchanged) }
            guard let capturedOriginal = request.submittedOriginalPropertyMaps[target.id] else {
                return plan(.rejected(Self.rawReviewedTargetUnavailableMessage))
            }

            var valuesToSet: [String: [String]] = [:]
            var removingKeys: Set<String> = []
            for change in changes {
                guard change.beforeValues == capturedOriginal[change.key],
                      change.afterValues == submitted[change.key] else {
                    return plan(.rejected(Self.rawCapturedDeltaMismatchMessage))
                }
                if let afterValues = change.afterValues {
                    guard !afterValues.isEmpty else {
                        return plan(.rejected(Self.rawEmptyValueListMessage))
                    }
                    valuesToSet[change.key] = afterValues
                } else {
                    removingKeys.insert(change.key)
                }
            }
            guard capturedOriginal == original else {
                return plan(.rejected(Self.rawCapturedDeltaMismatchMessage))
            }
            let capturedPatch = RawMetadataPatch(
                valuesToSet: valuesToSet,
                removingKeys: removingKeys
            )
            let baselinePatch = RawMetadataPatch(
                valuesToSet: submitted.filter { original[$0.key] != $0.value },
                removingKeys: Set(original.keys).subtracting(submitted.keys)
            )
            guard capturedPatch.valuesToSet == baselinePatch.valuesToSet,
                  capturedPatch.removingKeys == baselinePatch.removingKeys else {
                return plan(.rejected(Self.rawCapturedDeltaMismatchMessage))
            }
            patch = capturedPatch
        } else {
            patch = RawMetadataPatch(
                valuesToSet: submitted.filter { original[$0.key] != $0.value },
                removingKeys: Set(original.keys).subtracting(submitted.keys)
            )
        }

        if patch.valuesToSet.isEmpty && patch.removingKeys.isEmpty {
            return plan(.unchanged)
        }

        guard let projection = try? TagLibAudioMetadataPipeline().projectMetadataWrite(
            .raw(patch),
            fileExtension: target.url.pathExtension
        ) else {
            return plan(.rejected(Self.rawReviewedTargetUnavailableMessage))
        }
        switch projection.validation {
        case .executable:
            break
        case .rejected(let message):
            return plan(.rejected(message))
        case .unsupported:
            return plan(.rejected(String(localized: "AudioMator doesn't support writing raw metadata values to this file format.")))
        }

        let write = ReviewedMetadataWrite(
            target: reviewedTarget,
            intent: .raw(patch),
            projection: projection
        )
        return plan(.draft(ReviewedMetadataDraft(
            write: write,
            baseline: baseline,
            policy: policy,
            rawDraft: submitted
        )))
    }

    private static func rawApplyOutcome(
        _ request: MetadataEditorApplyRequest,
        failed: Set<AudioFile.ID>,
        succeeded: Set<AudioFile.ID>
    ) -> MetadataEditorApplyOutcome {
        MetadataEditorApplyOutcome(
            presentationID: request.presentationID,
            applyID: request.applyID,
            succeededTargetIDs: succeeded,
            failedTargetIDs: failed,
            didApplyAllChanges: failed.isEmpty
        )
    }

    private static var rawReviewedTargetUnavailableMessage: String {
        String(localized: "The file couldn’t be checked for changes. Close the Metadata Editor, choose Reload from Disk from the file’s context menu, then reopen the editor.")
    }

    private static var rawCapturedDeltaMismatchMessage: String {
        String(localized: "The reviewed changes no longer match this file’s captured values. Close the Metadata Editor, review the current values, and try again.")
    }

    private static var rawEmptyValueListMessage: String {
        String(localized: "An empty value list can’t be saved. Add at least one value, or use Delete Field to remove the metadata field.")
    }
}
