import Foundation

// MARK: - Recovery presentation

nonisolated struct RenameJournalRecoveryEntryPresentation: Identifiable, Equatable, Sendable {
    let index: Int
    let originalName: String
    let intendedName: String
    /// Localized role: original, temporary, new, missing, foreign, ambiguous, unavailable.
    let roleText: String

    var id: Int { index }
}

nonisolated struct RenameJournalRecoveryOperationPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let phaseTitle: String
    let statusTitle: String
    let entries: [RenameJournalRecoveryEntryPresentation]
    let canRestore: Bool
    let canAcknowledge: Bool
    let missingDirectoryURLs: [URL]
    let detailText: String?
}

nonisolated struct RenameJournalRecoveryIssuePresentation: Identifiable, Equatable, Sendable {
    let id: String
    let message: String
}

nonisolated struct RenameJournalRecoveryState: Equatable, Sendable {
    var operations: [RenameJournalRecoveryOperationPresentation]
    var issues: [RenameJournalRecoveryIssuePresentation]
    var isBusy: Bool
    var isRefreshing: Bool

    static let empty = RenameJournalRecoveryState(
        operations: [],
        issues: [],
        isBusy: false,
        isRefreshing: false
    )

    var isEmpty: Bool { operations.isEmpty && issues.isEmpty }
}

nonisolated enum RenameJournalOperationActionResult: Equatable, Sendable {
    case success(String)
    case failure(String)
    case busy(String)
}

/// Thrown by the shared writer guard when a recorded prepared operation still
/// blocks a path. The message directs the user to the Folders recovery surface.
nonisolated struct RenameJournalRecoveryError: LocalizedError, Equatable, Sendable {
    let fileName: String

    var errorDescription: String? {
        String(
            localized: "A rename for “\(fileName)” was interrupted or needs acknowledgement. Open Settings > Folders, review Rename Recovery, and restore or acknowledge the operation before editing this file."
        )
    }
}

// MARK: - Journal state, bootstrap, restore and acknowledgement

extension AudioViewModel {
    // MARK: Bootstrapping and read-only classification

    /// Synchronous read-only manifest load performed during initialization after
    /// authorized folders are available and before any scan or mutation runs.
    /// Installs path-keyed blocks immediately; classification is deferred.
    func bootstrapRenameJournalRecovery(scheduleClassification: Bool = true) {
        let load = renameJournalStore.loadManifests()
        applyRenameJournalLoad(load)
        guard scheduleClassification else { return }
        if !load.manifests.isEmpty || !load.issues.isEmpty {
            renameJournalRecovery = RenameJournalRecoveryState(
                operations: [],
                issues: makeRenameJournalIssuePresentations(load.issues),
                isBusy: false,
                isRefreshing: true
            )
            scheduleRenameJournalRefresh(presentStartupWarning: true)
        }
    }

    /// Read-only refresh used by the Folders surface and after rename outcomes.
    /// Never moves files and never removes a record.
    func refreshRenameJournalRecovery(presentStartupWarning: Bool = false) async {
        // Monotonic refresh generation: a slower classification must not overwrite
        // a newer refresh (for example the refresh that follows an acknowledgement).
        renameJournalRefreshGeneration &+= 1
        let refreshGeneration = renameJournalRefreshGeneration

        let load = renameJournalStore.loadManifests()
        guard refreshGeneration == renameJournalRefreshGeneration else { return }
        applyRenameJournalLoad(load)

        guard !load.manifests.isEmpty else {
            renameJournalRecovery = RenameJournalRecoveryState(
                operations: [],
                issues: makeRenameJournalIssuePresentations(load.issues),
                isBusy: false,
                isRefreshing: false
            )
            return
        }

        let fileSystem = renameFileSystem
        let journal = renameJournalStore
        let manifests = renameJournalManifests
        let classifications = await Task.detached(priority: .userInitiated) {
            RenameTransactionService(fileSystem: fileSystem, journal: journal).classify(manifests)
        }.value
        guard refreshGeneration == renameJournalRefreshGeneration else { return }

        let classificationByOperation = Dictionary(
            uniqueKeysWithValues: classifications.map { ($0.operationID, $0) }
        )
        var operations: [RenameJournalRecoveryOperationPresentation] = []
        for manifest in renameJournalManifests {
            guard let classification = classificationByOperation[manifest.operationID] else { continue }
            operations.append(makeRenameJournalOperationPresentation(
                manifest: manifest,
                classification: classification
            ))
        }
        operations.sort { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }

        renameJournalRecovery = RenameJournalRecoveryState(
            operations: operations,
            issues: makeRenameJournalIssuePresentations(load.issues),
            isBusy: classifications.contains(where: { $0.status == .busy }),
            isRefreshing: false
        )

        if presentStartupWarning {
            presentRenameJournalStartupWarningIfNeeded()
        }
    }

    func refreshRenameJournalRecoveryForSettings() async {
        await refreshRenameJournalRecovery(presentStartupWarning: false)
    }

    // MARK: Path-keyed mutation blocks

    func renameJournalOperationID(for url: URL) -> UUID? {
        for key in FileSystemPathSemantics.reservationKeys(for: url) {
            if let operationID = renameJournalOperationByPathKey[key] {
                return operationID
            }
        }
        return nil
    }

    /// Reservation-key lookup for callers that captured the keys before the
    /// observation was loaded (Quick Import candidates).
    func renameJournalOperationID(forReservationKeys keys: Set<String>) -> UUID? {
        for key in keys {
            if let operationID = renameJournalOperationByPathKey[key] {
                return operationID
            }
        }
        return nil
    }

    func isRenameJournalBlocked(url: URL) -> Bool {
        !renameJournalPathBlocks.isDisjoint(with: FileSystemPathSemantics.reservationKeys(for: url))
    }

    // MARK: Explicit restore

    func restoreRenameJournalOperation(id: UUID) async -> RenameJournalOperationActionResult {
        guard renameJournalActionInProgress == nil else {
            return .busy(String(localized: "Another rename recovery action is already in progress."))
        }

        let load = renameJournalStore.loadManifests()
        applyRenameJournalLoad(load)
        guard let manifest = renameJournalManifests.first(where: {
            $0.operationID == id && $0.phase == .prepared
        }) else {
            await refreshRenameJournalRecovery()
            return .failure(String(localized: "This interrupted rename record is no longer available."))
        }

        let candidateURLs = renameJournalCandidateURLs(for: manifest)
        let fileSystem = renameFileSystem
        let journal = renameJournalStore
        let classification: RenameJournalClassification?
        classification = await Task.detached(priority: .userInitiated) {
            RenameTransactionService(fileSystem: fileSystem, journal: journal)
                .classify([manifest])
                .first
        }.value

        guard let classification else {
            return .failure(String(localized: "The rename record couldn't be checked. Choose Retry."))
        }
        switch classification.status {
        case .preparedNoFilesMoved, .preparedNeedsRestore, .preparedAllAtIntended:
            break
        case .busy:
            return .busy(String(localized: "Another copy of AudioMator is using rename recovery. Try again."))
        default:
            return .failure(renameJournalClassificationFailureMessage(classification))
        }

        // Scope prompts happen before any journal lock or reservation is taken.
        if let accessFailure = ensureMutationDirectoryAccess(for: candidateURLs) {
            return .failure(accessFailure)
        }

        renameJournalActionInProgress = id
        defer { renameJournalActionInProgress = nil }

        let outcome: RenameRestoreOutcome
        do {
            outcome = try await withSecurityScopedAccessForQuickImportURLs(candidateURLs) {
                try await fileMutationCoordinator.withExclusiveAccess(to: candidateURLs) {
                    await Task.detached(priority: .userInitiated) {
                        RenameTransactionService(fileSystem: fileSystem, journal: journal)
                            .restoreOriginals(manifest)
                    }.value
                }
            }
        } catch is CancellationError {
            return .busy(String(localized: "Restoring the original names was cancelled. No further files were moved."))
        } catch {
            return .failure(String(localized: "Restoring the original names couldn't start. Details: \((error as NSError).localizedDescription)"))
        }

        let restoredFileIDs = renameJournalFileIDsByOperation[id] ?? []
        switch outcome {
        case .restored(let operationID, _, let retainedRecord):
            clearJournalRecoveryDecisions(forFileIDs: restoredFileIDs, operationID: operationID)
            // Quick Import memberships are re-keyed only when the restored file
            // entry's device/inode evidence matches the captured membership. An
            // ambiguous or unknown identity skips migration and keeps the
            // recovery decision; startup classification never moves files.
            migrateQuickImportMembershipsAfterJournalRestore(
                manifest: manifest,
                restoredFileIDs: restoredFileIDs
            )
            invalidateWatchedFolderScansForRestoredJournalFiles(restoredFileIDs)
            for folder in watchedFolders {
                scheduleWatchedFolderRescan(for: folder.id)
            }
            await refreshRenameJournalRecovery()
            var message = String(localized: "Original names were restored after verifying each file entry. Reload any affected files before editing them.")
            if retainedRecord {
                message += " " + String(localized: "The recovery record couldn't be removed and was kept for inspection.")
            }
            presentMetadataWriteHUD(
                style: retainedRecord ? .warning : .success,
                title: String(localized: "Original Names Restored"),
                subtitle: message
            )
            return .success(message)
        case .unresolved(_, let updatedClassification, _):
            await refreshRenameJournalRecovery()
            return .failure(renameJournalClassificationFailureMessage(updatedClassification))
        case .rejected(let rejection):
            await refreshRenameJournalRecovery()
            return .failure(renameJournalRestoreRejectionMessage(rejection))
        case .busy:
            return .busy(String(localized: "Another copy of AudioMator is using rename recovery. Try again."))
        }
    }

    // MARK: Explicit acknowledgement

    func acknowledgeRenameJournalOperation(id: UUID) async -> RenameJournalOperationActionResult {
        guard renameJournalActionInProgress == nil else {
            return .busy(String(localized: "Another rename recovery action is already in progress."))
        }

        let load = renameJournalStore.loadManifests()
        applyRenameJournalLoad(load)
        guard let manifest = renameJournalManifests.first(where: { $0.operationID == id }) else {
            await refreshRenameJournalRecovery()
            return .failure(String(localized: "This rename recovery record is no longer available."))
        }

        let candidateURLs = renameJournalCandidateURLs(for: manifest)
        let fileSystem = renameFileSystem
        let journal = renameJournalStore

        renameJournalActionInProgress = id
        defer { renameJournalActionInProgress = nil }

        let outcome: RenameRecordRemovalOutcome
        do {
            outcome = try await withSecurityScopedAccessForQuickImportURLs(candidateURLs) {
                try await fileMutationCoordinator.withExclusiveAccess(to: candidateURLs) {
                    await Task.detached(priority: .userInitiated) {
                        RenameTransactionService(fileSystem: fileSystem, journal: journal)
                            .removeAcknowledgedRecord(id)
                    }.value
                }
            }
        } catch {
            return .failure(String(localized: "The rename recovery record couldn't be removed. Details: \((error as NSError).localizedDescription)"))
        }

        switch outcome {
        case .removed(let operationID):
            let fileIDs = renameJournalFileIDsByOperation[operationID] ?? []
            clearJournalRecoveryDecisions(forFileIDs: fileIDs, operationID: operationID)
            await refreshRenameJournalRecovery()
            let message = String(localized: "The rename recovery record was removed. No files were moved.")
            presentMetadataWriteHUD(
                style: .success,
                title: String(localized: "Rename Record Removed"),
                subtitle: message
            )
            return .success(message)
        case .busy:
            return .busy(String(localized: "Another copy of AudioMator is using rename recovery. Try again."))
        case .rejected(let rejection):
            await refreshRenameJournalRecovery()
            return .failure(renameJournalRestoreRejectionMessage(rejection))
        case .unresolved(let classification):
            await refreshRenameJournalRecovery()
            return .failure(renameJournalClassificationFailureMessage(classification))
        }
    }

    // MARK: - Internal helpers

    private func applyRenameJournalLoad(_ load: RenameJournalLoadResult) {
        renameJournalManifests = load.manifests
        rebuildRenameJournalPathIndex()
        renameJournalRecovery.issues = makeRenameJournalIssuePresentations(load.issues)
    }

    private func rebuildRenameJournalPathIndex() {
        var blocks: Set<String> = []
        var operationByPathKey: [String: UUID] = [:]
        for manifest in renameJournalManifests where manifest.phase == .prepared {
            for entry in manifest.entries {
                for urlString in [entry.originalURL, entry.temporaryURL, entry.intendedURL] {
                    guard let url = URL(string: urlString) else { continue }
                    for key in FileSystemPathSemantics.reservationKeys(for: url) {
                        blocks.insert(key)
                        operationByPathKey[key] = manifest.operationID
                    }
                }
            }
        }
        renameJournalPathBlocks = blocks
        renameJournalOperationByPathKey = operationByPathKey
    }

    private func scheduleRenameJournalRefresh(presentStartupWarning: Bool) {
        renameJournalRefreshTask?.cancel()
        renameJournalRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshRenameJournalRecovery(presentStartupWarning: presentStartupWarning)
        }
    }

    private func presentRenameJournalStartupWarningIfNeeded() {
        guard !didPresentRenameJournalStartupWarning else { return }
        guard !renameJournalRecovery.operations.isEmpty || !renameJournalRecovery.issues.isEmpty else {
            return
        }
        didPresentRenameJournalStartupWarning = true

        let hasPrepared = renameJournalRecovery.operations.contains { $0.canRestore }
        presentMetadataWriteHUD(
            style: .warning,
            title: String(localized: "Interrupted Rename Needs Attention"),
            subtitle: hasPrepared
                ? String(localized: "A rename was interrupted before it finished. No files were changed automatically. Open Settings > Folders, then Rename Recovery to review the recorded locations and restore the original names.")
                : String(localized: "A finished rename record needs review. Open Settings > Folders, then Rename Recovery to inspect or remove it. No files are moved automatically."),
            summary: String(localized: "Rename Recovery")
        )
    }

    private func renameJournalCandidateURLs(for manifest: RenameJournalManifest) -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []
        for entry in manifest.entries {
            for urlString in [entry.originalURL, entry.temporaryURL, entry.intendedURL] {
                guard let url = URL(string: urlString) else { continue }
                let key = FileSystemPathSemantics.key(for: url)
                guard seen.insert(key).inserted else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    private func makeRenameJournalIssuePresentations(
        _ issues: [RenameJournalLoadIssue]
    ) -> [RenameJournalRecoveryIssuePresentation] {
        issues.map { issue in
            RenameJournalRecoveryIssuePresentation(
                id: issue.manifestFileName,
                message: renameJournalIssueMessage(issue)
            )
        }
    }

    private func renameJournalIssueMessage(_ issue: RenameJournalLoadIssue) -> String {
        switch issue.category {
        case .unreadable:
            return String(localized: "A saved rename recovery record couldn't be read and was kept for inspection.")
        case .unsupportedVersion:
            return String(localized: "A saved rename recovery record was created by a newer version and was kept for inspection.")
        case .invalidManifest:
            return String(localized: "A saved rename recovery record couldn't be validated and was kept for inspection.")
        case .incompleteWrite:
            return String(localized: "An incomplete rename recovery record was kept for inspection.")
        case .duplicateOperationID:
            return String(localized: "More than one rename recovery record uses the same identifier; they were kept for inspection.")
        }
    }

    private func makeRenameJournalOperationPresentation(
        manifest: RenameJournalManifest,
        classification: RenameJournalClassification
    ) -> RenameJournalRecoveryOperationPresentation {
        let rolesByIndex = Dictionary(
            uniqueKeysWithValues: classification.entries.map { ($0.index, $0.role) }
        )
        let entries = manifest.entries.map { entry -> RenameJournalRecoveryEntryPresentation in
            let role = rolesByIndex[entry.index] ?? .unavailable
            return RenameJournalRecoveryEntryPresentation(
                index: entry.index,
                originalName: URL(string: entry.originalURL)?.lastPathComponent ?? "",
                intendedName: URL(string: entry.intendedURL)?.lastPathComponent ?? "",
                roleText: renameJournalRoleText(role)
            )
        }
        let restorableStatuses: [RenameJournalOperationStatus] = [
            .preparedNoFilesMoved, .preparedNeedsRestore, .preparedAllAtIntended
        ]
        let acknowledgeableStatuses: [RenameJournalOperationStatus] = [
            .committedConfirmed, .committedUncertain, .preparedNoFilesMoved
        ]
        let missingDirectoryURLs = manifest.entries.compactMap { entry -> URL? in
            guard rolesByIndex[entry.index] == .unavailable,
                  let originalURL = URL(string: entry.originalURL)
            else { return nil }
            return originalURL.deletingLastPathComponent()
        }
        var seenDirectories: Set<String> = []
        let uniqueMissingDirectories = missingDirectoryURLs.filter {
            seenDirectories.insert(FileSystemPathSemantics.key(for: $0)).inserted
        }

        return RenameJournalRecoveryOperationPresentation(
            id: manifest.operationID,
            phaseTitle: manifest.phase == .prepared
                ? String(localized: "Interrupted")
                : String(localized: "Completed"),
            statusTitle: renameJournalStatusTitle(classification.status),
            entries: entries,
            canRestore: manifest.phase == .prepared && restorableStatuses.contains(classification.status),
            canAcknowledge: acknowledgeableStatuses.contains(classification.status),
            missingDirectoryURLs: uniqueMissingDirectories,
            detailText: classification.issueCodes.isEmpty
                ? nil
                : classification.issueCodes.map(\.rawValue).joined(separator: ", ")
        )
    }

    private func renameJournalRoleText(_ role: RenameEntryRole) -> String {
        switch role {
        case .original:
            return String(localized: "At the original name")
        case .staged:
            return String(localized: "At a temporary name")
        case .intended:
            return String(localized: "At the new name")
        case .missing:
            return String(localized: "Location not found")
        case .foreign:
            return String(localized: "Another file now has this name")
        case .ambiguous:
            return String(localized: "Multiple locations match")
        case .unavailable:
            return String(localized: "Folder unavailable")
        }
    }

    private func renameJournalStatusTitle(_ status: RenameJournalOperationStatus) -> String {
        switch status {
        case .preparedNoFilesMoved:
            return String(localized: "Interrupted before any file moved")
        case .preparedNeedsRestore:
            return String(localized: "Interrupted — original names can be restored")
        case .preparedAllAtIntended:
            return String(localized: "All files moved, but completion wasn't recorded")
        case .preparedUnresolved:
            return String(localized: "Needs inspection before restoration")
        case .preparedUnavailable:
            return String(localized: "Folder access is required")
        case .committedConfirmed:
            return String(localized: "Completed")
        case .committedUncertain:
            return String(localized: "Completed record couldn't be verified")
        case .busy:
            return String(localized: "Another copy of AudioMator is using rename recovery")
        }
    }

    private func renameJournalClassificationFailureMessage(
        _ classification: RenameJournalClassification
    ) -> String {
        let status = renameJournalStatusTitle(classification.status)
        return String(
            localized: "The rename recovery record can't be restored automatically: \(status). The recorded locations were left unchanged for inspection."
        )
    }

    private func renameJournalRestoreRejectionMessage(
        _ rejection: RenameRestoreRejection
    ) -> String {
        switch rejection {
        case .committedRecordFinal:
            return String(localized: "This rename was completed, so the new names are final and are not restored.")
        case .recordMissing:
            return String(localized: "The rename recovery record is no longer available.")
        case .journalUnavailable:
            return String(localized: "Rename recovery storage couldn't be read or written. Nothing was moved.")
        case .exclusiveRenameUnsupported(let folderName):
            return String(
                localized: "The folder “\(folderName)” is on a volume that can't provide safe exclusive renames. Nothing was moved."
            )
        }
    }
}
