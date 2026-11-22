import SwiftUI

struct MetadataFieldEntrySheet: View {
    let context: MetadataFieldEditorContext
    /// Returns the store outcome. The sheet stays open with an inline message when
    /// the commit is rejected (stale session/draft or an empty change list).
    let onSave: (String, [String]) -> MetadataFieldCommitOutcome

    @Environment(\.dismiss) private var dismiss

    @State private var fieldKey: String
    @State private var selectedMappingKey: String?
    @State private var draft: MetadataFieldValueDraft
    @State private var commitError: String?

    init(
        context: MetadataFieldEditorContext,
        onSave: @escaping (String, [String]) -> MetadataFieldCommitOutcome
    ) {
        self.context = context
        self.onSave = onSave
        _fieldKey = State(initialValue: context.key ?? "")
        _draft = State(initialValue: MetadataFieldValueDraft(context: context))
    }

    private var trimmedFieldKey: String {
        fieldKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var writeKey: String {
        context.resolvedWriteKey(input: trimmedFieldKey, selectedMappingKey: selectedMappingKey)
    }

    private struct DateScope: Equatable {
        let key: String
        let elementID: UUID?
    }

    @ViewBuilder
    private var dateButton: some View {
        if let eligibility = MetadataDatePickerEligibilityResolver.metadataEditorEligibility(
            rawKey: writeKey, targets: context.targets
        ) {
            let title = MetadataFieldGuide.displayName(for: eligibility.fieldKey)
            MetadataDatePickerButton(
                scope: DateScope(key: writeKey, elementID: draft.selectedElementID),
                title: title,
                value: selectedTextBinding.wrappedValue,
                format: eligibility.destinationFormat,
                onApply: { scope, value in
                    guard writeKey == scope.key, draft.selectedElementID == scope.elementID else { return }
                    selectedTextBinding.wrappedValue = value
                }
            ) {
                Label(String(localized: "Choose Date…"), systemImage: "calendar")
            }
            .fixedSize()
            .help(String(localized: "Choose \(title)"))
            .accessibilityLabel(Text("Choose \(title)"))
        }
    }

    private var canSave: Bool {
        switch context.mode {
        case .add:
            return !trimmedFieldKey.isEmpty && draft.canCommit
        case .edit:
            return draft.canCommit
        }
    }

    private var titleText: String {
        switch context.mode {
        case .add:
            return L10n.string("Add Metadata Field")
        case .edit:
            return L10n.string("Edit Metadata Field")
        }
    }

    private var descriptionText: String? {
        switch context.mode {
        case .add:
            return L10n.string("Choose an AudioMator field or enter a custom field name.")
        case .edit:
            if context.isMixed {
                return L10n.string("Selected files currently contain different values. Add the replacement values; saving replaces the whole value list on every selected file.")
            }
            if draft.emptyStartReason == .existingEmptyArray {
                return L10n.string("This field currently has no values. Add a value to replace the empty list, or use Delete Field to remove the key.")
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let descriptionText {
                    Text(descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if context.mode == .add {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field")
                        .font(.headline)

                    MacSearchDropdownField(
                        text: fieldKey,
                        placeholder: L10n.string("For example: Album or Release Date"),
                        accessibilityLabel: L10n.string("Field"),
                        suggestions: { query in
                            MetadataFieldSuggestion.allSupported
                                .filter { $0.matches(query: query) }
                                .map { .init(id: $0.canonicalKey, title: $0.displayName, detail: $0.detailText) }
                        },
                        onTextChange: { newValue in
                            selectedMappingKey = nil
                            fieldKey = newValue
                        },
                        onSelect: { suggestion in
                            fieldKey = suggestion.title
                            selectedMappingKey = suggestion.id
                            return true
                        }
                    )
                    .frame(height: 24)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field")
                        .font(.headline)

                    Text(context.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(context.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            valueEditorArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let commitError {
                Text(commitError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(context.mode == .add ? "Add" : "Save") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 860, height: 540)
    }

    private var valueEditorArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("Value")
                    .font(.headline)
                    .fixedSize()

                if draft.elements.count > 1 {
                    valuePicker
                }

                Spacer(minLength: 12)

                dateButton

                Button("Add Value") {
                    draft.addValue()
                }
                .fixedSize()

                if draft.elements.count > 1 {
                    Button("Remove Value") {
                        guard let selectedElementID = draft.selectedElementID else { return }
                        draft.removeValue(id: selectedElementID)
                    }
                    .fixedSize()
                }
            }

            MetadataFieldValueEditor(
                text: selectedTextBinding,
                placeholder: context.isMixed
                    ? L10n.string("Type the value to apply to all selected files.")
                    : L10n.string("Enter the metadata value")
            )
            .accessibilityLabel("Metadata Value")
        }
    }

    private var valuePicker: some View {
        let selection = Binding(
            get: { draft.selectedElementID },
            set: { id in
                if let id { draft.select(id) }
            }
        )
        return Picker("Value", selection: selection) {
            ForEach(Array(draft.elements.enumerated()), id: \.element.id) { index, element in
                Text("\(index + 1). \(valuePreview(element.text))")
                    .tag(Optional(element.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel(Text("Value"))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func valuePreview(_ text: String) -> String {
        guard !text.isEmpty else { return MetadataRawValueDisplay.emptyValuePlaceholder }
        let limit = 32
        let prefix = text.prefix(limit)
        let preview = MetadataRawValueDisplay.compactElementText(String(prefix))
        return prefix.endIndex == text.endIndex ? preview : preview + "…"
    }

    private var selectedTextBinding: Binding<String> {
        Binding(
            get: {
                guard let selectedElementID = draft.selectedElementID else { return "" }
                return draft.text(for: selectedElementID) ?? ""
            },
            set: { newValue in
                if let selectedElementID = draft.selectedElementID {
                    draft.setText(newValue, for: selectedElementID)
                } else if !newValue.isEmpty {
                    // Mixed selections and existing empty arrays start with no
                    // selected element so an unchanged confirmation stays a no-op;
                    // typing directly creates the first replacement value.
                    draft.addValue(text: newValue)
                }
            }
        )
    }

    private func commit() {
        commitError = nil
        let outcome = onSave(writeKey, draft.values)
        switch outcome {
        case .applied, .noChange:
            dismiss()
        case .rejected(let rejection):
            commitError = message(for: rejection)
        }
    }

    private func message(for rejection: MetadataFieldCommitRejection) -> String {
        switch rejection {
        case .emptyValueList:
            return L10n.string("Add at least one value, or use Delete Field to remove the entire field.")
        case .emptyKey:
            return L10n.string("Choose a field or enter a field name.")
        case .staleDraft:
            return L10n.string("The editor changed before this field could be saved. Close and reopen the field.")
        }
    }
}
