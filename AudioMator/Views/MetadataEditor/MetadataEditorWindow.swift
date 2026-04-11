import SwiftUI
import AppKit
import Combine

struct MetadataEditorTarget: Identifiable, Hashable {
    let id: AudioFile.ID
    let url: URL

    init(file: AudioFile) {
        self.id = file.id
        self.url = file.url
    }

    var fileName: String {
        url.lastPathComponent
    }
}

private struct MetadataEditorRow: Identifiable, Hashable {
    let key: String
    let value: String
    let isMixed: Bool

    var id: String { key }

    var displayValue: String {
        isMixed ? "Multiple Values" : value
    }
}

private enum MetadataFieldEditorMode {
    case add
    case edit
}

private struct MetadataFieldEditorContext: Identifiable {
    let mode: MetadataFieldEditorMode
    let key: String?
    let initialValue: String
    let isMixed: Bool

    var id: String {
        switch mode {
        case .add:
            return "add"
        case .edit:
            return "edit:\(key ?? "")"
        }
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
    @Published var selectedFieldKey: String?

    private var loadToken = UUID()

    var hasUnsavedChanges: Bool {
        draftPropertyMaps != originalPropertyMaps
    }

    fileprivate var rows: [MetadataEditorRow] {
        let allKeys = Set(draftPropertyMaps.values.flatMap(\.keys))

        return allKeys
            .map { key in
                let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
                let firstValue = values.first ?? ""
                let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }

                return MetadataEditorRow(
                    key: key,
                    value: firstValue,
                    isMixed: !isUniform
                )
            }
            .sorted { lhs, rhs in
                lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }

    var selectionSummaryText: String {
        if targets.count == 1, let target = targets.first {
            return target.fileName
        }

        return "\(targets.count) selected files"
    }

    var selectionDetailText: String {
        if targets.count == 1, let target = targets.first {
            return target.url.path
        }

        return "Only non-empty metadata fields are shown. Mixed values appear as Multiple Values, and changes apply to every selected file."
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

        Task(priority: .userInitiated) {
            let loadedState = Self.loadState(for: targets)

            await MainActor.run {
                guard self.loadToken == token else { return }
                self.originalPropertyMaps = loadedState.propertyMaps
                self.draftPropertyMaps = loadedState.propertyMaps
                self.loadErrorMessage = loadedState.errorMessage
                self.isLoading = false
                self.realignSelection(preferred: self.selectedFieldKey)
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
        guard let key = selectedFieldKey else { return nil }

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

    func deleteSelectedField() {
        guard let selectedFieldKey else { return }
        deleteField(named: selectedFieldKey)
    }

    func deleteField(named key: String) {
        guard !key.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap.removeValue(forKey: key)
            draftPropertyMaps[target.id] = propertyMap
        }

        realignSelection(preferred: nil)
    }

    private func realignSelection(preferred: String?) {
        let validKeys = Set(rows.map(\.key))

        if let preferred, validKeys.contains(preferred) {
            selectedFieldKey = preferred
        } else {
            selectedFieldKey = rows.first?.key
        }
    }

    nonisolated private static func loadState(for targets: [MetadataEditorTarget]) -> LoadedState {
        var propertyMaps: [AudioFile.ID: [String: String]] = [:]
        var failures: [String] = []

        for target in targets {
            do {
                propertyMaps[target.id] = try propertyMap(for: target.url)
            } catch {
                propertyMaps[target.id] = [:]
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

    nonisolated private static func propertyMap(for url: URL) throws -> [String: String] {
        let dump = try TagLibMetadataManager.rawMetadataResult(from: url)
        var propertyMap: [String: String] = [:]

        for entry in dump.properties {
            let key = normalizedFieldKey(entry.key)
            let valueSource = entry.values.isEmpty ? entry.value : entry.values.joined(separator: "; ")
            let value = normalizedFieldValue(valueSource)

            guard !key.isEmpty, !value.isEmpty else { continue }
            propertyMap[key] = value
        }

        return propertyMap
    }

    nonisolated private static func normalizedFieldKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
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
    @State private var isApplyingChanges: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
            footer
        }
        .padding(20)
        .frame(minWidth: 820, idealWidth: 920, maxWidth: 1040, minHeight: 540, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Metadata Editor")
        .sheet(item: $editorContext) { context in
            MetadataFieldEntrySheet(context: context) { key, value in
                store.upsertField(key: key, value: value)
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
                Text("Metadata Editor")
                    .font(.title2)
                    .fontWeight(.semibold)

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
                ProgressView("Loading metadata…")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.loadErrorMessage, store.rows.isEmpty {
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
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Field")
                        .frame(width: 230, alignment: .leading)

                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                List(store.rows, selection: $store.selectedFieldKey) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.key)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .frame(width: 230, alignment: .leading)

                        Text(row.displayValue)
                            .foregroundStyle(row.isMixed ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .tag(row.key)
                    .contextMenu {
                        Button("Edit…") {
                            store.selectedFieldKey = row.key
                            editorContext = store.makeEditFieldContext()
                        }

                        Button("Delete Field", role: .destructive) {
                            store.deleteField(named: row.key)
                        }
                    }
                    .onTapGesture(count: 2) {
                        store.selectedFieldKey = row.key
                        editorContext = store.makeEditFieldContext()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
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
            .disabled(store.selectedFieldKey == nil || store.isLoading || isApplyingChanges)

            Button("Add Field…") {
                editorContext = store.makeAddFieldContext()
            }
            .disabled(store.targets.isEmpty || store.isLoading || isApplyingChanges)

            Button("Delete Field", role: .destructive) {
                store.deleteSelectedField()
            }
            .disabled(store.selectedFieldKey == nil || store.isLoading || isApplyingChanges)

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

private struct MetadataFieldEntrySheet: View {
    let context: MetadataFieldEditorContext
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fieldKey: String
    @State private var fieldValue: String

    init(
        context: MetadataFieldEditorContext,
        onSave: @escaping (String, String) -> Void
    ) {
        self.context = context
        self.onSave = onSave
        _fieldKey = State(initialValue: context.key ?? "")
        _fieldValue = State(initialValue: context.initialValue)
    }

    private var trimmedFieldKey: String {
        fieldKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFieldValue: String {
        fieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedFieldKey.isEmpty && !trimmedFieldValue.isEmpty
    }

    private var titleText: String {
        switch context.mode {
        case .add:
            return "Add Metadata Field"
        case .edit:
            return "Edit Metadata Field"
        }
    }

    private var descriptionText: String {
        switch context.mode {
        case .add:
            return "Enter the property-map field name and the value to write."
        case .edit:
            if context.isMixed {
                return "Selected files currently contain different values. Saving replaces them with one shared value."
            }
            return "Update the selected metadata field for every file in the current selection."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if context.mode == .add {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field")
                        .font(.headline)

                    TextField("For example: MUSICBRAINZ_ALBUMID", text: $fieldKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field")
                        .font(.headline)

                    Text(context.key ?? "")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Value")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))

                    TextEditor(text: $fieldValue)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)

                    if fieldValue.isEmpty {
                        Text(context.isMixed ? "Type the value to apply to all selected files." : "Enter the metadata value")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                )
                .frame(minHeight: 190)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(context.mode == .add ? "Add" : "Save") {
                    onSave(trimmedFieldKey, trimmedFieldValue)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560, height: 360)
    }
}
