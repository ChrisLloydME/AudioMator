import SwiftUI

private let textImportInnerRadius: CGFloat = 12
private let textImportSectionInset: CGFloat = 10
private let textImportControlColumnWidth: CGFloat = 260
private let textImportContentInset: CGFloat = 20

private enum TextMetadataImportDelimiter: String, CaseIterable, Identifiable {
    case newline
    case englishComma
    case chineseComma
    case englishSemicolon
    case chineseSemicolon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newline:
            return L10n.string("Newline")
        case .englishComma:
            return L10n.string("English Comma (,)")
        case .chineseComma:
            return L10n.string("Chinese Comma (，)")
        case .englishSemicolon:
            return L10n.string("English Semicolon (;)")
        case .chineseSemicolon:
            return L10n.string("Chinese Semicolon (；)")
        }
    }

    var caption: String {
        switch self {
        case .newline:
            return L10n.string("Use one line per selected file.")
        case .englishComma:
            return L10n.string("Split on the ASCII comma.")
        case .chineseComma:
            return L10n.string("Split on the full-width comma.")
        case .englishSemicolon:
            return L10n.string("Split on the ASCII semicolon.")
        case .chineseSemicolon:
            return L10n.string("Split on the full-width semicolon.")
        }
    }

    func split(_ text: String) -> [String] {
        let source: String
        let separator: String

        switch self {
        case .newline:
            source = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            separator = "\n"
        case .englishComma:
            source = text
            separator = ","
        case .chineseComma:
            source = text
            separator = "，"
        case .englishSemicolon:
            source = text
            separator = ";"
        case .chineseSemicolon:
            source = text
            separator = "；"
        }

        guard !source.isEmpty else { return [""] }

        var components = source.components(separatedBy: separator)
        if source.hasSuffix(separator), components.count > 1 {
            components.removeLast()
        }

        return components.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private enum TextMetadataImportPreviewStatus {
    case ready
    case missingImportedValue
    case extraImportedValue

    var title: String {
        switch self {
        case .ready:
            return L10n.string("Ready")
        case .missingImportedValue:
            return L10n.string("Missing Value")
        case .extraImportedValue:
            return L10n.string("Unused Value")
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .missingImportedValue:
            return "exclamationmark.triangle.fill"
        case .extraImportedValue:
            return "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .missingImportedValue:
            return .orange
        case .extraImportedValue:
            return .secondary
        }
    }
}

private struct TextMetadataImportPreviewRow: Identifiable {
    let id: Int
    let position: Int
    let fileName: String
    let currentValue: String
    let importedValue: String
    let status: TextMetadataImportPreviewStatus
}

struct TextMetadataImportSheet: View {
    @ObservedObject var viewModel: AudioViewModel

    let targetFiles: [AudioFile]
    @Binding var isPresented: Bool

    @State private var selectedTextFileURL: URL?
    @State private var sourceText: String = ""
    @State private var selectedDelimiter: TextMetadataImportDelimiter = .newline
    @State private var selectedField: MultiFileEditableTextField = .title
    @State private var fileLoadError: String?
    @State private var isApplying: Bool = false

    private var sectionRadius: CGFloat {
        textImportInnerRadius + textImportSectionInset
    }

    private var hasLoadedSourceFile: Bool {
        selectedTextFileURL != nil && fileLoadError == nil
    }

    private var importedValues: [String] {
        guard hasLoadedSourceFile else { return [] }
        return selectedDelimiter.split(sourceText)
    }

    private var previewRows: [TextMetadataImportPreviewRow] {
        let rowCount = max(targetFiles.count, importedValues.count)

        return (0..<rowCount).map { index in
            let file = index < targetFiles.count ? targetFiles[index] : nil
            let importedValue = index < importedValues.count ? importedValues[index] : nil

            let status: TextMetadataImportPreviewStatus
            if file != nil, importedValue != nil {
                status = .ready
            } else if file != nil {
                status = .missingImportedValue
            } else {
                status = .extraImportedValue
            }

            return TextMetadataImportPreviewRow(
                id: index,
                position: index + 1,
                fileName: file?.url.lastPathComponent ?? "—",
                currentValue: file.map { previewValueText(for: selectedField.value(from: $0)) } ?? "—",
                importedValue: previewValueText(for: importedValue),
                status: status
            )
        }
    }

    private var previewStatusMessage: String {
        guard hasLoadedSourceFile else {
            return L10n.string("Choose a text file to preview how values map to the selected rows.")
        }

        if importedValues.count == targetFiles.count {
            return L10n.string("Counts match. Applying will overwrite only the selected field.")
        }

        if importedValues.count < targetFiles.count {
            return L10n.string("The text file doesn't provide enough values for all selected files.")
        }

        return L10n.string("The text file contains more values than the current selection.")
    }

    private var canApply: Bool {
        hasLoadedSourceFile &&
            !isApplying &&
            !targetFiles.isEmpty &&
            importedValues.count == targetFiles.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                configurationSection
                previewSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, textImportContentInset)
            .padding(.top, textImportContentInset)
            .padding(.bottom, textImportContentInset)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 860, height: 640)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Import Metadata Field from Text")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Choose a text file, split it into one value per row, then write the selected field in center-list order.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label("\(targetFiles.count) selected file(s)", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )

                Text("Unsaved inspector edits aren't included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                configurationRow(
                    title: "Text file",
                    caption: selectedTextFileURL?.path ?? "Choose a plain-text file."
                ) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button(selectedTextFileURL == nil ? "Choose File…" : "Change File…") {
                            chooseTextFile()
                        }
                        .disabled(isApplying)

                        if let selectedTextFileURL {
                            Text(selectedTextFileURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: textImportControlColumnWidth, alignment: .trailing)
                        }
                    }
                }

                Divider()

                configurationRow(
                    title: "Delimiter",
                    caption: selectedDelimiter.caption
                ) {
                    Picker("", selection: $selectedDelimiter) {
                        ForEach(TextMetadataImportDelimiter.allCases) { delimiter in
                            Text(delimiter.title).tag(delimiter)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isApplying || !hasLoadedSourceFile)
                }

                Divider()

                configurationRow(
                    title: "Target field",
                    caption: "Only this field will be rewritten for each selected row."
                ) {
                    Picker("", selection: $selectedField) {
                        ForEach(MultiFileEditableTextField.allCases, id: \.self) { field in
                            Text(field.displayName).tag(field)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isApplying)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(textImportSectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                if let fileLoadError {
                    Label(fileLoadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                } else {
                    Label(
                        previewStatusMessage,
                        systemImage: importedValues.count == targetFiles.count && hasLoadedSourceFile
                            ? "checkmark.circle.fill"
                            : "info.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(importedValues.count == targetFiles.count && hasLoadedSourceFile ? Color.green : Color.secondary)
                }

                if hasLoadedSourceFile {
                    #if os(iOS)
                    List {
                        Section {
                            ForEach(previewRows) { row in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\(row.position)")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)

                                        Text(row.fileName)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)

                                        Spacer(minLength: 0)

                                        Image(systemName: row.status.symbolName)
                                            .foregroundStyle(row.status.tint)
                                            .accessibilityLabel(row.status.title)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        previewValueLine("Current \(selectedField.displayName)", value: row.currentValue)
                                        previewValueLine("Imported Value", value: row.importedValue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .iPadRoundedGroupedListStyle()
                    .frame(minHeight: 280)
                    #else
                    previewTable
                        .frame(minHeight: 280)
                    #endif
                } else {
                    ContentUnavailableView(
                        "Choose a File",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Choose a text file to preview each imported value.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(textImportSectionInset)
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
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Button("Apply") {
                applyImport()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, textImportContentInset)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func configurationRow<Content: View>(
        title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(iOS)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                configurationLabel(title: title, caption: caption)
                    .frame(maxWidth: .infinity, alignment: .leading)

                content()
                    .frame(maxWidth: textImportControlColumnWidth, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 10) {
                configurationLabel(title: title, caption: caption)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        HStack(alignment: .top, spacing: 16) {
            configurationLabel(title: title, caption: caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(width: textImportControlColumnWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private func configurationLabel(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if os(macOS)
    private var previewTable: some View {
        Table(previewRows) {
            TableColumn("#") { row in
                Text("\(row.position)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .width(36)

            TableColumn("File") { row in
                Text(row.fileName)
                    .lineLimit(1)
            }
            .width(min: 180, ideal: 220)

            TableColumn("Current \(selectedField.displayName)") { row in
                Text(row.currentValue)
                    .lineLimit(2)
                    .foregroundStyle(row.currentValue == "Empty" ? Color.secondary : Color.primary)
            }
            .width(min: 170, ideal: 210)

            TableColumn("Imported Value") { row in
                Text(row.importedValue)
                    .lineLimit(2)
                    .foregroundStyle(row.importedValue == "Empty" ? Color.secondary : Color.primary)
            }
            .width(min: 170, ideal: 210)

            TableColumn("") { row in
                Image(systemName: row.status.symbolName)
                    .foregroundStyle(row.status.tint)
                    .frame(maxWidth: .infinity)
                    .help(row.status.title)
            }
            .width(34)
        }
    }
    #endif

    #if os(iOS)
    private func previewValueLine(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(value == "Empty" ? Color.secondary : Color.primary)
                .lineLimit(2)
        }
    }
    #endif

    private func chooseTextFile() {
        PlatformDocumentPicker.pickTextFile { url in
            guard let url else { return }

            Task { @MainActor in
                do {
                    sourceText = try loadTextFile(from: url)
                    selectedTextFileURL = url
                    fileLoadError = nil
                } catch {
                    selectedTextFileURL = nil
                    sourceText = ""
                    fileLoadError = (error as NSError).localizedDescription
                }
            }
        }
    }

    private func applyImport() {
        let values = importedValues
        let files = targetFiles
        let field = selectedField

        isApplying = true

        Task { @MainActor in
            await viewModel.importMetadataFieldValues(values, to: field, for: files)

            isApplying = false
            isPresented = false
        }
    }

    private func loadTextFile(from url: URL) throws -> String {
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
            domain: "TextMetadataImportSheet",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "AudioMator couldn't read that file as plain text."
            ]
        )
    }

    private func previewValueText(for value: String?) -> String {
        guard let value else { return "—" }

        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ↩ ")

        return normalized.isEmpty ? "Empty" : normalized
    }
}
