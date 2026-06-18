import SwiftUI

#if os(macOS)
struct MetadataTextExportPreviewList: View {
    let plan: MetadataTextExportPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            ContentUnavailableView(
                "Template Needs More Structure",
                systemImage: "text.cursor",
                description: Text(validationMessage)
            )
        } else if plan.rows.isEmpty {
            ContentUnavailableView(
                "No Files Selected",
                systemImage: "music.note.list",
                description: Text("Select one or more files to preview text export.")
            )
        } else {
            MetadataSectionCard(title: "Text Lines", symbolName: "text.alignleft") {
                ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 14) {
                        Text(row.fileName)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 180, alignment: .leading)
                            .lineLimit(2)

                        Text(row.output.isEmpty ? "Empty" : row.output)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(row.output.isEmpty ? Color.secondary : Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)

                    if index < plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }
}

struct MetadataCSVExportPreviewList: View {
    let plan: MetadataCSVExportPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            ContentUnavailableView(
                "Column Template Needs Work",
                systemImage: "tablecells",
                description: Text(validationMessage)
            )
        } else if plan.rows.isEmpty {
            ContentUnavailableView(
                "No Files Selected",
                systemImage: "music.note.list",
                description: Text("Select one or more files to preview CSV export.")
            )
        } else {
            MetadataSectionCard(title: "CSV Rows", symbolName: "tablecells") {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(plan.columns) { field in
                                csvCell(field.displayName, isHeader: true)
                            }
                        }

                        MetadataCardDivider()

                        ForEach(Array(plan.rows.prefix(24).enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                    csvCell(value.isEmpty ? "Empty" : value, isHeader: false)
                                }
                            }

                            if rowIndex < min(plan.rows.count, 24) - 1 {
                                MetadataCardDivider()
                            }
                        }
                    }
                }
                .audiomatorScrollEdgeEffect(.soft, for: .horizontal)
            }
        }
    }

    private func csvCell(_ value: String, isHeader: Bool) -> some View {
        Text(value)
            .font(isHeader ? .system(size: 11, weight: .semibold) : .system(size: 12, design: .monospaced))
            .foregroundStyle(value == "Empty" ? Color.secondary : Color.primary)
            .lineLimit(2)
            .frame(width: 150, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

struct MetadataExchangeImportPreviewList: View {
    let plan: MetadataExchangeImportPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            ContentUnavailableView(
                "Template Needs More Structure",
                systemImage: "exclamationmark.triangle",
                description: Text(validationMessage)
            )
        } else if plan.rows.isEmpty {
            ContentUnavailableView(
                "Add Source Records",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose or paste text to preview imported metadata.")
            )
        } else {
            MetadataSectionCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                    MetadataExchangeImportRowView(row: row)

                    if index < plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }
}

private struct MetadataExchangeImportRowView: View {
    let row: MetadataExchangeImportPreviewRow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(row.externalRecord.isEmpty ? "No external record" : row.externalRecord)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Label(row.status.title, systemImage: row.status.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(row.status.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(row.status.tint.opacity(0.12)))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if let issueMessage = row.issueMessage {
                Text(issueMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(row.status.isIssue ? row.status.tint : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }

            if !row.changes.isEmpty {
                Divider()
                    .padding(.leading, 18)

                MetadataExchangeImportHeader()

                ForEach(Array(row.changes.enumerated()), id: \.element.id) { index, change in
                    MetadataExchangeImportChangeRow(change: change)

                    if index < row.changes.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }
}

private struct MetadataExchangeImportHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Field")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Current")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Imported")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct MetadataExchangeImportChangeRow: View {
    let change: MetadataExchangeFieldChange

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(change.field.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            metadataValue(change.currentValue)

            Image(systemName: change.willWrite ? "pencil.circle.fill" : "equal.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(change.willWrite ? Color.green : Color.secondary)
                .frame(width: 18)
                .padding(.top, 1)

            metadataValue(change.importedValue, highlight: change.willWrite)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func metadataValue(_ value: String, highlight: Bool = false) -> some View {
        Text(value.isEmpty ? "Empty" : value)
            .font(.system(size: 12))
            .foregroundStyle(value.isEmpty ? Color.secondary : (highlight ? Color.green : Color.primary))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MetadataExchangePreviewStatus {
    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "equal.circle.fill"
        case .noMatch, .ambiguousMatch, .parseError, .missingExternalRecord:
            return "exclamationmark.triangle.fill"
        case .extraExternalRecord, .noWritableFields:
            return "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged, .extraExternalRecord, .noWritableFields:
            return .secondary
        case .noMatch, .ambiguousMatch, .parseError, .missingExternalRecord:
            return .orange
        }
    }
}
#endif
