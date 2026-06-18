import SwiftUI

#if os(macOS)
struct MetadataFilenameRenamePreviewList: View {
    let rows: [FileRenamePreviewRow]

    var body: some View {
        MetadataSectionCard(title: "Filename Comparison", symbolName: "arrow.left.arrow.right") {
            MetadataFilenameRenameComparisonHeader()

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                MetadataFilenameRenameComparisonRowView(row: row)

                if index < rows.count - 1 {
                    MetadataCardDivider()
                }
            }
        }
    }
}

private struct MetadataFilenameRenameComparisonHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Status")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Current Name")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Preview")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct MetadataFilenameRenameComparisonRowView: View {
    let row: FileRenamePreviewRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.status.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.status.tint)
                    .multilineTextAlignment(.leading)

                if row.status != .ready {
                    Text(row.status.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: 118, alignment: .leading)

            MetadataFilenameRenameComparisonValue(
                row.currentName,
                foregroundColor: .primary
            )

            Image(systemName: row.status.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.status.tint)
                .help(row.status.message)
                .frame(width: 18)
                .padding(.top, 1)

            MetadataFilenameRenameComparisonValue(
                row.previewName,
                foregroundColor: row.status.isError ? .orange : .primary
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct MetadataFilenameRenameComparisonValue: View {
    let value: String
    let foregroundColor: Color

    init(_ value: String, foregroundColor: Color) {
        self.value = value
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Text(value.isEmpty ? "—" : value)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(value.isEmpty ? Color(nsColor: .tertiaryLabelColor) : foregroundColor)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FilenameMetadataPreviewList: View {
    let plan: FilenameMetadataPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            MetadataSectionCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                ContentUnavailableView(
                    "Template Needs More Structure",
                    systemImage: "exclamationmark.triangle",
                    description: Text(validationMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        } else if plan.rows.isEmpty {
            MetadataSectionCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                ContentUnavailableView(
                    "No Files Selected",
                    systemImage: "music.note.list",
                    description: Text("Select one or more files to preview metadata extraction from filenames.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        } else {
            MetadataSectionCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                    FilenameMetadataComparisonGroupView(row: row)

                    if index < plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }
}

private struct FilenameMetadataComparisonGroupView: View {
    let row: FilenameMetadataPreviewRow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.currentName)
                        .font(.system(size: 13, weight: .semibold))

                    Text("Filename stem: \(row.sourceBaseName)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                FilenameMetadataStatusBadge(status: row.status)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, row.changes.isEmpty ? 8 : 12)

            if let issueMessage = row.issueMessage {
                Text(issueMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(row.status.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, row.changes.isEmpty ? 14 : 12)
            }

            if !row.changes.isEmpty {
                Divider()
                    .padding(.leading, 18)

                FilenameMetadataComparisonHeader()

                ForEach(Array(row.changes.enumerated()), id: \.element.id) { index, change in
                    FilenameMetadataComparisonRowView(change: change)

                    if index < row.changes.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            } else {
                FilenameMetadataComparisonEmptyStateRow(message: row.status.message)
            }
        }
    }
}

private struct FilenameMetadataStatusBadge: View {
    let status: FilenameMetadataPreviewStatus

    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(status.tint.opacity(0.12))
            )
    }
}

private struct FilenameMetadataComparisonHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Field")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Metadata")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Filename")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct FilenameMetadataComparisonRowView: View {
    let change: FilenameMetadataFieldChange

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(change.field.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            FilenameMetadataComparisonValue(
                value: change.currentValue,
                monospaced: change.field.usesMonospacedComparisonValue,
                foregroundColor: .primary
            )

            Image(systemName: change.status.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(change.status.tint)
                .help(change.willWrite ? "This value will be written to metadata." : "This field already matches.")
                .frame(width: 18)
                .padding(.top, 1)

            FilenameMetadataComparisonValue(
                value: change.extractedValue,
                monospaced: change.field.usesMonospacedComparisonValue,
                foregroundColor: change.willWrite ? change.status.tint : .primary
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct FilenameMetadataComparisonValue: View {
    let value: String
    let monospaced: Bool
    let foregroundColor: Color

    var body: some View {
        Text(value.isEmpty ? "—" : value)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
            .foregroundStyle(value.isEmpty ? Color(nsColor: .tertiaryLabelColor) : foregroundColor)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FilenameMetadataComparisonEmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }
}

private extension FileRenamePreviewStatus {
    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .emptyName, .duplicateTarget, .existingFile:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged:
            return .secondary
        case .emptyName, .duplicateTarget, .existingFile:
            return .orange
        }
    }
}

private extension FilenameMetadataPreviewStatus {
    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .noMatch:
            return "exclamationmark.triangle.fill"
        case .noWritableFields:
            return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged, .noWritableFields:
            return .secondary
        case .noMatch:
            return .orange
        }
    }
}

private extension FilenameMetadataFieldChangeStatus {
    var symbolName: String {
        switch self {
        case .same:
            return "checkmark.circle.fill"
        case .different:
            return "arrow.left.arrow.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .same:
            return .green
        case .different:
            return .orange
        }
    }
}

private extension FileRenameMetadataField {
    var usesMonospacedComparisonValue: Bool {
        switch self {
        case .year, .trackNumberText, .discNumberText, .releaseDate:
            return true
        case .title, .artist, .album, .albumArtist, .composer, .genre,
                .comment, .publisher, .copyright, .credits, .ignore:
            return false
        }
    }
}
#endif
