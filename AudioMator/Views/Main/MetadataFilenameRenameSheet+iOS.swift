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

    private var targetFiles: [AudioFile] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        return store.targetFileIDs.compactMap { filesByID[$0] }
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
            .navigationTitle("Filename & Metadata")
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
            } else {
                List {
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
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var canApply: Bool {
        switch mode {
        case .metadataToFilename:
            return renamePlan.canApply
        case .filenameToMetadata:
            return filenameMetadataPlan.canApply
        }
    }

    private func applyCurrentPlan() async {
        guard !isApplying else { return }
        isApplying = true

        switch mode {
        case .metadataToFilename:
            _ = await viewModel.renameFiles(using: renamePlan)
        case .filenameToMetadata:
            await viewModel.applyFilenameMetadataPlan(filenameMetadataPlan.writeEntries)
        }

        isApplying = false
        dismiss()
    }
}
#endif
