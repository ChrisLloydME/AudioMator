import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

struct MetadataTextUtilityPreviewRow: Identifiable, Hashable {
    let targetID: AudioFile.ID
    let fileName: String
    let fieldKey: String
    let currentValue: String
    let previewValue: String

    var id: String {
        "\(targetID.uuidString):\(fieldKey)"
    }

    var changed: Bool {
        currentValue != previewValue
    }
}

private enum MetadataTextUtilityOperation: String, CaseIterable, Identifiable {
    case trimWhitespaceAndNewlines
    case uppercase
    case lowercase
    case titleCase
    case capitalizeFirstLetter
    case sentenceCase
    case addPrefix
    case addSuffix
    case findAndReplace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trimWhitespaceAndNewlines:
            return "Trim Whitespace"
        case .uppercase:
            return "Uppercase"
        case .lowercase:
            return "Lowercase"
        case .titleCase:
            return "Capitalize Each Word"
        case .capitalizeFirstLetter:
            return "Capitalize Value Start"
        case .sentenceCase:
            return "Sentence Case"
        case .addPrefix:
            return "Add Prefix"
        case .addSuffix:
            return "Add Suffix"
        case .findAndReplace:
            return "Find & Replace"
        }
    }

    var detailText: String {
        switch self {
        case .trimWhitespaceAndNewlines:
            return "Remove whitespace and newlines from the beginning and end of each selected value."
        case .uppercase:
            return "Convert all letters in each selected value to uppercase."
        case .lowercase:
            return "Convert all letters in each selected value to lowercase."
        case .titleCase:
            return "Capitalize the first letter of every word. This does not apply special title-style rules for articles or prepositions."
        case .capitalizeFirstLetter:
            return "Capitalize only the first letter found in the value and leave the rest unchanged."
        case .sentenceCase:
            return "Lowercase the value, then capitalize only the first letter found in it."
        case .addPrefix:
            return "Insert text before each selected value."
        case .addSuffix:
            return "Insert text after each selected value."
        case .findAndReplace:
            return "Replace matching text inside each selected value."
        }
    }
}

struct MetadataTextUtilitiesSheet: View {
    @ObservedObject var store: MetadataEditorStore

    let fieldKeys: Set<String>
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var operation: MetadataTextUtilityOperation = .trimWhitespaceAndNewlines
    @State private var insertionText: String = ""
    @State private var findText: String = ""
    @State private var replacementText: String = ""
    @State private var matchesCase: Bool = false
    @State private var matchesWholeText: Bool = false

    private var sortedFieldKeys: [String] {
        fieldKeys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var pipeline: TextEditPipeline? {
        switch operation {
        case .trimWhitespaceAndNewlines:
            return TextEditPipeline(steps: [.trimEdges(.whitespacesAndNewlines)])
        case .uppercase:
            return TextEditPipeline(steps: [.transformCase(.uppercase)])
        case .lowercase:
            return TextEditPipeline(steps: [.transformCase(.lowercase)])
        case .titleCase:
            return TextEditPipeline(steps: [.transformCase(.titleCase)])
        case .capitalizeFirstLetter:
            return TextEditPipeline(steps: [.transformCase(.capitalizeFirstLetter)])
        case .sentenceCase:
            return TextEditPipeline(steps: [.transformCase(.sentenceCase)])
        case .addPrefix:
            guard !insertionText.isEmpty else { return nil }
            return TextEditPipeline(steps: [.insertText(insertionText, position: .prefix)])
        case .addSuffix:
            guard !insertionText.isEmpty else { return nil }
            return TextEditPipeline(steps: [.insertText(insertionText, position: .suffix)])
        case .findAndReplace:
            guard !findText.isEmpty else { return nil }
            return TextEditPipeline(steps: [
                .replaceText(
                    TextFindReplacement(
                        findText: findText,
                        replacementText: replacementText,
                        options: TextFindReplacementOptions(
                            matchesCase: matchesCase,
                            matchesWholeText: matchesWholeText
                        )
                    )
                )
            ])
        }
    }

    private var previewRows: [MetadataTextUtilityPreviewRow] {
        guard let pipeline else { return [] }
        return store.previewTextUtility(pipeline: pipeline, fieldKeys: fieldKeys)
    }

    private var changedPreviewRows: [MetadataTextUtilityPreviewRow] {
        previewRows.filter(\.changed)
    }

    private var canApply: Bool {
        pipeline != nil && !changedPreviewRows.isEmpty
    }

    private var previewSummary: String {
        let fileCount = Set(previewRows.map(\.targetID)).count
        let fieldCount = sortedFieldKeys.count
        let changeCount = changedPreviewRows.count

        return "\(changeCount) changes across \(fileCount) files and \(fieldCount) fields"
    }

    private var selectedFieldsText: String {
        sortedFieldKeys.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            selectedFields
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(20)
        .frame(width: 900, height: 640)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text Transform")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Apply a text transform to selected metadata values. Fields missing from a file are skipped.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Operation")
                    .font(.headline)

                Picker("Operation", selection: $operation) {
                    ForEach(MetadataTextUtilityOperation.allCases) { operation in
                        Text(operation.title).tag(operation)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(operation.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            operationFields
        }
    }

    private var selectedFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Fields")
                .font(.headline)

            Text(selectedFieldsText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var operationFields: some View {
        switch operation {
        case .addPrefix, .addSuffix:
            VStack(alignment: .leading, spacing: 8) {
                Text(operation == .addPrefix ? "Prefix" : "Suffix")
                    .font(.headline)

                TextField(operation == .addPrefix ? "Text to insert before value" : "Text to insert after value", text: $insertionText)
                    .textFieldStyle(.roundedBorder)
            }

        case .findAndReplace:
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find")
                        .font(.headline)
                    TextField("Text to find", text: $findText)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Replace With")
                        .font(.headline)
                    TextField("Replacement text", text: $replacementText)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Match case", isOn: $matchesCase)
                Toggle("Match whole value", isOn: $matchesWholeText)
            }

        default:
            EmptyView()
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Text(previewSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView([.vertical, .horizontal]) {
                Grid(horizontalSpacing: 10, verticalSpacing: 0) {
                    GridRow {
                        previewHeaderCell("File")
                            .gridColumnAlignment(.leading)
                            .frame(width: 150, alignment: .leading)
                        previewHeaderCell("Field")
                            .gridColumnAlignment(.leading)
                            .frame(width: 150, alignment: .leading)
                        previewHeaderCell("Current")
                            .gridColumnAlignment(.leading)
                            .frame(width: 230, alignment: .leading)
                        previewHeaderCell("Preview")
                            .gridColumnAlignment(.leading)
                            .frame(width: 230, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))

                    ForEach(previewRows) { row in
                        MetadataTextUtilityPreviewGridRow(row: row)
                    }
                }
            }
            .defaultScrollAnchor(.topLeading, for: .alignment)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
        }
    }

    private func previewHeaderCell(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
                onClose()
            }

            Button("Apply") {
                if let pipeline {
                    store.applyTextUtility(pipeline: pipeline, fieldKeys: fieldKeys)
                }
                dismiss()
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
    }
}

private struct MetadataTextUtilityPreviewGridRow: View {
    let row: MetadataTextUtilityPreviewRow

    var body: some View {
        GridRow {
            previewCell(row.fileName, font: .body, color: .primary)
                .frame(width: 150, alignment: .leading)
            previewCell(row.fieldKey, font: .system(size: 12, weight: .medium, design: .monospaced), color: .primary)
                .frame(width: 150, alignment: .leading)
            previewCell(row.currentValue, font: .system(size: 12, design: .monospaced), color: .secondary)
                .frame(width: 230, alignment: .leading)
            previewCell(row.previewValue, font: .system(size: 12, design: .monospaced), color: row.changed ? .primary : .secondary)
                .frame(width: 230, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(row.changed ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)
        }
    }

    private func previewCell(_ text: String, font: Font, color: Color) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(3)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
