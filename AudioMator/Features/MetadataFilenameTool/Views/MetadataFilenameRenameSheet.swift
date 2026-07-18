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
        var seenIDs: Set<AudioFile.ID> = []
        self.targetFileIDs = targetFileIDs.filter { seenIDs.insert($0).inserted }
        self.presentationID = UUID()
    }
}

private struct MetadataFilenameTargetResolution {
    let files: [AudioFile]
    let isComplete: Bool
}

enum MetadataExchangeExternalTextFileLoader {
    nonisolated static let maximumByteCount = MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount

    enum LoadingError: LocalizedError, Equatable, Sendable {
        case notRegularFile
        case tooLarge(maximumByteCount: Int)
        case unsupportedEncoding

        nonisolated var errorDescription: String? {
            switch self {
            case .notRegularFile:
                return String(localized: "AudioMator can only import a regular text file.")
            case .tooLarge(let maximumByteCount):
                let megabytes = maximumByteCount / (1_024 * 1_024)
                return String(localized: "That file is too large to import. Choose a text file no larger than \(megabytes) MB.")
            case .unsupportedEncoding:
                return String(localized: "AudioMator couldn't read that file as UTF-8, UTF-16, Windows-1252, or Mac Roman text.")
            }
        }
    }

    nonisolated static func load(
        from url: URL,
        maximumByteCount: Int = maximumByteCount
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard maximumByteCount >= 0 else {
                throw LoadingError.tooLarge(maximumByteCount: 0)
            }
            try Task.checkCancellation()

            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else {
                throw LoadingError.notRegularFile
            }

            if let fileSize = resourceValues.fileSize, fileSize > maximumByteCount {
                throw LoadingError.tooLarge(maximumByteCount: maximumByteCount)
            }

            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }

            var data = Data()
            while data.count <= maximumByteCount {
                try Task.checkCancellation()
                let remainingByteCount = maximumByteCount - data.count
                let chunkByteCount = remainingByteCount < 64 * 1_024
                    ? remainingByteCount + 1
                    : 64 * 1_024
                let chunk = try fileHandle.read(upToCount: chunkByteCount)
                guard let chunk, !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count <= maximumByteCount else {
                throw LoadingError.tooLarge(maximumByteCount: maximumByteCount)
            }

            try Task.checkCancellation()
            return try decode(data)
        }.value
    }

    nonisolated static func decode(_ data: Data) throws -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = decodedText(data.dropFirst(3), encoding: .utf8) else {
                throw LoadingError.unsupportedEncoding
            }
            return text
        }

        if data.starts(with: [0xFF, 0xFE]) {
            guard let text = decodedText(data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw LoadingError.unsupportedEncoding
            }
            return text
        }

        if data.starts(with: [0xFE, 0xFF]) {
            guard let text = decodedText(data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw LoadingError.unsupportedEncoding
            }
            return text
        }

        if data.count >= 2, data.count.isMultiple(of: 2) {
            let bytes = [UInt8](data)
            let pairCount = bytes.count / 2
            let evenNullCount = stride(from: 0, to: bytes.count, by: 2).reduce(into: 0) { count, index in
                if bytes[index] == 0 { count += 1 }
            }
            let oddNullCount = stride(from: 1, to: bytes.count, by: 2).reduce(into: 0) { count, index in
                if bytes[index] == 0 { count += 1 }
            }

            if oddNullCount > 0, oddNullCount * 2 >= pairCount,
               let text = decodedText(data, encoding: .utf16LittleEndian) {
                return text
            }

            if evenNullCount > 0, evenNullCount * 2 >= pairCount,
               let text = decodedText(data, encoding: .utf16BigEndian) {
                return text
            }
        }

        if let text = decodedText(data, encoding: .utf8) {
            return text
        }

        for encoding in [String.Encoding.windowsCP1252, .macOSRoman] {
            if let text = decodedText(data, encoding: encoding) {
                return text
            }
        }

        throw LoadingError.unsupportedEncoding
    }

    nonisolated private static func decodedText<D: DataProtocol>(
        _ data: D,
        encoding: String.Encoding
    ) -> String? {
        guard let text = String(data: Data(data), encoding: encoding) else { return nil }

        for scalar in text.unicodeScalars {
            if scalar.value == 0xFFFD || scalar.value == 0x7F {
                return nil
            }

            if scalar.value < 0x20 {
                switch scalar.value {
                case 0x09, 0x0A, 0x0D:
                    continue
                default:
                    return nil
                }
            }
        }

        return text
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
    @State private var clearBlankTextImportedValues: Bool = false
    @State private var clearBlankCSVImportedValues: Bool = false
    @State private var replaceUnderscoresWithSpaces: Bool = false
    @State private var isApplying: Bool = false
    @State private var externalFileLoadID: UUID?
    @State private var pendingFieldInsertion: FileRenameTemplateEditorInsertion?
    @State private var pendingExchangeFieldInsertion: MetadataExchangeTemplateEditorInsertion?
    @State private var renameFailureMessage: String?

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18
    private let controlRadius: CGFloat = 12
    private let contentInset: CGFloat = 20

    private var targetResolution: MetadataFilenameTargetResolution {
        let filesByID = Dictionary(grouping: viewModel.files, by: \.id)
        var resolvedFiles: [AudioFile] = []
        resolvedFiles.reserveCapacity(store.targetFileIDs.count)

        for id in store.targetFileIDs {
            guard let matches = filesByID[id], matches.count == 1, let file = matches.first else {
                return MetadataFilenameTargetResolution(files: [], isComplete: false)
            }
            resolvedFiles.append(file)
        }

        return MetadataFilenameTargetResolution(files: resolvedFiles, isComplete: true)
    }

    private var targetFiles: [AudioFile] {
        targetResolution.files
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
            clearBlankImportedValues: clearBlankTextImportedValues
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
            clearBlankImportedValues: clearBlankCSVImportedValues
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
        guard
            let selectedConverterMode,
            targetResolution.isComplete,
            !isApplying,
            viewModel.metadataSaveProgress == nil,
            !viewModel.hasUnsavedInspectorChanges
        else {
            return false
        }

        switch selectedConverterMode {
        case .metadataToFilename:
            return renamePlan.canApply
        case .filenameToMetadata:
            return filenameMetadataPlan.canApply
        case .metadataToText:
            return metadataTextExportPlan.canExport
        case .textToMetadata:
            return textMetadataImportPlan.canApply
        case .metadataToCSV:
            return metadataCSVExportPlan.canExport
        case .csvToMetadata:
            return csvMetadataImportPlan.canApply
        }
    }

    private var metadataToFilenameStatusMessage: String {
        MetadataFilenameStatusPresentation.renameMessage(
            targetCount: targetFiles.count,
            template: metadataToFilenameTemplate,
            plan: renamePlan
        )
    }

    private var filenameToMetadataStatusMessage: String {
        MetadataFilenameStatusPresentation.filenameMetadataMessage(
            targetCount: targetFiles.count,
            template: filenameToMetadataTemplate,
            plan: filenameMetadataPlan
        )
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
        .onChange(of: selectedConverterMode) { _, _ in
            pendingFieldInsertion = nil
            pendingExchangeFieldInsertion = nil
            externalFileLoadID = nil
            externalFileError = nil
        }
        .onChange(of: store.presentationID) { _, _ in
            resetForNewPresentation()
        }
        .alert(
            "Rename Failed",
            isPresented: Binding(
                get: { renameFailureMessage != nil },
                set: { if !$0 { renameFailureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                renameFailureMessage = nil
            }
        } message: {
            Text(renameFailureMessage ?? "")
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
        MetadataExchangeDetailView(
            selectedMode: selectedMode,
            targetCount: targetFiles.count,
            selectionSummaryText: selectionSummaryText,
            isApplying: isApplying,
            template: metadataExchangeTemplateBinding(for: selectedMode),
            pendingInsertion: $pendingExchangeFieldInsertion,
            externalSource: externalSourceBinding(for: selectedMode),
            externalSourceURL: externalSourceURL(for: selectedMode),
            externalFileError: externalFileError,
            includeCSVHeaderRow: $includeCSVHeaderRow,
            firstCSVRowIsHeader: $firstCSVRowIsHeader,
            clearBlankImportedValues: clearBlankImportedValuesBinding(for: selectedMode),
            metadataTextExportPlan: metadataTextExportPlan,
            textMetadataImportPlan: textMetadataImportPlan,
            metadataCSVExportPlan: metadataCSVExportPlan,
            csvMetadataImportPlan: csvMetadataImportPlan,
            chooseExternalFile: {
                chooseExternalTextFile(for: selectedMode)
            }
        )
        .safeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
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
                    selectedCSVImportURL = nil
                } else {
                    textImportSource = newValue
                    selectedTextImportURL = nil
                }
                externalFileLoadID = nil
                externalFileError = nil
            }
        )
    }

    private func clearBlankImportedValuesBinding(for selectedMode: MetadataConverterMode) -> Binding<Bool> {
        Binding(
            get: {
                selectedMode == .csvToMetadata
                    ? clearBlankCSVImportedValues
                    : clearBlankTextImportedValues
            },
            set: { newValue in
                if selectedMode == .csvToMetadata {
                    clearBlankCSVImportedValues = newValue
                } else if selectedMode == .textToMetadata {
                    clearBlankTextImportedValues = newValue
                }
            }
        )
    }

    private func externalSourceURL(for selectedMode: MetadataConverterMode) -> URL? {
        selectedMode == .csvToMetadata ? selectedCSVImportURL : selectedTextImportURL
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
        guard canApply, plan.canApply else { return }
        let presentationID = store.presentationID

        isApplying = true

        Task { @MainActor in
            let result = await viewModel.renameFiles(using: plan)
            isApplying = false

            guard store.presentationID == presentationID else { return }
            if let failureMessage = result.failureMessage {
                renameFailureMessage = failureMessage
            } else if plan.issueCount == 0 {
                dismiss()
            }
        }
    }

    private func applyFilenameMetadata() {
        let plan = filenameMetadataPlan
        guard canApply, plan.canApply else { return }
        let presentationID = store.presentationID

        isApplying = true

        Task { @MainActor in
            let summary = await viewModel.applyFilenameMetadataPlan(plan.writeEntries)
            isApplying = false

            guard store.presentationID == presentationID else { return }
            if let summary, summary.failureIssues.isEmpty, !plan.hasIssues {
                dismiss()
            }
        }
    }

    private func applyTextMetadata() {
        let plan = textMetadataImportPlan
        guard canApply, plan.canApply else { return }
        let presentationID = store.presentationID

        isApplying = true
        Task { @MainActor in
            _ = await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)
            isApplying = false
            guard store.presentationID == presentationID else { return }
        }
    }

    private func applyCSVMetadata() {
        let plan = csvMetadataImportPlan
        guard canApply, plan.canApply else { return }
        let presentationID = store.presentationID

        isApplying = true
        Task { @MainActor in
            _ = await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)
            isApplying = false
            guard store.presentationID == presentationID else { return }
        }
    }

    private func exportMetadataText() {
        let plan = metadataTextExportPlan
        guard canApply, plan.canExport else { return }
        saveText(plan.outputText, defaultFileName: "AudioMator Metadata.txt", fileExtension: "txt")
    }

    private func exportMetadataCSV() {
        let plan = metadataCSVExportPlan
        guard canApply, plan.canExport else { return }
        saveText(plan.outputText, defaultFileName: "AudioMator Metadata.csv", fileExtension: "csv")
    }

    private func chooseExternalTextFile(for selectedMode: MetadataConverterMode) {
        PlatformDocumentPicker.pickTextFile { url in
            guard let url else { return }
            guard selectedMode == .textToMetadata || selectedMode == .csvToMetadata else { return }

            let presentationID = store.presentationID
            let loadID = UUID()
            externalFileLoadID = loadID

            Task { @MainActor in
                do {
                    let text = try await MetadataExchangeExternalTextFileLoader.load(from: url)
                    guard
                        store.presentationID == presentationID,
                        selectedConverterMode == selectedMode,
                        externalFileLoadID == loadID
                    else { return }

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
                    externalFileLoadID = nil
                    externalFileError = nil
                } catch {
                    guard
                        store.presentationID == presentationID,
                        selectedConverterMode == selectedMode,
                        externalFileLoadID == loadID
                    else { return }
                    externalFileLoadID = nil
                    externalFileError = (error as NSError).localizedDescription
                }
            }
        }
    }

    private func resetForNewPresentation() {
        selectedConverterMode = nil
        mode = .metadataToFilename
        textImportSource = ""
        csvImportSource = ""
        selectedTextImportURL = nil
        selectedCSVImportURL = nil
        externalFileLoadID = nil
        externalFileError = nil
        includeCSVHeaderRow = true
        firstCSVRowIsHeader = true
        clearBlankTextImportedValues = false
        clearBlankCSVImportedValues = false
        replaceUnderscoresWithSpaces = false
        pendingFieldInsertion = nil
        pendingExchangeFieldInsertion = nil
        renameFailureMessage = nil
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
            try Data(text.utf8).write(to: url, options: .atomic)
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
