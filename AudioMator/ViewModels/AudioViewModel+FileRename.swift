import Foundation

struct FileRenameResult {
    let totalTargets: Int
    let renamed: Int
    let unchanged: Int
    let skippedIssues: Int
    let warnings: [String]
    let failureMessage: String?

    static let empty = FileRenameResult(
        totalTargets: 0,
        renamed: 0,
        unchanged: 0,
        skippedIssues: 0,
        warnings: [],
        failureMessage: nil
    )

    var didSucceed: Bool {
        failureMessage == nil
    }
}

private struct PreparedFileRenameOperation: Sendable {
    let operation: FileRenameOperation
    let temporaryURL: URL
}

private enum FileRenameExecutionResult: Sendable {
    case success([FileRenameOperation])
    case failure(String)
}

extension AudioViewModel {
    func renameFiles(using plan: FileRenamePlan) async -> FileRenameResult {
        let totalTargets = plan.totalTargets
        let unchangedCount = plan.unchangedCount
        let skippedIssues = plan.issueCount
        let issueWarnings = fileRenameIssueWarnings(from: plan.rows)
        let operations = plan.operations

        for warning in issueWarnings {
            print("[AudioMator] Rename issue: \(warning)")
        }

        guard !operations.isEmpty else {
            return FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: nil
            )
        }

        let scopedURLs = operations.map(\.sourceURL)
        if let accessFailure = ensureRenameDirectoryAccess(for: scopedURLs) {
            print("[AudioMator] Rename failed: \(accessFailure)")
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: [],
                failureMessage: accessFailure
            )
            presentFileRenameSummary(result)
            return result
        }

        let execution = withSecurityScopedAccessForQuickImportURLs(scopedURLs) {
            executeFileRenameTransaction(operations)
        }

        switch execution {
        case .failure(let reason):
            print("[AudioMator] Rename failed: \(reason)")
            let result = FileRenameResult(
                totalTargets: totalTargets,
                renamed: 0,
                unchanged: unchangedCount,
                skippedIssues: skippedIssues,
                warnings: issueWarnings,
                failureMessage: reason
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
                failureMessage: nil
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

private func executeFileRenameTransaction(_ operations: [FileRenameOperation]) -> FileRenameExecutionResult {
    let actionableOperations = operations.filter { $0.sourceURL.path != $0.destinationURL.path }
    guard !actionableOperations.isEmpty else {
        return .success([])
    }

    let fileManager = FileManager.default
    let preparedOperations = actionableOperations.map { operation in
        PreparedFileRenameOperation(
            operation: operation,
            temporaryURL: uniqueTemporaryRenameURL(for: operation.sourceURL)
        )
    }

    var stagedOperations: [PreparedFileRenameOperation] = []
    stagedOperations.reserveCapacity(preparedOperations.count)

    for prepared in preparedOperations {
        do {
            try fileManager.moveItem(at: prepared.operation.sourceURL, to: prepared.temporaryURL)
            stagedOperations.append(prepared)
        } catch {
            rollbackStagedRenameOperations(stagedOperations, using: fileManager)
            return .failure(renameFailureMessage(for: prepared.operation.sourceURL, error: error))
        }
    }

    var finalizedOperations: [PreparedFileRenameOperation] = []
    finalizedOperations.reserveCapacity(preparedOperations.count)

    for prepared in preparedOperations {
        do {
            try fileManager.moveItem(at: prepared.temporaryURL, to: prepared.operation.destinationURL)
            finalizedOperations.append(prepared)
        } catch {
            rollbackFinalizedRenameOperations(finalizedOperations, using: fileManager)
            rollbackStagedRenameOperations(preparedOperations, using: fileManager)
            return .failure(renameFailureMessage(for: prepared.operation.sourceURL, error: error))
        }
    }

    return .success(actionableOperations)
}

private func uniqueTemporaryRenameURL(for sourceURL: URL) -> URL {
    let directoryURL = sourceURL.deletingLastPathComponent()
    let extensionText = sourceURL.pathExtension
    let fileManager = FileManager.default

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

        if !fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }
}

private func rollbackFinalizedRenameOperations(
    _ operations: [PreparedFileRenameOperation],
    using fileManager: FileManager
) {
    for prepared in operations.reversed() {
        guard fileManager.fileExists(atPath: prepared.operation.destinationURL.path) else { continue }
        try? fileManager.moveItem(at: prepared.operation.destinationURL, to: prepared.temporaryURL)
    }
}

private func rollbackStagedRenameOperations(
    _ operations: [PreparedFileRenameOperation],
    using fileManager: FileManager
) {
    for prepared in operations.reversed() {
        guard fileManager.fileExists(atPath: prepared.temporaryURL.path) else { continue }
        try? fileManager.moveItem(at: prepared.temporaryURL, to: prepared.operation.sourceURL)
    }
}

private func renameFailureMessage(for sourceURL: URL, error: Error) -> String {
    "\(sourceURL.lastPathComponent): \((error as NSError).localizedDescription)"
}

private func fileRenameIssueWarnings(from rows: [FileRenamePreviewRow]) -> [String] {
    rows.compactMap { row in
        guard row.status.isError else { return nil }
        return "\(row.currentName): \(row.status.title)"
    }
}
