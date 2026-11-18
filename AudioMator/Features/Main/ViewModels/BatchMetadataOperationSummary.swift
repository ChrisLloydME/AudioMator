import Foundation

struct BatchMetadataWriteIssue: Equatable {
    let fileName: String
    let messages: [String]
}

enum BatchMetadataOperationKind: String, Codable, Equatable {
    case write
    case clear

    var successTitle: String {
        switch self {
        case .write:
            return L10n.string("Saved to Disk")
        case .clear:
            return L10n.string("Metadata Cleared")
        }
    }

    var warningTitle: String {
        switch self {
        case .write:
            return L10n.string("Changes Saved with Warnings")
        case .clear:
            return L10n.string("Metadata Cleared with Warnings")
        }
    }

    var partialFailureTitle: String {
        switch self {
        case .write:
            return String(localized: "Changes Saved to Some Files")
        case .clear:
            return String(localized: "Metadata Cleared from Some Files")
        }
    }

    var fullFailureTitle: String {
        switch self {
        case .write:
            return String(localized: "Changes Couldn’t Be Saved")
        case .clear:
            return String(localized: "Metadata Couldn’t Be Cleared")
        }
    }

    var noFilesText: String {
        switch self {
        case .write:
            return L10n.string("No changes were saved to any files.")
        case .clear:
            return L10n.string("Metadata wasn't cleared from any files.")
        }
    }
}

struct BatchMetadataOperationSummary: Equatable {
    let totalTargets: Int
    let operation: BatchMetadataOperationKind
    var succeeded: Int = 0
    var cancelledCount: Int {
        failureIssues.filter { issue in
            issue.messages.count == 1 && MetadataCancellation.isMessage(issue.messages[0])
        }.count
    }
    var warningIssues: [BatchMetadataWriteIssue] = []
    var failureIssues: [BatchMetadataWriteIssue] = []
    var skippedIssues: [BatchMetadataWriteIssue] = []
    var allSuccessfulFilesRefreshed = true

    init(totalTargets: Int, operation: BatchMetadataOperationKind = .write) {
        self.totalTargets = totalTargets
        self.operation = operation
    }

    mutating func recordCancelledFiles(_ fileNames: [String]) {
        failureIssues.append(contentsOf: fileNames.map {
            BatchMetadataWriteIssue(fileName: $0, messages: [
                MetadataCancellation.beforeFileMessage
            ])
        })
    }

    var hudStyle: MetadataWriteHUDStyle {
        if cancelledCount > 0, failureIssues.count == cancelledCount { return .warning }
        if failureIssues.isEmpty && warningIssues.isEmpty && skippedIssues.isEmpty {
            return .success
        }

        if failureIssues.isEmpty {
            return .warning
        }

        return succeeded > 0 ? .warning : .failure
    }

    var hudTitle: String {
        if succeeded == 0, failureIssues.isEmpty, !skippedIssues.isEmpty {
            return String(localized: "No Files Changed")
        }
        if cancelledCount > 0, failureIssues.count == cancelledCount {
            return String(localized: "Operation Cancelled")
        }
        if failureIssues.isEmpty && warningIssues.isEmpty && skippedIssues.isEmpty {
            return operation.successTitle
        }

        if failureIssues.isEmpty {
            return operation.warningTitle
        }

        return succeeded > 0 ? operation.partialFailureTitle : operation.fullFailureTitle
    }

    var hudSubtitle: String {
        var result = succeeded > 0 || failureIssues.count == cancelledCount ? [summaryLine] : []
        let failed = failureIssues.count - cancelledCount
        if failed > 0 {
            if operation == .clear {
                result.append(failed == 1
                    ? String(localized: "Metadata couldn’t be cleared from 1 file.")
                    : String(localized: "Metadata couldn’t be cleared from \(failed) files."))
            } else {
                result.append(failed == 1
                    ? String(localized: "Changes couldn’t be saved to 1 file.")
                    : String(localized: "Changes couldn’t be saved to \(failed) files."))
            }
        }
        if cancelledCount > 0 {
            result.append(String(localized: "Files not processed because the operation was cancelled: \(cancelledCount)."))
        }
        var lines = [result.joined(separator: " ")]
        if !warningIssues.isEmpty {
            lines.append(warningIssues.count == 1
                ? String(localized: "1 file has warnings.")
                : String(localized: "\(warningIssues.count) files have warnings."))
        }
        if !skippedIssues.isEmpty {
            lines.append(skippedIssues.count == 1
                ? String(localized: "1 file was skipped.")
                : String(localized: "\(skippedIssues.count) files were skipped."))
        }
        let issues = failureIssues + skippedIssues + warningIssues
        for issue in issues.prefix(2) {
            lines.append("")
            lines.append(issue.fileName)
            lines.append(contentsOf: issue.messages)
        }
        if issues.count > 2 {
            lines.append("")
            lines.append(String(localized: "Additional files with issues: \(issues.count - 2)."))
        }
        return lines.joined(separator: "\n")
    }

    private var summaryLine: String {
        guard succeeded > 0 else { return operation.noFilesText }
        if totalTargets == 1 {
            return operation == .write
                ? String(localized: "Changes were saved to this file.")
                : String(localized: "Metadata was cleared from this file.")
        }
        return operation == .write
            ? String(localized: "Changes were saved to \(succeeded) of \(totalTargets) files.")
            : String(localized: "Metadata was cleared from \(succeeded) of \(totalTargets) files.")
    }

}

/// Compatibility with the existing string-result pipeline. Only messages made by
/// our own cancellation branches are classified here, never arbitrary substrings.
enum MetadataCancellation {
    static var message: String {
        String(localized: "The operation was cancelled before it began. No changes were saved.")
    }

    static var beforeFileMessage: String {
        String(localized: "Cancelled before this file was processed. This file wasn't changed.")
    }

    static func isMessage(_ message: String) -> Bool {
        message == self.message || message == beforeFileMessage
    }
}
