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

private struct PreparedFileRenameOperation: Sendable {
    let operation: FileRenameOperation
    let temporaryURL: URL
}

struct FileRenameRecoveryItem: Equatable, Sendable {
    /// Retained file identity so the view model can rebind the model to the
    /// observed recovery location instead of leaving it on a vanished path.
    let id: UUID
    let originalURL: URL
    let intendedURL: URL
    let finalLocations: [URL]
    let rollbackErrors: [String]
    /// Present only when exactly one observed location matched the expected file
    /// entry. Carries the identity captured at that location so publication and
    /// readback can verify it.
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

enum FileRenameExecutionResult: Sendable {
    case success([FileRenameMoveReceipt])
    case failure(FileRenameTransactionFailure)
}

protocol FileRenameFileSystem: Sendable {
    nonisolated func fileExists(at url: URL) -> Bool
    nonisolated func fingerprint(at url: URL) throws -> AudioFileFingerprint
    nonisolated func entryIdentity(at url: URL) throws -> RenameEntryIdentity
    nonisolated func moveItem(at sourceURL: URL, to destinationURL: URL) throws
}

struct LocalFileRenameFileSystem: FileRenameFileSystem {
    nonisolated init() {}

    nonisolated func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated func fingerprint(at url: URL) throws -> AudioFileFingerprint {
        try AudioFileFingerprint.capture(at: url)
    }

    nonisolated func entryIdentity(at url: URL) throws -> RenameEntryIdentity {
        try FileEntryIdentityCapture.capture(at: url)
    }

    nonisolated func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
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

        let scopedURLs = operations.map(\.sourceURL)
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

        let mutationURLs = operations.flatMap { [$0.sourceURL, $0.destinationURL] }
        let fileMutationCoordinator = self.fileMutationCoordinator
        let execution: FileRenameExecutionResult
        do {
            execution = try await withSecurityScopedAccessForQuickImportURLs(scopedURLs) {
                try await fileMutationCoordinator.withExclusiveAccess(to: mutationURLs) {
                    let result = await Task.detached(priority: .userInitiated) {
                        executeFileRenameTransaction(operations)
                    }.value
                    // Publish the verified move receipts (or block unresolved
                    // recovery locations) before releasing the reservation. No
                    // writer can start on a destination without observing the
                    // pending recovery decision.
                    switch result {
                    case .success(let receipts):
                        await self.publishMovePlaceholders(receipts)
                    case .failure(let failure):
                        await self.publishRecoveryBlocks(failure.recoveryItems)
                    }
                    return result
                }
            }
        } catch is CancellationError {
            execution = .failure(FileRenameTransactionFailure(
                message: String(localized: "Renaming was cancelled before it began. No files were renamed."),
                recoveryItems: [], wasCancelled: true
            ))
        } catch {
            execution = .failure(FileRenameTransactionFailure(
                message: String(localized: "Files couldn’t be renamed.\nDetails: \(error.localizedDescription)"),
                recoveryItems: []
            ))
        }

        switch execution {
        case .failure(let failure):
            issueWarnings.append(contentsOf: await reconcileRenameRecovery(failure.recoveryItems))

            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: failure.message,
                recoveryItems: failure.recoveryItems,
                wasCancelled: failure.wasCancelled
            )
            presentFileRenameSummary(result)
            return result

        case .success(let receipts):
            issueWarnings.append(contentsOf: await readBackMovedFiles(receipts))

            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: receipts.count,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: nil,
                recoveryItems: []
            )
            presentFileRenameSummary(result)
            return result
        }
    }

    /// Applies verified recovery locations and makes unknown locations fail
    /// closed. Shared by the failure path and its orchestration regression.
    func reconcileRenameRecovery(_ items: [FileRenameRecoveryItem]) async -> [String] {
        guard !items.isEmpty else { return [] }

        // A fresh short reservation covers classification-to-publication; the
        // original move transaction has already ended.
        let urls = items.flatMap { item in
            [item.originalURL, item.intendedURL] + item.finalLocations
        }
        let fileMutationCoordinator = self.fileMutationCoordinator
        try? await fileMutationCoordinator.withExclusiveAccess(to: urls) {
            await self.publishRecoveryBlocks(items)
        }

        let receipts = Self.moveReceipts(from: items)
        // `publishRecoveryBlocks` normally records the unresolved decision while
        // reserved. If the reservation could not be acquired, block the same
        // identities here so publication never leaves a vanished path writable.
        for item in items where item.verifiedLocation == nil && !hasRecoveryDecision(for: item.id) {
            markFileRequiresRefresh(id: item.id)
        }
        return await readBackMovedFiles(receipts)
    }

    /// Publishes placeholders for uniquely verified recovery locations and blocks
    /// every ambiguous one. Caller holds the reserved affected paths.
    func publishRecoveryBlocks(_ items: [FileRenameRecoveryItem]) async {
        let receipts = Self.moveReceipts(from: items)
        if !receipts.isEmpty {
            publishMovePlaceholders(receipts)
        }
        for item in items where item.verifiedLocation == nil {
            recordRecoveryDecision(
                .recoveryLocationUnresolved(
                    expectedIdentity: EntryIdentityKey(fingerprint: committedFile(withID: item.id)?.fileFingerprint)
                ),
                for: item.id
            )
        }
    }

    private static func moveReceipts(from items: [FileRenameRecoveryItem]) -> [FileRenameMoveReceipt] {
        items.compactMap { item in
            guard let verifiedLocation = item.verifiedLocation else { return nil }
            return FileRenameMoveReceipt(
                moveID: FileMoveID(),
                fileID: item.id,
                sourceURL: item.originalURL,
                destinationURL: verifiedLocation.url,
                entryIdentity: verifiedLocation.identity
            )
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

nonisolated func executeFileRenameTransaction(
    _ operations: [FileRenameOperation],
    fileSystem: any FileRenameFileSystem = LocalFileRenameFileSystem()
) -> FileRenameExecutionResult {
    let actionableOperations = operations.filter { $0.sourceURL.path != $0.destinationURL.path }
    guard !actionableOperations.isEmpty else {
        return .success([])
    }

    let preparedOperations = actionableOperations.map { operation in
        PreparedFileRenameOperation(
            operation: operation,
            temporaryURL: uniqueTemporaryRenameURL(for: operation.sourceURL, using: fileSystem)
        )
    }

    let moveIDsByOperationID = Dictionary(
        uniqueKeysWithValues: preparedOperations.map { ($0.operation.id, FileMoveID()) }
    )

    var stagedOperations: [PreparedFileRenameOperation] = []
    stagedOperations.reserveCapacity(preparedOperations.count)

    for prepared in preparedOperations {
        do {
            let currentFingerprint = try fileSystem.fingerprint(at: prepared.operation.sourceURL)
            guard currentFingerprint == prepared.operation.expectedFileFingerprint else {
                throw FileRenameSourceValidationError.changedSincePreview
            }

            try fileSystem.moveItem(at: prepared.operation.sourceURL, to: prepared.temporaryURL)
            stagedOperations.append(prepared)
        } catch {
            let rollbackErrors = rollbackStagedRenameOperations(stagedOperations, using: fileSystem)
            return .failure(
                makeRenameTransactionFailure(
                    primaryMessage: renameFailureMessage(for: prepared.operation.sourceURL, error: error),
                    operations: preparedOperations,
                    rollbackErrors: rollbackErrors,
                    fileSystem: fileSystem
                )
            )
        }
    }

    var finalizedOperations: [PreparedFileRenameOperation] = []
    finalizedOperations.reserveCapacity(preparedOperations.count)
    var completedReceipts: [FileRenameMoveReceipt] = []
    completedReceipts.reserveCapacity(preparedOperations.count)

    for prepared in preparedOperations {
        do {
            try fileSystem.moveItem(at: prepared.temporaryURL, to: prepared.operation.destinationURL)
            let identity = try fileSystem.entryIdentity(at: prepared.operation.destinationURL)
            completedReceipts.append(
                FileRenameMoveReceipt(
                    moveID: moveIDsByOperationID[prepared.operation.id] ?? FileMoveID(),
                    fileID: prepared.operation.id,
                    sourceURL: prepared.operation.sourceURL,
                    destinationURL: prepared.operation.destinationURL,
                    entryIdentity: identity
                )
            )
            finalizedOperations.append(prepared)
        } catch {
            var rollbackErrors = rollbackFinalizedRenameOperations(finalizedOperations, using: fileSystem)
            mergeRollbackErrors(
                rollbackStagedRenameOperations(preparedOperations, using: fileSystem),
                into: &rollbackErrors
            )
            return .failure(
                makeRenameTransactionFailure(
                    primaryMessage: renameFailureMessage(for: prepared.operation.sourceURL, error: error),
                    operations: preparedOperations,
                    rollbackErrors: rollbackErrors,
                    fileSystem: fileSystem
                )
            )
        }
    }

    return .success(completedReceipts)
}

private enum FileRenameSourceValidationError: LocalizedError {
    case changedSincePreview

    var errorDescription: String? {
        switch self {
        case .changedSincePreview:
            return L10n.string("The file has changed since this preview was created. Close and reopen this tool to review the new filename.")
        }
    }
}

nonisolated private func uniqueTemporaryRenameURL(
    for sourceURL: URL,
    using fileSystem: any FileRenameFileSystem
) -> URL {
    let directoryURL = sourceURL.deletingLastPathComponent()
    let extensionText = sourceURL.pathExtension

    while true {
        let candidateBaseName = ".audiomator-rename-\(UUID().uuidString)"
        let candidateURL: URL

        if extensionText.isEmpty {
            candidateURL = directoryURL.appendingPathComponent(candidateBaseName, isDirectory: false)
        } else {
            candidateURL = directoryURL
                .appendingPathComponent(candidateBaseName, isDirectory: false)
                .appendingPathExtension(extensionText)
        }

        if !fileSystem.fileExists(at: candidateURL) {
            return candidateURL
        }
    }
}

nonisolated private func rollbackFinalizedRenameOperations(
    _ operations: [PreparedFileRenameOperation],
    using fileSystem: any FileRenameFileSystem
) -> [UUID: [String]] {
    var errorsByOperationID: [UUID: [String]] = [:]

    for prepared in operations.reversed() {
        guard fileSystem.fileExists(at: prepared.operation.destinationURL) else { continue }
        guard renameRollbackCandidateMatchesExpectedFile(
            prepared.operation.destinationURL,
            operation: prepared.operation,
            fileSystem: fileSystem
        ) else {
            errorsByOperationID[prepared.operation.id, default: []].append(
                rollbackIdentityFailureMessage(at: prepared.operation.destinationURL)
            )
            continue
        }
        do {
            try fileSystem.moveItem(at: prepared.operation.destinationURL, to: prepared.temporaryURL)
        } catch {
            errorsByOperationID[prepared.operation.id, default: []].append(
                rollbackFailureMessage(
                    from: prepared.operation.destinationURL,
                    to: prepared.temporaryURL,
                    error: error
                )
            )
        }
    }

    return errorsByOperationID
}

nonisolated private func rollbackStagedRenameOperations(
    _ operations: [PreparedFileRenameOperation],
    using fileSystem: any FileRenameFileSystem
) -> [UUID: [String]] {
    var errorsByOperationID: [UUID: [String]] = [:]

    for prepared in operations.reversed() {
        guard fileSystem.fileExists(at: prepared.temporaryURL) else { continue }
        guard renameRollbackCandidateMatchesExpectedFile(
            prepared.temporaryURL,
            operation: prepared.operation,
            fileSystem: fileSystem
        ) else {
            errorsByOperationID[prepared.operation.id, default: []].append(
                rollbackIdentityFailureMessage(at: prepared.temporaryURL)
            )
            continue
        }
        do {
            try fileSystem.moveItem(at: prepared.temporaryURL, to: prepared.operation.sourceURL)
        } catch {
            errorsByOperationID[prepared.operation.id, default: []].append(
                rollbackFailureMessage(
                    from: prepared.temporaryURL,
                    to: prepared.operation.sourceURL,
                    error: error
                )
            )
        }
    }

    return errorsByOperationID
}

nonisolated private func mergeRollbackErrors(
    _ incoming: [UUID: [String]],
    into accumulated: inout [UUID: [String]]
) {
    for (operationID, messages) in incoming {
        accumulated[operationID, default: []].append(contentsOf: messages)
    }
}

nonisolated private func makeRenameTransactionFailure(
    primaryMessage: String,
    operations: [PreparedFileRenameOperation],
    rollbackErrors: [UUID: [String]],
    fileSystem: any FileRenameFileSystem
) -> FileRenameTransactionFailure {
    let recoveryItems = operations.compactMap { prepared -> FileRenameRecoveryItem? in
        var finalLocations: [URL] = []
        let candidates = [
            prepared.operation.sourceURL,
            prepared.temporaryURL,
            prepared.operation.destinationURL
        ]

        for candidate in candidates where fileSystem.fileExists(at: candidate) {
            guard renameRollbackCandidateMatchesExpectedFile(
                candidate,
                operation: prepared.operation,
                fileSystem: fileSystem
            ) else {
                continue
            }
            if !finalLocations.contains(candidate) {
                finalLocations.append(candidate)
            }
        }

        let restoredOnlyToOriginal =
            finalLocations.count == 1 && finalLocations[0] == prepared.operation.sourceURL
        guard !restoredOnlyToOriginal else { return nil }

        var verifiedLocation: VerifiedRenameLocation?
        if finalLocations.count == 1,
           let identity = try? fileSystem.entryIdentity(at: finalLocations[0]) {
            verifiedLocation = VerifiedRenameLocation(url: finalLocations[0], identity: identity)
        }

        return FileRenameRecoveryItem(
            id: prepared.operation.id,
            originalURL: prepared.operation.sourceURL,
            intendedURL: prepared.operation.destinationURL,
            finalLocations: finalLocations,
            rollbackErrors: rollbackErrors[prepared.operation.id] ?? [],
            verifiedLocation: verifiedLocation
        )
    }

    guard !recoveryItems.isEmpty else {
        return FileRenameTransactionFailure(message: primaryMessage, recoveryItems: [])
    }

    let recoveryCountLabel = fileCountLabel(recoveryItems.count)
    var lines = [primaryMessage, String(localized: "Check the file locations before continuing (\(recoveryCountLabel)):")]
    for item in recoveryItems {
        if item.finalLocations.isEmpty {
            lines.append(String(localized: "“\(item.originalURL.lastPathComponent)”: current location couldn’t be determined."))
        } else {
            let locations = item.finalLocations.map(\.path).joined(separator: ", ")
            lines.append(String(localized: "“\(item.originalURL.lastPathComponent)” — current location: \(locations)"))
        }
        lines.append(contentsOf: item.rollbackErrors)
    }

    lines.append(String(localized: "Restore each listed file to its original location before attempting another rename."))

    return FileRenameTransactionFailure(
        message: lines.joined(separator: "\n"),
        recoveryItems: recoveryItems
    )
}

nonisolated private func renameRollbackCandidateMatchesExpectedFile(
    _ candidateURL: URL,
    operation: FileRenameOperation,
    fileSystem: any FileRenameFileSystem
) -> Bool {
    guard let current = try? fileSystem.fingerprint(at: candidateURL) else { return false }
    let expected = operation.expectedFileFingerprint

    guard
        let currentFileSystemNumber = current.fileSystemNumber,
        let expectedFileSystemNumber = expected.fileSystemNumber,
        let currentFileNumber = current.fileNumber,
        let expectedFileNumber = expected.fileNumber
    else {
        return false
    }

    return current.fileSize == expected.fileSize &&
        current.contentModificationDate == expected.contentModificationDate &&
        currentFileSystemNumber == expectedFileSystemNumber &&
        currentFileNumber == expectedFileNumber
}

nonisolated private func rollbackIdentityFailureMessage(at url: URL) -> String {
    String(localized: "The identity of “\(url.lastPathComponent)” couldn’t be confirmed, so its name wasn’t restored. Check its current location before renaming it again.")
}

nonisolated private func rollbackFailureMessage(from sourceURL: URL, to destinationURL: URL, error: Error) -> String {
    String(localized: "“\(sourceURL.lastPathComponent)” couldn’t be restored to “\(destinationURL.lastPathComponent)”. Check its current location before renaming it again.\nDetails: ")
        + (error as NSError).localizedDescription
}

nonisolated private func renameFailureMessage(for sourceURL: URL, error: Error) -> String {
    String(localized: "“\(sourceURL.lastPathComponent)” couldn’t be renamed.\nDetails: \((error as NSError).localizedDescription)")
}

private func fileRenameIssueWarnings(from rows: [FileRenamePreviewRow]) -> [String] {
    rows.compactMap { row in
        guard row.status.isError else { return nil }
        return "\(row.currentName): \(row.status.title)"
    }
}
