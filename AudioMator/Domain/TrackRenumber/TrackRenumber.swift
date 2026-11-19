import Foundation

/// Compact track-numbering direction. The first ordered row receives either the
/// lowest or the highest reviewed number; there is no persisted formatting
/// option in this workflow.
nonisolated enum TrackRenumberDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
}

/// Transient control state for the renumber sheet. The approved start range is
/// `1...9_999` with no zero value and no zero-padding option; numbers are stored
/// and previewed as integers.
nonisolated struct TrackRenumberOptions: Equatable {
    var direction: TrackRenumberDirection = .ascending
    var startNumber: Int = defaultTrackRenumberStartNumber
}

nonisolated let minimumTrackRenumberStartNumber = 1
nonisolated let maximumTrackRenumberStartNumber = 9_999
nonisolated let defaultTrackRenumberStartNumber = 1

/// Why a direct start-number entry is not usable. The sheet shows the message and
/// disables Apply; an invalid entry never clamps to a different sequence.
nonisolated enum TrackRenumberStartNumberIssue: Equatable, Sendable {
    case blank
    case malformed
    case outOfRange

    var message: String {
        switch self {
        case .blank:
            return String(localized: "Enter a start number from 1 to 9,999.")
        case .malformed:
            return String(localized: "Enter the start number using digits 0–9 only. Signs, fractions and other digit characters aren’t supported.")
        case .outOfRange:
            return String(localized: "Enter a start number from 1 to 9,999.")
        }
    }
}

/// Result of interpreting the sheet's start-number field.
///
/// The parse is intentionally strict: surrounding whitespace is trimmed, then
/// only plain ASCII decimal digits are accepted. Signs, fractions, separators
/// and Unicode lookalike digits are rejected rather than coerced. A trimmed
/// `"007"` is a valid entry that previews the numeric value 7.
nonisolated enum TrackRenumberStartNumberInput: Equatable, Sendable {
    case valid(Int)
    case invalid(TrackRenumberStartNumberIssue)

    nonisolated var startNumber: Int? {
        guard case .valid(let number) = self else { return nil }
        return number
    }

    nonisolated var isValid: Bool {
        startNumber != nil
    }

    nonisolated var issue: TrackRenumberStartNumberIssue? {
        guard case .invalid(let issue) = self else { return nil }
        return issue
    }

    nonisolated var validationMessage: String? {
        issue?.message
    }
}

nonisolated func trackRenumberStartNumberInput(_ text: String) -> TrackRenumberStartNumberInput {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .invalid(.blank) }

    // ASCII decimal digits only. `Int(_:)` alone would also accept a leading
    // sign, so validate the exact character set before parsing.
    guard trimmed.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
        return .invalid(.malformed)
    }
    guard let value = Int(trimmed) else {
        // An all-digit string that does not fit `Int` can never be inside the
        // approved range.
        return .invalid(.outOfRange)
    }
    guard (minimumTrackRenumberStartNumber...maximumTrackRenumberStartNumber).contains(value) else {
        return .invalid(.outOfRange)
    }
    return .valid(value)
}

nonisolated struct TrackRenumberFailure: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let reason: String
}

nonisolated struct TrackRenumberWarning: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let messages: [String]
}

/// Outcome summary for one reviewed renumber batch.
///
/// `totalTargets` counts every reviewed row, including rows classified before
/// numbering. `unchanged` counts numbered rows whose stored value already equals
/// the reviewed number; those rows keep their slot and cause no disk write.
nonisolated struct TrackRenumberResult: Equatable {
    var totalTargets: Int
    var succeeded: Int
    var unchanged: Int = 0
    var skippedUnsupported: Int = 0
    var skippedDuplicate: Int = 0
    var failed: Int
    var failures: [TrackRenumberFailure]
    var warnings: [TrackRenumberWarning]
    var cancelled: [TrackRenumberFailure] = []
    /// Set when the submitted plan itself was invalid (for example a blank or
    /// out-of-range start). No file write occurs in that case.
    var validationMessage: String?

    static let empty = TrackRenumberResult(
        totalTargets: 0,
        succeeded: 0,
        failed: 0,
        failures: [],
        warnings: []
    )
}
