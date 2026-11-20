import Foundation

struct FileRenameResult {
    let totalTargets: Int
    let renamed: Int
    let unchanged: Int
    let skippedIssues: Int
    let warnings: [String]
    let failureMessage: String?
    let recoveryItems: [FileRenameRecoveryItem]
    var wasCancelled: Bool = false
}

struct FileRenameRecoveryItem: Equatable, Sendable {
    /// Retained file identity so the view model can keep the model's display
    /// projection and recovery decision bound to the observed location.
    let id: UUID
    let originalURL: URL
    let intendedURL: URL
    let finalLocations: [URL]
    let rollbackErrors: [String]
    /// Present only when exactly one observed location matched the expected file
    /// entry. Carries the identity captured at that location.
    var verifiedLocation: VerifiedRenameLocation? = nil

    var finalURL: URL? {
        verifiedLocation?.url ?? (finalLocations.count == 1 ? finalLocations[0] : nil)
    }
}

struct FileRenameTransactionFailure: Sendable {
    let message: String
    let recoveryItems: [FileRenameRecoveryItem]
    var wasCancelled: Bool = false
}

/// Caller-side cancellation flag for the detached exclusive-move transaction.
/// The service checks it only before its first writable stage; once staging has
/// begun the operation owns completion or rollback and reports real effects.
private nonisolated final class RenameCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

extension AudioViewModel {
    func renameFiles(using plan: FileRenamePlan) async -> FileRenameResult {
        let totalTargets = plan.totalTargets
        let unchangedCount = plan.unchangedCount
        let skippedIssues = plan.issueCount
        var issueWarnings = fileRenameIssueWarnings(from: plan.rows)
        let operations = plan.operations

        guard !operations.isEmpty else {
            return FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: nil,
                recoveryItems: []
            )
        }
        guard canStartExternalFileMutation() else {
            return FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: String(localized: "Save or discard your unsaved Inspector edits before renaming files."),
                recoveryItems: []
            )
        }
        guard !operations.contains(where: { hasRecoveryDecision(for: $0.id) }) else {
            return FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: String(localized: "A file in this preview needs to be reloaded before it can be renamed again. Choose Reload from Disk for that file, then reopen this tool."),
                recoveryItems: []
            )
        }
        guard !operations.contains(where: {
            isRenameJournalBlocked(url: $0.sourceURL) || isRenameJournalBlocked(url: $0.destinationURL)
        }) else {
            return FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: String(localized: "An interrupted rename needs to be restored or acknowledged before these files can be renamed. Open Settings > Folders, review Rename Recovery, then reopen this tool."),
                recoveryItems: []
            )
        }

        let operationID = UUID()
        let preparedEntries = operations.enumerated().map { index, operation in
            PreparedRenameEntry(
                index: index,
                fileID: operation.id,
                originalURL: operation.sourceURL,
                temporaryURL: RenameStagingName.url(
                    for: operation.sourceURL,
                    operationID: operationID,
                    index: index
                ),
                intendedURL: operation.destinationURL,
                expectedSourceFingerprint: operation.expectedFileFingerprint
            )
        }
        let prepared = PreparedRenameTransaction(operationID: operationID, entries: preparedEntries)

        // Scope is requested against both the source and intended parents before
        // any journal lock or reservation is taken.
        let scopedURLs = operations.flatMap { [$0.sourceURL, $0.destinationURL] }
        if let accessFailure = ensureMutationDirectoryAccess(for: scopedURLs) {
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: [],
                failureMessage: accessFailure,
                recoveryItems: []
            )
            presentFileRenameSummary(result)
            return result
        }

        let mutationURLs = preparedEntries.flatMap {
            [$0.originalURL, $0.temporaryURL, $0.intendedURL]
        }
        let fileMutationCoordinator = self.fileMutationCoordinator
        let fileSystem = renameFileSystem
        let journal = renameJournalStore
        let cancellationFlag = RenameCancellationFlag()
        let service = RenameTransactionService(
            fileSystem: fileSystem,
            journal: journal,
            isCancelled: { cancellationFlag.isCancelled }
        )

        var execution: (outcome: RenameExecutionOutcome, receipts: [FileRenameMoveReceipt])
        do {
            execution = try await withSecurityScopedAccessForQuickImportURLs(scopedURLs) {
                try await fileMutationCoordinator.withExclusiveAccess(to: mutationURLs) {
                    let outcome = await withTaskCancellationHandler {
                        await Task.detached(priority: .userInitiated) {
                            service.execute(prepared)
                        }.value
                    } onCancel: {
                        cancellationFlag.cancel()
                    }

                    // Publication of verified move receipts happens while the
                    // union reservation is still held so no writer can start on a
                    // destination without observing the pending decision.
                    let receipts = await self.publishRenameOutcome(outcome, prepared: prepared)
                    return (outcome, receipts)
                }
            }
        } catch is CancellationError {
            execution = (
                .cancelledBeforeStaging(operationID: operationID),
                []
            )
        } catch {
            execution = (
                .rejected(.journalUnavailable),
                []
            )
        }

        switch execution.outcome {
        case .committed(_, let moves, let diagnostics):
            if diagnostics.contains(.journalCleanupDeferred) {
                await refreshRenameJournalRecovery()
            }
            let warnings = await readBackMovedFiles(execution.receipts)
            issueWarnings.append(contentsOf: warnings)
            _ = moves
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: execution.receipts.count,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: nil,
                recoveryItems: []
            )
            presentFileRenameSummary(result)
            return result

        case .rolledBack(_, let reason):
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: String(
                    localized: "Files couldn’t be renamed. Every moved file was restored to its original name.\nDetails: \(renameFailureReasonMessage(reason))"
                ),
                recoveryItems: []
            )
            presentFileRenameSummary(result)
            return result

        case .cancelledBeforeStaging:
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: String(localized: "Renaming was cancelled before it began. No files were renamed."),
                recoveryItems: [],
                wasCancelled: true
            )
            presentFileRenameSummary(result)
            return result

        case .unresolved(let unresolvedOperationID, let classification, let reason):
            await refreshRenameJournalRecovery()
            applyRenameJournalPendingDecisions(
                fileIDs: prepared.entries.map(\.fileID),
                operationID: unresolvedOperationID
            )
            let failure = makeRenameTransactionFailure(
                operationID: unresolvedOperationID,
                classification: classification,
                reason: reason,
                prepared: prepared
            )
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: failure.message,
                recoveryItems: failure.recoveryItems
            )
            presentFileRenameSummary(result)
            return result

        case .busy:
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: String(localized: "Another copy of AudioMator is using rename recovery. No files were renamed. Try again after that operation finishes."),
                recoveryItems: []
            )
            presentFileRenameSummary(result)
            return result

        case .rejected(let rejection):
            await refreshRenameJournalRecovery()
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: renamePreflightRejectionMessage(rejection),
                recoveryItems: []
            )
            presentFileRenameSummary(result)
            return result
        }
    }

    /// Publishes under the rename reservation. Returns the receipts used for the
    /// post-release bounded readback. On an unresolved outcome, records the named
    /// journal decision and path blocks for the claimed files; no move receipt is
    /// published because the on-disk locations are uncertain.
    private func publishRenameOutcome(
        _ outcome: RenameExecutionOutcome,
        prepared: PreparedRenameTransaction
    ) async -> [FileRenameMoveReceipt] {
        switch outcome {
        case .committed(_, let moves, _):
            let receipts = moves.map { move in
                FileRenameMoveReceipt(
                    moveID: FileMoveID(),
                    fileID: move.fileID,
                    sourceURL: move.originalURL,
                    destinationURL: move.intendedURL,
                    entryIdentity: move.entryIdentity
                )
            }
            publishMovePlaceholders(receipts)
            return receipts

        case .unresolved(let operationID, _, _):
            // Block every affected ID and path synchronously while the union
            // reservation is still held so no queued metadata writer can slip
            // through between reservation release and async classification.
            registerUnresolvedRenameJournalBlocks(
                operationID: operationID,
                preparedEntries: prepared.entries
            )
            return []

        default:
            return []
        }
    }

    private func makeRenameTransactionFailure(
        operationID: UUID,
        classification: RenameJournalClassification,
        reason: RenameFailureReason?,
        prepared: PreparedRenameTransaction
    ) -> FileRenameTransactionFailure {
        let entriesByIndex = Dictionary(
            uniqueKeysWithValues: prepared.entries.map { ($0.index, $0) }
        )
        var recoveryItems: [FileRenameRecoveryItem] = []
        var lines: [String] = []

        for entryClassification in classification.entries {
            guard let preparedEntry = entriesByIndex[entryClassification.index] else { continue }
            var finalLocations: [URL] = []
            if entryClassification.role != .original, let observedURL = entryClassification.observedURL {
                finalLocations.append(observedURL)
            }
            var verifiedLocation: VerifiedRenameLocation?
            if entryClassification.role == .intended || entryClassification.role == .staged,
               let observedURL = entryClassification.observedURL,
               let observedIdentity = entryClassification.observedIdentity {
                verifiedLocation = VerifiedRenameLocation(url: observedURL, identity: observedIdentity)
            }
            let originalName = preparedEntry.originalURL.lastPathComponent
            let observedText: String
            if finalLocations.isEmpty {
                observedText = String(localized: "current location couldn’t be determined")
            } else {
                observedText = finalLocations.map(\.path).joined(separator: ", ")
            }
            lines.append(String(localized: "“\(originalName)” — observed: \(observedText)"))
            recoveryItems.append(
                FileRenameRecoveryItem(
                    id: preparedEntry.fileID,
                    originalURL: preparedEntry.originalURL,
                    intendedURL: preparedEntry.intendedURL,
                    finalLocations: finalLocations,
                    rollbackErrors: [],
                    verifiedLocation: verifiedLocation
                )
            )
        }

        if !recoveryItems.isEmpty {
            lines.insert(
                String(localized: "Recovery required for \(fileCountLabel(recoveryItems.count)):"),
                at: 0
            )
        }

        let primary: String
        if let reason {
            primary = String(localized: "Files couldn’t be renamed. \(renameFailureReasonMessage(reason))")
        } else {
            primary = String(localized: "Files couldn’t be renamed and need recovery review.")
        }
        lines.append(String(localized: "Open Settings > Folders, then Rename Recovery to review the recorded locations and restore the original names. No file was overwritten."))
        _ = operationID

        return FileRenameTransactionFailure(
            message: ([primary] + lines).joined(separator: "\n"),
            recoveryItems: recoveryItems
        )
    }

    private func renameFailureReasonMessage(_ reason: RenameFailureReason) -> String {
        switch reason {
        case .sourceChanged(let index):
            return String(localized: "The file at position \(index + 1) changed since the preview was created.")
        case .sourceMissing(let index):
            return String(localized: "The file at position \(index + 1) is missing.")
        case .parentUnavailable(let index):
            return String(localized: "The folder for the file at position \(index + 1) is unavailable or changed.")
        case .destinationOccupied(let index):
            return String(localized: "The intended name for the file at position \(index + 1) is occupied by another file.")
        case .entryIdentityMismatch(let index):
            return String(localized: "The file entry at position \(index + 1) could not be verified after a move, so no further moves were attempted.")
        case .moveFailed(let index, let code):
            return String(localized: "A file move failed at position \(index + 1) (code \(code)).")
        case .directorySyncFailed(let code):
            return String(localized: "The folder metadata could not be flushed after moving files (code \(code)).")
        case .journalUnavailable:
            return String(localized: "The rename recovery record could not be read or written.")
        case .committedRecordFailed:
            return String(localized: "The completion record could not be written after moving files.")
        }
    }

    private func renamePreflightRejectionMessage(_ rejection: RenamePreflightRejection) -> String {
        switch rejection {
        case .invalidPlan:
            return String(localized: "The rename plan is no longer valid. Close and reopen this tool to review it again.")
        case .sourceChanged(let index):
            return String(localized: "The file at position \(index + 1) changed since the preview was created. No files were moved.")
        case .sourceMissing(let index):
            return String(localized: "The file at position \(index + 1) is missing. No files were moved.")
        case .unexpectedEntryKind(let index):
            return String(localized: "The item at position \(index + 1) is not a regular file or symbolic link that can be renamed. No files were moved.")
        case .sourceIdentityUnavailable(let index):
            return String(localized: "The file at position \(index + 1) does not provide enough identity evidence to be renamed safely. No files were moved.")
        case .parentUnavailable(let index):
            return String(localized: "The folder for the file at position \(index + 1) could not be opened or changed during the operation. No files were moved.")
        case .stageNameOccupied(let index):
            return String(localized: "A temporary name for the file at position \(index + 1) is unavailable. No files were moved.")
        case .stageNameTooLong(let index):
            return String(localized: "A temporary name for the file at position \(index + 1) is too long. No files were moved.")
        case .destinationOccupied(let index):
            return String(localized: "The intended name for the file at position \(index + 1) is occupied by another file. No files were moved.")
        case .exclusiveRenameUnsupported(let folderName):
            return String(
                localized: "The folder “\(folderName)” is on a volume that can’t provide safe exclusive renames. No files were moved. Choose a local folder that supports exclusive renaming."
            )
        case .journalUnavailable:
            return String(localized: "The rename recovery record could not be written safely, so no files were moved.")
        case .overlappingPreparedOperation:
            return String(localized: "Another interrupted rename covers one of these files. Open Settings > Folders, review Rename Recovery, then try again. No files were moved.")
        case .duplicateOperation:
            return String(localized: "A recovery record already exists for this operation. Open Settings > Folders, review Rename Recovery, then try again. No files were moved.")
        }
    }

    private func presentFileRenameSummary(_ result: FileRenameResult) {
        if let failureMessage = result.failureMessage {
            let subtitle = ([failureMessage] + result.warnings)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            presentMetadataWriteHUD(
                style: result.wasCancelled ? .warning : .failure,
                title: result.wasCancelled ? String(localized: "Operation Cancelled") : String(localized: "Files Couldn’t Be Renamed"),
                subtitle: subtitle,
                summary: failureMessage.components(separatedBy: .newlines).first ?? failureMessage,
                details: ([failureMessage.components(separatedBy: .newlines).dropFirst().joined(separator: "\n")] + result.warnings).filter { !$0.isEmpty }.joined(separator: "\n\n")
            )
            return
        }

        let renamedLabel = result.renamed == 1
            ? String(localized: "1 file was renamed.")
            : String(localized: "\(result.renamed) files were renamed.")
        let unchangedLabel = result.unchanged == 0 ? nil : String(localized: "Files unchanged: \(result.unchanged).")
        let skippedLabel = result.skippedIssues == 0 ? nil : String(localized: "Files skipped: \(result.skippedIssues).")

        if result.warnings.isEmpty {
            presentMetadataWriteHUD(
                style: result.skippedIssues == 0 ? .success : .warning,
                title: "Files Renamed",
                subtitle: [renamedLabel, unchangedLabel, skippedLabel]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            )
            return
        }

        var lines = [renamedLabel]
        if let unchangedLabel {
            lines.append(unchangedLabel)
        }
        if let skippedLabel {
            lines.append(skippedLabel)
        }

        for warning in result.warnings.prefix(2) {
            lines.append(warning)
        }

        if result.warnings.count > 2 {
            lines.append(String(localized: "Additional warnings: \(result.warnings.count - 2)."))
        }

        presentMetadataWriteHUD(
            style: .warning,
            title: String(localized: "Files Renamed with Warnings"),
            subtitle: lines.joined(separator: "\n")
        )
    }
}

private func fileRenameIssueWarnings(from rows: [FileRenamePreviewRow]) -> [String] {
    rows.compactMap { row in
        guard row.status.isError else { return nil }
        return "\(row.currentName): \(row.status.title)"
    }
}
