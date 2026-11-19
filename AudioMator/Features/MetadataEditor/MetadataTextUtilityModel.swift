import Foundation

// MARK: - Text utility preview over exact value arrays (E2)

/// One file/field row of a text-utility preview. The before/after arrays are the
/// reviewed truth; the string labels exist only for display.
struct MetadataTextUtilityPreviewRow: Identifiable, Hashable {
    let targetID: AudioFile.ID
    let fileName: String
    let fieldKey: String
    let beforeValues: [String]
    let afterValues: [String]

    var id: String {
        "\(targetID.uuidString):\(fieldKey)"
    }

    var changed: Bool {
        beforeValues != afterValues
    }

    var currentLabel: String {
        MetadataRawValueDisplay.joinedLabel(beforeValues)
    }

    var previewLabel: String {
        MetadataRawValueDisplay.joinedLabel(afterValues)
    }
}

/// Captured result of one transform over the current draft.
///
/// A preview is accepted only while its presentation, draft generation, target
/// set and every row's before-values are still current. Applying the captured
/// `afterValues` (never re-running the pipeline) makes the preview and the
/// staged draft one value.
struct MetadataTextUtilityPreview {
    let presentationID: MetadataEditorPresentationID
    let draftGeneration: UInt64
    let targetIDs: [AudioFile.ID]
    let rows: [MetadataTextUtilityPreviewRow]

    var changedRows: [MetadataTextUtilityPreviewRow] {
        rows.filter(\.changed)
    }

    var changedFileCount: Int {
        Set(changedRows.map(\.targetID)).count
    }

    var changedFieldCount: Int {
        Set(changedRows.map(\.fieldKey)).count
    }
}

enum MetadataTextUtilityApplyOutcome: Equatable {
    case applied(changeCount: Int)
    case noChanges
    /// The captured preview no longer matches the live presentation, target set,
    /// draft generation or before-values. Nothing was mutated.
    case stale
    /// No ready editable session is available.
    case unavailable
}
