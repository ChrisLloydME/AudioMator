import SwiftUI
#if os(macOS)
import AppKit
#endif
import Combine
import TagLibAudioMetadata

#if os(macOS)

struct MetadataEditorTarget: Identifiable, Hashable {
    let id: AudioFile.ID
    let url: URL
    let expectedFileFingerprint: AudioFileFingerprint?

    init(file: AudioFile) {
        self.id = file.id
        self.url = file.url
        self.expectedFileFingerprint = file.fileFingerprint
    }

    nonisolated var fileName: String {
        url.lastPathComponent
    }
}

private struct MetadataTextUtilitiesContext: Identifiable {
    let fieldKeys: Set<String>

    var id: String {
        fieldKeys.sorted().joined(separator: "\u{1F}")
    }
}

@MainActor
final class MetadataEditorStore: ObservableObject {
    private struct LoadedState {
        let propertyMaps: [AudioFile.ID: [String: String]]
        let errorMessage: String?
    }

    @Published private(set) var targets: [MetadataEditorTarget] = []
    @Published private(set) var originalPropertyMaps: [AudioFile.ID: [String: String]] = [:]
    @Published private(set) var draftPropertyMaps: [AudioFile.ID: [String: String]] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadErrorMessage: String?
    @Published var selectedFieldKeys: Set<String> = []

    private let metadataPipeline: any AudioMetadataPipeline
    private var loadToken = UUID()

    init(metadataPipeline: any AudioMetadataPipeline) {
        self.metadataPipeline = metadataPipeline
    }

    var hasUnsavedChanges: Bool {
        draftPropertyMaps != originalPropertyMaps
    }

    var isEditable: Bool {
        !isLoading &&
        loadErrorMessage == nil &&
        !targets.isEmpty &&
        originalPropertyMaps.count == targets.count
    }

    fileprivate var rows: [MetadataEditorRow] {
        MetadataEditorDraftRows.makeRows(targets: targets, draftPropertyMaps: draftPropertyMaps)
    }

    var selectionSummaryText: String {
        if targets.count == 1, let target = targets.first {
            return target.fileName
        }

        return "\(targets.count) selected files"
    }

    var selectedFieldKey: String? {
        get {
            selectedFieldKeys.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }.first
        }
        set {
            if let newValue {
                selectedFieldKeys = [newValue]
            } else {
                selectedFieldKeys = []
            }
        }
    }

    var selectionDetailText: String {
        if targets.count == 1, let target = targets.first {
            return target.url.path
        }

        return L10n.string("Only non-empty metadata fields are shown. Mixed values appear as Multiple Values, and changes apply to every selected file.")
    }

    func present(targetFiles: [AudioFile]) {
        let targets = targetFiles.map(MetadataEditorTarget.init(file:))
        let token = UUID()

        self.targets = targets
        self.originalPropertyMaps = [:]
        self.draftPropertyMaps = [:]
        self.loadErrorMessage = nil
        self.selectedFieldKeys = []
        self.isLoading = true
        self.loadToken = token
        let metadataPipeline = self.metadataPipeline

        Task.detached(priority: .userInitiated) { [targets, token, metadataPipeline] in
            let loadedState = Self.loadState(for: targets, metadataPipeline: metadataPipeline)

            await MainActor.run {
                guard self.loadToken == token else { return }
                self.originalPropertyMaps = loadedState.propertyMaps
                self.draftPropertyMaps = loadedState.propertyMaps
                self.loadErrorMessage = loadedState.errorMessage
                self.isLoading = false
                if loadedState.errorMessage == nil {
                    self.realignSelection(preferred: self.selectedFieldKey)
                } else {
                    self.selectedFieldKeys = []
                }
            }
        }
    }

    func discardChanges() {
        draftPropertyMaps = originalPropertyMaps
        realignSelection(preferred: selectedFieldKey)
    }

    fileprivate func makeAddFieldContext() -> MetadataFieldEditorContext {
        MetadataFieldEditorContext(
            mode: .add,
            key: nil,
            initialValue: "",
            isMixed: false
        )
    }

    fileprivate func makeEditFieldContext() -> MetadataFieldEditorContext? {
        guard isEditable, let key = selectedFieldKey else { return nil }

        let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
        let firstValue = values.first ?? ""
        let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }

        return MetadataFieldEditorContext(
            mode: .edit,
            key: key,
            initialValue: isUniform ? firstValue : "",
            isMixed: !isUniform
        )
    }

    func upsertField(key: String, value: String) {
        guard isEditable else { return }
        let normalizedKey = Self.normalizedFieldKey(key)
        let normalizedValue = Self.normalizedFieldValue(value)

        guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap[normalizedKey] = normalizedValue
            draftPropertyMaps[target.id] = propertyMap
        }

        selectedFieldKey = normalizedKey
    }

    fileprivate func commitFieldEntry(
        context: MetadataFieldEditorContext,
        key: String,
        value: String
    ) {
        guard isEditable else { return }
        let normalizedValue = Self.normalizedFieldValue(value)

        switch context.mode {
        case .add:
            upsertField(key: key, value: normalizedValue)
        case .edit:
            guard let originalKey = context.key else { return }

            if normalizedValue.isEmpty {
                deleteField(named: originalKey)
            } else {
                upsertField(key: originalKey, value: normalizedValue)
            }
        }
    }

    func previewTextUtility(
        pipeline: TextEditPipeline,
        fieldKeys: Set<String>
    ) -> [MetadataTextUtilityPreviewRow] {
        guard !fieldKeys.isEmpty else { return [] }

        let sortedKeys = fieldKeys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return targets.flatMap { target in
            sortedKeys.compactMap { key in
                guard let currentValue = draftPropertyMaps[target.id]?[key] else { return nil }
                return MetadataTextUtilityPreviewRow(
                    targetID: target.id,
                    fileName: target.fileName,
                    fieldKey: key,
                    currentValue: currentValue,
                    previewValue: pipeline.applying(to: currentValue)
                )
            }
        }
    }

    func applyTextUtility(
        pipeline: TextEditPipeline,
        fieldKeys: Set<String>
    ) {
        guard isEditable, !fieldKeys.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]

            for key in fieldKeys {
                guard let currentValue = propertyMap[key] else { continue }
                let nextValue = pipeline.applying(to: currentValue)

                if nextValue.isEmpty {
                    propertyMap.removeValue(forKey: key)
                } else {
                    propertyMap[key] = nextValue
                }
            }

            draftPropertyMaps[target.id] = propertyMap
        }

        realignSelection(preferred: selectedFieldKey)
    }

    func deleteSelectedField() {
        guard isEditable, !selectedFieldKeys.isEmpty else { return }

        for key in selectedFieldKeys {
            deleteField(named: key, realignAfterDelete: false)
        }

        realignSelection(preferred: nil)
    }

    func deleteField(named key: String, realignAfterDelete: Bool = true) {
        guard isEditable, !key.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap.removeValue(forKey: key)
            draftPropertyMaps[target.id] = propertyMap
        }

        if realignAfterDelete {
            realignSelection(preferred: nil)
        }
    }

    private func realignSelection(preferred: String?) {
        selectedFieldKeys = MetadataEditorDraftRows.realignedSelection(
            currentSelection: selectedFieldKeys,
            preferred: preferred,
            rows: rows
        )
    }

    nonisolated private static func loadState(
        for targets: [MetadataEditorTarget],
        metadataPipeline: any AudioMetadataPipeline
    ) -> LoadedState {
        var propertyMaps: [AudioFile.ID: [String: String]] = [:]
        var failures: [String] = []

        for target in targets {
            do {
                propertyMaps[target.id] = try metadataPipeline.rawMetadataPropertyMap(for: target.url)
            } catch {
                failures.append("\(target.fileName): \((error as NSError).localizedDescription)")
            }
        }

        let errorMessage: String?
        if failures.isEmpty {
            errorMessage = nil
        } else if failures.count == 1 {
            errorMessage = failures[0]
        } else {
            errorMessage = ([ "\(failures.count) files could not be read." ] + failures.prefix(3)).joined(separator: "\n")
        }

        return LoadedState(propertyMaps: propertyMaps, errorMessage: errorMessage)
    }

    nonisolated private static func normalizedFieldKey(_ key: String) -> String {
        MetadataFieldSuggestion.resolvedKey(for: key)
    }

    nonisolated private static func normalizedFieldValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MetadataEditorWindowView: View {
    static let windowID = "metadata-editor"

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var store: MetadataEditorStore

    @Environment(\.dismiss) private var dismiss

    @State private var editorContext: MetadataFieldEditorContext?
    @State private var utilityContext: MetadataTextUtilitiesContext?
    @State private var isApplyingChanges: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
                footer
            }
            .padding(20)
            .frame(minWidth: 820, idealWidth: 920, maxWidth: 1040, minHeight: 540, idealHeight: 640)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(AppWindowTitle.metadataEditor)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
        }
        .sheet(item: $editorContext) { context in
            MetadataFieldEntrySheet(context: context) { key, value in
                store.commitFieldEntry(context: context, key: key, value: value)
            }
        }
        .sheet(item: $utilityContext) { context in
            MetadataTextUtilitiesSheet(store: store, fieldKeys: context.fieldKeys) {
                utilityContext = nil
            }
        }
        .onDisappear {
            if !isApplyingChanges {
                store.discardChanges()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if store.hasUnsavedChanges {
                    Text("Unsaved Changes")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                }
            }

            Text(store.selectionSummaryText)
                .font(.headline)

            Text(store.selectionDetailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            VStack(spacing: 10) {
                Spacer()
                ProgressView("Loading metadata…".localizedUI)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.loadErrorMessage {
            ContentUnavailableView(
                "Unable to Read Metadata",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.rows.isEmpty {
            ContentUnavailableView(
                "No Metadata Fields",
                systemImage: "tag",
                description: Text(
                    store.loadErrorMessage ?? "No non-empty TagLib metadata fields were found for the current selection."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MetadataEditorTable(
                rows: store.rows,
                selectedFieldKeys: $store.selectedFieldKeys,
                onEditField: {
                    editorContext = store.makeEditFieldContext()
                },
                onDeleteField: { key in
                    store.deleteField(named: key)
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Edit Selected…") {
                editorContext = store.makeEditFieldContext()
            }
            .disabled(store.selectedFieldKeys.count != 1 || !store.isEditable || isApplyingChanges)

            Button("Add Field…") {
                editorContext = store.makeAddFieldContext()
            }
            .disabled(!store.isEditable || isApplyingChanges)

            Button("Delete Field", role: .destructive) {
                store.deleteSelectedField()
            }
            .disabled(store.selectedFieldKeys.isEmpty || !store.isEditable || isApplyingChanges)

            Button("Utilities…") {
                utilityContext = MetadataTextUtilitiesContext(fieldKeys: store.selectedFieldKeys)
            }
            .disabled(store.selectedFieldKeys.isEmpty || !store.isEditable || isApplyingChanges)

            Spacer()

            if isApplyingChanges {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Cancel") {
                store.discardChanges()
                dismiss()
            }
            .disabled(isApplyingChanges)

            Button("Done") {
                Task {
                    await commitAndDismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.isLoading || isApplyingChanges)
        }
    }

    private func commitAndDismiss() async {
        guard !isApplyingChanges else { return }

        if !store.hasUnsavedChanges {
            dismiss()
            return
        }

        isApplyingChanges = true
        await viewModel.applyRawMetadataPropertyMaps(store.draftPropertyMaps, to: store.targets)
        isApplyingChanges = false
        dismiss()
    }
}

#endif
