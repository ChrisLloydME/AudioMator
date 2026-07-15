import Foundation

enum MetadataFilenameStatusPresentation {
    static func renameMessage(
        targetCount: Int,
        template: String,
        plan: FileRenamePlan
    ) -> String {
        if targetCount == 0 {
            return L10n.string("Select files in the center list first.")
        }

        if template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Enter a template or drag metadata chips into the field.")
        }

        if let validationMessage = plan.validationMessage {
            return validationMessage
        }

        if plan.hasIssues {
            return "\(plan.readyCount) file(s) are ready. \(renameIssueSummary(for: plan))"
        }

        if plan.readyCount == 0 {
            return L10n.string("The filenames already match.")
        }

        return "\(plan.readyCount) file(s) will be renamed. File extensions stay the same."
    }

    static func filenameMetadataMessage(
        targetCount: Int,
        template: String,
        plan: FilenameMetadataPlan
    ) -> String {
        if targetCount == 0 {
            return L10n.string("Select files in the center list first.")
        }

        if template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Enter a matching template or drag metadata chips into the field.")
        }

        if let validationMessage = plan.validationMessage {
            return validationMessage
        }

        if plan.hasIssues {
            return "\(plan.readyCount) file(s) are ready. \(filenameMetadataIssueSummary(for: plan))"
        }

        if plan.readyCount > 0 {
            return "\(plan.readyCount) file(s) will have metadata updated from their filenames."
        }

        if plan.noWritableCount > 0 {
            return L10n.string("The template matched, but it did not extract any writable metadata fields.")
        }

        return "The extracted metadata already matches the current tags."
    }

    static func textExportMessage(
        targetCount: Int,
        plan: MetadataTextExportPlan
    ) -> String {
        if targetCount == 0 {
            return L10n.string("Select files in the center list first.")
        }

        if let validationMessage = plan.validationMessage {
            return validationMessage
        }

        return "\(plan.rows.count) line(s) will be exported."
    }

    static func csvExportMessage(
        targetCount: Int,
        plan: MetadataCSVExportPlan
    ) -> String {
        if targetCount == 0 {
            return L10n.string("Select files in the center list first.")
        }

        if let validationMessage = plan.validationMessage {
            return validationMessage
        }

        return "\(plan.rows.count) row(s), \(plan.columns.count) column(s) will be exported."
    }

    static func importMessage(
        targetCount: Int,
        plan: MetadataExchangeImportPlan
    ) -> String {
        if targetCount == 0 {
            return L10n.string("Select files in the center list first.")
        }

        if let validationMessage = plan.validationMessage {
            return validationMessage
        }

        if plan.readyCount > 0, plan.issueCount > 0 {
            return "\(plan.readyCount) file(s) are ready. \(plan.issueCount) issue(s) need review."
        }

        if plan.readyCount > 0 {
            return "\(plan.readyCount) file(s) will have metadata updated."
        }

        if plan.issueCount > 0 {
            return "\(plan.issueCount) issue(s) need review before writing."
        }

        return L10n.string("No metadata changes to write.")
    }

    private static func renameIssueSummary(for plan: FileRenamePlan) -> String {
        let issueRows = plan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return L10n.string("No conflicts.") }

        let summary = issueSummary(
            titles: issueRows.map(\.status.title)
        )
        return "\(issueRows.count) file(s) will be skipped: \(summary)."
    }

    private static func filenameMetadataIssueSummary(for plan: FilenameMetadataPlan) -> String {
        let issueRows = plan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return L10n.string("No filename matching issues.") }

        let summary = issueSummary(
            titles: issueRows.map(\.status.title)
        )
        return "\(issueRows.count) file(s) could not be parsed: \(summary)."
    }

    private static func issueSummary(titles: [String]) -> String {
        var countsByTitle: [String: Int] = [:]
        for title in titles {
            countsByTitle[title, default: 0] += 1
        }

        return countsByTitle
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.lowercased())" }
            .joined(separator: ", ")
    }
}
