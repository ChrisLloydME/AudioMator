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
            .navigationTitle(selectedConverterMode?.title ?? "Filename & Metadata")
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
            return L10n.string("The column template is one CSV row of field tokens. AudioMator escapes commas, quotes, newlines, and empty fields.")
        case .csvToMetadata:
            return L10n.string("The column template maps CSV cells to fields. Include fileName or baseName to match rows by filename, otherwise rows map in selection order.")
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

private struct MetadataConverterModePickerView: View {
    let onSelect: (MetadataConverterMode) -> Void

    private let rowRadius: CGFloat = 12
    private let rowMaxWidth: CGFloat = 690

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                ForEach(MetadataConverterMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(mode.title)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    if mode.showsBetaBadge {
                                        MetadataConverterModeBetaBadge()
                                    }
                                }

                                Text(mode.subtitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: rowRadius)
                            .fill(Color.secondary.opacity(0.075))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: rowRadius)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                }
            }
            .frame(maxWidth: rowMaxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MetadataConverterModeBetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.8)
            )
    }
}

private extension MetadataConverterMode {
    var showsBetaBadge: Bool {
        switch self {
        case .metadataToText, .textToMetadata, .metadataToCSV, .csvToMetadata:
            return true
        case .metadataToFilename, .filenameToMetadata:
            return false
        }
    }
}

private struct MetadataTextExportPreviewList: View {
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

private struct MetadataCSVExportPreviewList: View {
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

private struct MetadataExchangeImportPreviewList: View {
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

private struct MetadataExchangeTemplateEditorInsertion: Equatable {
    let id = UUID()
    let field: MetadataExchangeField
}

private struct MetadataExchangeTemplateEditor: NSViewRepresentable {
    @Binding var template: String
    @Binding var pendingInsertion: MetadataExchangeTemplateEditorInsertion?
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
        var parent: MetadataExchangeTemplateEditor
        weak var textView: NSTextView?
        var isApplyingProgrammaticUpdate = false
        var selectedRange = NSRange(location: 0, length: 0)
        var lastAppliedInsertionID: UUID?

        init(parent: MetadataExchangeTemplateEditor) {
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

            let document = MetadataExchangeTemplateDocument(rawValue: replacementString)
            guard document.segments.contains(where: { segment in
                if case .field = segment { return true }
                return false
            }) else {
                return true
            }

            replaceCharacters(in: affectedCharRange, with: document, in: textView)
            return false
        }

        func applyTemplate(_ template: String, to textView: NSTextView) {
            let document = MetadataExchangeTemplateDocument(rawValue: template)
            let attributed = attributedString(for: document)
            let clampedRange = clampSelectedRange(selectedRange, textLength: attributed.length)

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(clampedRange)
            selectedRange = clampedRange
            refreshLiteralStyling(in: textView)
            isApplyingProgrammaticUpdate = false
        }

        func insert(field: MetadataExchangeField, into textView: NSTextView) {
            let insertionRange = clampSelectedRange(
                selectedRange,
                textLength: textView.textStorage?.length ?? 0
            )
            replaceCharacters(
                in: insertionRange,
                with: MetadataExchangeTemplateDocument(rawValue: field.token),
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
                if let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? MetadataExchangeFieldAttachment {
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
            with document: MetadataExchangeTemplateDocument,
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

        private func attributedString(for document: MetadataExchangeTemplateDocument) -> NSAttributedString {
            let attributed = NSMutableAttributedString()

            for segment in document.segments {
                switch segment {
                case .literal(let literal):
                    attributed.append(NSAttributedString(string: literal, attributes: literalAttributes()))
                case .field(let field):
                    attributed.append(NSAttributedString(attachment: MetadataExchangeFieldAttachment(field: field)))
                }
            }

            if attributed.length == 0 {
                attributed.append(NSAttributedString(string: "", attributes: literalAttributes()))
            }

            return attributed
        }

        private func literalAttributes() -> [NSAttributedString.Key: Any] {
            [
                .font: MetadataExchangeTemplateEditor.editorFont,
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

                if !(attachment is MetadataExchangeFieldAttachment) {
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

private final class MetadataExchangeFieldAttachment: NSTextAttachment {
    let field: MetadataExchangeField

    init(field: MetadataExchangeField) {
        self.field = field
        super.init(data: nil, ofType: nil)
        attachmentCell = NSTextAttachmentCell(imageCell: FileRenameFieldAttachment.makeChipImage(title: field.displayName))
    }

    required init?(coder: NSCoder) {
        return nil
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

    fileprivate static func makeChipImage(title: String) -> NSImage {
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
#endif
