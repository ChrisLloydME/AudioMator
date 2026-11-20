import Foundation
import TagLibAudioMetadata

/// Strict reviewed-write execution and the permit revocation hooks shared by the
/// source-membership, recovery and scope mutations owned by `AudioViewModel`.
extension AudioViewModel {
    // MARK: - Reviewed writes

    /// Executes one frozen reviewed write through the shared reservation,
    /// cancellation handler and commit permit. The captured nonoptional revision is
    /// the only expected version passed to the package.
    func executeReviewedMetadataWrite(
        _ write: ReviewedMetadataWrite,
        publication: MetadataPublicationPolicy
    ) async -> MetadataWriteExecutionResult {
        await executeReviewedWrite(
            write,
            draft: nil,
            publication: publication
        )
    }

    /// Executes one conflict-aware Inspector/Raw Editor draft. The resolver keeps
    /// its documented identity checks and policy-driven merge; the permit still
    /// gates membership, protection and cancellation.
    func executeReviewedDraftMetadataWrite(
        _ draft: ReviewedMetadataDraft,
        publication: MetadataPublicationPolicy
    ) async -> MetadataWriteExecutionResult {
        await executeReviewedWrite(
            draft.write,
            draft: draft,
            publication: publication
        )
    }

    private func executeReviewedWrite(
        _ write: ReviewedMetadataWrite,
        draft: ReviewedMetadataDraft?,
        publication: MetadataPublicationPolicy
    ) async -> MetadataWriteExecutionResult {
        let target = write.target

        // 1. Plan-time classification. A rejected or no-op intent never reaches a
        //    writer and never asks the user for authorization.
        switch write.projection.validation {
        case .executable:
            break
        case .rejected(let message):
            return .failure(message)
        case .unsupported(let fields):
            return .failure(Self.unsupportedReviewedWriteMessage(for: fields))
        }
        if write.isNoOp {
            return .success(
                MetadataWriteSuccessOutcome(warnings: [], didRefreshFileModel: true)
            )
        }

        // 2. Pre-prompt eligibility: current source membership, operational URL,
        //    recovery state and format. A stale capture cannot be authorized.
        if let failure = reviewedWriteEligibilityFailure(for: target, allowsChangedRevision: draft != nil) {
            return .failure(failure)
        }
        if let accessFailure = ensureReviewedMetadataDirectoryAccess(
            for: draft == nil ? [write] : [],
            conflictAwareWrites: draft == nil ? [] : [write]
        ) {
            return .failure(accessFailure)
        }

        // 3. Register the permit before queueing so cancellation can revoke it
        //    synchronously; unregister on operation exit. Conflict-aware drafts
        //    allow revision-only refreshes at the same path so the conflict
        //    resolver can evaluate merge/prefer-disk policies.
        let operationID = UUID()
        let permit = metadataCommitPermits.register(
            target: target,
            allowsChangedRevision: draft != nil,
            operationID: operationID
        )
        defer { metadataCommitPermits.unregister(fileID: target.id, operationID: operationID) }

        let executor = MetadataFileMutationExecutor(
            metadataPipeline: metadataPipeline,
            fileMutationCoordinator: fileMutationCoordinator
        )
        let refreshGeneration = makeFileModelRefreshGeneration()
        let admission: MetadataFileMutationAdmission = draft == nil
            ? .reviewed(target, permit: permit)
            : .reviewedDraft(target, permit: permit)
        let writeClosure = Self.reviewedWriteClosure(
            write,
            draft: draft,
            target: target
        )

        let result = await executor.execute(
            at: target.url,
            id: target.id,
            admission: admission,
            validateBeforeWrite: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.revalidateReviewedWriteTarget(
                    target,
                    allowsChangedRevision: draft != nil
                )
            },
            write: writeClosure
        )

        return publishReviewedWriteResult(
            result,
            write: write,
            target: target,
            refreshGeneration: refreshGeneration,
            publication: publication
        )
    }

    /// MainActor recheck inside the reservation: membership, URL, recovery state and
    /// (strict routes) the captured tokens must still describe the current
    /// observation. A refreshed observation with equal tokens remains eligible.
    private func revalidateReviewedWriteTarget(
        _ target: ReviewedMetadataTarget,
        allowsChangedRevision: Bool
    ) throws {
        try validateMetadataWriteRecovery(id: target.id, url: target.url)
        guard let current = committedFile(withID: target.id) else {
            throw ReviewedMetadataWriteError.fileNotLoaded(fileName: target.url.lastPathComponent)
        }
        guard target.associates(with: current) else {
            throw ReviewedMetadataWriteError.changedSinceReview(fileName: target.url.lastPathComponent)
        }
        guard !current.requiresMetadataRefreshBeforeWriting else {
            throw AudioFileFingerprintValidationError.recoveryRequired(
                fileName: target.url.lastPathComponent
            )
        }
        if !allowsChangedRevision, !target.matches(observation: current) {
            throw ReviewedMetadataWriteError.changedSinceReview(fileName: target.url.lastPathComponent)
        }
    }

    /// Pre-prompt eligibility classification. Returns a localized rejection or nil.
    func reviewedWriteEligibilityFailure(
        for target: ReviewedMetadataTarget,
        allowsChangedRevision: Bool
    ) -> String? {
        guard isTagWriteSupportedExtension(target.url.pathExtension) else {
            return String(localized: "AudioMator doesn't support saving metadata to this file format.")
        }
        if isRenameJournalBlocked(url: target.url) {
            return RenameJournalRecoveryError(fileName: target.url.lastPathComponent).errorDescription
        }
        if hasRecoveryDecision(for: target.id) {
            return AudioFileFingerprintValidationError.recoveryRequired(
                fileName: target.url.lastPathComponent
            ).errorDescription
        }
        guard let current = committedFile(withID: target.id) else {
            return String(localized: "This file is no longer loaded in AudioMator. Import it again before applying changes.")
        }
        guard target.associates(with: current), !current.requiresMetadataRefreshBeforeWriting else {
            return String(localized: "The file changed since it was reviewed. Review the current values before applying changes.")
        }
        if !allowsChangedRevision, !target.matches(observation: current) {
            return String(localized: "The file changed since it was reviewed. Close and reopen the tool, then review the current values before applying changes.")
        }
        return nil
    }

    /// Keeps the reviewed rows attached to their directory through authorization
    /// so an earlier modal prompt cannot leave a later prompt using stale eligibility.
    func ensureReviewedMetadataDirectoryAccess(
        for writes: [ReviewedMetadataWrite],
        conflictAwareWrites: [ReviewedMetadataWrite] = [],
        whileCurrent: () -> Bool = { true }
    ) -> String? {
        guard metadataPipeline.requiresTransactionalDirectoryAccess else { return nil }
        let candidates = writes.map { ($0, false) } + conflictAwareWrites.map { ($0, true) }
        var urls: [URL] = []
        var targetsByDirectory: [String: [(target: ReviewedMetadataTarget, allowsChangedRevision: Bool)]] = [:]
        for (write, allowsChangedRevision) in candidates where write.projection.isExecutable && !write.isNoOp {
            let url = write.target.url
            let directory = url.standardizedFileURL.deletingLastPathComponent()
            targetsByDirectory[FileSystemPathSemantics.key(for: directory), default: []].append(
                (write.target, allowsChangedRevision)
            )
            urls.append(url)
        }
        return ensureMutationDirectoryAccess(for: urls, whileCurrent: whileCurrent) { directory in
            targetsByDirectory[FileSystemPathSemantics.key(for: directory)]?.contains {
                reviewedWriteEligibilityFailure(
                    for: $0.target, allowsChangedRevision: $0.allowsChangedRevision
                ) == nil
            } == true
        }
    }

    private static func unsupportedReviewedWriteMessage(for fields: Set<MetadataFieldKey>) -> String {
        let labels = ListFormatter.localizedString(byJoining: fields.map {
            MetadataFieldRegistry.schema(for: $0)?.displayName ?? String(localized: "Metadata field")
        }.sorted())
        return String(localized: "Changes to \(labels) can’t be saved in this file format. No changes were saved.")
    }

    private static func reviewedWriteClosure(
        _ write: ReviewedMetadataWrite,
        draft: ReviewedMetadataDraft?,
        target: ReviewedMetadataTarget
    ) -> @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult {
        if let draft {
            return { pipeline, url in
                switch write.intent {
                case .semantic(let payload):
                    return try MetadataConflictResolver.writeMetadata(
                        payload,
                        original: draft.baseline,
                        originalFingerprint: target.fingerprint,
                        originalVersion: target.version,
                        policy: draft.policy,
                        pipeline: pipeline,
                        url: url
                    )
                case .raw(let patch):
                    // The resolver validates file identity and audio continuity,
                    // then merges the captured raw draft under the configured
                    // policy. The frozen exact delta is used only on the
                    // unchanged-revision fast path inside the resolver.
                    guard let rawDraft = draft.rawDraft else {
                        throw CocoaError(.featureUnsupported)
                    }
                    _ = patch
                    return try MetadataConflictResolver.writeRawMetadata(
                        rawDraft,
                        original: draft.baseline,
                        originalFingerprint: target.fingerprint,
                        originalVersion: target.version,
                        policy: draft.policy,
                        pipeline: pipeline,
                        url: url
                    )
                case .eraseAll:
                    throw CocoaError(.featureUnsupported)
                }
            }
        }
        return { pipeline, url in
            switch write.intent {
            case .semantic(let payload):
                return try pipeline.writeReviewedMetadata(
                    payload,
                    to: url,
                    expectedVersion: target.version
                )
            case .raw(let patch):
                return try pipeline.writeReviewedRawPatch(
                    patch,
                    to: url,
                    expectedVersion: target.version
                )
            case .eraseAll:
                return try pipeline.eraseAllMetadataReviewed(
                    at: url,
                    expectedVersion: target.version
                )
            }
        }
    }

    private func publishReviewedWriteResult(
        _ result: MetadataFileMutationResult,
        write: ReviewedMetadataWrite,
        target: ReviewedMetadataTarget,
        refreshGeneration: UInt64,
        publication: MetadataPublicationPolicy
    ) -> MetadataWriteExecutionResult {
        switch result {
        case .success(let success):
            var didApplyReloadedFile = false
            if let reloadedFile = success.reloadedFile {
                didApplyReloadedFile = replaceLoadedFile(
                    reloadedFile,
                    refreshGeneration: refreshGeneration,
                    deferVisibleRefresh: publication == .batched && metadataSaveProgress != nil
                )
            }

            var warnings = success.writeResult.warnings
            if case .durabilityUncertain(let detail) = success.writeResult.commitStatus {
                warnings.append(MetadataCommitWarning.durability(detail))
            }
            if let reloadErrorDescription = success.reloadErrorDescription {
                warnings.append(MetadataCommitWarning.reload(reloadErrorDescription))
            }

            return .success(
                MetadataWriteSuccessOutcome(
                    warnings: warnings,
                    didRefreshFileModel: didApplyReloadedFile
                )
            )

        case .failure(let reason):
            let affectedLabels: [String]
            switch write.intent {
            case .semantic(let payload):
                affectedLabels = payload.requestedFields.map { MetadataFieldGuide.displayName(for: $0) }
            case .raw(let patch):
                let keys = Array(Set(patch.valuesToSet.keys).union(patch.removingKeys))
                affectedLabels = keys.map {
                    MetadataFieldGuide.displayName(
                        forRawKey: $0,
                        fileExtensions: [target.url.pathExtension]
                    )
                }
            case .eraseAll:
                affectedLabels = []
            }
            return .failure(annotatingWriteFailureWithFields(reason, fieldLabels: affectedLabels))

        case .cancelled:
            return .cancelled
        }
    }

    // MARK: - Permit revocation hooks

    /// Called when files leave the authoritative source membership. A queued write
    /// for a removed file must fail before admission.
    func revokeCommitPermitsForRemovedSourceFiles(_ fileIDs: Set<AudioFile.ID>) {
        guard !fileIDs.isEmpty else { return }
        metadataCommitPermits.revoke(
            fileIDs: fileIDs,
            reason: .ineligible(String(localized: "The file was removed from its source before the change was written."))
        )
    }

    /// Called when a named recovery decision is recorded for a file.
    func revokeCommitPermitsForRecoveryDecision(_ fileID: AudioFile.ID) {
        metadataCommitPermits.revoke(
            fileID: fileID,
            reason: .ineligible(String(localized: "The file must be reloaded before it can be changed."))
        )
    }

    /// Called when an observation is published. Republishing an equal observation
    /// keeps its permit; an incompatible revision or a display projection revokes.
    func revokeCommitPermitsIfObservationIncompatible(_ file: AudioFile) {
        metadataCommitPermits.revokeIncompatibleObservation(
            file,
            reason: .ineligible(String(localized: "The file changed since this change was reviewed."))
        )
    }

    /// Called when a shared authorization scope is revoked.
    func revokeCommitPermitsForAccessScopeLoss() {
        metadataCommitPermits.revokeAll(
            reason: .ineligible(String(localized: "Access to the file’s folder was removed before the change was written."))
        )
    }
}

private enum ReviewedMetadataWriteError: LocalizedError {
    case fileNotLoaded(fileName: String)
    case changedSinceReview(fileName: String)

    var errorDescription: String? {
        switch self {
        case .fileNotLoaded(let fileName):
            return String(localized: "“\(fileName)” is no longer loaded in AudioMator. Import it again before applying changes.")
        case .changedSinceReview(let fileName):
            return String(localized: "“\(fileName)” changed since it was reviewed. Review the current values before applying changes.")
        }
    }
}
