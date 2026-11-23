import Foundation
import TagLibAudioMetadata

// MARK: - Environment

/// Injected collaborators for progressive Quick Import. Production uses the
/// filesystem provider and the system security-scope APIs; tests forward
/// counting/synthetic adapters through the `AudioViewModel` initializer.
struct QuickImportEnvironment: Sendable {
    let identityProvider: any QuickImportPathIdentityProviding
    let scopeAccess: any QuickImportScopeAccessing
    let loadPolicy: QuickImportLoadPolicy

    init(
        identityProvider: any QuickImportPathIdentityProviding,
        scopeAccess: any QuickImportScopeAccessing,
        loadPolicy: QuickImportLoadPolicy
    ) {
        self.identityProvider = identityProvider
        self.scopeAccess = scopeAccess
        self.loadPolicy = loadPolicy
    }

    static let production = QuickImportEnvironment(
        identityProvider: FileSystemQuickImportPathIdentityProvider(),
        scopeAccess: SystemQuickImportScopeAccess(),
        loadPolicy: .production
    )
}

// MARK: - Loader values

/// One immutable loader input. Quick Import carries the candidate evidence so the
/// worker can verify the observation without resolving the path again; watched
/// folders pass `expected == nil` and keep the exact lexical-URL check.
nonisolated struct AudioFileLoadInput: Sendable {
    let index: Int
    let url: URL
    let id: UUID
    let previousFile: AudioFile?
    let expected: QuickImportObservationExpectation?
}

/// Verification evidence captured during candidate preparation.
nonisolated struct QuickImportObservationExpectation: Sendable {
    let operationalURL: URL
    let canonicalPath: String
    let entryIdentity: QuickImportEntryIdentity?
}

nonisolated struct AudioFileLoadOutcome: Sendable {
    let input: AudioFileLoadInput
    let file: AudioFile?
    let failureReason: String?
}

nonisolated struct AudioFileLoadResult: Sendable {
    let outcomes: [AudioFileLoadOutcome]
}

nonisolated struct AudioFileLoadFailure: Sendable {
    let url: URL
    let reason: String
}

// MARK: - Candidate and request values

/// One prepared import candidate. Everything the main actor needs to admit,
/// load and publish the file is carried here; no filesystem identity work is
/// repeated per batch.
struct QuickImportCandidate: Sendable {
    let requestID: UUID
    let sequence: UInt64
    let requestToken: UUID
    let ordinal: Int
    let identity: QuickImportPathIdentity
}

struct QuickImportAcceptedCandidate: Sendable {
    let candidate: QuickImportCandidate
    let fileID: UUID
}

struct QuickImportPendingFailure: Sendable {
    let fileKey: String
    let token: UUID
    let failure: AudioFileLoadFailure
}

// MARK: - Bookkeeping

struct QuickImportMetrics: Sendable {
    var watchedObservationLookups = 0
    var watchedObservationRowsUpdated = 0
    var acceptedCount = 0
    var rejectedStaleCount = 0
    var rejectedReadCount = 0
    var discardedSupersededCount = 0
    var moveMigrationIdentityMismatchCount = 0
    var restoredMembershipMigrationCount = 0
    var publicationCount = 0
    var publishedRowCount = 0
    /// Rows accepted in each published callback, in publication order. Lets the
    /// counter tests assert per-callback work and that the sum is the row total.
    var batchPublicationRowCounts: [Int] = []
    /// Falsifiable terminal-mutation detector: incremented when a terminal path
    /// mutates the published rows, publishes a batch, or calls the merge seam.
    var terminalMergeCount = 0
    var terminalMergedRowCount = 0
    var batchCount = 0
    var totalBatchItemCount = 0
    var cumulativePublicationDuration: Duration = .zero
    var maximumPublicationDuration: Duration = .zero
    // Delivery accounting for the diagnostics/tests: a batch that reaches the
    // publisher but is dropped before the row loop must be distinguishable from
    // a batch the loader never flushed.
    var batchDeliveryCount = 0
    var batchDropGenerationCount = 0
    var batchDropMissingRequestCount = 0
    var batchDropEmptyCount = 0
}

/// Token/sequence ownership recorded by one request for one file key at
/// admission time. Terminal pruning only removes an unpublished key when the
/// current registry still holds this exact ownership, so a newer overlapping
/// request's token is never deleted by an older request finishing.
struct QuickImportRequestKeyOwnership: Sendable, Equatable {
    let sequence: UInt64
    let token: UUID
}

struct QuickImportRequestState {
    let requestID: UUID
    let sequence: UInt64
    let generation: UInt64
    let refreshGeneration: UInt64
    let taskID: UUID
    let authorizationEpoch: UInt64
    var preparedKeys: [String: QuickImportRequestKeyOwnership] = [:]
    var pendingFailures: [QuickImportPendingFailure] = []
}

/// Main-actor Quick Import bookkeeping: the ordered index, refcounted scope
/// leases, replacement tokens, admission sequences and request registry.
struct QuickImportBookkeeping {
    var index = QuickImportPathIndex()
    var leases: QuickImportScopeLeases
    var tokensByFileKey: [String: UUID] = [:]
    var admittedSequenceByFileKey: [String: UInt64] = [:]
    var requests: [UUID: QuickImportRequestState] = [:]
    var metrics = QuickImportMetrics()
    /// True only for the synchronous terminal body. The merge seam increments
    /// `terminalMergeCount` if a terminal path ever merges published rows again.
    var isFinishingRequest = false
    private var nextSequence: UInt64 = 0

    init(environment: QuickImportEnvironment) {
        leases = QuickImportScopeLeases(access: environment.scopeAccess)
    }

    mutating func allocateSequence() -> UInt64 {
        nextSequence &+= 1
        return nextSequence
    }

    /// Records a tombstone token and supersession sequence for one file key. No
    /// in-flight batch whose admission sequence is older can publish afterwards.
    @discardableResult
    mutating func tombstone(fileKey: String) -> UInt64 {
        let sequence = allocateSequence()
        tokensByFileKey[fileKey] = UUID()
        admittedSequenceByFileKey[fileKey] = sequence
        return sequence
    }

    mutating func resetForClear() {
        leases.releaseAll()
        index.removeAll()
        tokensByFileKey.removeAll()
        admittedSequenceByFileKey.removeAll()
        requests.removeAll()
    }

    /// Drops registry entries for this request's prepared-but-unpublished keys,
    /// but only while this request still owns the token/sequence. A newer
    /// overlapping request that has already admitted the same key keeps its
    /// token and can publish normally.
    mutating func pruneUnpublishedKeys(for request: QuickImportRequestState) {
        for (fileKey, ownership) in request.preparedKeys
        where index.id(forFileKey: fileKey) == nil {
            guard tokensByFileKey[fileKey] == ownership.token,
                  admittedSequenceByFileKey[fileKey] == ownership.sequence else {
                continue
            }
            tokensByFileKey.removeValue(forKey: fileKey)
            admittedSequenceByFileKey.removeValue(forKey: fileKey)
        }
    }
}

/// Test/debug snapshot of Quick Import bookkeeping. Counters are cheap to read
/// and let the deterministic budget tests assert work without wall-clock timing.
struct QuickImportDiagnostics {
    let orderedIDs: [UUID]
    let fileKeyRefCounts: [String: Int]
    let parentKeyRefCounts: [String: Int]
    let tokensByFileKey: [String: UUID]
    let admittedSequenceByFileKey: [String: UInt64]
    let metrics: QuickImportMetrics
    let leaseMetrics: QuickImportScopeLeases.Metrics
    let pendingFailureCount: Int
    let activeRequestCount: Int
    let leaseStatesByKey: [String: QuickImportScopeLeaseState]
    let leaseOwnersByKey: [String: Set<QuickImportScopeOwner>]
    let membershipIdentitiesByID: [UUID: QuickImportPathIdentity]
    let consistencyIssues: [String]
}

// MARK: - Progressive import

extension AudioViewModel {
    // MARK: Intake

    /// Progressive Quick Import.
    ///
    /// Intake is main-actor and filesystem-free: standardize, dedupe exact paths,
    /// sort lexically, register one replacement token per request and start the
    /// job's URL-level scopes. Candidate identities are prepared off the main
    /// actor; only then are stable IDs allocated and the keyed loader started.
    func importQuickFiles(from urls: [URL]) {
        let candidateURLs = Self.uniqueStandardizedSortedURLs(urls)
        guard !candidateURLs.isEmpty else { return }

        let taskID = UUID()
        let requestID = UUID()
        let sequence = quickImportBookkeeping.allocateSequence()
        let generation = quickImportGeneration
        let refreshGeneration = makeFileModelRefreshGeneration()
        // Explicit user import = an authorization event: a previously
        // not-required/revoked key may retry its scope start once here.
        let authorizationEpoch = quickImportBookkeeping.leases.beginAuthorizationEpoch()
        quickImportBookkeeping.requests[requestID] = QuickImportRequestState(
            requestID: requestID,
            sequence: sequence,
            generation: generation,
            refreshGeneration: refreshGeneration,
            taskID: taskID,
            authorizationEpoch: authorizationEpoch
        )
        quickImportLoadingURLs[taskID] = candidateURLs
        inFlightQuickImportTaskIDs.insert(taskID)
        for url in candidateURLs {
            quickImportBookkeeping.leases.acquire(
                url: url,
                key: Self.quickImportIntakeLeaseKey(for: url),
                owner: .job(requestID),
                authorizationEpoch: authorizationEpoch
            )
        }

        let environment = quickImportEnvironment
        let pipeline = metadataPipeline
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let candidates = await Self.prepareQuickImportCandidates(
                urls: candidateURLs,
                requestID: requestID,
                sequence: sequence,
                provider: environment.identityProvider
            )

            let admitted: [QuickImportAcceptedCandidate]? = await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return nil }
                return self.admitQuickImportCandidates(
                    candidates,
                    requestID: requestID,
                    generation: generation
                )
            }

            guard let admitted, !admitted.isEmpty, !Task.isCancelled else {
                let cancelled = Task.isCancelled
                await MainActor.run { [weak self] in
                    self?.finishQuickImportRequest(
                        requestID: requestID,
                        taskID: taskID,
                        generation: generation,
                        cancelled: cancelled
                    )
                }
                return
            }

            let inputs = admitted.enumerated().map { offset, accepted in
                AudioFileLoadInput(
                    index: offset,
                    url: accepted.candidate.identity.operationalURL,
                    id: accepted.fileID,
                    previousFile: nil,
                    expected: QuickImportObservationExpectation(
                        operationalURL: accepted.candidate.identity.operationalURL,
                        canonicalPath: accepted.candidate.identity.canonicalPath,
                        entryIdentity: accepted.candidate.identity.fileIdentity
                    )
                )
            }

            let loadResult = await Self.loadAudioFiles(
                inputs: inputs,
                metadataPipeline: pipeline,
                policy: environment.loadPolicy,
                retryTransientFailures: true,
                onBatchLoaded: { [weak self] batch in
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.publishQuickImportBatch(
                            batch,
                            admitted: admitted,
                            requestID: requestID,
                            generation: generation,
                            refreshGeneration: refreshGeneration
                        )
                    }
                }
            )
            let failureOutcomes = loadResult.outcomes.filter {
                $0.file == nil && $0.failureReason != nil
            }
            let pendingFailures: [QuickImportPendingFailure] = failureOutcomes.compactMap { outcome in
                guard outcome.input.index >= 0,
                      outcome.input.index < admitted.count,
                      let reason = outcome.failureReason else {
                    return nil
                }
                let candidate = admitted[outcome.input.index].candidate
                return QuickImportPendingFailure(
                    fileKey: candidate.identity.fileKey,
                    token: candidate.requestToken,
                    failure: AudioFileLoadFailure(
                        url: candidate.identity.operationalURL,
                        reason: reason
                    )
                )
            }

            let cancelled = Task.isCancelled
            await MainActor.run { [weak self] in
                self?.finishQuickImportRequest(
                    requestID: requestID,
                    taskID: taskID,
                    generation: generation,
                    cancelled: cancelled,
                    additionalFailures: pendingFailures
                )
            }
        }
        quickImportTasks[taskID] = task
    }

    // MARK: Admission

    func admitQuickImportCandidates(
        _ candidates: [QuickImportCandidate],
        requestID: UUID,
        generation: UInt64
    ) -> [QuickImportAcceptedCandidate] {
        guard generation == quickImportGeneration,
              quickImportBookkeeping.requests[requestID] != nil else {
            return []
        }

        // Later alias in the same request wins, preserving the existing
        // last-wins behavior for duplicate canonical keys.
        var lastByFileKey: [String: QuickImportCandidate] = [:]
        for candidate in candidates {
            lastByFileKey[candidate.identity.fileKey] = candidate
        }
        let admittedOrdinals = Set(lastByFileKey.values.map(\.ordinal))
        for candidate in candidates where !admittedOrdinals.contains(candidate.ordinal) {
            quickImportBookkeeping.leases.release(
                key: Self.quickImportIntakeLeaseKey(for: candidate.identity.operationalURL),
                owner: .job(requestID)
            )
        }

        var accepted: [QuickImportAcceptedCandidate] = []
        accepted.reserveCapacity(lastByFileKey.count)
        var admittedOwnership: [String: QuickImportRequestKeyOwnership] = [:]
        for candidate in lastByFileKey.values.sorted(by: { $0.ordinal < $1.ordinal }) {
            let fileKey = candidate.identity.fileKey
            if let admittedSequence = quickImportBookkeeping.admittedSequenceByFileKey[fileKey],
               admittedSequence > candidate.sequence {
                quickImportBookkeeping.metrics.rejectedStaleCount += 1
                quickImportBookkeeping.leases.release(
                    key: Self.quickImportIntakeLeaseKey(for: candidate.identity.operationalURL),
                    owner: .job(requestID)
                )
                continue
            }

            quickImportBookkeeping.tokensByFileKey[fileKey] = candidate.requestToken
            quickImportBookkeeping.admittedSequenceByFileKey[fileKey] = candidate.sequence
            admittedOwnership[fileKey] = QuickImportRequestKeyOwnership(
                sequence: candidate.sequence,
                token: candidate.requestToken
            )

            // The selected-URL lease is already held by intake and keeps its
            // non-granted state across imports, so the parent directory is the
            // only new key started here. Passing the explicit authorization
            // epoch lets a previously revoked parent scope retry once.
            let authorizationEpoch = quickImportBookkeeping.requests[requestID]?.authorizationEpoch
            quickImportBookkeeping.leases.acquire(
                url: candidate.identity.parentURL,
                key: candidate.identity.parentKey,
                owner: .job(requestID),
                authorizationEpoch: authorizationEpoch
            )

            accepted.append(
                QuickImportAcceptedCandidate(
                    candidate: candidate,
                    fileID: quickImportStableFileID(forFileKey: fileKey)
                )
            )
        }

        if var request = quickImportBookkeeping.requests[requestID] {
            request.preparedKeys.merge(admittedOwnership) { _, new in new }
            quickImportBookkeeping.requests[requestID] = request
        }
        return accepted
    }

    private func quickImportStableFileID(forFileKey fileKey: String) -> UUID {
        if let existing = fileIDsByKey[fileKey] { return existing }
        let id = UUID()
        fileIDsByKey[fileKey] = id
        return id
    }

    // MARK: Publication

    /// Publishes one non-empty contiguous loader batch. Applies the index delta to
    /// the published array, registers membership leases and rebuilds the visible
    /// collection exactly once. Empty/stale batches publish nothing.
    func publishQuickImportBatch(
        _ outcomes: [AudioFileLoadOutcome],
        admitted: [QuickImportAcceptedCandidate],
        requestID: UUID,
        generation: UInt64,
        refreshGeneration: UInt64
    ) {
        quickImportBookkeeping.metrics.batchDeliveryCount += 1
        if generation != quickImportGeneration {
            quickImportBookkeeping.metrics.batchDropGenerationCount += 1
            return
        }
        if quickImportBookkeeping.requests[requestID] == nil {
            quickImportBookkeeping.metrics.batchDropMissingRequestCount += 1
            return
        }
        guard !outcomes.isEmpty else {
            quickImportBookkeeping.metrics.batchDropEmptyCount += 1
            return
        }
        let start = ContinuousClock.now
        var publishedRowCount = 0
        var newlyAcceptedFiles: [AudioFile] = []
        var failures: [QuickImportPendingFailure] = []

        for outcome in outcomes {
            guard outcome.input.index >= 0, outcome.input.index < admitted.count else { continue }
            let acceptedCandidate = admitted[outcome.input.index]
            let candidate = acceptedCandidate.candidate
            let fileKey = candidate.identity.fileKey
            let fileLeaseKey = Self.quickImportIntakeLeaseKey(for: candidate.identity.operationalURL)

            guard quickImportBookkeeping.tokensByFileKey[fileKey] == candidate.requestToken,
                  quickImportBookkeeping.admittedSequenceByFileKey[fileKey] == candidate.sequence else {
                quickImportBookkeeping.metrics.rejectedStaleCount += 1
                quickImportBookkeeping.leases.release(key: fileLeaseKey, owner: .job(requestID))
                continue
            }

            if let file = outcome.file {
                let newObservation = acceptFileObservation(
                    file,
                    generation: refreshGeneration,
                    pathIdentity: candidate.identity
                )
                let acceptedFile: AudioFile
                if let newObservation {
                    acceptedFile = newObservation
                    invalidateWatchedFolderScans(containingFileID: acceptedFile.id)
                    newlyAcceptedFiles.append(acceptedFile)
                } else if let current = committedFile(withID: file.id),
                          Self.verificationFailureReason(for: current, input: outcome.input) == nil {
                    // A newer source observation may win while this import is
                    // reading. Keep the admitted membership with that observation
                    // only if it still describes the entry this request selected.
                    acceptedFile = current
                } else {
                    quickImportBookkeeping.leases.release(key: fileLeaseKey, owner: .job(requestID))
                    continue
                }

                let record = QuickImportMembershipRecord(
                    id: acceptedCandidate.fileID,
                    identity: candidate.identity,
                    requestToken: candidate.requestToken
                )
                let previousRecord = quickImportBookkeeping.index.record(forID: record.id)
                    ?? quickImportBookkeeping.index.record(forFileKey: fileKey)
                let mutation = quickImportBookkeeping.index.insertOrReplace(record)
                applyQuickImportIndexChange(mutation.change, file: acceptedFile)

                quickImportBookkeeping.leases.acquire(
                    url: candidate.identity.operationalURL,
                    key: fileLeaseKey,
                    owner: .membership(record.id)
                )
                quickImportBookkeeping.leases.acquire(
                    url: candidate.identity.parentURL,
                    key: candidate.identity.parentKey,
                    owner: .membership(record.id)
                )
                quickImportBookkeeping.leases.release(key: fileLeaseKey, owner: .job(requestID))
                if let previousRecord {
                    let previousFileLeaseKey = Self.quickImportIntakeLeaseKey(
                        for: previousRecord.identity.operationalURL
                    )
                    if previousFileLeaseKey != fileLeaseKey {
                        quickImportBookkeeping.leases.release(
                            key: previousFileLeaseKey,
                            owner: .membership(previousRecord.id)
                        )
                    }
                    if previousRecord.identity.parentKey != candidate.identity.parentKey {
                        quickImportBookkeeping.leases.release(
                            key: previousRecord.identity.parentKey,
                            owner: .membership(previousRecord.id)
                        )
                    }
                    if previousRecord.id != record.id {
                        quickImportBookkeeping.leases.release(
                            key: fileLeaseKey,
                            owner: .membership(previousRecord.id)
                        )
                        quickImportBookkeeping.leases.release(
                            key: candidate.identity.parentKey,
                            owner: .membership(previousRecord.id)
                        )
                    }
                }

                quickImportBookkeeping.metrics.acceptedCount += 1
                publishedRowCount += 1
            } else if let reason = outcome.failureReason {
                failures.append(
                    QuickImportPendingFailure(
                        fileKey: fileKey,
                        token: candidate.requestToken,
                        failure: AudioFileLoadFailure(
                            url: candidate.identity.operationalURL,
                            reason: reason
                        )
                    )
                )
                quickImportBookkeeping.leases.release(key: fileLeaseKey, owner: .job(requestID))
            } else {
                // Cancelled read: release the job's file lease only.
                quickImportBookkeeping.leases.release(key: fileLeaseKey, owner: .job(requestID))
            }
        }

        if var request = quickImportBookkeeping.requests[requestID] {
            request.pendingFailures.append(contentsOf: failures)
            quickImportBookkeeping.requests[requestID] = request
        }

        guard publishedRowCount > 0 else { return }

        if !newlyAcceptedFiles.isEmpty {
            syncAcceptedObservationsToOtherSources(
                newlyAcceptedFiles,
                includeQuickImport: false
            )
        }

        rebuildVisibleFiles()
        let duration = start.duration(to: ContinuousClock.now)
        quickImportBookkeeping.metrics.publicationCount += 1
        quickImportBookkeeping.metrics.publishedRowCount += publishedRowCount
        quickImportBookkeeping.metrics.batchPublicationRowCounts.append(publishedRowCount)
        quickImportBookkeeping.metrics.batchCount += 1
        quickImportBookkeeping.metrics.totalBatchItemCount += publishedRowCount
        quickImportBookkeeping.metrics.cumulativePublicationDuration += duration
        if duration > quickImportBookkeeping.metrics.maximumPublicationDuration {
            quickImportBookkeeping.metrics.maximumPublicationDuration = duration
        }
    }

    /// Applies one index change to the published ordered array and the ID lookup
    /// dictionary. No path keys are recomputed.
    private func applyQuickImportIndexChange(_ change: QuickImportIndexChange, file: AudioFile) {
        switch change {
        case .inserted:
            quickImportFiles.append(file)
        case .replaced(_, let position):
            if position < quickImportFiles.count {
                quickImportFiles[position] = file
            } else {
                quickImportFiles.append(file)
            }
        case .removed(_, let position):
            if position < quickImportFiles.count {
                quickImportFiles.remove(at: position)
            }
        }
        quickImportFilesByID[file.id] = file
    }

    // MARK: Terminal

    /// Exactly-once terminal path: release the job's leases, prune tokens for keys
    /// that never published, report filtered failures and remove task bookkeeping.
    /// Cancellation and a newer generation only suppress reporting; cleanup always
    /// runs. There is no end-of-job merge of already published results.
    func finishQuickImportRequest(
        requestID: UUID,
        taskID: UUID,
        generation: UInt64,
        cancelled: Bool,
        additionalFailures: [QuickImportPendingFailure] = []
    ) {
        withTerminalMergeDetector {
            finishQuickImportRequestBody(
                requestID: requestID,
                taskID: taskID,
                generation: generation,
                cancelled: cancelled,
                additionalFailures: additionalFailures
            )
        }
    }

    /// Runs `body` under the falsifiable terminal-mutation detector. A terminal
    /// path may not add rows or publish after the request has terminated.
    private func withTerminalMergeDetector(_ body: () -> Void) {
        let rowCountBefore = quickImportFiles.count
        let publicationCountBefore = quickImportBookkeeping.metrics.publicationCount
        quickImportBookkeeping.isFinishingRequest = true
        defer {
            quickImportBookkeeping.isFinishingRequest = false
            let rowsAdded = quickImportFiles.count - rowCountBefore
            if rowsAdded != 0
                || quickImportBookkeeping.metrics.publicationCount != publicationCountBefore {
                quickImportBookkeeping.metrics.terminalMergeCount += 1
                quickImportBookkeeping.metrics.terminalMergedRowCount += abs(rowsAdded)
            }
        }
        body()
    }

    /// Test-only negative control: executes the same terminal detector around a
    /// synthetic mutation to prove `terminalMergeCount`/`terminalMergedRowCount`
    /// are falsifiable. Never called from production.
    func runTerminalMergeDetectorForTesting(_ body: () -> Void) {
        withTerminalMergeDetector(body)
    }

    private func finishQuickImportRequestBody(
        requestID: UUID,
        taskID: UUID,
        generation: UInt64,
        cancelled: Bool,
        additionalFailures: [QuickImportPendingFailure]
    ) {
        inFlightQuickImportTaskIDs.remove(taskID)
        quickImportTasks[taskID] = nil
        quickImportLoadingURLs[taskID] = nil
        quickImportBookkeeping.leases.release(owner: .job(requestID))

        if !additionalFailures.isEmpty,
           var pendingRequest = quickImportBookkeeping.requests[requestID] {
            pendingRequest.pendingFailures.append(contentsOf: additionalFailures)
            quickImportBookkeeping.requests[requestID] = pendingRequest
        }
        guard let request = quickImportBookkeeping.requests.removeValue(forKey: requestID) else {
            return
        }
        // Failures are filtered against the live token BEFORE token pruning: a
        // failed candidate never publishes a membership, so pruning first would
        // discard every reportable failure.
        let reportable = request.pendingFailures.filter { pending in
            quickImportBookkeeping.tokensByFileKey[pending.fileKey] == pending.token
        }
        quickImportBookkeeping.metrics.rejectedReadCount += reportable.count
        quickImportBookkeeping.pruneUnpublishedKeys(for: request)

        guard !cancelled, generation == quickImportGeneration else { return }
        presentQuickImportFailures(reportable.map(\.failure))
    }

    // MARK: Membership mutations

    func clearQuickImportFiles() {
        let removedFileIDs = Set(quickImportFiles.map(\.id))
        quickImportGeneration &+= 1
        quickImportTasks.values.forEach { $0.cancel() }
        quickImportTasks.removeAll()
        inFlightQuickImportTaskIDs.removeAll()
        quickImportLoadingURLs.removeAll()
        quickImportBookkeeping.resetForClear()
        quickImportFiles.removeAll()
        quickImportFilesByID.removeAll()
        revokeCommitPermitsForRemovedSourceFiles(removedFileIDs)
        prunePendingReplacementFileReviews(removingIDs: removedFileIDs)
        let resolvedSelection = normalizedSidebarSelection(activeSidebarSelection)
        if activeSidebarSelection != resolvedSelection {
            activeSidebarSelection = resolvedSelection
        }
        rebuildVisibleFiles()
    }

    func removeQuickImportFile(id: UUID) {
        guard let record = quickImportBookkeeping.index.record(forID: id) else {
            // Defensive: a row that is not in the index (e.g. a pending reload)
            // is still removed from the published collection.
            quickImportFiles.removeAll { $0.id == id }
            quickImportFilesByID[id] = nil
            revokeCommitPermitsForRemovedSourceFiles([id])
            prunePendingReplacementFileReviews(removingIDs: [id])
            rebuildVisibleFiles()
            return
        }

        let fileKey = record.identity.fileKey
        quickImportBookkeeping.tombstone(fileKey: fileKey)

        if let mutation = quickImportBookkeeping.index.remove(id: id) {
            if mutation.change.position < quickImportFiles.count {
                quickImportFiles.remove(at: mutation.change.position)
            } else {
                quickImportFiles.removeAll { $0.id == id }
            }
        }
        quickImportFilesByID[id] = nil
        quickImportBookkeeping.leases.release(
            key: Self.quickImportIntakeLeaseKey(for: record.identity.operationalURL),
            owner: .membership(id)
        )
        quickImportBookkeeping.leases.release(key: record.identity.parentKey, owner: .membership(id))

        revokeCommitPermitsForRemovedSourceFiles([id])
        prunePendingReplacementFileReviews(removingIDs: [id])
        rebuildVisibleFiles()
    }

    /// Direct insertion seam used by tests and the 1,000/4,000 synthetic
    /// single-merge performance test. Computes each incoming identity through the
    /// environment provider exactly once and maintains the index/leases; it never
    /// walks the whole loaded collection for path keys and never starts a full
    /// scope reconciliation.
    func mergeQuickImportFiles(_ incoming: [AudioFile], refreshGeneration: UInt64? = nil) {
        guard !incoming.isEmpty else { return }
        if quickImportBookkeeping.isFinishingRequest {
            quickImportBookkeeping.metrics.terminalMergeCount += 1
        }
        let generation = refreshGeneration ?? makeFileModelRefreshGeneration()
        var parentEvidenceByPath: [String: QuickImportParentEvidence] = [:]
        var newlyAcceptedFiles: [AudioFile] = []
        var publishedAnything = false

        for file in incoming {
            let standardizedURL = file.url.standardizedFileURL
            let parentPath = standardizedURL.deletingLastPathComponent().path
            let identity = quickImportEnvironment.identityProvider.prepareIdentity(
                forFileURL: standardizedURL,
                parent: parentEvidenceByPath[parentPath]
            )
            parentEvidenceByPath[parentPath] = identity.parentEvidence

            guard let accepted = acceptFileObservation(
                file,
                generation: generation,
                pathIdentity: identity
            ) else { continue }
            invalidateWatchedFolderScans(containingFileID: accepted.id)

            fileIDsByKey[identity.fileKey] = accepted.id
            let existingToken = quickImportBookkeeping.tokensByFileKey[identity.fileKey] ?? UUID()
            quickImportBookkeeping.tokensByFileKey[identity.fileKey] = existingToken
            if quickImportBookkeeping.admittedSequenceByFileKey[identity.fileKey] == nil {
                quickImportBookkeeping.admittedSequenceByFileKey[identity.fileKey] =
                    quickImportBookkeeping.allocateSequence()
            }

            let record = QuickImportMembershipRecord(
                id: accepted.id,
                identity: identity,
                requestToken: existingToken
            )
            let mutation = quickImportBookkeeping.index.insertOrReplace(record)
            applyQuickImportIndexChange(mutation.change, file: accepted)
            let newFileLeaseKey = Self.quickImportIntakeLeaseKey(for: identity.operationalURL)
            quickImportBookkeeping.leases.acquire(
                url: identity.operationalURL,
                key: newFileLeaseKey,
                owner: .membership(accepted.id)
            )
            quickImportBookkeeping.leases.acquire(
                url: identity.parentURL,
                key: identity.parentKey,
                owner: .membership(accepted.id)
            )
            if let previousRecord = mutation.previousRecord {
                let previousFileLeaseKey = Self.quickImportIntakeLeaseKey(
                    for: previousRecord.identity.operationalURL
                )
                if previousRecord.id != record.id {
                    quickImportFilesByID[previousRecord.id] = nil
                    quickImportBookkeeping.leases.release(
                        key: previousFileLeaseKey,
                        owner: .membership(previousRecord.id)
                    )
                    quickImportBookkeeping.leases.release(
                        key: previousRecord.identity.parentKey,
                        owner: .membership(previousRecord.id)
                    )
                    revokeCommitPermitsForRemovedSourceFiles([previousRecord.id])
                } else {
                    if previousFileLeaseKey != newFileLeaseKey {
                        quickImportBookkeeping.leases.release(
                            key: previousFileLeaseKey,
                            owner: .membership(accepted.id)
                        )
                    }
                    if previousRecord.identity.parentKey != identity.parentKey {
                        quickImportBookkeeping.leases.release(
                            key: previousRecord.identity.parentKey,
                            owner: .membership(accepted.id)
                        )
                    }
                }
            }
            newlyAcceptedFiles.append(accepted)
            publishedAnything = true
        }

        if publishedAnything {
            syncAcceptedObservationsToOtherSources(
                newlyAcceptedFiles,
                includeQuickImport: false
            )
            rebuildVisibleFiles()
        }
    }

    // MARK: Diagnostics

    func quickImportDiagnostics() -> QuickImportDiagnostics {
        let leaseSnapshot = quickImportBookkeeping.leases.leaseSnapshot()
        return QuickImportDiagnostics(
            orderedIDs: quickImportBookkeeping.index.orderedIDs,
            fileKeyRefCounts: quickImportBookkeeping.index.fileKeyRefCounts,
            parentKeyRefCounts: quickImportBookkeeping.index.parentKeyRefCounts,
            tokensByFileKey: quickImportBookkeeping.tokensByFileKey,
            admittedSequenceByFileKey: quickImportBookkeeping.admittedSequenceByFileKey,
            metrics: quickImportBookkeeping.metrics,
            leaseMetrics: quickImportBookkeeping.leases.metricsSnapshot(),
            pendingFailureCount: quickImportBookkeeping.requests.values.reduce(0) {
                $0 + $1.pendingFailures.count
            },
            activeRequestCount: quickImportBookkeeping.requests.count,
            leaseStatesByKey: leaseSnapshot.mapValues { $0.state },
            leaseOwnersByKey: leaseSnapshot.mapValues { $0.owners },
            membershipIdentitiesByID: quickImportBookkeeping.index.membershipIdentitiesByID(),
            consistencyIssues: quickImportBookkeeping.index.consistencyIssues()
        )
    }

    /// Live granted security-scope URLs, used for mutation directory access and
    /// tests. No stale full-collection map is retained.
    func quickImportGrantedScopeURLs() -> [URL] {
        quickImportBookkeeping.leases.liveGrantedURLs()
    }

    // MARK: Intake helpers

    nonisolated static func quickImportIntakeLeaseKey(for url: URL) -> String {
        "url:" + url.standardizedFileURL.path
    }

    nonisolated static func uniqueStandardizedSortedURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var unique: [URL] = []
        unique.reserveCapacity(urls.count)
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else { continue }
            unique.append(standardizedURL)
        }
        return unique.sorted(by: compareURLs)
    }

    // MARK: Candidate preparation (off the main actor)

    /// One canonical/volume/entry computation per candidate; the parent evidence
    /// of a previously prepared sibling is reused so a directory resolves once.
    nonisolated static func prepareQuickImportCandidates(
        urls: [URL],
        requestID: UUID,
        sequence: UInt64,
        provider: any QuickImportPathIdentityProviding
    ) async -> [QuickImportCandidate] {
        var candidates: [QuickImportCandidate] = []
        candidates.reserveCapacity(urls.count)
        var parentEvidenceByPath: [String: QuickImportParentEvidence] = [:]
        parentEvidenceByPath.reserveCapacity(max(1, urls.count / 16))

        for (ordinal, url) in urls.enumerated() {
            if ordinal % 64 == 0, Task.isCancelled { break }
            let standardizedURL = url.standardizedFileURL
            let parentPath = standardizedURL.deletingLastPathComponent().path
            let identity = provider.prepareIdentity(
                forFileURL: standardizedURL,
                parent: parentEvidenceByPath[parentPath]
            )
            parentEvidenceByPath[parentPath] = identity.parentEvidence
            candidates.append(
                QuickImportCandidate(
                    requestID: requestID,
                    sequence: sequence,
                    requestToken: UUID(),
                    ordinal: ordinal,
                    identity: identity
                )
            )
        }
        if Task.isCancelled {
            return []
        }
        return candidates
    }

    // MARK: Keyed loader

    /// Ordered, batch-coalesced loader shared by Quick Import and watched-folder
    /// rescans. Inputs already carry their URLs and stable IDs, so the loader
    /// performs no path-key work.
    nonisolated static func loadAudioFiles(
        inputs: [AudioFileLoadInput],
        metadataPipeline: any AudioMetadataPipeline,
        policy: QuickImportLoadPolicy,
        retryTransientFailures: Bool = false,
        onBatchLoaded: (@Sendable ([AudioFileLoadOutcome]) async -> Void)? = nil
    ) async -> AudioFileLoadResult {
        guard !inputs.isEmpty else { return AudioFileLoadResult(outcomes: []) }
        guard !Task.isCancelled else { return AudioFileLoadResult(outcomes: []) }

        let maxConcurrentLoads = min(
            max(ProcessInfo.processInfo.activeProcessorCount * 2, 6),
            min(12, inputs.count)
        )
        var nextInputIndex = maxConcurrentLoads
        var completedByIndex: [Int: AudioFileLoadOutcome] = [:]
        completedByIndex.reserveCapacity(inputs.count)
        var allOutcomes: [AudioFileLoadOutcome] = []
        allOutcomes.reserveCapacity(inputs.count)
        var nextContiguousIndex = 0
        var resolvedIndices = Set<Int>()
        var pendingBatch: [AudioFileLoadOutcome] = []
        pendingBatch.reserveCapacity(policy.partialBatchSize)
        var failureOutcomes: [AudioFileLoadOutcome] = []
        var lastFlushTime = Date.timeIntervalSinceReferenceDate

        await withTaskGroup(of: AudioFileLoadOutcome.self) { group in
            for input in inputs.prefix(maxConcurrentLoads) {
                group.addTask {
                    guard !Task.isCancelled else {
                        return AudioFileLoadOutcome(input: input, file: nil, failureReason: nil)
                    }
                    if let previousFile = input.previousFile,
                       let previousFingerprint = previousFile.fileFingerprint,
                       let previousVersion = previousFile.metadataFileVersion,
                       (try? AudioFileFingerprint.capture(at: input.url)) == previousFingerprint,
                       (try? metadataPipeline.metadataFileVersion(at: input.url)) == previousVersion {
                        return AudioFileLoadOutcome(input: input, file: previousFile, failureReason: nil)
                    }
                    do {
                        let file = try await loadSingleAudioFile(
                            at: input.url,
                            id: input.id,
                            metadataPipeline: metadataPipeline,
                            retryTransientFailures: retryTransientFailures
                        )
                        if let failureReason = verificationFailureReason(for: file, input: input) {
                            return AudioFileLoadOutcome(
                                input: input,
                                file: nil,
                                failureReason: failureReason
                            )
                        }
                        return AudioFileLoadOutcome(input: input, file: file, failureReason: nil)
                    } catch is CancellationError {
                        return AudioFileLoadOutcome(input: input, file: nil, failureReason: nil)
                    } catch {
                        return AudioFileLoadOutcome(
                            input: input,
                            file: nil,
                            failureReason: (error as NSError).localizedDescription
                        )
                    }
                }
            }

            while let outcome = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                let index = outcome.input.index
                completedByIndex[index] = outcome
                resolvedIndices.insert(index)

                // Advance past both successes and failures. A failed early
                // index must not prevent later files from being published.
                while resolvedIndices.contains(nextContiguousIndex) {
                    if let resolved = completedByIndex.removeValue(forKey: nextContiguousIndex) {
                        if resolved.file != nil {
                            pendingBatch.append(resolved)
                        } else if resolved.failureReason != nil {
                            failureOutcomes.append(resolved)
                        }
                    }
                    nextContiguousIndex += 1

                    let now = Date.timeIntervalSinceReferenceDate
                    let shouldFlush =
                        pendingBatch.count >= policy.forceFlushBatchSize ||
                        (
                            pendingBatch.count >= policy.partialBatchSize &&
                            now - lastFlushTime >= policy.minimumFlushInterval
                        )

                    if shouldFlush, let onBatchLoaded, !Task.isCancelled {
                        await onBatchLoaded(pendingBatch)
                        allOutcomes.append(contentsOf: pendingBatch)
                        pendingBatch.removeAll(keepingCapacity: true)
                        lastFlushTime = now
                    }
                }

                guard nextInputIndex < inputs.count else { continue }
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                let input = inputs[nextInputIndex]
                nextInputIndex += 1
                group.addTask {
                    guard !Task.isCancelled else {
                        return AudioFileLoadOutcome(input: input, file: nil, failureReason: nil)
                    }
                    if let previousFile = input.previousFile,
                       let previousFingerprint = previousFile.fileFingerprint,
                       let previousVersion = previousFile.metadataFileVersion,
                       (try? AudioFileFingerprint.capture(at: input.url)) == previousFingerprint,
                       (try? metadataPipeline.metadataFileVersion(at: input.url)) == previousVersion {
                        return AudioFileLoadOutcome(input: input, file: previousFile, failureReason: nil)
                    }
                    do {
                        let file = try await loadSingleAudioFile(
                            at: input.url,
                            id: input.id,
                            metadataPipeline: metadataPipeline,
                            retryTransientFailures: retryTransientFailures
                        )
                        if let failureReason = verificationFailureReason(for: file, input: input) {
                            return AudioFileLoadOutcome(
                                input: input,
                                file: nil,
                                failureReason: failureReason
                            )
                        }
                        return AudioFileLoadOutcome(input: input, file: file, failureReason: nil)
                    } catch is CancellationError {
                        return AudioFileLoadOutcome(input: input, file: nil, failureReason: nil)
                    } catch {
                        return AudioFileLoadOutcome(
                            input: input,
                            file: nil,
                            failureReason: (error as NSError).localizedDescription
                        )
                    }
                }
            }
        }

        if !pendingBatch.isEmpty {
            if let onBatchLoaded, !Task.isCancelled {
                await onBatchLoaded(pendingBatch)
            }
            allOutcomes.append(contentsOf: pendingBatch)
        }

        allOutcomes.append(contentsOf: failureOutcomes)
        allOutcomes.sort { $0.input.index < $1.input.index }
        return AudioFileLoadResult(outcomes: allOutcomes)
    }

    nonisolated static func loadSingleAudioFile(
        at url: URL,
        id: UUID,
        metadataPipeline: any AudioMetadataPipeline,
        retryTransientFailures: Bool
    ) async throws -> AudioFile {
        do {
            return try await metadataPipeline.loadAudioFile(at: url, id: id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard retryTransientFailures, !Task.isCancelled else { throw error }

            // A newly selected security-scoped or file-provider URL can be
            // briefly unavailable while macOS grants access or materializes its
            // contents. Keep the scope alive and retry the read once instead of
            // requiring the user to select the same file again.
            try await Task.sleep(for: .milliseconds(200))
            return try await metadataPipeline.loadAudioFile(at: url, id: id)
        }
    }

    /// Verifies that a full read observed the exact selected entry. The captured
    /// candidate loses no evidence to a re-resolution: the canonical path must
    /// match and, when the candidate captured device/inode, the observation must
    /// report the same entry. A symlink or parent retarget therefore declines the
    /// result and is reported as "select it again" rather than retried.
    nonisolated static func verificationFailureReason(
        for file: AudioFile,
        input: AudioFileLoadInput
    ) -> String? {
        guard file.url == input.url, let observation = file.observation else {
            return Self.changedWhileReadingMessage
        }
        guard let expected = input.expected else { return nil }
        guard observation.url == expected.operationalURL,
              observation.fingerprint.normalizedPath == expected.canonicalPath else {
            return Self.changedWhileReadingMessage
        }
        if let captured = expected.entryIdentity {
            guard let device = observation.fingerprint.fileSystemNumber,
                  let inode = observation.fingerprint.fileNumber,
                  device == captured.device,
                  inode == captured.inode else {
                return Self.changedWhileReadingMessage
            }
        }
        return nil
    }

    nonisolated static var changedWhileReadingMessage: String {
        String(localized: "The file changed while it was being read. Select it again to reload it.")
    }
}

// MARK: - Rename and recovery migration

extension AudioViewModel {
    /// Publishes verified move receipts while the rename transaction's union
    /// reservation is still held (F1 contract), and migrates every Quick Import
    /// membership in one main-actor step: row ID map, replacement tokens,
    /// admission sequence, ordered index, file/parent scope leases and the
    /// membership URL. No path keys are resolved for the old location; the
    /// destination identity is computed once per receipt.
    func publishMovePlaceholders(_ receipts: [FileRenameMoveReceipt]) {
        guard !receipts.isEmpty else { return }

        var parentEvidenceByPath: [String: QuickImportParentEvidence] = [:]
        let oldURLKeys = Set(receipts.map { Self.urlKey(for: $0.sourceURL) })
        for oldKey in oldURLKeys {
            fileIDsByKey.removeValue(forKey: oldKey)
        }

        // Pass 1: capture destination identities and tombstone every old key
        // before writing any new destination tokens, so swap renames (A <-> B)
        // never let the second receipt tombstone the first receipt's new key.
        struct PreparedReceiptMigration {
            let receipt: FileRenameMoveReceipt
            let destinationURL: URL
            let destinationIdentity: QuickImportPathIdentity
            let existingRecord: QuickImportMembershipRecord?
        }

        var migrations: [PreparedReceiptMigration] = []
        migrations.reserveCapacity(receipts.count)

        for receipt in receipts {
            let destinationURL = receipt.destinationURL.standardizedFileURL
            let destinationParentPath = destinationURL.deletingLastPathComponent().path
            let destinationIdentity = quickImportEnvironment.identityProvider.prepareIdentity(
                forFileURL: destinationURL,
                parent: parentEvidenceByPath[destinationParentPath]
            )
            parentEvidenceByPath[destinationParentPath] = destinationIdentity.parentEvidence
            let existingRecord = quickImportBookkeeping.index.record(forID: receipt.fileID)
            if let existingRecord {
                quickImportBookkeeping.tombstone(fileKey: existingRecord.identity.fileKey)
            } else {
                quickImportBookkeeping.tombstone(fileKey: Self.urlKey(for: receipt.sourceURL))
            }
            migrations.append(
                PreparedReceiptMigration(
                    receipt: receipt,
                    destinationURL: destinationURL,
                    destinationIdentity: destinationIdentity,
                    existingRecord: existingRecord
                )
            )
        }

        // Pass 2: install destination keys, migrate index/leases, and record
        // pending readback decisions (revoking any pending commit permits).
        for migration in migrations {
            let receipt = migration.receipt
            let destinationURL = migration.destinationURL
            let destinationIdentity = migration.destinationIdentity

            fileIDsByKey[destinationIdentity.fileKey] = receipt.fileID

            if let record = migration.existingRecord {
                let destinationToken = UUID()
                quickImportBookkeeping.tokensByFileKey[destinationIdentity.fileKey] = destinationToken
                quickImportBookkeeping.admittedSequenceByFileKey[destinationIdentity.fileKey] =
                    quickImportBookkeeping.allocateSequence()
                _ = quickImportBookkeeping.index.migrate(
                    id: receipt.fileID,
                    to: destinationIdentity
                )
                quickImportBookkeeping.index.updateRequestToken(
                    id: receipt.fileID,
                    token: destinationToken
                )
                quickImportBookkeeping.leases.migrateKey(
                    from: Self.quickImportIntakeLeaseKey(for: record.identity.operationalURL),
                    to: Self.quickImportIntakeLeaseKey(for: destinationURL),
                    url: destinationURL,
                    owner: .membership(receipt.fileID)
                )
                if record.identity.parentKey != destinationIdentity.parentKey {
                    quickImportBookkeeping.leases.migrateKey(
                        from: record.identity.parentKey,
                        to: destinationIdentity.parentKey,
                        url: destinationIdentity.parentURL,
                        owner: .membership(receipt.fileID)
                    )
                }
                if let expectedDevice = receipt.entryIdentity.device,
                   let expectedInode = receipt.entryIdentity.inode,
                   let captured = destinationIdentity.fileIdentity,
                   captured.device != expectedDevice || captured.inode != expectedInode {
                    // The destination membership is retained under the resolved
                    // identity (bookkeeping stays consistent), but a mismatch is
                    // counted: F1 readback remains the only authority restore.
                    quickImportBookkeeping.metrics.moveMigrationIdentityMismatchCount += 1
                }
            } else {
                quickImportBookkeeping.tokensByFileKey[destinationIdentity.fileKey] = UUID()
                quickImportBookkeeping.admittedSequenceByFileKey[destinationIdentity.fileKey] =
                    quickImportBookkeeping.allocateSequence()
            }

            recoveryDecisionsByID[receipt.fileID, default: []].insert(
                .moveReadbackPending(
                    moveID: receipt.moveID,
                    destinationURL: receipt.destinationURL,
                    entryIdentity: EntryIdentityKey(receipt.entryIdentity)
                )
            )
            revokeCommitPermitsForRecoveryDecision(receipt.fileID)
            pendingMetadataReloadsByID.removeValue(forKey: receipt.fileID)
            appliedFileModelRefreshGenerations[receipt.fileID] = makeFileModelRefreshGeneration()
            if let current = committedFile(withID: receipt.fileID) {
                replaceSourceMembershipEntry(current.projectingDisplay(to: receipt.destinationURL))
            }
            invalidateWatchedFolderScans(containingFileID: receipt.fileID)
            lastAutomaticReloadFailures = []
        }

        rebuildVisibleFiles()
    }

    /// ID-map helper kept for callers that only know the old/new URLs. When the
    /// affected ID is a Quick Import membership, its tokens, index keys and scope
    /// leases migrate with the mapping.
    func registerMovedFiles(_ changes: [(id: UUID, oldURL: URL, newURL: URL)]) {
        guard !changes.isEmpty else { return }

        for oldKey in Set(changes.map { Self.urlKey(for: $0.oldURL) }) {
            fileIDsByKey.removeValue(forKey: oldKey)
        }
        var parentEvidenceByPath: [String: QuickImportParentEvidence] = [:]
        struct PreparedMove {
            let id: UUID
            let destinationURL: URL
            let identity: QuickImportPathIdentity
            let existingRecord: QuickImportMembershipRecord?
        }
        var preparedMoves: [PreparedMove] = []
        preparedMoves.reserveCapacity(changes.count)

        for change in changes {
            let destinationURL = change.newURL.standardizedFileURL
            let parentPath = destinationURL.deletingLastPathComponent().path
            let identity = quickImportEnvironment.identityProvider.prepareIdentity(
                forFileURL: destinationURL,
                parent: parentEvidenceByPath[parentPath]
            )
            parentEvidenceByPath[parentPath] = identity.parentEvidence
            let existingRecord = quickImportBookkeeping.index.record(forID: change.id)
            if let existingRecord {
                quickImportBookkeeping.tombstone(fileKey: existingRecord.identity.fileKey)
            }
            preparedMoves.append(
                PreparedMove(
                    id: change.id,
                    destinationURL: destinationURL,
                    identity: identity,
                    existingRecord: existingRecord
                )
            )
        }

        for move in preparedMoves {
            fileIDsByKey[move.identity.fileKey] = move.id
            guard let record = move.existingRecord else {
                continue
            }
            let destinationToken = UUID()
            quickImportBookkeeping.tokensByFileKey[move.identity.fileKey] = destinationToken
            quickImportBookkeeping.admittedSequenceByFileKey[move.identity.fileKey] =
                quickImportBookkeeping.allocateSequence()
            _ = quickImportBookkeeping.index.migrate(id: move.id, to: move.identity)
            quickImportBookkeeping.index.updateRequestToken(id: move.id, token: destinationToken)
            quickImportBookkeeping.leases.migrateKey(
                from: Self.quickImportIntakeLeaseKey(for: record.identity.operationalURL),
                to: Self.quickImportIntakeLeaseKey(for: move.destinationURL),
                url: move.destinationURL,
                owner: .membership(move.id)
            )
            if record.identity.parentKey != move.identity.parentKey {
                quickImportBookkeeping.leases.migrateKey(
                    from: record.identity.parentKey,
                    to: move.identity.parentKey,
                    url: move.identity.parentURL,
                    owner: .membership(move.id)
                )
            }
        }
    }

    /// F2 restore completion: migrate Quick Import memberships of restored file
    /// IDs back to the manifest's original URL only when the restored entry's
    /// device/inode evidence matches the membership that was captured at import.
    /// Ambiguous or missing evidence skips migration rather than fabricating
    /// authority or resurrecting a row.
    func migrateQuickImportMembershipsAfterJournalRestore(
        manifest: RenameJournalManifest,
        restoredFileIDs: Set<AudioFile.ID>
    ) {
        guard !restoredFileIDs.isEmpty else { return }
        var parentEvidenceByPath: [String: QuickImportParentEvidence] = [:]

        struct PreparedRestoreMigration {
            let fileID: AudioFile.ID
            let record: QuickImportMembershipRecord
            let originalURL: URL
            let identity: QuickImportPathIdentity
        }

        var migrations: [PreparedRestoreMigration] = []

        for fileID in restoredFileIDs {
            guard let record = quickImportBookkeeping.index.record(forID: fileID),
                  let captured = record.identity.fileIdentity else {
                continue
            }
            let matchingEntries = manifest.entries.filter { entry in
                entry.sourceIdentity.device == captured.device
                    && entry.sourceIdentity.inode == captured.inode
            }
            guard matchingEntries.count == 1, let entry = matchingEntries.first else {
                continue
            }
            // RenameJournalEntry stores file:// URL strings (validated by
            // RenameJournalManifest). Reject non-file URLs instead of feeding
            // URL strings into URL(fileURLWithPath:).
            guard let parsedURL = URL(string: entry.originalURL), parsedURL.isFileURL else {
                continue
            }
            let originalURL = parsedURL.standardizedFileURL
            let parentPath = originalURL.deletingLastPathComponent().path
            let identity = quickImportEnvironment.identityProvider.prepareIdentity(
                forFileURL: originalURL,
                parent: parentEvidenceByPath[parentPath]
            )
            parentEvidenceByPath[parentPath] = identity.parentEvidence
            guard let restoredEvidence = identity.fileIdentity,
                  restoredEvidence == captured else {
                continue
            }
            migrations.append(
                PreparedRestoreMigration(
                    fileID: fileID,
                    record: record,
                    originalURL: originalURL,
                    identity: identity
                )
            )
        }

        guard !migrations.isEmpty else { return }

        // Pass 1: remove old keys and tombstone old file keys before installing
        // restored destination keys (preserves swap atomicity).
        for migration in migrations {
            fileIDsByKey.removeValue(forKey: migration.record.identity.fileKey)
            quickImportBookkeeping.tombstone(fileKey: migration.record.identity.fileKey)
        }

        // Pass 2: install restored tokens, index identities, leases and display
        // projections.
        for migration in migrations {
            let fileID = migration.fileID
            let record = migration.record
            let originalURL = migration.originalURL
            let identity = migration.identity

            let restoredToken = UUID()
            quickImportBookkeeping.tokensByFileKey[identity.fileKey] = restoredToken
            quickImportBookkeeping.admittedSequenceByFileKey[identity.fileKey] =
                quickImportBookkeeping.allocateSequence()
            _ = quickImportBookkeeping.index.migrate(id: fileID, to: identity)
            quickImportBookkeeping.index.updateRequestToken(id: fileID, token: restoredToken)
            quickImportBookkeeping.leases.migrateKey(
                from: Self.quickImportIntakeLeaseKey(for: record.identity.operationalURL),
                to: Self.quickImportIntakeLeaseKey(for: originalURL),
                url: originalURL,
                owner: .membership(fileID)
            )
            if record.identity.parentKey != identity.parentKey {
                quickImportBookkeeping.leases.migrateKey(
                    from: record.identity.parentKey,
                    to: identity.parentKey,
                    url: identity.parentURL,
                    owner: .membership(fileID)
                )
            }
            fileIDsByKey[identity.fileKey] = fileID
            if let current = committedFile(withID: fileID) {
                replaceSourceMembershipEntry(current.projectingDisplay(to: originalURL))
            }
        }

        quickImportBookkeeping.metrics.restoredMembershipMigrationCount += migrations.count
        rebuildVisibleFiles()
    }
}
