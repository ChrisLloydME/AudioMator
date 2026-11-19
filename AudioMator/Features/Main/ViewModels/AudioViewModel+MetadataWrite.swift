import Foundation
import TagLibAudioMetadata

nonisolated func unsupportedMetadataWriteFields(
    in editPayload: MetadataEditPayload,
    forFileExtension fileExtension: String
) -> Set<MetadataFieldKey> {
    unsupportedMetadataWriteFields(
        editPayload.requestedFields,
        forFileExtension: fileExtension
    )
}

nonisolated func unsupportedMetadataWriteFields(
    _ requestedFields: Set<MetadataFieldKey>,
    forFileExtension fileExtension: String
) -> Set<MetadataFieldKey> {
    guard !requestedFields.isEmpty else { return [] }
    guard let writableFields = AudioFormatSupport.writableMetadataFields(for: fileExtension) else {
        // Missing concrete-format capability information is not permission to
        // write: treat every requested field as unsupported (fail closed).
        return requestedFields
    }
    return requestedFields.subtracting(writableFields)
}

/// One captured Inspector save target. The reviewed target and frozen payload are
/// built from `inspectorEditSourceFilesByID` at save start, before the bounded
/// batch or any suspension; the model loaded at Apply is never consulted for
/// revision authority.
private struct InspectorWritePlan: Sendable {
    enum Route: Sendable {
        case draft(ReviewedMetadataDraft)
        case strict(ReviewedMetadataWrite)
        case rejected(String)
    }

    let targetID: AudioFile.ID
    let fileName: String
    let url: URL
    /// Snapshot identity of the captured Inspector source observation. Completion
    /// may advance this file's baseline only while the draft still represents it.
    let sourceSnapshotID: UUID?
    let route: Route
}

extension AudioViewModel {
    // MARK: - Inspector Writes (TagLib)

    func saveInspectorEdits() {
        guard metadataSaveProgress == nil else { return }
        guard !hasInspectorPendingReview else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Inspector Draft Needs Review"),
                subtitle: String(localized: "Resume editing the captured files or discard the pending Inspector edits before saving.")
            )
            return
        }
        guard hasUnsavedInspectorChanges else { return }

        if selectedAudioIDs.count > 1 {
            saveMultiFileEdits()
        } else {
            saveSingleEdits()
        }
    }

    /// Writes the current inspector edits back to the selected audio file.
    ///
    /// The write is authoritatively bound to the captured Inspector source
    /// observation (`inspectorEditSourceFilesByID`): a missing source or missing
    /// disk tokens fail closed instead of borrowing the model loaded at Apply.
    /// The documented conflict-aware draft route runs through
    /// `executeReviewedDraftMetadataWrite`, whose resolver keeps its baseline,
    /// policy and audio-identity checks.
    func saveSingleEdits() {
        guard
            let edit = edit,
            let id = selectedAudioIDs.first
        else {
            return
        }

        guard editSourceFileID == id else {
            updateEditForSelection()
            return
        }

        guard let sourceFile = inspectorEditSourceFilesByID[id] else {
            presentMetadataWriteFailure(
                for: fileNameForInspectorTarget(id)
                    ?? String(localized: "This file"),
                reason: Self.inspectorSourceUnavailableMessage
            )
            return
        }

        guard let receipt = captureInspectorSaveReceipt() else { return }
        let plan = makeInspectorWritePlan(
            edit: edit,
            sourceFile: sourceFile,
            sessionID: receipt.identity.sessionID,
            targetIDs: receipt.targetIDs
        )
        if case .rejected(let message) = plan.route {
            finishInspectorSave()
            presentMetadataWriteFailure(for: plan.fileName, reason: message)
            return
        }

        beginMetadataSaveProgress(
            title: "Saving Metadata",
            subtitle: plan.fileName,
            totalUnitCount: 1
        )

        Task(priority: .userInitiated) {
            let result = await self.executeInspectorWritePlan(plan, publication: .immediate)
            self.updateMetadataSaveProgress(
                subtitle: plan.fileName,
                completedUnitCount: 1
            )
            self.endMetadataSaveProgress()

            switch result {
            case .success(let success):
                self.recordInspectorSaveTargetCompletion(
                    InspectorSavedTargetOutcome(
                        targetID: plan.targetID,
                        didRefreshFileModel: success.didRefreshFileModel,
                        readback: success.didRefreshFileModel
                            ? self.loadedFile(withID: plan.targetID) : nil
                    )
                )
                self.finishInspectorSave()
                self.publishInspectorSingleSaveSuccess(plan: plan, success: success)
            case .failure(let reason):
                self.finishInspectorSave()
                self.presentMetadataWriteFailure(for: plan.fileName, reason: reason)
            case .cancelled:
                self.finishInspectorSave()
                self.presentMetadataWriteCancellation(for: plan.fileName)
            }
        }
    }

    /// Applies only the modified multi-file fields to each selected file.
    ///
    /// Every target/payload pair is captured before the bounded batch starts. A
    /// selected file without a captured Inspector source observation becomes a
    /// rejected row; the live model is not used to synthesize authority.
    func saveMultiFileEdits() {
        guard selectedAudioIDs.count > 1, let multiEdit else {
            return
        }

        guard multiEdit.hasUnsavedChanges else {
            return
        }

        let completedEdits = completedInspectorEditsByID
        let editSnapshot = multiEdit
        let selectionSnapshot = selectedAudioIDs
        guard let receipt = captureInspectorSaveReceipt() else { return }
        let sessionID = receipt.identity.sessionID
        let sessionTargetIDs = receipt.targetIDs

        var plans: [InspectorWritePlan] = []
        for file in files where selectedAudioIDs.contains(file.id) {
            guard let sourceFile = inspectorEditSourceFilesByID[file.id] else {
                plans.append(
                    InspectorWritePlan(
                        targetID: file.id,
                        fileName: file.url.lastPathComponent,
                        url: file.url,
                        sourceSnapshotID: nil,
                        route: .rejected(Self.inspectorSourceUnavailableMessage)
                    )
                )
                continue
            }

            guard multiEdit.hasPendingChanges(
                comparedTo: sourceFile,
                excluding: completedEdits[file.id]
            ) else {
                continue
            }

            let effectiveEdit = editSnapshot.applyingChanges(
                to: sourceFile,
                excluding: completedEdits[file.id]
            )
            plans.append(
                makeInspectorWritePlan(
                    edit: effectiveEdit,
                    sourceFile: sourceFile,
                    sessionID: sessionID,
                    targetIDs: sessionTargetIDs
                )
            )
        }
        guard !plans.isEmpty else { return }
        guard prepareMetadataMutationDirectoryAccess(for: plans.map(\.url)) else { return }

        beginMetadataSaveProgress(
            title: "Saving Metadata",
            subtitle: "Preparing \(plans.count) files…",
            totalUnitCount: plans.count
        )

        Task(priority: .userInitiated) {
            var summary = BatchMetadataOperationSummary(totalTargets: plans.count)
            var completedCount = 0
            var resultsByIndex: [Int: MetadataWriteExecutionResult] = [:]

            await MetadataBatchExecutor.execute(count: plans.count) { index in
                let plan = plans[index]
                return await self.executeInspectorWritePlan(plan, publication: .batched)
            } onCompletion: { index, result in
                let plan = plans[index]
                completedCount += 1
                resultsByIndex[index] = result
                self.updateMetadataSaveProgress(
                    subtitle: plan.fileName,
                    completedUnitCount: completedCount
                )

                if case .success(let success) = result {
                    self.recordInspectorSaveTargetCompletion(
                        InspectorSavedTargetOutcome(
                            targetID: plan.targetID,
                            didRefreshFileModel: success.didRefreshFileModel,
                            readback: success.didRefreshFileModel
                                ? self.loadedFile(withID: plan.targetID) : nil
                        )
                    )
                }
            }

            // Keep issue presentation in captured plan order, independent of disk timing.
            for (index, plan) in plans.enumerated() {
                guard let result = resultsByIndex[index] else { continue }
                switch result {
                case .success(let success):
                    summary.succeeded += 1
                    summary.allSuccessfulFilesRefreshed =
                        summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                    if !success.warnings.isEmpty {
                        summary.warningIssues.append(
                            BatchMetadataWriteIssue(
                                fileName: plan.fileName,
                                messages: success.warnings
                            )
                        )
                    }
                case .failure(let reason):
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: plan.fileName,
                            messages: [reason]
                        )
                    )
                case .cancelled:
                    summary.recordCancelledFiles([plan.fileName])
                }
            }

            self.updateMetadataSaveProgress(
                subtitle: "Finishing…",
                completedUnitCount: plans.count
            )
            self.endMetadataSaveProgress()

            self.finishInspectorSave()
            self.presentBatchMetadataOperationSummary(summary)
        }
    }

    // MARK: - Inspector captured plan construction and execution

    /// Builds the frozen reviewed plan for one captured Inspector target.
    private func makeInspectorWritePlan(
        edit: SingleFileEditModel,
        sourceFile: AudioFile,
        sessionID: InspectorDraftSessionID,
        targetIDs: [AudioFile.ID]
    ) -> InspectorWritePlan {
        // Capture the F3 draft identity with the plan so a completion can be
        // scoped to the draft that submitted it. Session IDs never substitute for
        // disk tokens; they only guard presentation.
        _ = InspectorDraftIdentity(
            sessionID: sessionID,
            targetIDs: targetIDs,
            editGeneration: 0,
            artworkGeneration: 0
        )

        let targetID = sourceFile.id
        let fileName = sourceFile.url.lastPathComponent
        let url = sourceFile.url
        let snapshotID: UUID? = sourceFile.snapshotID

        func plan(_ route: InspectorWritePlan.Route) -> InspectorWritePlan {
            InspectorWritePlan(
                targetID: targetID,
                fileName: fileName,
                url: url,
                sourceSnapshotID: snapshotID,
                route: route
            )
        }

        guard !sourceFile.requiresMetadataRefreshBeforeWriting else {
            return plan(.rejected(Self.inspectorRecoveryRequiredMessage))
        }
        guard isTagWriteSupportedExtension(sourceFile.url.pathExtension) else {
            return plan(.rejected(String(localized: "AudioMator doesn't support saving metadata to this file format.")))
        }
        guard let write = ReviewedMetadataWriteFactory.semanticWrite(
            edit: edit,
            comparedTo: sourceFile
        ) else {
            return plan(.rejected(Self.inspectorSourceUnavailableMessage))
        }

        switch write.projection.validation {
        case .rejected(let message):
            return plan(.rejected(message))
        case .unsupported(let fields):
            return plan(.rejected(Self.unsupportedInspectorFieldsMessage(fields)))
        case .executable:
            break
        }

        // A genuinely unchanged edit produces no write; the executor classifies
        // the frozen projection as a no-op and reports success without a writer.
        if write.isNoOp {
            return plan(.strict(write))
        }

        let policy = MetadataConflictPolicy.load(from: conflictPolicyDefaults)
        if let baseline = sourceFile.metadataConflictBaseline {
            return plan(.draft(ReviewedMetadataDraft(
                write: write,
                baseline: baseline,
                policy: policy
            )))
        }
        return plan(.strict(write))
    }

    private func executeInspectorWritePlan(
        _ plan: InspectorWritePlan,
        publication: MetadataPublicationPolicy
    ) async -> MetadataWriteExecutionResult {
        switch plan.route {
        case .rejected(let message):
            return .failure(message)
        case .strict(let write):
            return await executeReviewedMetadataWrite(write, publication: publication)
        case .draft(let draft):
            return await executeReviewedDraftMetadataWrite(draft, publication: publication)
        }
    }

    /// Presents the single-file save outcome. Draft baseline advancement is done
    /// by the F3 draft-session completion before this presentation helper.
    private func publishInspectorSingleSaveSuccess(
        plan: InspectorWritePlan,
        success: MetadataWriteSuccessOutcome
    ) {
        if success.warnings.isEmpty {
            presentMetadataWriteSuccess(for: plan.fileName)
        } else {
            presentMetadataWriteWarning(
                title: String(localized: "Changes Saved with Warnings"),
                fileName: plan.fileName,
                warnings: success.warnings
            )
        }
    }

    private func fileNameForInspectorTarget(_ id: AudioFile.ID) -> String? {
        inspectorEditSourceFilesByID[id]?.url.lastPathComponent
            ?? files.first(where: { $0.id == id })?.url.lastPathComponent
    }

    private static func unsupportedInspectorFieldsMessage(
        _ fields: Set<MetadataFieldKey>
    ) -> String {
        let labels = ListFormatter.localizedString(byJoining: fields.map {
            MetadataFieldRegistry.schema(for: $0)?.displayName ?? String(localized: "Metadata field")
        }.sorted())
        return String(localized: "Changes to \(labels) can’t be saved in this file format. No changes were saved.")
    }

    private static var inspectorSourceUnavailableMessage: String {
        String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")
    }

    private static var inspectorRecoveryRequiredMessage: String {
        String(localized: "The file couldn’t be checked after it moved. Before editing, choose Reload from Disk from the file’s context menu.")
    }

    // MARK: - Temporary unmigrated writer

    /// **Temporary unmigrated helper.** Inspector saves no longer use this mixed
    /// route. It remains only for callers scheduled to migrate in later packages
    /// (E1 exchange/filename plans, N1 LRCLIB, rename follow-ups) and legacy
    /// conflict-policy tests. Do not add new callers; delete after the final
    /// family migration.
    func persistMetadataEdit(
        _ edit: SingleFileEditModel,
        to file: AudioFile,
        comparedTo sourceFile: AudioFile? = nil,
        syncInspectorAfterReload: Bool = true,
        expectedFileFingerprint: AudioFileFingerprint? = nil,
        expectedMetadataVersion: MetadataFileVersion? = nil
    ) async -> MetadataWriteExecutionResult {
        guard !file.requiresMetadataRefreshBeforeWriting else {
            return .failure(
                String(localized: "The file couldn’t be checked after it moved. Before editing, choose Reload from Disk from the file’s context menu. Unsaved Inspector edits must be discarded to reload.")
            )
        }
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            return .failure(String(localized: "AudioMator doesn't support saving metadata to this file format."))
        }

        let editPayload = MetadataEditPayload(edit, comparedTo: sourceFile ?? file)
        if let message = editPayload.numberPairValidationMessage {
            return .failure(message)
        }
        if let message = editPayload.dateValidationMessage {
            return .failure(message)
        }
        let unsupportedFields = unsupportedMetadataWriteFields(
            in: editPayload,
            forFileExtension: file.url.pathExtension
        )
        if !unsupportedFields.isEmpty {
            let labels = ListFormatter.localizedString(byJoining: unsupportedFields.map {
                MetadataFieldRegistry.schema(for: $0)?.displayName ?? String(localized: "Metadata field")
            }.sorted())
            return .failure(
                String(localized: "Changes to \(labels) can’t be saved in this file format. No changes were saved.")
            )
        }

        let policy = MetadataConflictPolicy.load(from: conflictPolicyDefaults)
        let baselineFile = sourceFile ?? file
        let canResolve = sourceFile != nil
            && baselineFile.metadataConflictBaseline != nil
            && baselineFile.fileFingerprint != nil
            && baselineFile.metadataFileVersion != nil
            && (expectedFileFingerprint == nil || expectedFileFingerprint == baselineFile.fileFingerprint)
            && (expectedMetadataVersion == nil || expectedMetadataVersion == baselineFile.metadataFileVersion)

        return await executeMetadataFileMutation(
            at: file.url,
            id: file.id,
            // The resolver performs a fresh read and identity validation inside
            // the same reservation; strict preview-based writes keep this guard.
            expectedFileFingerprint: canResolve ? nil : expectedFileFingerprint,
            syncInspectorAfterReload: syncInspectorAfterReload
        ) { metadataPipeline, url in
            if canResolve, let baseline = baselineFile.metadataConflictBaseline,
               let fingerprint = baselineFile.fileFingerprint,
               let version = baselineFile.metadataFileVersion {
                return try MetadataConflictResolver.writeMetadata(
                    editPayload,
                    original: baseline,
                    originalFingerprint: fingerprint,
                    originalVersion: version,
                    policy: policy,
                    pipeline: metadataPipeline,
                    url: url
                )
            }
            return try metadataPipeline.writeMetadata(
                editPayload,
                to: url,
                expectedVersion: expectedMetadataVersion ?? file.metadataFileVersion
            )
        }
    }

    func presentBatchMetadataOperationSummary(_ summary: BatchMetadataOperationSummary) {
        guard summary.totalTargets > 0 else { return }

        saveIssueLogStore.record(summary: summary)

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
    }

}
