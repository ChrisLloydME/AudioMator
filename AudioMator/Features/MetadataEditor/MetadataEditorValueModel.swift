import Foundation

// MARK: - E2 raw value arrays: reviewed per-target changes

/// One reviewed change to one raw field of one target.
///
/// `nil` for `beforeValues`/`afterValues` means the key is absent (a missing
/// key). An empty array is an existing key that stores no values, and `[""]` is
/// one explicit blank element. The three states are distinct data and must never
/// be collapsed into a joined string.
struct RawFieldValueChange: Hashable {
    let targetID: AudioFile.ID
    let key: String
    let beforeValues: [String]?
    let afterValues: [String]?

    init(
        targetID: AudioFile.ID,
        key: String,
        beforeValues: [String]?,
        afterValues: [String]?
    ) {
        self.targetID = targetID
        self.key = key
        self.beforeValues = beforeValues
        self.afterValues = afterValues
    }

    var isNoOp: Bool {
        beforeValues == afterValues
    }
}

/// Exact per-file/key diff between the captured original and draft raw maps.
///
/// This is the single diff implementation used when Done captures an apply
/// request and by the tests that verify the captured before/after arrays. It
/// never reads the disk and keeps array order, duplicates, empty elements and
/// missing keys intact.
enum MetadataEditorDraftChanges {
    static func changes(
        original: [AudioFile.ID: RawMetadataValueMap],
        draft: [AudioFile.ID: RawMetadataValueMap],
        targetIDs: [AudioFile.ID]
    ) -> [RawFieldValueChange] {
        targetIDs.flatMap { targetID in
            let originalMap = original[targetID] ?? [:]
            let draftMap = draft[targetID] ?? [:]
            let keys = Set(originalMap.keys).union(draftMap.keys).sorted(by: rawKeyOrder)

            return keys.compactMap { key -> RawFieldValueChange? in
                let beforeValues = originalMap[key]
                let afterValues = draftMap[key]
                guard beforeValues != afterValues else { return nil }
                return RawFieldValueChange(
                    targetID: targetID,
                    key: key,
                    beforeValues: beforeValues,
                    afterValues: afterValues
                )
            }
        }
    }

    private static func rawKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
        switch lhs.localizedCaseInsensitiveCompare(rhs) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return lhs < rhs
        }
    }
}

// MARK: - Array display helpers

/// Display-only projections of a raw value array.
///
/// Element boundaries are never inferred from text and joined labels are only
/// used for presentation. Equality, change detection and writes use the arrays.
enum MetadataRawValueDisplay {
    /// Visible hint for a line break embedded inside one value.
    static let lineBreakMarker = "\u{23CE}"

    static let noValuesPlaceholder = L10n.string("(No values)")
    static let emptyValuePlaceholder = L10n.string("(Empty value)")

    /// Multi-line presentation for a preview cell: an embedded LF stays inside
    /// the element and is shown as `⏎` at the end of its line.
    static func elementText(_ value: String) -> String {
        normalizedNewlines(value).replacingOccurrences(
            of: "\n",
            with: "\(lineBreakMarker)\n"
        )
    }

    /// One-line presentation for an ordered list row.
    static func compactElementText(_ value: String) -> String {
        normalizedNewlines(value).replacingOccurrences(
            of: "\n",
            with: " \(lineBreakMarker) "
        )
    }

    /// Display label for one element, including the empty-element placeholder.
    static func elementLabel(_ value: String) -> String {
        value.isEmpty ? emptyValuePlaceholder : elementText(value)
    }

    /// Display label for a whole array. Never use this for equality or a write.
    static func joinedLabel(_ values: [String]) -> String {
        values.isEmpty ? noValuesPlaceholder : values.joined(separator: "\n")
    }

    private static func normalizedNewlines(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
