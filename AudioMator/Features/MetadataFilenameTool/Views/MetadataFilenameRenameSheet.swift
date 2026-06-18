import SwiftUI
#if os(macOS)
import AppKit
#endif
import Combine
import UniformTypeIdentifiers

#if os(macOS)

private enum MetadataFilenameToolMode: String, CaseIterable, Identifiable {
    case metadataToFilename
    case filenameToMetadata

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Metadata to Filename")
        case .filenameToMetadata:
            return L10n.string("Filename to Metadata")
        }
    }

    var actionTitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Rename")
        case .filenameToMetadata:
            return L10n.string("Write Metadata")
        }
    }

    var templateTitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Rename template")
        case .filenameToMetadata:
            return L10n.string("Match template")
        }
    }

    var placeholderText: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Type separators, then insert fields where you want them.")
        case .filenameToMetadata:
            return L10n.string("Type the literal filename separators, then insert the fields you want to extract.")
        }
    }

    var emptyPreviewDescription: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Add text or metadata fields to preview the new filenames.")
        case .filenameToMetadata:
            return L10n.string("Add literal filename parts and metadata fields to preview the extracted tags.")
        }
    }

    var headerDescription: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Type the punctuation and spacing you want. Click or drag a field to insert it at the caret.")
        case .filenameToMetadata:
            return L10n.string("Type the fixed filename separators you expect. Click or drag a field to mark where metadata should be extracted.")
        }
    }
}

@MainActor
final class MetadataFilenameToolStore: ObservableObject {
    @Published private(set) var targetFileIDs: [AudioFile.ID] = []
    @Published private(set) var presentationID = UUID()

    func present(targetFileIDs: [AudioFile.ID]) {
        self.targetFileIDs = targetFileIDs
        self.presentationID = UUID()
    }
}

struct MetadataFilenameWindowView: View {
    static let windowID = "metadata-filename-tool"

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var store: MetadataFilenameToolStore

    @Environment(\.dismiss) private var dismiss

    @State private var selectedConverterMode: MetadataConverterMode?
    @State private var mode: MetadataFilenameToolMode = .metadataToFilename
    @State private var metadataToFilenameTemplate: String = ""
    @State private var filenameToMetadataTemplate: String = ""
    @State private var metadataToTextTemplate: String = "{{trackNumber}}. {{artist}} - {{title}}"
    @State private var textToMetadataTemplate: String = "{{fileName}} | {{title}} | {{artist}} | {{album}}"
    @State private var metadataToCSVTemplate: String = "{{fileName}},{{trackNumber}},{{title}},{{artist}},{{album}}"
    @State private var csvToMetadataTemplate: String = "{{fileName}},{{trackNumber}},{{title}},{{artist}},{{album}}"
    @State private var textImportSource: String = ""
    @State private var csvImportSource: String = ""
    @State private var selectedTextImportURL: URL?
    @State private var selectedCSVImportURL: URL?
    @State private var externalFileError: String?
    @State private var includeCSVHeaderRow: Bool = true
    @State private var firstCSVRowIsHeader: Bool = true
    @State private var clearBlankImportedValues: Bool = false
    @State private var replaceUnderscoresWithSpaces: Bool = false
    @State private var isApplying: Bool = false
    @State private var pendingFieldInsertion: FileRenameTemplateEditorInsertion?
    @State private var pendingExchangeFieldInsertion: MetadataExchangeTemplateEditorInsertion?

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18
    private let controlRadius: CGFloat = 12
    private let contentInset: CGFloat = 20

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

    private var metadataTextExportPlan: MetadataTextExportPlan {
        MetadataExchangePlanner.makeTextExportPlan(
            template: metadataToTextTemplate,
            targetFiles: targetFiles
        )
    }

    private var textMetadataImportPlan: MetadataExchangeImportPlan {
        MetadataExchangePlanner.makeTextImportPlan(
            template: textToMetadataTemplate,
            sourceText: textImportSource,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues
        )
    }

    private var metadataCSVExportPlan: MetadataCSVExportPlan {
        MetadataExchangePlanner.makeCSVExportPlan(
            template: metadataToCSVTemplate,
            includeHeaderRow: includeCSVHeaderRow,
            targetFiles: targetFiles
        )
    }

    private var csvMetadataImportPlan: MetadataExchangeImportPlan {
        MetadataExchangePlanner.makeCSVImportPlan(
            template: csvToMetadataTemplate,
            sourceText: csvImportSource,
            firstRowIsHeader: firstCSVRowIsHeader,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues
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
        guard let selectedConverterMode else {
            return false
        }

        switch selectedConverterMode {
        case .metadataToFilename:
            return renamePlan.canApply && !isApplying
        case .filenameToMetadata:
            return filenameMetadataPlan.canApply && !isApplying
        case .metadataToText:
            return metadataTextExportPlan.canExport && !isApplying
        case .textToMetadata:
            return textMetadataImportPlan.canApply && !isApplying
        case .metadataToCSV:
            return metadataCSVExportPlan.canExport && !isApplying
        case .csvToMetadata:
            return csvMetadataImportPlan.canApply && !isApplying
        }
    }

    private var metadataToFilenameStatusMessage: String {
        if targetFiles.isEmpty {
            return L10n.string("Select files in the center list first.")
        }

        if metadataToFilenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Enter a template or drag metadata chips into the field.")
        }

        if renamePlan.hasIssues {
            return "\(renamePlan.readyCount) file(s) are ready. \(renameIssueSummaryText)"
        }

        if renamePlan.readyCount == 0 {
            return L10n.string("The filenames already match.")
        }

        return "\(renamePlan.readyCount) file(s) will be renamed. File extensions stay the same."
    }

    private var renameIssueSummaryText: String {
        let issueRows = renamePlan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return L10n.string("No conflicts.") }

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
            return L10n.string("Select files in the center list first.")
        }

        if filenameToMetadataTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Enter a matching template or drag metadata chips into the field.")
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
            return L10n.string("The template matched, but it did not extract any writable metadata fields.")
        }

        return "The extracted metadata already matches the current tags."
    }

    private var filenameMetadataIssueSummaryText: String {
        let issueRows = filenameMetadataPlan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return L10n.string("No filename matching issues.") }

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
            Group {
                if let selectedConverterMode {
                    converterDetail(for: selectedConverterMode)
                } else {
                    MetadataConverterModePickerView(
                        onSelect: selectConverterMode
                    )
                }
            }
            .frame(minWidth: 820, idealWidth: 860, maxWidth: .infinity, minHeight: 620, idealHeight: 720, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(selectedConverterMode?.title ?? AppWindowTitle.filenameMetadata)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }

                if selectedConverterMode != nil {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            selectedConverterMode = nil
                            pendingFieldInsertion = nil
                        } label: {
                            Label("Modes", systemImage: "chevron.left")
                        }
                        .disabled(isApplying)
                    }
                }
            }
        }
        .onChange(of: selectedConverterMode) { _, _ in pendingFieldInsertion = nil }
        .onChange(of: store.presentationID) { _, _ in
            selectedConverterMode = nil
            pendingFieldInsertion = nil
            pendingExchangeFieldInsertion = nil
            externalFileError = nil
        }
    }

    @ViewBuilder
    private func converterDetail(for selectedMode: MetadataConverterMode) -> some View {
        switch selectedMode {
        case .metadataToFilename, .filenameToMetadata:
            filenameMetadataDetail
        case .metadataToText, .textToMetadata, .metadataToCSV, .csvToMetadata:
            metadataExchangeDetail(for: selectedMode)
        }
    }

    private var filenameMetadataDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                setupSection
                previewSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentInset)
            .padding(.top, contentInset)
            .padding(.bottom, contentInset)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func selectConverterMode(_ selectedMode: MetadataConverterMode) {
        switch selectedMode {
        case .metadataToFilename:
            mode = .metadataToFilename
        case .filenameToMetadata:
            mode = .filenameToMetadata
        case .metadataToText, .textToMetadata, .metadataToCSV, .csvToMetadata:
            break
        }
        selectedConverterMode = selectedMode
        externalFileError = nil
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
                        RoundedRectangle(cornerRadius: controlRadius)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: controlRadius)
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
            return L10n.string("AudioMator keeps each file's current extension. The template changes only the filename.")
        case .filenameToMetadata:
            return L10n.string("AudioMator matches the current filename without its extension. The template must match the whole filename, and only extracted metadata fields will be written.")
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

    private func metadataExchangeDetail(for selectedMode: MetadataConverterMode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metadataExchangeHeader(for: selectedMode)
                metadataExchangeSetupSection(for: selectedMode)
                metadataExchangePreviewSection(for: selectedMode)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentInset)
            .padding(.top, contentInset)
            .padding(.bottom, contentInset)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func metadataExchangeHeader(for selectedMode: MetadataConverterMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedMode.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(selectedMode.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(selectionSummaryText, systemImage: "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }

    private func metadataExchangeSetupSection(for selectedMode: MetadataConverterMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text(metadataExchangeSetupDescription(for: selectedMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedMode == .textToMetadata || selectedMode == .csvToMetadata {
                    externalSourceControls(for: selectedMode)
                    Toggle("Clear blank imported values", isOn: $clearBlankImportedValues)
                        .toggleStyle(.checkbox)
                        .disabled(isApplying)
                }

                if selectedMode == .metadataToCSV {
                    Toggle("Include header row", isOn: $includeCSVHeaderRow)
                        .toggleStyle(.checkbox)
                        .disabled(isApplying)
                }

                if selectedMode == .csvToMetadata {
                    Toggle("First row is header", isOn: $firstCSVRowIsHeader)
                        .toggleStyle(.checkbox)
                        .disabled(isApplying)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(metadataExchangePalette(for: selectedMode)) { field in
                        metadataExchangeChip(field, for: selectedMode)
                    }
                }

                metadataExchangeTemplateEditor(for: selectedMode)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private func externalSourceControls(for selectedMode: MetadataConverterMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(externalSourceURL(for: selectedMode) == nil ? "Choose File…" : "Change File…") {
                    chooseExternalTextFile(for: selectedMode)
                }
                .disabled(isApplying)

                if let url = externalSourceURL(for: selectedMode) {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if let externalFileError {
                Label(externalFileError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            TextEditor(text: externalSourceBinding(for: selectedMode))
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 96)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: controlRadius)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: controlRadius)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .disabled(isApplying)
        }
    }

    private func metadataExchangeTemplateEditor(for selectedMode: MetadataConverterMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metadataExchangeTemplateTitle(for: selectedMode))
                .font(.headline)

            MetadataExchangeTemplateEditor(
                template: metadataExchangeTemplateBinding(for: selectedMode),
                pendingInsertion: $pendingExchangeFieldInsertion,
                isEnabled: !isApplying
            )
            .frame(minHeight: 86)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: controlRadius)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: controlRadius)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .disabled(isApplying)
        }
    }

    private func metadataExchangePreviewSection(for selectedMode: MetadataConverterMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Label(
                    metadataExchangeStatusMessage(for: selectedMode),
                    systemImage: metadataExchangeStatusSymbol(for: selectedMode)
                )
                .font(.subheadline)
                .foregroundStyle(metadataExchangeStatusTint(for: selectedMode))

                metadataExchangePreviewContent(for: selectedMode)
                    .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    @ViewBuilder
    private func metadataExchangePreviewContent(for selectedMode: MetadataConverterMode) -> some View {
        switch selectedMode {
        case .metadataToText:
            MetadataTextExportPreviewList(plan: metadataTextExportPlan)
        case .textToMetadata:
            MetadataExchangeImportPreviewList(plan: textMetadataImportPlan)
        case .metadataToCSV:
            MetadataCSVExportPreviewList(plan: metadataCSVExportPlan)
        case .csvToMetadata:
            MetadataExchangeImportPreviewList(plan: csvMetadataImportPlan)
        case .metadataToFilename, .filenameToMetadata:
            EmptyView()
        }
    }

    private func metadataExchangeSetupDescription(for selectedMode: MetadataConverterMode) -> String {
        switch selectedMode {
        case .metadataToText:
            return L10n.string("Each selected file renders one line from the text template.")
        case .textToMetadata:
            return L10n.string("Each non-empty text line is parsed as one record. Include fileName or baseName to match by filename, otherwise records map in selection order.")
        case .metadataToCSV:
            return L10n.string("The column template is one delimited row of field tokens. Use commas, semicolons, pipes, or tabs.")
        case .csvToMetadata:
            return L10n.string("The column template maps delimited cells to fields. Include fileName or baseName to match rows by filename, otherwise rows map in selection order.")
        case .metadataToFilename, .filenameToMetadata:
            return ""
        }
    }

    private func metadataExchangeTemplateTitle(for selectedMode: MetadataConverterMode) -> String {
        switch selectedMode {
        case .metadataToCSV, .csvToMetadata:
            return L10n.string("Column template")
        case .metadataToText, .textToMetadata:
            return L10n.string("Text template")
        case .metadataToFilename, .filenameToMetadata:
            return L10n.string("Template")
        }
    }

    private func metadataExchangePalette(for selectedMode: MetadataConverterMode) -> [MetadataExchangeField] {
        switch selectedMode {
        case .metadataToText, .metadataToCSV:
            return MetadataExchangeField.exportPalette
        case .textToMetadata, .csvToMetadata:
            return MetadataExchangeField.importPalette
        case .metadataToFilename, .filenameToMetadata:
            return []
        }
    }

    private func metadataExchangeTemplateBinding(for selectedMode: MetadataConverterMode) -> Binding<String> {
        Binding(
            get: {
                switch selectedMode {
                case .metadataToText:
                    return metadataToTextTemplate
                case .textToMetadata:
                    return textToMetadataTemplate
                case .metadataToCSV:
                    return metadataToCSVTemplate
                case .csvToMetadata:
                    return csvToMetadataTemplate
                case .metadataToFilename, .filenameToMetadata:
                    return ""
                }
            },
            set: { newValue in
                switch selectedMode {
                case .metadataToText:
                    metadataToTextTemplate = newValue
                case .textToMetadata:
                    textToMetadataTemplate = newValue
                case .metadataToCSV:
                    metadataToCSVTemplate = newValue
                case .csvToMetadata:
                    csvToMetadataTemplate = newValue
                case .metadataToFilename, .filenameToMetadata:
                    break
                }
            }
        )
    }

    private func externalSourceBinding(for selectedMode: MetadataConverterMode) -> Binding<String> {
        Binding(
            get: { selectedMode == .csvToMetadata ? csvImportSource : textImportSource },
            set: { newValue in
                if selectedMode == .csvToMetadata {
                    csvImportSource = newValue
                } else {
                    textImportSource = newValue
                }
            }
        )
    }

    private func externalSourceURL(for selectedMode: MetadataConverterMode) -> URL? {
        selectedMode == .csvToMetadata ? selectedCSVImportURL : selectedTextImportURL
    }

    private func metadataExchangeChip(_ field: MetadataExchangeField, for selectedMode: MetadataConverterMode) -> some View {
        Button {
            guard !isApplying else { return }
            pendingExchangeFieldInsertion = MetadataExchangeTemplateEditorInsertion(field: field)
        } label: {
            Text(field.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help("Click to insert at the caret, or drag into the template")
        .onDrag {
            NSItemProvider(object: field.token as NSString)
        }
    }

    private func metadataExchangeStatusMessage(for selectedMode: MetadataConverterMode) -> String {
        if targetFiles.isEmpty {
            return L10n.string("Select files in the center list first.")
        }

        switch selectedMode {
        case .metadataToText:
            if let validationMessage = metadataTextExportPlan.validationMessage { return validationMessage }
            return "\(metadataTextExportPlan.rows.count) line(s) will be exported."
        case .textToMetadata:
            if let validationMessage = textMetadataImportPlan.validationMessage { return validationMessage }
            return metadataExchangeImportStatusMessage(for: textMetadataImportPlan)
        case .metadataToCSV:
            if let validationMessage = metadataCSVExportPlan.validationMessage { return validationMessage }
            return "\(metadataCSVExportPlan.rows.count) row(s), \(metadataCSVExportPlan.columns.count) column(s) will be exported."
        case .csvToMetadata:
            if let validationMessage = csvMetadataImportPlan.validationMessage { return validationMessage }
            return metadataExchangeImportStatusMessage(for: csvMetadataImportPlan)
        case .metadataToFilename, .filenameToMetadata:
            return ""
        }
    }

    private func metadataExchangeImportStatusMessage(for plan: MetadataExchangeImportPlan) -> String {
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

    private func metadataExchangeStatusSymbol(for selectedMode: MetadataConverterMode) -> String {
        switch selectedMode {
        case .metadataToText:
            return metadataTextExportPlan.canExport ? "checkmark.circle.fill" : "info.circle.fill"
        case .metadataToCSV:
            return metadataCSVExportPlan.canExport ? "checkmark.circle.fill" : "info.circle.fill"
        case .textToMetadata:
            return textMetadataImportPlan.issueCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .csvToMetadata:
            return csvMetadataImportPlan.issueCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        case .metadataToFilename, .filenameToMetadata:
            return "info.circle.fill"
        }
    }

    private func metadataExchangeStatusTint(for selectedMode: MetadataConverterMode) -> Color {
        switch selectedMode {
        case .metadataToText:
            return metadataTextExportPlan.canExport ? .green : .secondary
        case .metadataToCSV:
            return metadataCSVExportPlan.canExport ? .green : .secondary
        case .textToMetadata:
            return textMetadataImportPlan.issueCount > 0 ? .orange : .green
        case .csvToMetadata:
            return csvMetadataImportPlan.issueCount > 0 ? .orange : .green
        case .metadataToFilename, .filenameToMetadata:
            return .secondary
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

            Button(selectedConverterMode?.actionTitle ?? mode.actionTitle) {
                applyCurrentMode()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, contentInset)
        .padding(.top, 12)
        .padding(.bottom, 16)
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
        guard let selectedConverterMode else { return }

        switch selectedConverterMode {
        case .metadataToFilename:
            applyRename()
        case .filenameToMetadata:
            applyFilenameMetadata()
        case .metadataToText:
            exportMetadataText()
        case .textToMetadata:
            applyTextMetadata()
        case .metadataToCSV:
            exportMetadataCSV()
        case .csvToMetadata:
            applyCSVMetadata()
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

    private func applyTextMetadata() {
        let plan = textMetadataImportPlan
        guard plan.canApply else { return }

        isApplying = true
        Task { @MainActor in
            await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)
            isApplying = false
        }
    }

    private func applyCSVMetadata() {
        let plan = csvMetadataImportPlan
        guard plan.canApply else { return }

        isApplying = true
        Task { @MainActor in
            await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)
            isApplying = false
        }
    }

    private func exportMetadataText() {
        let plan = metadataTextExportPlan
        guard plan.canExport else { return }
        saveText(plan.outputText, defaultFileName: "AudioMator Metadata.txt", fileExtension: "txt")
    }

    private func exportMetadataCSV() {
        let plan = metadataCSVExportPlan
        guard plan.canExport else { return }
        saveText(plan.outputText, defaultFileName: "AudioMator Metadata.csv", fileExtension: "csv")
    }

    private func chooseExternalTextFile(for selectedMode: MetadataConverterMode) {
        PlatformDocumentPicker.pickTextFile { url in
            guard let url else { return }

            Task { @MainActor in
                do {
                    let text = try loadExternalTextFile(from: url)
                    switch selectedMode {
                    case .textToMetadata:
                        textImportSource = text
                        selectedTextImportURL = url
                    case .csvToMetadata:
                        csvImportSource = text
                        selectedCSVImportURL = url
                    case .metadataToFilename, .filenameToMetadata, .metadataToText, .metadataToCSV:
                        break
                    }
                    externalFileError = nil
                } catch {
                    externalFileError = (error as NSError).localizedDescription
                }
            }
        }
    }

    private func loadExternalTextFile(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode,
            .windowsCP1252,
            .macOSRoman
        ]

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw NSError(
            domain: "MetadataFilenameWindowView",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "AudioMator couldn't read that file as text."]
        )
    }

    private func saveText(_ text: String, defaultFileName: String, fileExtension: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFileName
        panel.title = "Export"
        panel.prompt = "Export"
        if let contentType = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [contentType]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            viewModel.presentMetadataWriteHUD(
                style: .failure,
                title: "Export Failed",
                subtitle: (error as NSError).localizedDescription
            )
        }
    }
}

#endif
