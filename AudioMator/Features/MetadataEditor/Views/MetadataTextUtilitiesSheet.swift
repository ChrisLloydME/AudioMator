import SwiftUI
import AppKit


enum MetadataTextUtilityOperation: String, CaseIterable, Identifiable {
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
            return L10n.string("Trim Whitespace")
        case .uppercase:
            return L10n.string("Uppercase")
        case .lowercase:
            return L10n.string("Lowercase")
        case .titleCase:
            return L10n.string("Capitalize Each Word")
        case .capitalizeFirstLetter:
            return L10n.string("Capitalize Value Start")
        case .sentenceCase:
            return L10n.string("Sentence Case")
        case .addPrefix:
            return L10n.string("Add Prefix")
        case .addSuffix:
            return L10n.string("Add Suffix")
        case .findAndReplace:
            return L10n.string("Find & Replace")
        }
    }

    var detailText: String {
        switch self {
        case .trimWhitespaceAndNewlines:
            return L10n.string("Remove whitespace and newlines from the beginning and end of each selected value.")
        case .uppercase:
            return L10n.string("Convert all letters in each selected value to uppercase.")
        case .lowercase:
            return L10n.string("Convert all letters in each selected value to lowercase.")
        case .titleCase:
            return L10n.string("Capitalize the first letter of every word. This does not apply special title-style rules for articles or prepositions.")
        case .capitalizeFirstLetter:
            return L10n.string("Capitalize only the first letter found in the value and leave the rest unchanged.")
        case .sentenceCase:
            return L10n.string("Lowercase the value, then capitalize only the first letter found in it.")
        case .addPrefix:
            return L10n.string("Insert text before each selected value.")
        case .addSuffix:
            return L10n.string("Insert text after each selected value.")
        case .findAndReplace:
            return L10n.string("Replace matching text inside each selected value.")
        }
    }
}

struct MetadataTextUtilitiesSheet: View {
    @ObservedObject var store: MetadataEditorStore

    let fieldKeys: Set<String>
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var operation: MetadataTextUtilityOperation
    @State private var insertionText: String = ""
    @State private var findText: String
    @State private var replacementText: String
    @State private var matchesCase: Bool = false
    @State private var matchesWholeText: Bool = false
    @State private var staleMessage: String?

    init(
        store: MetadataEditorStore,
        fieldKeys: Set<String>,
        initialOperation: MetadataTextUtilityOperation = .trimWhitespaceAndNewlines,
        initialFindText: String = "",
        initialReplacementText: String = "",
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.fieldKeys = fieldKeys
        self.onClose = onClose
        _operation = State(initialValue: initialOperation)
        _findText = State(initialValue: initialFindText)
        _replacementText = State(initialValue: initialReplacementText)
    }

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

    private func makePreview() -> MetadataTextUtilityPreview? {
        guard let pipeline else { return nil }
        return store.makeTextUtilityPreview(pipeline: pipeline, fieldKeys: fieldKeys)
    }

    private func previewSummary(_ preview: MetadataTextUtilityPreview?) -> String {
        guard let preview else {
            return L10n.string("Preview unavailable")
        }

        return "\(preview.changedRows.count) changes across \(preview.changedFileCount) files and \(preview.changedFieldCount) fields"
    }

    private var selectedFieldsText: String {
        sortedFieldKeys.joined(separator: ", ")
    }

    var body: some View {
        let preview = makePreview()

        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            selectedFields
            previewSection(preview)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer(preview)
        }
        .padding(MetadataTextUtilityPreviewLayout.outerPadding)
        .frame(
            width: MetadataTextUtilityPreviewLayout.sheetWidth,
            height: MetadataTextUtilityPreviewLayout.sheetHeight
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Text Transform")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Apply a text transform to selected metadata values. Fields missing from a file are skipped.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected Fields")
                .font(.headline)

            Text(selectedFieldsText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(selectedFieldsText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var operationFields: some View {
        switch operation {
        case .addPrefix, .addSuffix:
            VStack(alignment: .leading, spacing: 6) {
                Text(operation == .addPrefix ? "Prefix" : "Suffix")
                    .font(.headline)

                TextField(operation == .addPrefix ? "Text to insert before value" : "Text to insert after value", text: $insertionText)
                    .textFieldStyle(.roundedBorder)
            }

        case .findAndReplace:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Find")
                            .font(.headline)
                        TextField("Text to find", text: $findText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Replace With")
                            .font(.headline)
                        TextField("Replacement text", text: $replacementText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 16) {
                    Toggle("Match case", isOn: $matchesCase)
                    Toggle("Match whole value", isOn: $matchesWholeText)
                    Spacer()
                }
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func previewSection(_ preview: MetadataTextUtilityPreview?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Text(previewSummary(preview))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let preview, !preview.rows.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(preview.rows) { row in
                                MetadataTextUtilityPreviewTableRow(row: row)
                            }
                        } header: {
                            HStack(spacing: MetadataTextUtilityPreviewLayout.columnSpacing) {
                                previewHeaderCell("File")
                                    .frame(width: MetadataTextUtilityPreviewLayout.labelWidth, alignment: .leading)
                                previewHeaderCell("Field")
                                    .frame(width: MetadataTextUtilityPreviewLayout.labelWidth, alignment: .leading)
                                previewHeaderCell("Current values")
                                    .frame(width: MetadataTextUtilityPreviewLayout.valueWidth, alignment: .leading)
                                previewHeaderCell("Preview values")
                                    .frame(width: MetadataTextUtilityPreviewLayout.valueWidth, alignment: .leading)
                            }
                            .padding(.horizontal, MetadataTextUtilityPreviewLayout.horizontalPadding)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                }
                .defaultScrollAnchor(.topLeading, for: .alignment)
                .frame(minHeight: 120, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                )
            } else {
                Text(pipeline == nil
                    ? String(localized: "Enter text above to preview changes.")
                    : (preview == nil
                        ? String(localized: "The selected fields cannot be previewed in the current editor session.")
                        : String(localized: "No metadata values are available for the selected fields.")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func previewHeaderCell(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func footer(_ preview: MetadataTextUtilityPreview?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let staleMessage {
                Text(staleMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
                onClose()
            }

            Button("Apply") {
                guard let preview else {
                    dismiss()
                    onClose()
                    return
                }

                switch store.applyTextUtilityPreview(preview) {
                case .applied, .noChanges:
                    dismiss()
                    onClose()
                case .stale:
                    staleMessage = L10n.string("The values changed. Review the updated preview and apply again.")
                case .unavailable:
                    dismiss()
                    onClose()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(preview.map { $0.changedRows.isEmpty } ?? true)
        }
    }
}

enum MetadataTextUtilityPreviewLayout {
    static let sheetWidth: CGFloat = 820
    static let sheetHeight: CGFloat = 540
    static let outerPadding: CGFloat = 20
    static let horizontalPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 10
    static let labelWidth: CGFloat = 120
    static let valueWidth: CGFloat = 243

    static var availableContentWidth: CGFloat {
        sheetWidth - (outerPadding * 2)
    }

    static var totalRowWidth: CGFloat {
        (horizontalPadding * 2) + (columnSpacing * 3) + (labelWidth * 2) + (valueWidth * 2)
    }
}

private struct MetadataTextUtilityPreviewTableRow: View {
    let row: MetadataTextUtilityPreviewRow

    var body: some View {
        HStack(alignment: .top, spacing: MetadataTextUtilityPreviewLayout.columnSpacing) {
            Text(row.fileName)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(row.fileName)
                .frame(width: MetadataTextUtilityPreviewLayout.labelWidth, alignment: .leading)
            Text(row.fieldKey)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(row.fieldKey)
                .frame(width: MetadataTextUtilityPreviewLayout.labelWidth, alignment: .leading)
            MetadataRawValueListText(values: row.beforeValues)
                .frame(width: MetadataTextUtilityPreviewLayout.valueWidth, alignment: .leading)
            MetadataRawValueListText(values: row.afterValues)
                .frame(width: MetadataTextUtilityPreviewLayout.valueWidth, alignment: .leading)
        }
        .padding(.horizontal, MetadataTextUtilityPreviewLayout.horizontalPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.changed ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                .frame(height: 1)
        }
    }
}

/// Ordered value list used by the preview table. Element boundaries are visible
/// separators and an embedded line break inside one element is shown as `⏎`.
private struct MetadataRawValueListText: View {
    let values: [String]

    var body: some View {
        if values.isEmpty {
            Text(MetadataRawValueDisplay.noValuesPlaceholder)
                .font(.system(size: 11, design: .monospaced))
                .italic()
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)

                        Text(value.isEmpty
                            ? MetadataRawValueDisplay.emptyValuePlaceholder
                            : MetadataRawValueDisplay.elementText(value))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(value.isEmpty ? .secondary : .primary)
                            .lineLimit(6)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if index < values.count - 1 {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.4))
                            .frame(height: 1)
                            .padding(.leading, 21)
                    }
                }
            }
        }
    }
}
