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

enum MetadataExchangeExternalTextFileLoader {
    nonisolated static let maximumByteCount = MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount

    enum LoadingError: LocalizedError, Equatable, Sendable {
        case notRegularFile
        case tooLarge(maximumByteCount: Int)
        case unsupportedEncoding

        nonisolated var errorDescription: String? {
            switch self {
            case .notRegularFile:
                return String(localized: "This item isn't a regular text file. Choose a text file to import.")
            case .tooLarge(let maximumByteCount):
                let megabytes = maximumByteCount / (1_024 * 1_024)
                return String(localized: "This file exceeds the \(megabytes) MB import limit. Choose a smaller text file or split it into smaller files.")
            case .unsupportedEncoding:
                return String(localized: "This file’s text encoding couldn’t be read. Save a copy as UTF-8, then import the copy. UTF-16, Windows-1252, and Mac Roman are also supported.")
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

    @StateObject private var fieldTransferStore = MetadataFieldTransferStore()
    @State private var pendingFieldInsertion: FileRenameTemplateEditorInsertion?
    @State private var pendingExchangeFieldInsertion: MetadataExchangeTemplateEditorInsertion?
    @State private var renameFailureMessage: String?

    private var selectedConverterMode: MetadataConverterMode? { store.selectedMode }
    private var isApplying: Bool { store.isApplying }
    private var externalFileError: String? { store.externalFileError }

    private var filenameMode: MetadataFilenameToolMode {
        selectedConverterMode == .filenameToMetadata ? .filenameToMetadata : .metadataToFilename
    }

    private var activeConverterMode: MetadataConverterMode {
        filenameMode == .filenameToMetadata ? .filenameToMetadata : .metadataToFilename
    }

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18
    private let controlRadius: CGFloat = 12
    private let contentInset: CGFloat = 20

    // MARK: – Stored plan reads
    //
    // Every preview value below reads the single plan the store published for
    // the active mode. No planner call runs while laying out a window, and the
    // counts, rows, gating, export and write all share that one value.

    private var renamePlan: FileRenamePlan { store.displayRenamePlan() }
    private var filenameMetadataPlan: FilenameMetadataPlan { store.displayFilenameMetadataPlan() }
    private var metadataTextExportPlan: MetadataTextExportPlan { store.displayTextExportPlan() }
    private var textMetadataImportPlan: MetadataExchangeImportPlan {
        store.displayImportPlan(for: .textToMetadata)
    }
    private var metadataCSVExportPlan: MetadataCSVExportPlan { store.displayCSVExportPlan() }
    private var csvMetadataImportPlan: MetadataExchangeImportPlan {
        store.displayImportPlan(for: .csvToMetadata)
    }
    private var fieldTransferPlan: MetadataExchangeImportPlan {
        store.displayImportPlan(for: .metadataFieldTransfer)
    }
    private var previewPhaseMessage: String? { store.previewPhaseMessage() }

    private var activeTemplate: String { store.template(for: activeConverterMode) }

    private var activeTemplateBinding: Binding<String> {
        Binding(
            get: { store.template(for: activeConverterMode) },
            set: { store.updateTemplate($0, for: activeConverterMode) }
        )
    }

    private var activeFieldPalette: [FileRenameMetadataField] {
        switch filenameMode {
        case .metadataToFilename:
            return FileRenameMetadataField.metadataToFilenameFields
        case .filenameToMetadata:
            return FileRenameMetadataField.filenameToMetadataFields
        }
    }

    private var selectionSummaryText: String { store.selectionSummaryText }

    private var previewStatusMessage: String {
        if let previewPhaseMessage { return previewPhaseMessage }
        switch filenameMode {
        case .metadataToFilename:
            return metadataToFilenameStatusMessage
        case .filenameToMetadata:
            return filenameToMetadataStatusMessage
        }
    }

    private var previewStatusSymbolName: String {
        if store.isPlanning {
            return "info.circle.fill"
        }
        if previewPhaseMessage != nil {
            return "exclamationmark.triangle.fill"
        }

        if previewHasIssues {
            return "exclamationmark.triangle.fill"
        }

        if previewReadyCount > 0 {
            return "checkmark.circle.fill"
        }

        return "info.circle.fill"
    }

    private var previewStatusTint: Color {
        if store.isPlanning {
            return .secondary
        }
        if previewPhaseMessage != nil {
            return .orange
        }

        if previewHasIssues {
            return .orange
        }

        if previewReadyCount > 0 {
            return .green
        }

        return .secondary
    }

    private var previewHasIssues: Bool {
        switch filenameMode {
        case .metadataToFilename:
            return renamePlan.hasIssues
        case .filenameToMetadata:
            return filenameMetadataPlan.hasIssues
        }
    }

    private var previewReadyCount: Int {
        switch filenameMode {
        case .metadataToFilename:
            return renamePlan.readyCount
        case .filenameToMetadata:
            return filenameMetadataPlan.readyCount
        }
    }

    private var canApply: Bool {
        guard
            let selectedConverterMode,
            store.isTargetResolutionComplete,
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
        case .metadataFieldTransfer:
            return fieldTransferPlan.canApply
        }
    }

    private var metadataToFilenameStatusMessage: String {
        MetadataFilenameStatusPresentation.renameMessage(
            targetCount: store.targetCount,
            template: store.template(for: .metadataToFilename),
            plan: renamePlan
        )
    }

    private var filenameToMetadataStatusMessage: String {
        MetadataFilenameStatusPresentation.filenameMetadataMessage(
            targetCount: store.targetCount,
            template: store.template(for: .filenameToMetadata),
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
                            store.selectMode(nil)
                            pendingFieldInsertion = nil
                        } label: {
                            Label("Modes", systemImage: "chevron.left")
                        }
                        .disabled(isApplying)
                    }
                }
            }
        }
        .onChange(of: store.selectedMode) { _, _ in
            pendingFieldInsertion = nil
            pendingExchangeFieldInsertion = nil
        }
        .onChange(of: store.presentationID) { _, _ in
            resetForNewPresentation()
        }
        .onChange(of: viewModel.filesRevision) { _, _ in
            refreshConversionInput()
        }
        .onChange(of: fieldTransferStore.source) { _, _ in
            store.setFieldTransferOptions(
                source: fieldTransferStore.source,
                destination: fieldTransferStore.destination,
                operation: fieldTransferStore.operation
            )
        }
        .onChange(of: fieldTransferStore.destination) { _, _ in
            store.setFieldTransferOptions(
                source: fieldTransferStore.source,
                destination: fieldTransferStore.destination,
                operation: fieldTransferStore.operation
            )
        }
        .onChange(of: fieldTransferStore.operation) { _, _ in
            store.setFieldTransferOptions(
                source: fieldTransferStore.source,
                destination: fieldTransferStore.destination,
                operation: fieldTransferStore.operation
            )
        }
        .task {
            // The converter may request mutation scope only for the executable
            // targets captured by an Apply; opening, previewing and exporting
            // never prompt.
            let viewModel = self.viewModel
            store.setScopeRequester { urls in
                viewModel.ensureMutationDirectoryAccess(for: urls)
            }
            refreshConversionInput()
        }
        .onDisappear {
            store.cancelPresentation()
        }
        .alert(
            String(localized: "Files Couldn’t Be Renamed"),
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
        case .metadataFieldTransfer:
            MetadataFieldTransferDetailView(
                store: fieldTransferStore,
                plan: fieldTransferPlan,
                isPlanning: store.isPlanning,
                phaseMessage: previewPhaseMessage,
                targetCount: store.targetCount,
                selectionSummaryText: selectionSummaryText,
                isApplying: isApplying
            )
            .audiomatorSafeAreaBar(edge: .bottom, spacing: 0) { footer }
            .scrollBounceBehavior(.basedOnSize)
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
        .audiomatorSafeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func refreshConversionInput() {
        store.refresh(
            files: viewModel.files,
            filesRevision: viewModel.filesRevision,
            projector: viewModel.metadataPipeline
        )
    }

    private func selectConverterMode(_ selectedMode: MetadataConverterMode) {
        store.setFieldTransferOptions(
            source: fieldTransferStore.source,
            destination: fieldTransferStore.destination,
            operation: fieldTransferStore.operation
        )
        store.selectMode(selectedMode)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(filenameMode.pickerTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(filenameMode.headerDescription)
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

                if filenameMode == .filenameToMetadata {
                    Toggle(
                        "Replace underscores with spaces in extracted values",
                        isOn: Binding(
                            get: { store.replaceUnderscoresWithSpaces },
                            set: { store.setReplaceUnderscoresWithSpaces($0) }
                        )
                    )
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
                    Text(filenameMode.templateTitle)
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        if activeTemplate.isEmpty {
                            Text(filenameMode.placeholderText)
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
        switch filenameMode {
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

                if store.isPlanning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if activeTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Add a Template",
                        systemImage: "text.cursor",
                        description: Text(filenameMode.emptyPreviewDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    switch filenameMode {
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
            targetCount: store.targetCount,
            selectionSummaryText: selectionSummaryText,
            isApplying: isApplying,
            isPlanning: store.isPlanning,
            phaseMessage: previewPhaseMessage,
            template: metadataExchangeTemplateBinding(for: selectedMode),
            pendingInsertion: $pendingExchangeFieldInsertion,
            externalSource: externalSourceBinding(for: selectedMode),
            externalSourceURL: externalSourceURL(for: selectedMode),
            externalFileError: externalFileError,
            includeCSVHeaderRow: Binding(
                get: { store.includeCSVHeaderRow },
                set: { store.setIncludeCSVHeaderRow($0) }
            ),
            firstCSVRowIsHeader: Binding(
                get: { store.firstCSVRowIsHeader },
                set: { store.setFirstCSVRowIsHeader($0) }
            ),
            clearBlankImportedValues: clearBlankImportedValuesBinding(for: selectedMode),
            result: store.displayResult(for: selectedMode),
            chooseExternalFile: {
                chooseExternalTextFile(for: selectedMode)
            }
        )
        .audiomatorSafeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func metadataExchangeTemplateBinding(for selectedMode: MetadataConverterMode) -> Binding<String> {
        Binding(
            get: { store.template(for: selectedMode) },
            set: { store.updateTemplate($0, for: selectedMode) }
        )
    }

    private func externalSourceBinding(for selectedMode: MetadataConverterMode) -> Binding<String> {
        Binding(
            get: { store.externalSource(for: selectedMode) },
            set: { store.setExternalSource($0, for: selectedMode) }
        )
    }

    private func clearBlankImportedValuesBinding(for selectedMode: MetadataConverterMode) -> Binding<Bool> {
        Binding(
            get: { store.clearBlankImportedValues(for: selectedMode) },
            set: { store.setClearBlankImportedValues($0, for: selectedMode) }
        )
    }

    private func externalSourceURL(for selectedMode: MetadataConverterMode) -> URL? {
        store.externalSourceURL(for: selectedMode)
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Close") {
                store.cancelPresentation()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Button(selectedConverterMode == .metadataFieldTransfer
                ? fieldTransferStore.operation.title
                : selectedConverterMode?.actionTitle ?? filenameMode.actionTitle) {
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
        guard let selectedConverterMode, canApply else { return }
        // Capture the exact displayed plan once. A pending or superseded plan
        // cannot dispatch, and completion is scoped to this presentation.
        guard let dispatch = store.beginDispatch(for: selectedConverterMode) else {
            if let scopeError = store.lastScopeRequestError {
                viewModel.presentMetadataWriteHUD(
                    style: .warning,
                    title: String(localized: "Allow Folder Access"),
                    subtitle: scopeError
                )
            }
            return
        }

        switch selectedConverterMode {
        case .metadataToFilename:
            applyRename(dispatch: dispatch)
        case .filenameToMetadata:
            applyFilenameMetadata(dispatch: dispatch)
        case .metadataToText:
            defer { _ = store.finishDispatch(dispatch) }
            exportMetadataText(dispatch: dispatch)
        case .textToMetadata:
            applyTextMetadata(dispatch: dispatch)
        case .metadataToCSV:
            defer { _ = store.finishDispatch(dispatch) }
            exportMetadataCSV(dispatch: dispatch)
        case .csvToMetadata:
            applyCSVMetadata(dispatch: dispatch)
        case .metadataFieldTransfer:
            applyFieldTransfer(dispatch: dispatch)
        }
    }

    private func applyRename(dispatch: MetadataFilenameConverterDispatch) {
        guard let plan = dispatch.result.renamePlan else { return }

        Task { @MainActor in
            let result = await viewModel.renameFiles(using: plan)
            guard store.finishDispatch(dispatch) else { return }
            if result.wasCancelled { return }
            if let failureMessage = result.failureMessage {
                renameFailureMessage = failureMessage
            } else if plan.issueCount == 0 {
                dismiss()
            }
        }
    }

    private func applyFilenameMetadata(dispatch: MetadataFilenameConverterDispatch) {
        guard let plan = dispatch.result.filenameMetadataPlan else { return }

        Task { @MainActor in
            let skipped = plan.rows.compactMap { row -> BatchMetadataWriteIssue? in
                guard row.writeEntry == nil, row.status != .unchanged else { return nil }
                return BatchMetadataWriteIssue(
                    fileName: row.currentName,
                    messages: [row.issueMessage ?? row.status.message]
                )
            }
            let summary = await viewModel.applyFilenameMetadataPlan(
                plan.writeEntries,
                skippedIssues: skipped
            )
            guard store.finishDispatch(dispatch) else { return }
            if let summary, summary.failureIssues.isEmpty, !plan.hasIssues {
                dismiss()
            }
        }
    }

    private func applyTextMetadata(dispatch: MetadataFilenameConverterDispatch) {
        guard let plan = dispatch.result.textImportPlan else { return }

        Task { @MainActor in
            _ = await viewModel.applyMetadataExchangeWriteEntries(
                plan.writeEntries,
                skippedIssues: Self.skippedExchangeIssues(for: plan)
            )
            _ = store.finishDispatch(dispatch)
        }
    }

    private func applyCSVMetadata(dispatch: MetadataFilenameConverterDispatch) {
        guard let plan = dispatch.result.csvImportPlan else { return }

        Task { @MainActor in
            _ = await viewModel.applyMetadataExchangeWriteEntries(
                plan.writeEntries,
                skippedIssues: Self.skippedExchangeIssues(for: plan)
            )
            _ = store.finishDispatch(dispatch)
        }
    }

    private func applyFieldTransfer(dispatch: MetadataFilenameConverterDispatch) {
        guard let plan = dispatch.result.fieldTransferPlan else { return }

        let progressTitle = fieldTransferStore.operation.progressTitle
        Task { @MainActor in
            _ = await viewModel.applyMetadataExchangeWriteEntries(
                plan.writeEntries,
                skippedIssues: Self.skippedExchangeIssues(for: plan),
                progressTitle: progressTitle
            )
            _ = store.finishDispatch(dispatch)
        }
    }

    private func exportMetadataText(dispatch: MetadataFilenameConverterDispatch) {
        guard let text = dispatch.encodedExportText else { return }
        saveText(text, defaultFileName: "AudioMator Metadata.txt", fileExtension: "txt")
    }

    private func exportMetadataCSV(dispatch: MetadataFilenameConverterDispatch) {
        guard let text = dispatch.encodedExportText else { return }
        saveText(text, defaultFileName: "AudioMator Metadata.csv", fileExtension: "csv")
    }

    private func chooseExternalTextFile(for selectedMode: MetadataConverterMode) {
        MacDocumentPicker.pickTextFile { url in
            guard let url else { return }
            guard selectedMode == .textToMetadata || selectedMode == .csvToMetadata else { return }

            store.loadExternalTextFile(from: url, for: selectedMode) { url in
                try await MetadataExchangeExternalTextFileLoader.load(from: url)
            }
        }
    }

    private func resetForNewPresentation() {
        fieldTransferStore.reset()
        pendingFieldInsertion = nil
        pendingExchangeFieldInsertion = nil
        renameFailureMessage = nil
    }

    private static func skippedExchangeIssues(
        for plan: MetadataExchangeImportPlan
    ) -> [BatchMetadataWriteIssue] {
        plan.rows.compactMap { row in
            guard row.writeEntry == nil, row.status != .unchanged else { return nil }
            return BatchMetadataWriteIssue(
                fileName: row.fileName,
                messages: [row.issueMessage ?? row.status.title]
            )
        }
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
                title: String(localized: "Metadata Couldn’t Be Exported"),
                subtitle: (error as NSError).localizedDescription
            )
        }
    }
}
