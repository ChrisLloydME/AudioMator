import Foundation

nonisolated enum RenameRecordRemovalOutcome: Equatable, Sendable {
    case removed(operationID: UUID)
    case busy
    case rejected(RenameRestoreRejection)
    case unresolved(RenameJournalClassification)
}

/// Durable, exclusive rename transaction service.
///
/// The service owns filesystem effects and durability ordering; the view model
/// owns authorization, path reservations, security scopes and publication. All
/// entry points are synchronous and take immutable input so the caller can run
/// the service in a detached task and hold its journal lock for the whole call.
nonisolated struct RenameTransactionService: Sendable {
    private let fileSystem: any RenameFileSystem
    private let journal: any RenameJournalStoring
    private let isCancelled: @Sendable () -> Bool

    init(
        fileSystem: any RenameFileSystem,
        journal: any RenameJournalStoring,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) {
        self.fileSystem = fileSystem
        self.journal = journal
        self.isCancelled = isCancelled
    }

    // MARK: - Execute

    func execute(_ prepared: PreparedRenameTransaction) -> RenameExecutionOutcome {
        if let failure = validate(prepared) {
            return .rejected(.invalidPlan(failure))
        }

        do {
            try journal.ensureDirectory()
        } catch {
            return .rejected(.journalUnavailable)
        }

        let lock: RenameJournalLock
        do {
            guard let acquired = try journal.tryAcquireLock() else { return .busy }
            lock = acquired
        } catch {
            return .rejected(.journalUnavailable)
        }
        defer { lock.release() }

        let loaded = journal.loadManifests()
        if loaded.manifests.contains(where: { $0.operationID == prepared.operationID }) {
            return .rejected(.duplicateOperation(operationID: prepared.operationID))
        }
        if let overlapping = overlappingPreparedOperation(of: prepared, in: loaded.manifests) {
            return .rejected(.overlappingPreparedOperation(operationID: overlapping))
        }

        let handles: [String: RenameDirectoryHandle]
        do {
            handles = try openHandles(for: prepared)
        } catch let rejection as RenamePreflightRejection {
            return .rejected(rejection)
        } catch {
            return .rejected(.parentUnavailable(index: 0))
        }

        let evidence: [Int: CapturedIdentity]
        switch preflight(prepared, handles: handles) {
        case .success(let captured):
            evidence = captured
        case .failure(let rejection):
            return .rejected(rejection)
        }

        var diagnostics: [RenameJournalDiagnosticCode] = []
        if journal.directoryBarrierSupport() == .unsupported {
            diagnostics.append(.directoryBarrierUnsupported)
        }

        let manifestEntries: [RenameJournalEntry]
        do {
            manifestEntries = try makeManifestEntries(prepared: prepared, evidence: evidence)
        } catch {
            return .rejected(.sourceIdentityUnavailable(index: 0))
        }

        let manifest = RenameJournalManifest(
            formatVersion: RenameJournalFormat.currentVersion,
            operationID: prepared.operationID,
            phase: .prepared,
            createdAt: Date().timeIntervalSince1970,
            committedAt: nil,
            diagnostics: diagnostics.map(\.rawValue),
            entries: manifestEntries
        )

        do {
            try manifest.validate()
        } catch {
            return .rejected(.invalidPlan(.invalidRoleCollision))
        }

        do {
            try journal.writePrepared(manifest)
        } catch {
            if let installed = journal.loadManifests().manifests.first(where: {
                $0.operationID == prepared.operationID
            }) {
                // The record may have been installed before its directory barrier
                // failed. No audio move has happened; report the uncertain record
                // and leave recovery evidence in place.
                return .unresolved(
                    operationID: prepared.operationID,
                    classification: classifyManifest(installed),
                    reason: .journalUnavailable
                )
            }
            return .rejected(.journalUnavailable)
        }

        if isCancelled() {
            try? journal.removeManifest(operationID: prepared.operationID)
            return .cancelledBeforeStaging(operationID: prepared.operationID)
        }

        let stagedIndices: [Int]
        switch stage(prepared, manifest: manifest, handles: handles, evidence: evidence) {
        case .success(let indices):
            stagedIndices = indices
        case .failure(let failure):
            return rollback(
                reason: failure.reason,
                manifest: manifest,
                handles: handles,
                evidence: evidence,
                finalized: [],
                staged: failure.stagedPrefix
            )
        }

        let finalizedIndices: [Int]
        switch finalize(
            prepared,
            manifest: manifest,
            handles: handles,
            evidence: evidence,
            stagedIndices: stagedIndices
        ) {
        case .success(let indices):
            finalizedIndices = indices
        case .failure(let failure):
            return rollback(
                reason: failure.reason,
                manifest: manifest,
                handles: handles,
                evidence: evidence,
                finalized: failure.finalizedPrefix,
                staged: stagedIndices
            )
        }

        let flushResult = flushAudioDirectories(handles: handles)
        if let flushFailure = flushResult.failure {
            return unresolvedOutcome(reason: flushFailure, manifest: manifest)
        }
        let flushDiagnostics = flushResult.barrierUnsupported
            ? [RenameJournalDiagnosticCode.directoryBarrierUnsupported]
            : []

        if let mismatch = firstIntendedIdentityMismatch(
            prepared,
            manifest: manifest,
            handles: handles,
            evidence: evidence
        ) {
            return unresolvedOutcome(reason: .entryIdentityMismatch(index: mismatch), manifest: manifest)
        }

        var committedDiagnostics = manifest.diagnostics
        for code in flushDiagnostics where !committedDiagnostics.contains(code.rawValue) {
            committedDiagnostics.append(code.rawValue)
        }
        let committedManifest = RenameJournalManifest(
            formatVersion: manifest.formatVersion,
            operationID: manifest.operationID,
            phase: .committed,
            createdAt: manifest.createdAt,
            committedAt: Date().timeIntervalSince1970,
            diagnostics: committedDiagnostics,
            entries: manifest.entries
        )

        do {
            try journal.markCommitted(committedManifest)
        } catch {
            if let installed = journal.loadManifests().manifests.first(where: {
                $0.operationID == prepared.operationID
            }) {
                return .unresolved(
                    operationID: prepared.operationID,
                    classification: classifyManifest(installed),
                    reason: .committedRecordFailed
                )
            }
            return unresolvedOutcome(reason: .committedRecordFailed, manifest: manifest)
        }

        var commitDiagnostics = diagnostics
        for code in flushDiagnostics where !commitDiagnostics.contains(code) {
            commitDiagnostics.append(code)
        }
        do {
            try journal.removeManifest(operationID: prepared.operationID)
        } catch {
            commitDiagnostics.append(.journalCleanupDeferred)
        }

        let moves = prepared.entries.compactMap { entry -> RenameExecutedMove? in
            guard let identity = evidence[entry.index] else { return nil }
            return RenameExecutedMove(
                index: entry.index,
                fileID: entry.fileID,
                originalURL: entry.originalURL,
                intendedURL: entry.intendedURL,
                entryIdentity: identity.journalIdentity.renameEntryIdentity
            )
        }
        _ = finalizedIndices
        return .committed(
            operationID: prepared.operationID,
            moves: moves,
            diagnostics: commitDiagnostics
        )
    }

    // MARK: - Classify

    func classify(_ manifests: [RenameJournalManifest]) -> [RenameJournalClassification] {
        let lock: RenameJournalLock?
        do {
            lock = try journal.tryAcquireLock()
        } catch {
            lock = nil
        }
        defer { lock?.release() }
        let busy = lock == nil

        return manifests.map { manifest in
            if busy, manifest.phase == .prepared {
                return RenameJournalClassification(
                    operationID: manifest.operationID,
                    phase: manifest.phase,
                    status: .busy,
                    entries: [],
                    issueCodes: [.busy]
                )
            }
            return classifyManifest(manifest)
        }
    }

    // MARK: - Restore

    func restoreOriginals(_ manifest: RenameJournalManifest) -> RenameRestoreOutcome {
        guard manifest.phase == .prepared else {
            return .rejected(.committedRecordFinal)
        }

        let lock: RenameJournalLock
        do {
            guard let acquired = try journal.tryAcquireLock() else { return .busy }
            lock = acquired
        } catch {
            return .rejected(.journalUnavailable)
        }
        defer { lock.release() }

        guard let current = journal.loadManifests().manifests.first(where: {
            $0.operationID == manifest.operationID
        }) else {
            return .rejected(.recordMissing)
        }
        guard current.phase == .prepared else {
            return .rejected(.committedRecordFinal)
        }

        let classification = classifyManifest(current)
        switch classification.status {
        case .preparedNoFilesMoved, .preparedNeedsRestore, .preparedAllAtIntended:
            break
        default:
            return .unresolved(operationID: current.operationID, classification: classification, reason: nil)
        }

        let handles: [String: RenameDirectoryHandle]
        do {
            handles = try openHandles(forManifest: current)
        } catch let rejection as RenameRestoreRejection {
            return .rejected(rejection)
        } catch {
            return .rejected(.journalUnavailable)
        }

        for handle in handles.values {
            let supported = (try? fileSystem.volumeSupportsExclusiveRename(forDirectoryAt: handle.url)) == true
            guard supported else {
                return .rejected(.exclusiveRenameUnsupported(folderName: handle.url.lastPathComponent))
            }
        }

        let reversePlan: ReversePlan
        switch makeReversePlan(
            manifest: current,
            classification: classification,
            handles: handles
        ) {
        case .success(let plan):
            reversePlan = plan
        case .failure(let reason):
            return .unresolved(
                operationID: current.operationID,
                classification: classification,
                reason: reason
            )
        }

        for move in reversePlan.toStage {
            guard let entry = current.entries.first(where: { $0.index == move.index }),
                  let intendedURL = URL(string: entry.intendedURL),
                  let temporaryURL = URL(string: entry.temporaryURL),
                  let handle = handle(for: intendedURL, in: handles)
            else {
                return .unresolved(operationID: current.operationID, classification: classification, reason: nil)
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return .unresolved(operationID: current.operationID, classification: classification, reason: .parentUnavailable(index: move.index))
            }
            do {
                try fileSystem.exclusiveMove(
                    named: intendedURL.lastPathComponent,
                    to: temporaryURL.lastPathComponent,
                    in: handle
                )
                try verifyEntryIdentity(
                    at: temporaryURL.lastPathComponent,
                    in: handle,
                    expected: entry.sourceIdentity,
                    expectedLinkTarget: entry.linkTarget
                )
            } catch let error as RenameFileSystemError {
                return .unresolved(
                    operationID: current.operationID,
                    classification: classifyManifest(current),
                    reason: failureReason(for: error, index: move.index)
                )
            } catch {
                return .unresolved(
                    operationID: current.operationID,
                    classification: classifyManifest(current),
                    reason: .moveFailed(index: move.index, code: "unknown")
                )
            }
        }

        for move in reversePlan.toOriginal {
            guard let entry = current.entries.first(where: { $0.index == move.index }),
                  let originalURL = URL(string: entry.originalURL),
                  let temporaryURL = URL(string: entry.temporaryURL),
                  let handle = handle(for: originalURL, in: handles)
            else {
                return .unresolved(operationID: current.operationID, classification: classification, reason: nil)
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return .unresolved(operationID: current.operationID, classification: classification, reason: .parentUnavailable(index: move.index))
            }
            do {
                try fileSystem.exclusiveMove(
                    named: temporaryURL.lastPathComponent,
                    to: originalURL.lastPathComponent,
                    in: handle
                )
                try verifyEntryIdentity(
                    at: originalURL.lastPathComponent,
                    in: handle,
                    expected: entry.sourceIdentity,
                    expectedLinkTarget: entry.linkTarget
                )
            } catch let error as RenameFileSystemError {
                return .unresolved(
                    operationID: current.operationID,
                    classification: classifyManifest(current),
                    reason: failureReason(for: error, index: move.index)
                )
            } catch {
                return .unresolved(
                    operationID: current.operationID,
                    classification: classifyManifest(current),
                    reason: .moveFailed(index: move.index, code: "unknown")
                )
            }
        }

        for handle in handles.values {
            try? fileSystem.syncDirectory(handle)
        }

        var retainedRecord = false
        do {
            try journal.removeManifest(operationID: current.operationID)
        } catch {
            retainedRecord = true
        }

        let restoredMoves = current.entries.compactMap { entry -> RenameRestoredMove? in
            guard let originalURL = URL(string: entry.originalURL) else { return nil }
            return RenameRestoredMove(
                index: entry.index,
                originalURL: originalURL,
                entryIdentity: entry.sourceIdentity.renameEntryIdentity
            )
        }

        return .restored(
            operationID: current.operationID,
            moves: restoredMoves,
            retainedRecord: retainedRecord
        )
    }

    // MARK: - Explicit acknowledgement

    /// Removes a record only after an explicit user acknowledgement and a fresh
    /// read-only verification under the journal lock. A committed record (or a
    /// prepared record that proves no file moved) may be removed; everything else
    /// stays for inspection.
    func removeAcknowledgedRecord(_ operationID: UUID) -> RenameRecordRemovalOutcome {
        let lock: RenameJournalLock
        do {
            guard let acquired = try journal.tryAcquireLock() else { return .busy }
            lock = acquired
        } catch {
            return .rejected(.journalUnavailable)
        }
        defer { lock.release() }

        guard let current = journal.loadManifests().manifests.first(where: {
            $0.operationID == operationID
        }) else {
            return .rejected(.recordMissing)
        }

        let classification = classifyManifest(current)
        switch classification.status {
        case .committedConfirmed, .committedUncertain, .preparedNoFilesMoved:
            do {
                try journal.removeManifest(operationID: operationID)
                return .removed(operationID: operationID)
            } catch {
                return .rejected(.journalUnavailable)
            }
        case .busy:
            return .busy
        default:
            return .unresolved(classification)
        }
    }

    // MARK: - Input validation

    private func validate(_ prepared: PreparedRenameTransaction) -> RenamePlanValidationFailure? {
        let entries = prepared.entries
        guard !entries.isEmpty else { return .emptyBatch }
        guard entries.count <= RenameJournalFormat.maximumEntryCount else { return .tooManyEntries }
        guard entries.map(\.index) == Array(0..<entries.count) else { return .invalidIndex }

        var fileIDs: Set<UUID> = []
        var originalURLs: Set<String> = []
        var temporaryURLs: Set<String> = []
        var intendedKeys: Set<String> = []
        var parentURLs: Set<String> = []

        for entry in entries {
            guard fileIDs.insert(entry.fileID).inserted else { return .duplicateFileID }

            guard
                entry.originalURL.isFileURL,
                entry.originalURL.path.hasPrefix("/"),
                entry.intendedURL.isFileURL,
                entry.intendedURL.path.hasPrefix("/"),
                entry.temporaryURL.isFileURL,
                entry.temporaryURL.path.hasPrefix("/")
            else { return .notAFileURL }

            let parent = entry.originalURL.deletingLastPathComponent().absoluteString
            parentURLs.insert(parent)
            guard
                entry.intendedURL.deletingLastPathComponent().absoluteString == parent,
                entry.temporaryURL.deletingLastPathComponent().absoluteString == parent
            else { return .mixedParent }

            guard RenameStagingName.validates(
                entry.temporaryURL,
                for: entry.originalURL,
                operationID: prepared.operationID,
                index: entry.index
            ) else { return .temporaryNameMismatch }

            guard entry.originalURL.absoluteString != entry.temporaryURL.absoluteString,
                  entry.temporaryURL.absoluteString != entry.intendedURL.absoluteString,
                  entry.originalURL.pathExtension == entry.intendedURL.pathExtension
            else { return .unchangedEntry }

            guard originalURLs.insert(entry.originalURL.absoluteString).inserted else {
                return .duplicateSource
            }
            guard temporaryURLs.insert(entry.temporaryURL.absoluteString).inserted else {
                return .temporaryNameMismatch
            }
            let intendedKey = FileSystemPathSemantics.key(for: entry.intendedURL)
            guard intendedKeys.insert(intendedKey).inserted else { return .duplicateTarget }

            guard entry.originalURL.pathExtension == entry.intendedURL.pathExtension else {
                return .invalidExtension
            }
        }
        _ = parentURLs
        return nil
    }

    private func overlappingPreparedOperation(
        of prepared: PreparedRenameTransaction,
        in manifests: [RenameJournalManifest]
    ) -> UUID? {
        let requestedKeys = Set(prepared.entries.flatMap { entry in
            [
                FileSystemPathSemantics.key(for: entry.originalURL),
                FileSystemPathSemantics.key(for: entry.temporaryURL),
                FileSystemPathSemantics.key(for: entry.intendedURL)
            ]
        })

        for manifest in manifests where manifest.phase == .prepared {
            let recordedKeys = Set(manifest.entries.flatMap { entry -> [String] in
                var urls: [URL] = []
                if let original = URL(string: entry.originalURL) { urls.append(original) }
                if let temporary = URL(string: entry.temporaryURL) { urls.append(temporary) }
                if let intended = URL(string: entry.intendedURL) { urls.append(intended) }
                return urls.map(FileSystemPathSemantics.key(for:))
            })
            if !requestedKeys.isDisjoint(with: recordedKeys) {
                return manifest.operationID
            }
        }
        return nil
    }

    // MARK: - Handles

    private func openHandles(for prepared: PreparedRenameTransaction) throws -> [String: RenameDirectoryHandle] {
        var handles: [String: RenameDirectoryHandle] = [:]
        for entry in prepared.entries {
            let parentURL = entry.originalURL.deletingLastPathComponent().standardizedFileURL
            let key = parentURL.absoluteString
            if handles[key] != nil { continue }

            let supported: Bool
            do {
                supported = try fileSystem.volumeSupportsExclusiveRename(forDirectoryAt: parentURL)
            } catch {
                throw RenamePreflightRejection.parentUnavailable(index: entry.index)
            }
            guard supported else {
                throw RenamePreflightRejection.exclusiveRenameUnsupported(
                    folderName: parentURL.lastPathComponent
                )
            }
            do {
                handles[key] = try fileSystem.openDirectory(at: parentURL)
            } catch {
                throw RenamePreflightRejection.parentUnavailable(index: entry.index)
            }
        }
        return handles
    }

    private func openHandles(forManifest manifest: RenameJournalManifest) throws -> [String: RenameDirectoryHandle] {
        var handles: [String: RenameDirectoryHandle] = [:]
        for entry in manifest.entries {
            guard let originalURL = URL(string: entry.originalURL) else {
                throw RenameRestoreRejection.recordMissing
            }
            let parentURL = originalURL.deletingLastPathComponent().standardizedFileURL
            if handles[parentURL.absoluteString] != nil { continue }
            let supported = (try? fileSystem.volumeSupportsExclusiveRename(forDirectoryAt: parentURL)) == true
            guard supported else {
                throw RenameRestoreRejection.exclusiveRenameUnsupported(
                    folderName: parentURL.lastPathComponent
                )
            }
            guard let handle = try? fileSystem.openDirectory(at: parentURL) else {
                throw RenameRestoreRejection.journalUnavailable
            }
            handles[parentURL.absoluteString] = handle
        }
        return handles
    }

    private func handle(
        for url: URL,
        in handles: [String: RenameDirectoryHandle]
    ) -> RenameDirectoryHandle? {
        handles[url.deletingLastPathComponent().standardizedFileURL.absoluteString]
    }

    // MARK: - Preflight

    private struct CapturedIdentity: Sendable {
        let journalIdentity: RenameJournalEntryIdentity
        let linkTarget: String?
    }

    private func preflight(
        _ prepared: PreparedRenameTransaction,
        handles: [String: RenameDirectoryHandle]
    ) -> Result<[Int: CapturedIdentity], RenamePreflightRejection> {
        let sourceKeys = Set(
            prepared.entries.map { FileSystemPathSemantics.key(for: $0.originalURL) }
        )
        var evidence: [Int: CapturedIdentity] = [:]

        for entry in prepared.entries {
            guard let parentHandle = handle(for: entry.originalURL, in: handles) else {
                return .failure(.parentUnavailable(index: entry.index))
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(parentHandle) else {
                return .failure(.parentUnavailable(index: entry.index))
            }

            let originalIdentity: RenameEntryIdentity?
            do {
                originalIdentity = try fileSystem.entryIdentityIfPresent(at: entry.originalURL)
            } catch {
                return .failure(.parentUnavailable(index: entry.index))
            }
            guard let originalIdentity else {
                return .failure(.sourceMissing(index: entry.index))
            }
            guard originalIdentity.kind == .regular || originalIdentity.kind == .symlink else {
                return .failure(.unexpectedEntryKind(index: entry.index))
            }

            let fingerprint: AudioFileFingerprint
            do {
                fingerprint = try fileSystem.fingerprint(at: entry.originalURL)
            } catch {
                return .failure(.parentUnavailable(index: entry.index))
            }
            guard fingerprint == entry.expectedSourceFingerprint else {
                return .failure(.sourceChanged(index: entry.index))
            }

            let linkTarget = originalIdentity.kind == .symlink
                ? fileSystem.linkTarget(at: entry.originalURL)
                : nil
            if originalIdentity.kind == .symlink, linkTarget == nil {
                return .failure(.sourceIdentityUnavailable(index: entry.index))
            }

            let enriched = RenameEntryIdentity(
                device: originalIdentity.device,
                inode: originalIdentity.inode,
                kind: originalIdentity.kind,
                size: originalIdentity.size,
                modificationDate: originalIdentity.modificationDate,
                creationDate: originalIdentity.creationDate,
                volumeIdentifier: parentHandle.identity.volumeIdentifier,
                linkTarget: linkTarget
            )
            do {
                evidence[entry.index] = CapturedIdentity(
                    journalIdentity: try RenameJournalEntryIdentity(enriched),
                    linkTarget: linkTarget
                )
            } catch {
                return .failure(.sourceIdentityUnavailable(index: entry.index))
            }

            let temporaryName = entry.temporaryURL.lastPathComponent
            guard temporaryName.utf8.count <= 255 else {
                return .failure(.stageNameTooLong(index: entry.index))
            }
            do {
                if try fileSystem.entryIdentity(named: temporaryName, in: parentHandle) != nil {
                    return .failure(.stageNameOccupied(index: entry.index))
                }
            } catch {
                return .failure(.parentUnavailable(index: entry.index))
            }

            let intendedIdentity: RenameEntryIdentity?
            do {
                intendedIdentity = try fileSystem.entryIdentityIfPresent(at: entry.intendedURL)
            } catch {
                return .failure(.parentUnavailable(index: entry.index))
            }
            if intendedIdentity != nil {
                let intendedKey = FileSystemPathSemantics.key(for: entry.intendedURL)
                let originalKey = FileSystemPathSemantics.key(for: entry.originalURL)
                if intendedKey != originalKey, !sourceKeys.contains(intendedKey) {
                    return .failure(.destinationOccupied(index: entry.index))
                }
            }
        }
        return .success(evidence)
    }

    private func makeManifestEntries(
        prepared: PreparedRenameTransaction,
        evidence: [Int: CapturedIdentity]
    ) throws -> [RenameJournalEntry] {
        try prepared.entries.map { entry in
            guard let identity = evidence[entry.index] else {
                throw RenameJournalIdentityError.missingDeviceOrInode
            }
            return RenameJournalEntry(
                index: entry.index,
                originalURL: entry.originalURL.absoluteString,
                temporaryURL: entry.temporaryURL.absoluteString,
                intendedURL: entry.intendedURL.absoluteString,
                sourceIdentity: identity.journalIdentity,
                linkTarget: identity.linkTarget
            )
        }
    }

    // MARK: - Stage and finalize

    private struct StageFailure: Error {
        let reason: RenameFailureReason
        let stagedPrefix: [Int]

        init(reason: RenameFailureReason, stagedPrefix: [Int]) {
            self.reason = reason
            self.stagedPrefix = stagedPrefix
        }
    }

    private func stage(
        _ prepared: PreparedRenameTransaction,
        manifest: RenameJournalManifest,
        handles: [String: RenameDirectoryHandle],
        evidence: [Int: CapturedIdentity]
    ) -> Result<[Int], StageFailure> {
        var staged: [Int] = []

        for entry in prepared.entries {
            guard let handle = handle(for: entry.originalURL, in: handles),
                  let expected = evidence[entry.index]
            else {
                return .failure(StageFailure(reason: .parentUnavailable(index: entry.index), stagedPrefix: staged))
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return .failure(StageFailure(reason: .parentUnavailable(index: entry.index), stagedPrefix: staged))
            }

            do {
                try verifyEntryIdentity(
                    at: entry.originalURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch RenameFileSystemError.sourceMissing {
                return .failure(StageFailure(reason: .sourceMissing(index: entry.index), stagedPrefix: staged))
            } catch {
                return .failure(StageFailure(reason: .sourceChanged(index: entry.index), stagedPrefix: staged))
            }

            do {
                try fileSystem.exclusiveMove(
                    named: entry.originalURL.lastPathComponent,
                    to: entry.temporaryURL.lastPathComponent,
                    in: handle
                )
            } catch let error as RenameFileSystemError {
                return .failure(StageFailure(reason: failureReason(for: error, index: entry.index), stagedPrefix: staged))
            } catch {
                return .failure(StageFailure(reason: .moveFailed(index: entry.index, code: "unknown"), stagedPrefix: staged))
            }

            do {
                try verifyEntryIdentity(
                    at: entry.temporaryURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch {
                return .failure(StageFailure(reason: .entryIdentityMismatch(index: entry.index), stagedPrefix: staged))
            }
            staged.append(entry.index)
        }

        return .success(staged)
    }

    private struct FinalizeFailure: Error {
        let reason: RenameFailureReason
        let finalizedPrefix: [Int]

        init(reason: RenameFailureReason, finalizedPrefix: [Int]) {
            self.reason = reason
            self.finalizedPrefix = finalizedPrefix
        }
    }

    private func finalize(
        _ prepared: PreparedRenameTransaction,
        manifest: RenameJournalManifest,
        handles: [String: RenameDirectoryHandle],
        evidence: [Int: CapturedIdentity],
        stagedIndices: [Int]
    ) -> Result<[Int], FinalizeFailure> {
        var finalized: [Int] = []

        for entry in prepared.entries {
            guard let handle = handle(for: entry.originalURL, in: handles),
                  let expected = evidence[entry.index]
            else {
                return .failure(FinalizeFailure(reason: .parentUnavailable(index: entry.index), finalizedPrefix: finalized))
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return .failure(FinalizeFailure(reason: .parentUnavailable(index: entry.index), finalizedPrefix: finalized))
            }

            do {
                try verifyEntryIdentity(
                    at: entry.temporaryURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch {
                return .failure(FinalizeFailure(reason: .entryIdentityMismatch(index: entry.index), finalizedPrefix: finalized))
            }

            do {
                try fileSystem.exclusiveMove(
                    named: entry.temporaryURL.lastPathComponent,
                    to: entry.intendedURL.lastPathComponent,
                    in: handle
                )
            } catch let error as RenameFileSystemError {
                return .failure(FinalizeFailure(reason: failureReason(for: error, index: entry.index), finalizedPrefix: finalized))
            } catch {
                return .failure(FinalizeFailure(reason: .moveFailed(index: entry.index, code: "unknown"), finalizedPrefix: finalized))
            }

            do {
                try verifyEntryIdentity(
                    at: entry.intendedURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch {
                return .failure(FinalizeFailure(reason: .entryIdentityMismatch(index: entry.index), finalizedPrefix: finalized))
            }
            finalized.append(entry.index)
        }
        _ = stagedIndices
        return .success(finalized)
    }

    // MARK: - Rollback

    private func rollback(
        reason: RenameFailureReason,
        manifest: RenameJournalManifest,
        handles: [String: RenameDirectoryHandle],
        evidence: [Int: CapturedIdentity],
        finalized: [Int],
        staged: [Int]
    ) -> RenameExecutionOutcome {
        for index in finalized.reversed() {
            guard let entry = manifest.entries.first(where: { $0.index == index }),
                  let originalURL = URL(string: entry.originalURL),
                  let intendedURL = URL(string: entry.intendedURL),
                  let temporaryURL = URL(string: entry.temporaryURL),
                  let handle = handle(for: originalURL, in: handles),
                  let expected = evidence[index]
            else {
                return unresolvedOutcome(reason: reason, manifest: manifest)
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return unresolvedOutcome(reason: reason, manifest: manifest)
            }
            do {
                try verifyEntryIdentity(
                    at: intendedURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
                try fileSystem.exclusiveMove(
                    named: intendedURL.lastPathComponent,
                    to: temporaryURL.lastPathComponent,
                    in: handle
                )
                try verifyEntryIdentity(
                    at: temporaryURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch {
                return unresolvedOutcome(reason: reason, manifest: manifest)
            }
        }

        for index in staged.reversed() {
            guard let entry = manifest.entries.first(where: { $0.index == index }),
                  let originalURL = URL(string: entry.originalURL),
                  let temporaryURL = URL(string: entry.temporaryURL),
                  let handle = handle(for: originalURL, in: handles),
                  let expected = evidence[index]
            else {
                return unresolvedOutcome(reason: reason, manifest: manifest)
            }
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return unresolvedOutcome(reason: reason, manifest: manifest)
            }
            do {
                try verifyEntryIdentity(
                    at: temporaryURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
                try fileSystem.exclusiveMove(
                    named: temporaryURL.lastPathComponent,
                    to: originalURL.lastPathComponent,
                    in: handle
                )
                try verifyEntryIdentity(
                    at: originalURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch {
                return unresolvedOutcome(reason: reason, manifest: manifest)
            }
        }

        for handle in handles.values {
            try? fileSystem.syncDirectory(handle)
        }
        try? journal.removeManifest(operationID: manifest.operationID)
        return .rolledBack(operationID: manifest.operationID, reason: reason)
    }

    // MARK: - Verification

    private func verifyEntryIdentity(
        at name: String,
        in handle: RenameDirectoryHandle,
        expected: RenameJournalEntryIdentity,
        expectedLinkTarget: String?
    ) throws {
        guard let observed = try fileSystem.entryIdentity(named: name, in: handle) else {
            throw RenameFileSystemError.sourceMissing
        }
        // fstatat cannot report volume identity or a symlink target; add the
        // held-directory volume evidence and the current link target before the
        // exact comparison.
        let entryURL = handle.url.appendingPathComponent(name, isDirectory: false)
        let linkTarget = observed.kind == .symlink ? fileSystem.linkTarget(at: entryURL) : nil
        let enriched = RenameEntryIdentity(
            device: observed.device,
            inode: observed.inode,
            kind: observed.kind,
            size: observed.size,
            modificationDate: observed.modificationDate,
            creationDate: observed.creationDate,
            volumeIdentifier: handle.identity.volumeIdentifier,
            linkTarget: linkTarget
        )
        guard expected.matchesEntryIdentity(enriched) else {
            throw RenameFileSystemError.entryIdentityUnavailable
        }
        if expected.kind == .symlink {
            guard linkTarget == expectedLinkTarget else {
                throw RenameFileSystemError.entryIdentityUnavailable
            }
        }
    }

    private func firstIntendedIdentityMismatch(
        _ prepared: PreparedRenameTransaction,
        manifest: RenameJournalManifest,
        handles: [String: RenameDirectoryHandle],
        evidence: [Int: CapturedIdentity]
    ) -> Int? {
        for entry in prepared.entries {
            guard let handle = handle(for: entry.originalURL, in: handles),
                  let expected = evidence[entry.index]
            else { return entry.index }
            do {
                try verifyEntryIdentity(
                    at: entry.intendedURL.lastPathComponent,
                    in: handle,
                    expected: expected.journalIdentity,
                    expectedLinkTarget: expected.linkTarget
                )
            } catch {
                return entry.index
            }
        }
        return nil
    }

    private struct DirectoryFlushResult {
        let failure: RenameFailureReason?
        let barrierUnsupported: Bool
    }

    private func flushAudioDirectories(
        handles: [String: RenameDirectoryHandle]
    ) -> DirectoryFlushResult {
        var barrierUnsupported = false
        for handle in handles.values {
            do {
                try fileSystem.syncDirectory(handle)
            } catch let error as RenameFileSystemError {
                switch error {
                case .directorySyncUnsupported:
                    barrierUnsupported = true
                default:
                    return DirectoryFlushResult(
                        failure: .directorySyncFailed(code: codeString(for: error)),
                        barrierUnsupported: barrierUnsupported
                    )
                }
            } catch {
                return DirectoryFlushResult(
                    failure: .directorySyncFailed(code: "unknown"),
                    barrierUnsupported: barrierUnsupported
                )
            }
        }
        return DirectoryFlushResult(failure: nil, barrierUnsupported: barrierUnsupported)
    }

    // MARK: - Classification

    private func classifyManifest(_ manifest: RenameJournalManifest) -> RenameJournalClassification {
        var entryClassifications: [RenameEntryClassification] = []
        var issueCodes: [RenameClassificationIssueCode] = []

        for entry in manifest.entries {
            let classification = classifyEntry(entry)
            entryClassifications.append(classification.classification)
            issueCodes.append(contentsOf: classification.issueCodes)
        }

        let status = operationStatus(for: manifest, entries: entryClassifications)
        return RenameJournalClassification(
            operationID: manifest.operationID,
            phase: manifest.phase,
            status: status,
            entries: entryClassifications,
            issueCodes: Array(Set(issueCodes)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private struct EntryClassificationResult {
        let classification: RenameEntryClassification
        let issueCodes: [RenameClassificationIssueCode]
    }

    private func classifyEntry(_ entry: RenameJournalEntry) -> EntryClassificationResult {
        guard
            let originalURL = URL(string: entry.originalURL),
            let temporaryURL = URL(string: entry.temporaryURL),
            let intendedURL = URL(string: entry.intendedURL)
        else {
            return EntryClassificationResult(
                classification: RenameEntryClassification(
                    index: entry.index,
                    role: .unavailable,
                    expectedIdentity: entry.sourceIdentity,
                    observedURL: nil,
                    observedIdentity: nil
                ),
                issueCodes: [.directoryUnavailable]
            )
        }

        // Check the containing directory before probing entries so a missing or
        // unreadable folder is reported as unavailable rather than missing.
        do {
            if try fileSystem.entryIdentityIfPresent(at: originalURL.deletingLastPathComponent()) == nil {
                return unavailableClassification(for: entry, issueCodes: [.directoryUnavailable])
            }
        } catch {
            return unavailableClassification(for: entry, issueCodes: [.directoryUnavailable])
        }

        var matches: [(role: RenameEntryRole, url: URL, identity: RenameEntryIdentity)] = []
        var foreign: (url: URL, identity: RenameEntryIdentity)?
        var unavailable = false
        var matchedKeys: Set<String> = []

        for candidate in [
            (RenameEntryRole.original, originalURL),
            (RenameEntryRole.staged, temporaryURL),
            (RenameEntryRole.intended, intendedURL)
        ] {
            do {
                guard let observed = try fileSystem.entryIdentityIfPresent(at: candidate.1) else {
                    continue
                }
                let enriched = try enrich(observed, at: candidate.1)
                if entry.sourceIdentity.matchesEntryIdentity(enriched) {
                    let key = FileSystemPathSemantics.key(for: candidate.1)
                    if matchedKeys.insert(key).inserted {
                        matches.append((candidate.0, candidate.1, enriched))
                    }
                } else {
                    foreign = (candidate.1, enriched)
                }
            } catch {
                unavailable = true
            }
        }

        if matches.count > 1 {
            return EntryClassificationResult(
                classification: RenameEntryClassification(
                    index: entry.index,
                    role: .ambiguous,
                    expectedIdentity: entry.sourceIdentity,
                    observedURL: matches.first?.url,
                    observedIdentity: matches.first?.identity
                ),
                issueCodes: [.ambiguousEntry]
            )
        }

        if let match = matches.first {
            var role = match.role
            if role == .original, aliasResolvesToIntendedName(
                originalURL: originalURL,
                intendedURL: intendedURL
            ) {
                role = .intended
            }
            return EntryClassificationResult(
                classification: RenameEntryClassification(
                    index: entry.index,
                    role: role,
                    expectedIdentity: entry.sourceIdentity,
                    observedURL: match.url,
                    observedIdentity: match.identity
                ),
                issueCodes: []
            )
        }

        if let foreign {
            return EntryClassificationResult(
                classification: RenameEntryClassification(
                    index: entry.index,
                    role: .foreign,
                    expectedIdentity: entry.sourceIdentity,
                    observedURL: foreign.url,
                    observedIdentity: foreign.identity
                ),
                issueCodes: [.foreignEntry]
            )
        }

        if unavailable {
            return EntryClassificationResult(
                classification: RenameEntryClassification(
                    index: entry.index,
                    role: .unavailable,
                    expectedIdentity: entry.sourceIdentity,
                    observedURL: nil,
                    observedIdentity: nil
                ),
                issueCodes: [.directoryUnavailable]
            )
        }

        return EntryClassificationResult(
            classification: RenameEntryClassification(
                index: entry.index,
                role: .missing,
                expectedIdentity: entry.sourceIdentity,
                observedURL: nil,
                observedIdentity: nil
            ),
            issueCodes: [.missingEntry]
        )
    }

    private func unavailableClassification(
        for entry: RenameJournalEntry,
        issueCodes: [RenameClassificationIssueCode]
    ) -> EntryClassificationResult {
        EntryClassificationResult(
            classification: RenameEntryClassification(
                index: entry.index,
                role: .unavailable,
                expectedIdentity: entry.sourceIdentity,
                observedURL: nil,
                observedIdentity: nil
            ),
            issueCodes: issueCodes
        )
    }

    private func aliasResolvesToIntendedName(originalURL: URL, intendedURL: URL) -> Bool {
        guard
            FileSystemPathSemantics.key(for: originalURL)
                == FileSystemPathSemantics.key(for: intendedURL),
            let actual = try? fileSystem.actualEntryName(
                inDirectoryAt: originalURL.deletingLastPathComponent(),
                matching: originalURL.lastPathComponent
            )
        else { return false }
        return actual == intendedURL.lastPathComponent && actual != originalURL.lastPathComponent
    }

    private func enrich(
        _ observed: RenameEntryIdentity,
        at url: URL
    ) throws -> RenameEntryIdentity {
        let parentURL = url.deletingLastPathComponent()
        let volumeIdentifier = fileSystem.volumeIdentifier(forDirectoryAt: parentURL)
        let linkTarget = observed.kind == .symlink ? fileSystem.linkTarget(at: url) : nil
        return RenameEntryIdentity(
            device: observed.device,
            inode: observed.inode,
            kind: observed.kind,
            size: observed.size,
            modificationDate: observed.modificationDate,
            creationDate: observed.creationDate,
            volumeIdentifier: volumeIdentifier,
            linkTarget: linkTarget
        )
    }

    private func operationStatus(
        for manifest: RenameJournalManifest,
        entries: [RenameEntryClassification]
    ) -> RenameJournalOperationStatus {
        let roles = entries.map(\.role)

        switch manifest.phase {
        case .prepared:
            if roles.contains(.unavailable) { return .preparedUnavailable }
            if entries.contains(where: {
                $0.role == .ambiguous || $0.role == .foreign || $0.role == .missing
            }) {
                return .preparedUnresolved
            }
            if roles.allSatisfy({ $0 == .original }) { return .preparedNoFilesMoved }
            if roles.allSatisfy({ $0 == .intended }) { return .preparedAllAtIntended }
            return .preparedNeedsRestore
        case .committed:
            if roles.allSatisfy({ $0 == .intended }) { return .committedConfirmed }
            return .committedUncertain
        }
    }

    // MARK: - Reverse plan

    private struct ReversePlan {
        let toStage: [(index: Int, intendedURL: URL, temporaryURL: URL)]
        let toOriginal: [(index: Int, temporaryURL: URL, originalURL: URL)]
    }

    private func makeReversePlan(
        manifest: RenameJournalManifest,
        classification: RenameJournalClassification,
        handles: [String: RenameDirectoryHandle]
    ) -> Result<ReversePlan, RenameFailureReason> {
        let rolesByIndex = Dictionary(
            uniqueKeysWithValues: classification.entries.map { ($0.index, $0.role) }
        )

        var toStage: [(index: Int, intendedURL: URL, temporaryURL: URL)] = []
        var toOriginal: [(index: Int, temporaryURL: URL, originalURL: URL)] = []

        var intendedLocationKeys: Set<String> = []

        for entry in manifest.entries {
            let role = rolesByIndex[entry.index] ?? .unavailable
            guard
                let originalURL = URL(string: entry.originalURL),
                let temporaryURL = URL(string: entry.temporaryURL),
                let intendedURL = URL(string: entry.intendedURL),
                let handle = handle(for: originalURL, in: handles)
            else { return .failure(.parentUnavailable(index: entry.index)) }

            switch role {
            case .original:
                continue
            case .staged:
                toOriginal.append((entry.index, temporaryURL, originalURL))
            case .intended:
                intendedLocationKeys.insert(FileSystemPathSemantics.key(for: intendedURL))
                toStage.append((entry.index, intendedURL, temporaryURL))
                toOriginal.append((entry.index, temporaryURL, originalURL))
            default:
                return .failure(.sourceMissing(index: entry.index))
            }

            if role == .intended {
                do {
                    if try fileSystem.entryIdentity(named: temporaryURL.lastPathComponent, in: handle) != nil {
                        return .failure(.destinationOccupied(index: entry.index))
                    }
                } catch {
                    return .failure(.parentUnavailable(index: entry.index))
                }
            }
        }

        for move in toOriginal {
            guard
                let originalURL = URL(string: manifest.entries.first(where: { $0.index == move.index })?.originalURL ?? ""),
                let handle = handle(for: originalURL, in: handles)
            else { return .failure(.parentUnavailable(index: move.index)) }

            do {
                if try fileSystem.entryIdentityIfPresent(at: originalURL) != nil,
                   !intendedLocationKeys.contains(FileSystemPathSemantics.key(for: originalURL)) {
                    return .failure(.destinationOccupied(index: move.index))
                }
            } catch {
                return .failure(.parentUnavailable(index: move.index))
            }
        }

        for handle in handles.values {
            guard fileSystem.authorizedPathStillIdentifiesDirectory(handle) else {
                return .failure(.parentUnavailable(index: 0))
            }
        }

        return .success(ReversePlan(toStage: toStage, toOriginal: toOriginal))
    }

    // MARK: - Outcome helpers

    private func unresolvedOutcome(
        reason: RenameFailureReason?,
        manifest: RenameJournalManifest
    ) -> RenameExecutionOutcome {
        let current = journal.loadManifests().manifests.first(where: {
            $0.operationID == manifest.operationID
        }) ?? manifest
        return .unresolved(
            operationID: manifest.operationID,
            classification: classifyManifest(current),
            reason: reason
        )
    }

    private func failureReason(
        for error: RenameFileSystemError,
        index: Int
    ) -> RenameFailureReason {
        switch error {
        case .sourceMissing:
            return .sourceMissing(index: index)
        case .destinationOccupied:
            return .destinationOccupied(index: index)
        case .exclusiveRenameUnsupported:
            return .moveFailed(index: index, code: "exclusiveRenameUnsupported")
        case .directorySyncUnsupported:
            return .directorySyncFailed(code: "directorySyncUnsupported")
        case .entryIdentityUnavailable:
            return .entryIdentityMismatch(index: index)
        case .io(let code):
            return .moveFailed(index: index, code: "errno\(code)")
        }
    }

    private func codeString(for error: RenameFileSystemError) -> String {
        switch error {
        case .sourceMissing: return "sourceMissing"
        case .destinationOccupied: return "destinationOccupied"
        case .exclusiveRenameUnsupported: return "exclusiveRenameUnsupported"
        case .directorySyncUnsupported: return "directorySyncUnsupported"
        case .entryIdentityUnavailable: return "entryIdentityUnavailable"
        case .io(let code): return "errno\(code)"
        }
    }
}
