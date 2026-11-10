import Foundation

/// Shape checks for the independently stored date identities.
///
/// These are *pre-edit* checks only. They never compare one date field with
/// another, never complete a partial value, and never truncate YEAR text. The
/// package validates the concrete destination (for example ID3v2.3 TDAT is a
/// legacy DDMM value while ID3v2.4 uses a TXXX DATE text frame).
///
/// This file stays Foundation-only so the SwiftPM core-logic target can compile
/// it without acquiring the TagLib dependency.
nonisolated enum MetadataDateText {
    /// YEAR keeps the complete stored text. A Year slot may legitimately hold a
    /// full date such as `2004-07-15`, so a four-character rule would discard
    /// supported data.
    static func isPlausibleYear(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true } // explicit removal
        return trimmed.range(
            of: #"^\d{4}(?:-\d{2}(?:-\d{2})?)?(?:[T ].+)?$"#,
            options: .regularExpression
        ) != nil
    }

    /// DATE has version-specific shapes. Accept a legacy DDMM four-digit value
    /// or the ISO-like text form; the destination capability decides which form
    /// is representable.
    static func isPlausibleStandaloneDate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
            || trimmed.range(
                of: #"^\d{4}-\d{2}(?:-\d{2})?(?:[T ].+)?$"#,
                options: .regularExpression
            ) != nil
    }

    static func isPlausibleDate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.range(
            of: #"^\d{4}(?:-\d{2}(?:-\d{2})?)?(?:[T ].+)?$"#,
            options: .regularExpression
        ) != nil
    }
}
