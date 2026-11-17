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

    var pastTenseVerb: String {
        switch self {
        case .write:
            return "saved"
        case .clear:
            return "cleared"
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
                String(localized: "Cancelled before this file was processed. This file wasn't changed.")
            ])
        })
    }

    var hudStyle: MetadataWriteHUDStyle {
        if failureIssues.isEmpty && warningIssues.isEmpty && skippedIssues.isEmpty {
            return .success
        }

        if failureIssues.isEmpty {
            return .warning
        }

        return succeeded > 0 ? .warning : .failure
    }

    var hudTitle: String {
        if failureIssues.isEmpty && warningIssues.isEmpty && skippedIssues.isEmpty {
            return operation.successTitle
        }

        if failureIssues.isEmpty {
            return operation.warningTitle
        }

        return succeeded > 0 ? operation.partialFailureTitle : operation.fullFailureTitle
    }

    var hudSubtitle: String {
        var result = [summaryLine]
        if !failureIssues.isEmpty {
            result.append(failureIssues.count == 1
                ? String(localized: "1 file couldn’t be updated.")
                : String(localized: "\(failureIssues.count) files couldn’t be updated."))
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
            lines.append(String(localized: "More file details are available in Settings → Save Logs."))
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

typealias BatchMetadataWriteSummary = BatchMetadataOperationSummary
