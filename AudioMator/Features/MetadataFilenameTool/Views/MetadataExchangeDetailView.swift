import SwiftUI

#if os(macOS)
import AppKit

struct MetadataExchangeDetailView: View {
    let selectedMode: MetadataConverterMode
    let targetCount: Int
    let selectionSummaryText: String
    let isApplying: Bool
    @Binding var template: String
    @Binding var pendingInsertion: MetadataExchangeTemplateEditorInsertion?
    @Binding var externalSource: String
    let externalSourceURL: URL?
    let externalFileError: String?
    @Binding var includeCSVHeaderRow: Bool
    @Binding var firstCSVRowIsHeader: Bool
    @Binding var clearBlankImportedValues: Bool
    let metadataTextExportPlan: MetadataTextExportPlan
    let textMetadataImportPlan: MetadataExchangeImportPlan
    let metadataCSVExportPlan: MetadataCSVExportPlan
    let csvMetadataImportPlan: MetadataExchangeImportPlan
    let chooseExternalFile: () -> Void

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18
    private let controlRadius: CGFloat = 12
    private let contentInset: CGFloat = 20

    var body: some View {
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
    }

    private var header: some View {
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

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text(setupDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedMode == .textToMetadata || selectedMode == .csvToMetadata {
                    externalSourceControls
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
                    ForEach(fieldPalette) { field in
                        metadataExchangeChip(field)
                    }
                }

                templateEditor
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var externalSourceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(externalSourceURL == nil ? "Choose File…" : "Change File…") {
                    chooseExternalFile()
                }
                .disabled(isApplying)

                if let externalSourceURL {
                    Text(externalSourceURL.lastPathComponent)
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

            TextEditor(text: $externalSource)
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

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(templateTitle)
                .font(.headline)

            MetadataExchangeTemplateEditor(
                template: $template,
                pendingInsertion: $pendingInsertion,
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

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Label(statusMessage, systemImage: statusSymbol)
                    .font(.subheadline)
                    .foregroundStyle(statusTint)

                previewContent
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
    private var previewContent: some View {
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

    private var setupDescription: String {
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

    private var templateTitle: String {
        switch selectedMode {
        case .metadataToCSV, .csvToMetadata:
            return L10n.string("Column template")
        case .metadataToText, .textToMetadata:
            return L10n.string("Text template")
        case .metadataToFilename, .filenameToMetadata:
            return L10n.string("Template")
        }
    }

    private var fieldPalette: [MetadataExchangeField] {
        switch selectedMode {
        case .metadataToText, .metadataToCSV:
            return MetadataExchangeField.exportPalette
        case .textToMetadata, .csvToMetadata:
            return MetadataExchangeField.importPalette
        case .metadataToFilename, .filenameToMetadata:
            return []
        }
    }

    private func metadataExchangeChip(_ field: MetadataExchangeField) -> some View {
        Button {
            guard !isApplying else { return }
            pendingInsertion = MetadataExchangeTemplateEditorInsertion(field: field)
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

    private var statusMessage: String {
        switch selectedMode {
        case .metadataToText:
            return MetadataFilenameStatusPresentation.textExportMessage(
                targetCount: targetCount,
                plan: metadataTextExportPlan
            )
        case .textToMetadata:
            return MetadataFilenameStatusPresentation.importMessage(
                targetCount: targetCount,
                plan: textMetadataImportPlan
            )
        case .metadataToCSV:
            return MetadataFilenameStatusPresentation.csvExportMessage(
                targetCount: targetCount,
                plan: metadataCSVExportPlan
            )
        case .csvToMetadata:
            return MetadataFilenameStatusPresentation.importMessage(
                targetCount: targetCount,
                plan: csvMetadataImportPlan
            )
        case .metadataToFilename, .filenameToMetadata:
            return ""
        }
    }

    private var statusSymbol: String {
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

    private var statusTint: Color {
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
}
#endif
