import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private enum MetadataFilenameToolMode: String, CaseIterable, Identifiable {
    case metadataToFilename
    case filenameToMetadata

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .metadataToFilename:
            return "Metadata to Filename"
        case .filenameToMetadata:
            return "Filename to Metadata"
        }
    }

    var actionTitle: String {
        switch self {
        case .metadataToFilename:
            return "Rename"
        case .filenameToMetadata:
            return "Write Metadata"
        }
    }

    var templateTitle: String {
        switch self {
        case .metadataToFilename:
            return "Rename template"
        case .filenameToMetadata:
            return "Match template"
        }
    }

    var placeholderText: String {
        switch self {
        case .metadataToFilename:
            return "Type separators, then insert fields where you want them."
        case .filenameToMetadata:
            return "Type the literal filename separators, then insert the fields you want to extract."
        }
    }

    var emptyPreviewDescription: String {
        switch self {
        case .metadataToFilename:
            return "Add text or metadata fields to preview the new filenames."
        case .filenameToMetadata:
            return "Add literal filename parts and metadata fields to preview the extracted tags."
        }
    }

    var headerDescription: String {
        switch self {
        case .metadataToFilename:
            return "Type the punctuation and spacing you want. Click or drag a field to insert it at the caret."
        case .filenameToMetadata:
            return "Type the fixed filename separators you expect. Click or drag a field to mark where metadata should be extracted."
        }
    }
}

@MainActor
final class MetadataFilenameToolStore: ObservableObject {
    @Published private(set) var targetFileIDs: [AudioFile.ID] = []

    func present(targetFileIDs: [AudioFile.ID]) {
        self.targetFileIDs = targetFileIDs
    }
}

struct MetadataFilenameWindowView: View {
    static let windowID = "metadata-filename-tool"

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var store: MetadataFilenameToolStore

    @Environment(\.dismiss) private var dismiss

    @State private var mode: MetadataFilenameToolMode = .metadataToFilename
    @State private var metadataToFilenameTemplate: String = ""
    @State private var filenameToMetadataTemplate: String = ""
    @State private var replaceUnderscoresWithSpaces: Bool = false
    @State private var isApplying: Bool = false
    @State private var pendingFieldInsertion: FileRenameTemplateEditorInsertion?

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18

    private var targetFiles: [AudioFile] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        return store.targetFileIDs.compactMap { filesByID[$0] }
    }

    private var renamePlan: FileRenamePlan {
        makeFileRenamePlan(template: metadataToFilenameTemplate, targetFiles: targetFiles)
    }

    private var filenameMetadataPlan: FilenameMetadataPlan {
        makeFilenameMetadataPlan(
            template: filenameToMetadataTemplate,
            targetFiles: targetFiles,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces
        )
    }

    private var activeTemplate: String {
        switch mode {
        case .metadataToFilename:
            return metadataToFilenameTemplate
        case .filenameToMetadata:
            return filenameToMetadataTemplate
        }
    }

    private var activeTemplateBinding: Binding<String> {
        Binding(
            get: { activeTemplate },
            set: { newValue in
                switch mode {
                case .metadataToFilename:
                    metadataToFilenameTemplate = newValue
                case .filenameToMetadata:
                    filenameToMetadataTemplate = newValue
                }
            }
        )
    }

    private var activeFieldPalette: [FileRenameMetadataField] {
        switch mode {
        case .metadataToFilename:
            return FileRenameMetadataField.metadataToFilenameFields
        case .filenameToMetadata:
            return FileRenameMetadataField.filenameToMetadataFields
        }
    }

    private var selectionSummaryText: String {
        targetFiles.count == 1
            ? "1 selected file"
            : "\(targetFiles.count) selected files"
    }

    private var previewStatusMessage: String {
        switch mode {
        case .metadataToFilename:
            return metadataToFilenameStatusMessage
        case .filenameToMetadata:
            return filenameToMetadataStatusMessage
        }
    }

    private var previewStatusSymbolName: String {
        if previewHasIssues {
            return "exclamationmark.triangle.fill"
        }

        if previewReadyCount > 0 {
            return "checkmark.circle.fill"
        }

        return "info.circle.fill"
    }

    private var previewStatusTint: Color {
        if previewHasIssues {
            return .orange
        }

        if previewReadyCount > 0 {
            return .green
        }

        return .secondary
    }

    private var previewHasIssues: Bool {
        switch mode {
        case .metadataToFilename:
            return renamePlan.hasIssues
        case .filenameToMetadata:
            return filenameMetadataPlan.hasIssues
        }
    }

    private var previewReadyCount: Int {
        switch mode {
        case .metadataToFilename:
            return renamePlan.readyCount
        case .filenameToMetadata:
            return filenameMetadataPlan.readyCount
        }
    }

    private var canApply: Bool {
        switch mode {
        case .metadataToFilename:
            return renamePlan.canApply && !isApplying
        case .filenameToMetadata:
            return filenameMetadataPlan.canApply && !isApplying
        }
    }

    private var metadataToFilenameStatusMessage: String {
        if targetFiles.isEmpty {
            return "Select files in the center list first."
        }

        if metadataToFilenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a template or drag metadata chips into the field."
        }

        if renamePlan.hasIssues {
            return "\(renamePlan.readyCount) file(s) are ready. \(renameIssueSummaryText)"
        }

        if renamePlan.readyCount == 0 {
            return "The filenames already match."
        }

        return "\(renamePlan.readyCount) file(s) will be renamed. File extensions stay the same."
    }

    private var renameIssueSummaryText: String {
        let issueRows = renamePlan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return "No conflicts." }

        var countsByTitle: [String: Int] = [:]
        for row in issueRows {
            countsByTitle[row.status.title, default: 0] += 1
        }

        let summary = countsByTitle
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.lowercased())" }
            .joined(separator: ", ")

        return "\(issueRows.count) file(s) will be skipped: \(summary)."
    }

    private var filenameToMetadataStatusMessage: String {
        if targetFiles.isEmpty {
            return "Select files in the center list first."
        }

        if filenameToMetadataTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a matching template or drag metadata chips into the field."
        }

        if let validationMessage = filenameMetadataPlan.validationMessage {
            return validationMessage
        }

        if filenameMetadataPlan.hasIssues {
            return "\(filenameMetadataPlan.readyCount) file(s) are ready. \(filenameMetadataIssueSummaryText)"
        }

        if filenameMetadataPlan.readyCount > 0 {
            return "\(filenameMetadataPlan.readyCount) file(s) will have metadata updated from their filenames."
        }

        if filenameMetadataPlan.noWritableCount > 0 {
            return "The template matched, but it did not extract any writable metadata fields."
        }

        return "The extracted metadata already matches the current tags."
    }

    private var filenameMetadataIssueSummaryText: String {
        let issueRows = filenameMetadataPlan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return "No filename matching issues." }

        var countsByTitle: [String: Int] = [:]
        for row in issueRows {
            countsByTitle[row.status.title, default: 0] += 1
        }

        let summary = countsByTitle
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.lowercased())" }
            .joined(separator: ", ")

        return "\(issueRows.count) file(s) could not be parsed: \(summary)."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        setupSection
                        previewSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
                .scrollBounceBehavior(.basedOnSize)

                footer
            }
            .padding(20)
            .frame(minWidth: 820, idealWidth: 860, maxWidth: 980, minHeight: 620, idealHeight: 720)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Filename & Metadata")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        ForEach(MetadataFilenameToolMode.allCases) { mode in
                            Text(mode.pickerTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isApplying)
                }
            }
        }
        .onChange(of: mode) { _, _ in
            pendingFieldInsertion = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode.pickerTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(mode.headerDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(selectionSummaryText, systemImage: "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text(setupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if mode == .filenameToMetadata {
                    Toggle("Replace underscores with spaces in extracted values", isOn: $replaceUnderscoresWithSpaces)
                        .toggleStyle(.checkbox)
                        .disabled(isApplying)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(activeFieldPalette, id: \.self) { field in
                        metadataChip(for: field)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.templateTitle)
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        if activeTemplate.isEmpty {
                            Text(mode.placeholderText)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                        }

                        FileRenameTemplateEditor(
                            template: activeTemplateBinding,
                            pendingInsertion: $pendingFieldInsertion,
                            isEnabled: !isApplying
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .disabled(isApplying)
                    }
                    .frame(minHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var setupDescription: String {
        switch mode {
        case .metadataToFilename:
            return "AudioMator keeps each file's current extension. The template changes only the filename."
        case .filenameToMetadata:
            return "AudioMator matches the current filename without its extension. The template must match the whole filename, and only extracted metadata fields will be written."
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Label(previewStatusMessage, systemImage: previewStatusSymbolName)
                    .font(.subheadline)
                    .foregroundStyle(previewStatusTint)

                if activeTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Add a Template",
                        systemImage: "text.cursor",
                        description: Text(mode.emptyPreviewDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    switch mode {
                    case .metadataToFilename:
                        MetadataFilenameRenamePreviewList(rows: renamePlan.rows)
                            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                    case .filenameToMetadata:
                        FilenameMetadataPreviewList(plan: filenameMetadataPlan)
                            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Button(mode.actionTitle) {
                applyCurrentMode()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
    }

    private func metadataChip(for field: FileRenameMetadataField) -> some View {
        Button {
            insertFieldToken(field)
        } label: {
            Text(field.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help("Click to insert at the caret, or drag into the template")
        .onDrag {
            NSItemProvider(object: field.token as NSString)
        }
    }

    private func insertFieldToken(_ field: FileRenameMetadataField) {
        guard !isApplying else { return }
        pendingFieldInsertion = FileRenameTemplateEditorInsertion(field: field)
    }

    private func applyCurrentMode() {
        switch mode {
        case .metadataToFilename:
            applyRename()
        case .filenameToMetadata:
            applyFilenameMetadata()
        }
    }

    private func applyRename() {
        let plan = renamePlan
        guard plan.canApply else { return }

        isApplying = true

        Task { @MainActor in
            let result = await viewModel.renameFiles(using: plan)
            isApplying = false

            if result.didSucceed && renamePlan.issueCount == 0 {
                dismiss()
            }
        }
    }

    private func applyFilenameMetadata() {
        let plan = filenameMetadataPlan
        guard plan.canApply else { return }

        isApplying = true

        Task { @MainActor in
            await viewModel.applyFilenameMetadataPlan(plan.writeEntries)
            isApplying = false

            if !plan.hasIssues {
                dismiss()
            }
        }
    }
}

private struct MetadataFilenameRenamePreviewList: View {
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

private struct FilenameMetadataPreviewList: View {
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

private struct FileRenameTemplateEditorInsertion: Equatable {
    let id = UUID()
    let field: FileRenameMetadataField
}

private struct FileRenameTemplateEditor: NSViewRepresentable {
    @Binding var template: String
    @Binding var pendingInsertion: FileRenameTemplateEditorInsertion?
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.font = Self.editorFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.applyTemplate(template, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.isEditable != isEnabled {
            textView.isEditable = isEnabled
        }

        context.coordinator.refreshLiteralStyling(in: textView)

        let serializedTemplate = context.coordinator.serialize(textStorage: textView.textStorage)
        if serializedTemplate != template {
            context.coordinator.applyTemplate(template, to: textView)
        }

        if context.coordinator.lastAppliedInsertionID != pendingInsertion?.id,
           let insertion = pendingInsertion {
            context.coordinator.insert(field: insertion.field, into: textView)
            context.coordinator.lastAppliedInsertionID = insertion.id
        }
    }

    private static let editorFont = NSFont.monospacedSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FileRenameTemplateEditor
        weak var textView: NSTextView?
        var isApplyingProgrammaticUpdate = false
        var selectedRange = NSRange(location: 0, length: 0)
        var lastAppliedInsertionID: UUID?

        init(parent: FileRenameTemplateEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView, notification.object as AnyObject? === textView else { return }

            refreshLiteralStyling(in: textView)

            let serializedTemplate = serialize(textStorage: textView.textStorage)
            guard serializedTemplate != parent.template else { return }

            parent.template = serializedTemplate
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, notification.object as AnyObject? === textView else { return }
            selectedRange = textView.selectedRange()
            textView.typingAttributes = literalAttributes()
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingProgrammaticUpdate else { return true }
            guard let replacementString, !replacementString.isEmpty else { return true }

            let document = FileRenameTemplateDocument(rawValue: replacementString)
            guard document.containsFieldSegments else { return true }

            replaceCharacters(in: affectedCharRange, with: document, in: textView)
            return false
        }

        func applyTemplate(_ template: String, to textView: NSTextView) {
            let document = FileRenameTemplateDocument(rawValue: template)
            let attributed = attributedString(for: document)
            let clampedRange = clampSelectedRange(selectedRange, textLength: attributed.length)

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(clampedRange)
            selectedRange = clampedRange
            refreshLiteralStyling(in: textView)
            isApplyingProgrammaticUpdate = false
        }

        func insert(field: FileRenameMetadataField, into textView: NSTextView) {
            let insertionRange = clampSelectedRange(
                selectedRange,
                textLength: textView.textStorage?.length ?? 0
            )
            replaceCharacters(
                in: insertionRange,
                with: FileRenameTemplateDocument(rawValue: field.token),
                in: textView,
                clearPendingInsertion: true
            )
            textView.window?.makeFirstResponder(textView)
        }

        func serialize(textStorage: NSTextStorage?) -> String {
            guard let textStorage else { return "" }

            var serialized = ""
            var index = 0

            while index < textStorage.length {
                if let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? FileRenameFieldAttachment {
                    serialized += attachment.field.token
                    index += 1
                    continue
                }

                var effectiveRange = NSRange(location: 0, length: 0)
                _ = textStorage.attribute(.attachment, at: index, effectiveRange: &effectiveRange)
                let literalRange = effectiveRange.length > 0
                    ? effectiveRange
                    : NSRange(location: index, length: 1)
                serialized += textStorage.attributedSubstring(from: literalRange).string
                index = literalRange.location + literalRange.length
            }

            return serialized
        }

        private func replaceCharacters(
            in affectedCharRange: NSRange,
            with document: FileRenameTemplateDocument,
            in textView: NSTextView,
            clearPendingInsertion: Bool = false
        ) {
            let replacement = attributedString(for: document)
            let clampedRange = clampSelectedRange(
                affectedCharRange,
                textLength: textView.textStorage?.length ?? 0
            )

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: clampedRange, with: replacement)
            let insertionLocation = clampedRange.location + replacement.length
            let newSelection = NSRange(location: insertionLocation, length: 0)
            textView.setSelectedRange(newSelection)
            selectedRange = newSelection
            refreshLiteralStyling(in: textView)
            textView.didChangeText()
            isApplyingProgrammaticUpdate = false

            scheduleTemplateStateSync(
                from: textView,
                clearPendingInsertion: clearPendingInsertion
            )
        }

        private func attributedString(for document: FileRenameTemplateDocument) -> NSAttributedString {
            let attributed = NSMutableAttributedString()

            for segment in document.segments {
                switch segment {
                case .literal(let literal):
                    attributed.append(NSAttributedString(string: literal, attributes: literalAttributes()))
                case .field(let field):
                    attributed.append(NSAttributedString(attachment: FileRenameFieldAttachment(field: field)))
                }
            }

            if attributed.length == 0 {
                attributed.append(NSAttributedString(string: "", attributes: literalAttributes()))
            }

            return attributed
        }

        private func literalAttributes() -> [NSAttributedString.Key: Any] {
            [
                .font: FileRenameTemplateEditor.editorFont,
                .foregroundColor: parent.isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
        }

        func refreshLiteralStyling(in textView: NSTextView) {
            let literalColor = parent.isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            textView.textColor = literalColor
            textView.insertionPointColor = literalColor
            textView.typingAttributes = literalAttributes()

            guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }

            let attributes = literalAttributes()
            textStorage.beginEditing()

            var index = 0
            while index < textStorage.length {
                var effectiveRange = NSRange(location: 0, length: 0)
                let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: &effectiveRange)
                let range = effectiveRange.length > 0
                    ? effectiveRange
                    : NSRange(location: index, length: 1)

                if !(attachment is FileRenameFieldAttachment) {
                    textStorage.addAttributes(attributes, range: range)
                }

                index = range.location + range.length
            }

            textStorage.endEditing()
        }

        private func scheduleTemplateStateSync(
            from textView: NSTextView,
            clearPendingInsertion: Bool
        ) {
            let serializedTemplate = serialize(textStorage: textView.textStorage)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if self.parent.template != serializedTemplate {
                    self.parent.template = serializedTemplate
                }

                if clearPendingInsertion {
                    self.parent.pendingInsertion = nil
                }
            }
        }

        private func clampSelectedRange(_ range: NSRange, textLength: Int) -> NSRange {
            let location = min(max(range.location, 0), textLength)
            let length = min(max(range.length, 0), textLength - location)
            return NSRange(location: location, length: length)
        }
    }
}

private final class FileRenameFieldAttachment: NSTextAttachment {
    let field: FileRenameMetadataField

    init(field: FileRenameMetadataField) {
        self.field = field
        super.init(data: nil, ofType: nil)
        attachmentCell = NSTextAttachmentCell(imageCell: Self.makeChipImage(title: field.displayName))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private static func makeChipImage(title: String) -> NSImage {
        let chipFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 4
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: chipFont,
            .foregroundColor: NSColor.controlAccentColor
        ]
        let textSize = title.size(withAttributes: textAttributes)
        let size = NSSize(
            width: ceil(textSize.width) + (horizontalPadding * 2),
            height: ceil(textSize.height) + (verticalPadding * 2)
        )

        let image = NSImage(size: size)
        image.lockFocus()

        let drawingFrame = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 1.5)
        let backgroundPath = NSBezierPath(
            roundedRect: drawingFrame,
            xRadius: drawingFrame.height / 2,
            yRadius: drawingFrame.height / 2
        )

        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        backgroundPath.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.24).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let textRect = NSRect(
            x: round((size.width - textSize.width) / 2),
            y: round((size.height - textSize.height) / 2),
            width: textSize.width,
            height: textSize.height
        )
        title.draw(in: textRect, withAttributes: textAttributes)

        image.unlockFocus()
        return image
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
