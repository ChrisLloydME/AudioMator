import Foundation

struct BatchMetadataWriteIssue: Equatable {
    let fileName: String
    let messages: [String]
}

enum BatchMetadataOperationKind: Equatable {
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
            return L10n.string("Saved with Issues")
        case .clear:
            return L10n.string("Cleared with Issues")
        }
    }

    var partialFailureTitle: String {
        switch self {
        case .write:
            return "Partially Saved"
        case .clear:
            return "Partially Cleared"
        }
    }

    var fullFailureTitle: String {
        switch self {
        case .write:
            return "Save Failed"
        case .clear:
            return "Clear Failed"
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
            return L10n.string("No files were saved")
        case .clear:
            return L10n.string("No files were cleared")
        }
    }
}

struct BatchMetadataOperationSummary: Equatable {
    let totalTargets: Int
    let operation: BatchMetadataOperationKind
    var succeeded: Int = 0
    var warningIssues: [BatchMetadataWriteIssue] = []
    var failureIssues: [BatchMetadataWriteIssue] = []
    var allSuccessfulFilesRefreshed = true

    init(totalTargets: Int, operation: BatchMetadataOperationKind = .write) {
        self.totalTargets = totalTargets
        self.operation = operation
    }

    var hudStyle: MetadataWriteHUDStyle {
        if failureIssues.isEmpty && warningIssues.isEmpty {
            return .success
        }

        if failureIssues.isEmpty {
            return .warning
        }

        return succeeded > 0 ? .warning : .failure
    }

    var hudTitle: String {
        if failureIssues.isEmpty && warningIssues.isEmpty {
            return operation.successTitle
        }

        if failureIssues.isEmpty {
            return operation.warningTitle
        }

        return succeeded > 0 ? operation.partialFailureTitle : operation.fullFailureTitle
    }

    var hudSubtitle: String {
        if failureIssues.isEmpty && warningIssues.isEmpty {
            return fileCountLabel(succeeded)
        }

        var lines: [String] = [summaryLine]

        if !warningIssues.isEmpty {
            lines.append("\(warningIssues.count) file(s) \(operation.pastTenseVerb) with issues")
        }

        if !failureIssues.isEmpty {
            lines.append("\(failureIssues.count) file(s) failed")
        }

        let detailSource = failureIssues.isEmpty ? warningIssues : failureIssues
        for issue in detailSource.prefix(2) {
            let detail = issue.messages.joined(separator: " ")
            lines.append("\(issue.fileName): \(detail)")
        }

        if detailSource.count > 2 {
            lines.append("...and \(detailSource.count - 2) more")
        }

        return lines.joined(separator: "\n")
    }

    private var summaryLine: String {
        switch succeeded {
        case totalTargets:
            return "\(totalTargets) of \(totalTargets) files \(operation.pastTenseVerb)"
        case 0:
            return operation.noFilesText
        default:
            return "\(succeeded) of \(totalTargets) files \(operation.pastTenseVerb)"
        }
    }
}

typealias BatchMetadataWriteSummary = BatchMetadataOperationSummary
