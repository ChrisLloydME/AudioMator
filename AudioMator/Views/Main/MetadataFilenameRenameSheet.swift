import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MetadataFilenameRenameSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    let targetFileIDs: [AudioFile.ID]
    @Binding var isPresented: Bool

    @State private var renameTemplate: String = ""
    @State private var isApplying: Bool = false
    @State private var isTemplateDropTarget: Bool = false

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18

    private var targetFiles: [AudioFile] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        return targetFileIDs.compactMap { filesByID[$0] }
    }

    private var renamePlan: FileRenamePlan {
        makeFileRenamePlan(template: renameTemplate, targetFiles: targetFiles)
    }

    private var selectionSummaryText: String {
        targetFiles.count == 1
            ? "1 selected file"
            : "\(targetFiles.count) selected files"
    }

    private var previewStatusMessage: String {
        if targetFiles.isEmpty {
            return "Select files in the center list first."
        }

        if renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    private var previewStatusSymbolName: String {
        if renamePlan.hasIssues {
            return "exclamationmark.triangle.fill"
        }

        if renamePlan.readyCount > 0 {
            return "checkmark.circle.fill"
        }

        return "info.circle.fill"
    }

    private var previewStatusTint: Color {
        if renamePlan.hasIssues {
            return .orange
        }

        if renamePlan.readyCount > 0 {
            return .green
        }

        return .secondary
    }

    private var canApply: Bool {
        renamePlan.canApply && !isApplying
    }

    var body: some View {
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
        .frame(width: 760, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rename Files from Metadata")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Build a filename pattern with text and metadata tokens. Click or drag a token to insert it.")
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
                Text("AudioMator keeps each file's current extension. The template changes only the filename.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(FileRenameMetadataField.allCases, id: \.self) { field in
                        metadataChip(for: field)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rename template")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        if renameTemplate.isEmpty {
                            Text("Example: {{artist}} - {{title}}")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                        }

                        TextEditor(text: $renameTemplate)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
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
                            .stroke(
                                isTemplateDropTarget ? Color.accentColor : Color.secondary.opacity(0.18),
                                lineWidth: isTemplateDropTarget ? 1.5 : 1
                            )
                    )
                    .onDrop(of: [UTType.text.identifier], isTargeted: $isTemplateDropTarget, perform: handleTemplateDrop)
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

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Label(previewStatusMessage, systemImage: previewStatusSymbolName)
                    .font(.subheadline)
                    .foregroundStyle(previewStatusTint)

                if renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Add a Template",
                        systemImage: "text.cursor",
                        description: Text("Add text or metadata tokens to preview the new filenames.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    Table(renamePlan.rows) {
                        TableColumn("Current Name") { row in
                            Text(row.currentName)
                                .lineLimit(1)
                        }
                        .width(min: 220, ideal: 250)

                        TableColumn("Preview") { row in
                            Text(row.previewName)
                                .lineLimit(2)
                                .foregroundStyle(row.status.isError ? Color.orange : Color.primary)
                        }
                        .width(min: 260, ideal: 320)

                        TableColumn("Status") { row in
                            HStack(spacing: 6) {
                                Image(systemName: row.status.symbolName)
                                    .foregroundStyle(row.status.tint)

                                Text(row.status.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(row.status.tint)
                            }
                            .help(row.status.message)
                        }
                        .width(min: 120, ideal: 140)
                    }
                    .frame(minHeight: 300)
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
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Button("Rename") {
                applyRename()
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
        .help("Click or drag \(field.token) into the template")
        .onDrag {
            NSItemProvider(object: field.token as NSString)
        }
    }

    private func insertFieldToken(_ field: FileRenameMetadataField) {
        guard !isApplying else { return }
        renameTemplate.append(field.token)
    }

    private func handleTemplateDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String else { return }

            Task { @MainActor in
                guard !isApplying else { return }
                renameTemplate.append(string)
            }
        }

        return true
    }

    private func applyRename() {
        let plan = renamePlan
        guard plan.canApply else { return }

        isApplying = true

        Task { @MainActor in
            let result = await viewModel.renameFiles(using: plan)
            isApplying = false

            if result.didSucceed && renamePlan.issueCount == 0 {
                isPresented = false
            }
        }
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
