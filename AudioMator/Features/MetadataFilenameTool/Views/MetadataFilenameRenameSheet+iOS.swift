#if os(iOS)
import SwiftUI
import Combine

private enum MetadataFilenameToolMode: String, CaseIterable, Identifiable {
    case metadataToFilename
    case filenameToMetadata

    var id: String { rawValue }

    var title: String {
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
}

@MainActor
final class MetadataFilenameToolStore: ObservableObject {
    @Published private(set) var targetFileIDs: [AudioFile.ID] = []

    func present(targetFileIDs: [AudioFile.ID]) {
        var seenIDs = Set<AudioFile.ID>()
        self.targetFileIDs = targetFileIDs.filter { seenIDs.insert($0).inserted }
    }
}

private struct MetadataFilenameTargetResolution {
    let files: [AudioFile]
    let isComplete: Bool
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
    @State private var renameFailureMessage: String?

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

    private var activeTemplateBinding: Binding<String> {
        Binding(
            get: {
                switch mode {
                case .metadataToFilename:
                    return metadataToFilenameTemplate
                case .filenameToMetadata:
                    return filenameToMetadataTemplate
                }
            },
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(MetadataFilenameToolMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Template")
                        .font(.headline)

                    TextEditor(text: activeTemplateBinding)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(platformColor: .audiomatorTextBackground))
                        )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeFieldPalette) { field in
                            Button(field.displayName) {
                                activeTemplateBinding.wrappedValue += field.token
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .audiomatorScrollEdgeEffect(.soft, for: .horizontal)

                if mode == .filenameToMetadata {
                    Toggle("Replace underscores with spaces", isOn: $replaceUnderscoresWithSpaces)
                }

                previewSection

                HStack {
                    Button("Done") {
                        dismiss()
                    }

                    Spacer()

                    if isApplying {
                        ProgressView()
                    }

                    Button(mode.actionTitle) {
                        Task { await applyCurrentPlan() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply || isApplying)
                }
            }
            .padding(20)
            .navigationTitle(AppWindowTitle.filenameMetadata)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isApplying)
                }
            }
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
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline)

            if targetFiles.isEmpty {
                ContentUnavailableView(
                    "No Selected Files",
                    systemImage: "music.note.list",
                    description: Text("Select files in the current session first.")
                )
            } else if let validationMessage = activeValidationMessage {
                ContentUnavailableView(
                    "Invalid Template",
                    systemImage: "exclamationmark.triangle",
                    description: Text(validationMessage)
                )
            } else {
                List {
                    Section {
                        if mode == .metadataToFilename {
                            ForEach(Array(renamePlan.rows), id: \.id) { (row: FileRenamePreviewRow) in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.currentName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(row.previewName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(row.status.message)
                                        .font(.caption)
                                        .foregroundStyle(row.status.isError ? .orange : .secondary)
                                }
                            }
                        } else {
                            ForEach(Array(filenameMetadataPlan.rows), id: \.id) { (row: FilenameMetadataPreviewRow) in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.currentName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(row.status.message)
                                        .font(.caption)
                                        .foregroundStyle(row.status.isError ? .orange : .secondary)
                                    if !row.changes.isEmpty {
                                        Text(row.changes.map { "\($0.field.displayName): \($0.extractedValue)" }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .iPadRoundedGroupedListStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var canApply: Bool {
        guard
            targetResolution.isComplete,
            !isApplying,
            viewModel.metadataSaveProgress == nil,
            !viewModel.hasUnsavedInspectorChanges
        else {
            return false
        }

        switch mode {
        case .metadataToFilename:
            return renamePlan.canApply
        case .filenameToMetadata:
            return filenameMetadataPlan.canApply
        }
    }

    private var activeValidationMessage: String? {
        switch mode {
        case .metadataToFilename:
            return renamePlan.validationMessage
        case .filenameToMetadata:
            return filenameMetadataPlan.validationMessage
        }
    }

    private func applyCurrentPlan() async {
        guard canApply else { return }
        isApplying = true

        switch mode {
        case .metadataToFilename:
            let result = await viewModel.renameFiles(using: renamePlan)
            if let failureMessage = result.failureMessage {
                renameFailureMessage = failureMessage
                isApplying = false
                return
            }
        case .filenameToMetadata:
            guard let summary = await viewModel.applyFilenameMetadataPlan(filenameMetadataPlan.writeEntries),
                  summary.failureIssues.isEmpty else {
                isApplying = false
                return
            }
        }

        isApplying = false
        dismiss()
    }
}
#endif
