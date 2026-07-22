import Foundation

struct FileRenameResult {
    let totalTargets: Int
    let renamed: Int
    let unchanged: Int
    let skippedIssues: Int
    let warnings: [String]
    let failureMessage: String?
    let recoveryItems: [FileRenameRecoveryItem]

    static let empty = FileRenameResult(
        totalTargets: 0,
        renamed: 0,
        unchanged: 0,
        skippedIssues: 0,
        warnings: [],
        failureMessage: nil,
        recoveryItems: []
    )

    var didSucceed: Bool {
        failureMessage == nil
    }
}

private struct PreparedFileRenameOperation: Sendable {
    let operation: FileRenameOperation
    let temporaryURL: URL
}

struct FileRenameRecoveryItem: Equatable, Sendable {
    let originalURL: URL
    let intendedURL: URL
    let finalLocations: [URL]
    let rollbackErrors: [String]

    var finalURL: URL? {
        finalLocations.count == 1 ? finalLocations[0] : nil
    }

    var rollbackError: String? {
        rollbackErrors.isEmpty ? nil : rollbackErrors.joined(separator: "\n")
    }
}

struct FileRenameTransactionFailure: Sendable {
    let message: String
    let recoveryItems: [FileRenameRecoveryItem]
}

enum FileRenameExecutionResult: Sendable {
    case success([FileRenameOperation])
    case failure(FileRenameTransactionFailure)
}

protocol FileRenameFileSystem: Sendable {
    nonisolated func fileExists(at url: URL) -> Bool
    nonisolated func fingerprint(at url: URL) throws -> AudioFileFingerprint
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

    nonisolated func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
}

extension AudioViewModel {
    func renameFiles(using plan: FileRenamePlan) async -> FileRenameResult {
        let totalTargets = plan.totalTargets
        let unchangedCount = plan.unchangedCount
        let skippedIssues = plan.issueCount
        let issueWarnings = fileRenameIssueWarnings(from: plan.rows)
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
                failureMessage: String(localized: "Save or discard the pending inspector edits before renaming files."),
                recoveryItems: []
            )
        }

        let scopedURLs = operations.map(\.sourceURL)
        if let accessFailure = ensureRenameDirectoryAccess(for: scopedURLs) {
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
                    await Task.detached(priority: .userInitiated) {
                        executeFileRenameTransaction(operations)
                    }.value
                }
            }
        } catch {
            execution = .failure(
                FileRenameTransactionFailure(
                    message: "File renaming was cancelled before it started.",
                    recoveryItems: []
                )
            )
        }

        switch execution {
        case .failure(let failure):
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

        case .success(let completedOperations):
            registerMovedFiles(
                completedOperations.map { (id: $0.id, oldURL: $0.sourceURL, newURL: $0.destinationURL) }
            )
            applyMovedFiles(
                completedOperations.map { (id: $0.id, newURL: $0.destinationURL) }
            )

            if !completedOperations.isEmpty {
                updateEditForSelection()
            }

            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: completedOperations.count,
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

    private func presentFileRenameSummary(_ result: FileRenameResult) {
        if let failureMessage = result.failureMessage {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Rename Failed",
                subtitle: failureMessage
            )
            return
        }

        let renamedLabel = fileCountLabel(result.renamed)
        let unchangedLabel = result.unchanged == 0 ? nil : "\(result.unchanged) unchanged"
        let skippedLabel = result.skippedIssues == 0 ? nil : "\(result.skippedIssues) skipped"

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
            lines.append("...and \(result.warnings.count - 2) more")
        }

        presentMetadataWriteHUD(
            style: .warning,
            title: "Renamed with Issues",
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

    for prepared in preparedOperations {
        do {
            try fileSystem.moveItem(at: prepared.temporaryURL, to: prepared.operation.destinationURL)
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

    return .success(actionableOperations)
}

private enum FileRenameSourceValidationError: LocalizedError {
    case changedSincePreview

    var errorDescription: String? {
        switch self {
        case .changedSincePreview:
            return L10n.string("The file changed after the preview was shown. Refresh the preview and try again.")
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
            if !finalLocations.contains(candidate) {
                finalLocations.append(candidate)
            }
        }

        let restoredOnlyToOriginal =
            finalLocations.count == 1 && finalLocations[0] == prepared.operation.sourceURL
        guard !restoredOnlyToOriginal else { return nil }

        return FileRenameRecoveryItem(
            originalURL: prepared.operation.sourceURL,
            intendedURL: prepared.operation.destinationURL,
            finalLocations: finalLocations,
            rollbackErrors: rollbackErrors[prepared.operation.id] ?? []
        )
    }

    guard !recoveryItems.isEmpty else {
        return FileRenameTransactionFailure(message: primaryMessage, recoveryItems: [])
    }

    let recoveryCountLabel = recoveryItems.count == 1
        ? "1 file"
        : "\(recoveryItems.count) files"
    var lines = [primaryMessage, "Recovery required for \(recoveryCountLabel):"]
    for item in recoveryItems {
        let locations = item.finalLocations.isEmpty
            ? "location unknown"
            : item.finalLocations.map(\.path).joined(separator: ", ")
        lines.append("\(item.originalURL.lastPathComponent) is at \(locations)")
        lines.append(contentsOf: item.rollbackErrors)
    }

    lines.append("Move each listed file back to its original path before retrying.")

    return FileRenameTransactionFailure(
        message: lines.joined(separator: "\n"),
        recoveryItems: recoveryItems
    )
}

nonisolated private func rollbackFailureMessage(from sourceURL: URL, to destinationURL: URL, error: Error) -> String {
    "Rollback failed (\(sourceURL.lastPathComponent) → \(destinationURL.lastPathComponent)): "
        + (error as NSError).localizedDescription
}

nonisolated private func renameFailureMessage(for sourceURL: URL, error: Error) -> String {
    "\(sourceURL.lastPathComponent): \((error as NSError).localizedDescription)"
}

private func fileRenameIssueWarnings(from rows: [FileRenamePreviewRow]) -> [String] {
    rows.compactMap { row in
        guard row.status.isError else { return nil }
        return "\(row.currentName): \(row.status.title)"
    }
}
