#if os(iOS)
import SwiftUI
import Combine

struct MetadataEditorTarget: Identifiable, Hashable {
    let id: AudioFile.ID
    let url: URL

    init(file: AudioFile) {
        self.id = file.id
        self.url = file.url
    }

    nonisolated var fileName: String {
        url.lastPathComponent
    }
}

private struct MetadataEditorRow: Identifiable, Hashable {
    let key: String
    let value: String
    let isMixed: Bool

    var id: String { key }
}

private struct MetadataFieldEditorContext: Identifiable {
    let key: String?
    let initialValue: String

    var id: String { key ?? "new-field" }
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
    @Published var selectedFieldKey: String?

    private let metadataPipeline: any AudioMetadataPipeline
    private var loadToken = UUID()

    init(metadataPipeline: any AudioMetadataPipeline) {
        self.metadataPipeline = metadataPipeline
    }

    var hasUnsavedChanges: Bool {
        draftPropertyMaps != originalPropertyMaps
    }

    fileprivate var rows: [MetadataEditorRow] {
        let allKeys = Set(draftPropertyMaps.values.flatMap(\.keys))
        return allKeys.sorted().map { key in
            let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
            let firstValue = values.first ?? ""
            let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }
            return MetadataEditorRow(key: key, value: firstValue, isMixed: !isUniform)
        }
    }

    func present(targetFiles: [AudioFile]) {
        let targets = targetFiles.map(MetadataEditorTarget.init(file:))
        let token = UUID()

        self.targets = targets
        self.originalPropertyMaps = [:]
        self.draftPropertyMaps = [:]
        self.loadErrorMessage = nil
        self.selectedFieldKey = nil
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
                self.selectedFieldKey = self.rows.first?.key
            }
        }
    }

    func discardChanges() {
        draftPropertyMaps = originalPropertyMaps
    }

    fileprivate func makeAddFieldContext() -> MetadataFieldEditorContext {
        MetadataFieldEditorContext(key: nil, initialValue: "")
    }

    fileprivate func makeEditFieldContext() -> MetadataFieldEditorContext? {
        guard let selectedFieldKey else { return nil }
        let values = targets.compactMap { draftPropertyMaps[$0.id]?[selectedFieldKey] }
        let firstValue = values.first ?? ""
        let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }
        return MetadataFieldEditorContext(key: selectedFieldKey, initialValue: isUniform ? firstValue : "")
    }

    func upsertField(key: String, value: String) {
        let normalizedKey = MetadataFieldSuggestion.resolvedKey(for: key)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap[normalizedKey] = normalizedValue
            draftPropertyMaps[target.id] = propertyMap
        }

        selectedFieldKey = normalizedKey
    }

    fileprivate func commitFieldEntry(context: MetadataFieldEditorContext, key: String, value: String) {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingKey = context.key {
            if normalizedValue.isEmpty {
                deleteField(named: existingKey)
            } else {
                upsertField(key: existingKey, value: normalizedValue)
            }
        } else {
            upsertField(key: key, value: normalizedValue)
        }
    }

    func deleteSelectedField() {
        guard let selectedFieldKey else { return }
        deleteField(named: selectedFieldKey)
    }

    private func deleteField(named key: String) {
        guard !key.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap.removeValue(forKey: key)
            draftPropertyMaps[target.id] = propertyMap
        }

        self.selectedFieldKey = rows.first?.key
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
                propertyMaps[target.id] = [:]
                failures.append("\(target.fileName): \((error as NSError).localizedDescription)")
            }
        }

        let errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        return LoadedState(propertyMaps: propertyMaps, errorMessage: errorMessage)
    }
}

struct MetadataEditorWindowView: View {
    static let windowID = "metadata-editor"

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var store: MetadataEditorStore

    @Environment(\.dismiss) private var dismiss

    @State private var editorContext: MetadataFieldEditorContext?
    @State private var fieldKeyDraft: String = ""
    @State private var fieldValueDraft: String = ""
    @State private var isApplyingChanges: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if store.isLoading {
                    ProgressView("Loading metadata…".localizedUI)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $store.selectedFieldKey) {
                        Section {
                            ForEach(store.rows) { row in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.key)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    Text(row.isMixed ? "Multiple Values" : row.value)
                                        .font(.subheadline)
                                        .foregroundStyle(row.isMixed ? .secondary : .primary)
                                }
                            }
                        }
                    }
                    .iPadRoundedGroupedListStyle()
                }

                HStack {
                    Button("Add Field") {
                        prepareEditor(context: store.makeAddFieldContext())
                    }

                    Button("Edit") {
                        if let context = store.makeEditFieldContext() {
                            prepareEditor(context: context)
                        }
                    }
                    .disabled(store.selectedFieldKey == nil)

                    Button("Delete", role: .destructive) {
                        store.deleteSelectedField()
                    }
                    .disabled(store.selectedFieldKey == nil)

                    Spacer()

                    if isApplyingChanges {
                        ProgressView()
                    }

                    Button("Done") {
                        Task { await commitAndDismiss() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .navigationTitle(AppWindowTitle.metadataEditor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Task { await commitAndDismiss() }
                    }
                    .disabled(isApplyingChanges)
                }
            }
        }
        .sheet(item: $editorContext) { context in
            NavigationStack {
                Form {
                    Section("Field") {
                        if let key = context.key {
                            Text(key)
                                .font(.system(size: 13, design: .monospaced))
                        } else {
                            TextField("MUSICBRAINZ_ALBUMID", text: $fieldKeyDraft)
                                .textInputAutocapitalization(.characters)
                        }
                    }

                    Section("Value") {
                        TextEditor(text: $fieldValueDraft)
                            .frame(minHeight: 240)
                            .font(.system(size: 14, design: .monospaced))
                    }
                }
                .iPadRoundedGroupedFormStyle()
                .navigationTitle(context.key == nil ? "Add Field" : "Edit Field")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editorContext = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let key = context.key ?? fieldKeyDraft
                            store.commitFieldEntry(context: context, key: key, value: fieldValueDraft)
                            editorContext = nil
                        }
                        .disabled(context.key == nil && fieldValueDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func prepareEditor(context: MetadataFieldEditorContext) {
        fieldKeyDraft = context.key ?? ""
        fieldValueDraft = context.initialValue
        editorContext = context
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
