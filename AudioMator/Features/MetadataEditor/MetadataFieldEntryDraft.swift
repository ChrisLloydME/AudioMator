import Foundation
import TagLibAudioMetadata

// MARK: - Raw field entry draft (E2)

enum MetadataFieldEditorMode: Equatable {
    case add
    case edit
}

/// Why an edit started with no value elements. Drives the sheet guidance and is
/// unit-tested; it is not derived from joined text.
enum MetadataFieldEmptyStartReason: Hashable {
    /// A new field: one blank element is offered as an explicit value slot.
    case newField
    /// Selected files disagree or some files do not have the key. Saving must
    /// replace them with an explicit list the user builds (no elements yet).
    case mixedSelection
    /// Every selected file has the key with an empty array. Preserve it unless
    /// the user adds an explicit value or deletes the field.
    case existingEmptyArray
}

/// Everything the field entry sheet needs to edit one raw field as an ordered
/// array. Captured once when the sheet opens and verified again by the store on
/// commit, so a stale sheet cannot stage data against a different session.
struct MetadataFieldEditorContext: Identifiable {
    let mode: MetadataFieldEditorMode
    /// Exact existing raw key for `.edit`. Never normalized or redirected.
    let key: String?
    /// Exact uniform before-values for `.edit`; empty when mixed or adding.
    let values: [String]
    /// Captured target identity at sheet open. A target-set change invalidates
    /// the commit just like a draft mutation does.
    let targetIDs: [AudioFile.ID]
    /// Exact per-target before-values for `.edit`; `nil` means the key is absent.
    let beforeValuesByTarget: [AudioFile.ID: [String]?]
    /// Optional editor seed (0 for the first value of a nonempty uniform edit).
    let selectedValueIndex: Int?
    let isMixed: Bool
    let presentationID: MetadataEditorPresentationID
    let draftGeneration: UInt64
    var displayName: String = ""
    var emptyStartReason: MetadataFieldEmptyStartReason?

    var targets: [MetadataEditorTarget] = []

    func resolvedWriteKey(input: String, selectedMappingKey: String?) -> String {
        switch mode {
        case .edit:
            return key ?? ""
        case .add:
            let resolved = selectedMappingKey ?? MetadataFieldSuggestion.resolvedKey(for: input)
            let dateTitle = MetadataFieldGuide.displayName(for: .standaloneDate)
            let selectsDate = selectedMappingKey == "STANDALONEDATE"
                || (input != "DATE" && input.localizedCaseInsensitiveCompare(dateTitle) == .orderedSame)
            return MetadataDatePickerEligibilityResolver.rawKeyForNewField(
                resolved, selectedDateSuggestion: selectsDate, targets: targets
            )
        }
    }

    var id: String {
        switch mode {
        case .add:
            return "add:\(presentationID.rawValue.uuidString)"
        case .edit:
            return "edit:\(presentationID.rawValue.uuidString):\(key ?? "")"
        }
    }
}

/// One value element inside an ordered value list. The stable identity keeps
/// duplicate and empty elements independently addressable while editing.
struct MetadataFieldValueElement: Identifiable, Hashable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// Value-type state of the ordered field-value editor.
///
/// The draft enforces the same guards the store re-checks on commit: an empty
/// element list is never a key deletion, the last element cannot be removed from
/// the list, and an unchanged confirmation is a no-op instead of a write.
struct MetadataFieldValueDraft {
    private let mode: MetadataFieldEditorMode
    private let beforeValues: [String]
    private let isMixed: Bool

    private(set) var elements: [MetadataFieldValueElement]
    private(set) var selectedElementID: UUID?
    private(set) var emptyStartReason: MetadataFieldEmptyStartReason?

    init(context: MetadataFieldEditorContext) {
        mode = context.mode
        beforeValues = context.values
        isMixed = context.isMixed
        emptyStartReason = context.emptyStartReason

        switch context.mode {
        case .add:
            let element = MetadataFieldValueElement(text: "")
            elements = [element]
            selectedElementID = element.id
        case .edit:
            if context.isMixed {
                elements = []
                selectedElementID = nil
            } else {
                elements = context.values.map { MetadataFieldValueElement(text: $0) }
                let seedIndex = min(
                    max(context.selectedValueIndex ?? 0, 0),
                    max(elements.count - 1, 0)
                )
                selectedElementID = elements.isEmpty ? nil : elements[seedIndex].id
            }
        }
    }

    var values: [String] {
        elements.map(\.text)
    }

    /// A same-value save of a uniform edit is allowed and becomes a no-op.
    var isUnchangedConfirmation: Bool {
        guard mode == .edit, !isMixed else { return false }
        return values == beforeValues
    }

    /// Nonempty list or an unchanged uniform confirmation. An empty list typed as
    /// a change is never allowed; key removal belongs to Delete Field.
    var canCommit: Bool {
        isUnchangedConfirmation || !elements.isEmpty
    }

    var selectedElement: MetadataFieldValueElement? {
        guard let selectedElementID else { return nil }
        return elements.first { $0.id == selectedElementID }
    }

    var selectedElementIndex: Int? {
        guard let selectedElementID else { return nil }
        return elements.firstIndex { $0.id == selectedElementID }
    }

    func text(for id: UUID) -> String? {
        elements.first { $0.id == id }?.text
    }

    mutating func select(_ id: UUID) {
        guard elements.contains(where: { $0.id == id }) else { return }
        selectedElementID = id
    }

    mutating func setText(_ text: String, for id: UUID) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].text = text
    }

    @discardableResult
    mutating func addValue(text: String = "") -> UUID {
        let element = MetadataFieldValueElement(text: text)
        elements.append(element)
        selectedElementID = element.id
        emptyStartReason = nil
        return element.id
    }

    /// Removes one value. Returns false when the last remaining element would be
    /// removed (the sheet directs the user to Delete Field) or when nothing
    /// matches; a false result must not change the value list.
    @discardableResult
    mutating func removeValue(id: UUID) -> Bool {
        guard elements.count > 1,
              let index = elements.firstIndex(where: { $0.id == id }) else { return false }

        elements.remove(at: index)
        if selectedElementID == id {
            let nextIndex = min(index, elements.count - 1)
            selectedElementID = elements.isEmpty ? nil : elements[nextIndex].id
        }
        return true
    }
}

// MARK: - Commit outcome

enum MetadataFieldCommitOutcome: Equatable {
    case applied
    case noChange
    case rejected(MetadataFieldCommitRejection)
}

enum MetadataFieldCommitRejection: Equatable {
    /// An empty list was submitted as a change. Never inferred from the editor
    /// list; removing the key requires the explicit Delete Field command.
    case emptyValueList
    /// Add mode without a usable raw key.
    case emptyKey
    /// The presentation or draft generation changed since the sheet opened.
    case staleDraft
}
