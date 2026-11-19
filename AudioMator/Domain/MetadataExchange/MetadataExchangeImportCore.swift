import Foundation

// MARK: – Positional framing

/// One physical source record slot, including empty slots.
///
/// `sourceIndex` is the zero-based slot position in the source document after
/// marker/BOM handling and line-ending normalization. Blank slots keep their
/// position; they are never compacted away before binding.
nonisolated struct MetadataExchangeFramedRecord: Sendable, Equatable {
    let sourceIndex: Int
    let rawText: String
}

/// The result of framing a text import document into physical record slots.
nonisolated struct MetadataExchangeFraming: Sendable, Equatable {
    let records: [MetadataExchangeFramedRecord]
    /// `nil` for unmarked legacy input, otherwise the accepted marker version.
    let profileVersion: Int?
    let hadMarker: Bool
    /// False when a marker line was recognized but is not followed by a line
    /// break. That is an incomplete marker line, not an empty import.
    let markerLineTerminated: Bool
    /// True when the normalized source ended with a line break. Used only by the
    /// legacy count-driven terminator rule, never as an implicit terminator for
    /// the current marked grammar.
    let sourceEndedWithLineBreak: Bool
    let validationMessage: String?
}

/// The result of binding framed text slots to the reviewed ordered targets.
nonisolated enum MetadataExchangePositionalBinding: Sendable, Equatable {
    /// One record for each target, in target order.
    case aligned([MetadataExchangeFramedRecord])
    /// Legacy unmarked/v1 one-file tolerance: exactly one usable record with
    /// blank padding. The single record binds to the single target.
    case legacyOneRecordPadding(targetIndex: Int, recordIndex: Int)
    /// The slot count cannot be mapped one-to-one to the reviewed targets.
    case countMismatch(records: Int, targets: Int)
    /// The framed document itself is invalid (for example an incomplete marker line).
    case invalid(String)
}

nonisolated enum MetadataExchangeTextFramer {
    /// Frames `sourceText` using the already-extracted profile result.
    ///
    /// Rules:
    /// - A marker with its own line break and an empty body is the exporter's
    ///   single empty record.
    /// - All other marked documents preserve every empty component, including
    ///   leading, interior and final empty records, with no implicit terminator.
    /// - Unmarked documents strip a leading BOM and preserve every empty
    ///   component; the legacy terminator rule is applied by the binder.
    nonisolated static func frame(
        _ sourceText: String,
        extraction: MetadataExchangeProfile.Extraction
    ) -> MetadataExchangeFraming {
        if let errorMessage = extraction.errorMessage {
            return MetadataExchangeFraming(
                records: [],
                profileVersion: extraction.version,
                hadMarker: extraction.hadMarker,
                markerLineTerminated: extraction.markerLineTerminated,
                sourceEndedWithLineBreak: false,
                validationMessage: errorMessage
            )
        }

        guard extraction.hadMarker else {
            var text = sourceText
            if text.hasPrefix("\u{FEFF}") {
                text.removeFirst()
            }
            let normalized = normalizeLineEndings(text)
            return MetadataExchangeFraming(
                records: frameRecordsFromBody(normalized),
                profileVersion: nil,
                hadMarker: false,
                markerLineTerminated: false,
                sourceEndedWithLineBreak: normalized.hasSuffix("\n"),
                validationMessage: nil
            )
        }

        guard extraction.markerLineTerminated else {
            return MetadataExchangeFraming(
                records: [],
                profileVersion: extraction.version,
                hadMarker: true,
                markerLineTerminated: false,
                sourceEndedWithLineBreak: false,
                validationMessage: String(
                    localized: "The AudioMator version label isn’t on its own line. Put a line break after it, or remove the label before importing."
                )
            )
        }

        let normalized = normalizeLineEndings(extraction.source)
        let records: [MetadataExchangeFramedRecord]
        if normalized.isEmpty {
            // The marker plus its own separator and an empty body is the
            // exported single empty record.
            records = [MetadataExchangeFramedRecord(sourceIndex: 0, rawText: "")]
        } else {
            records = frameRecordsFromBody(normalized)
        }

        return MetadataExchangeFraming(
            records: records,
            profileVersion: extraction.version,
            hadMarker: true,
            markerLineTerminated: true,
            sourceEndedWithLineBreak: normalized.hasSuffix("\n"),
            validationMessage: nil
        )
    }

    nonisolated private static func frameRecordsFromBody(
        _ body: String
    ) -> [MetadataExchangeFramedRecord] {
        guard !body.isEmpty else { return [] }
        return body.components(separatedBy: "\n").enumerated().map { index, record in
            MetadataExchangeFramedRecord(sourceIndex: index, rawText: record)
        }
    }

    nonisolated private static func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

nonisolated enum MetadataExchangePositionalBinder {
    /// Binds framed slots to the reviewed target count.
    ///
    /// Marked version 2 uses the current exporter grammar: exactly one record per
    /// target, with no implicit terminator. Unmarked and marked v1 input keep the
    /// legacy one-file padding tolerance and the count-driven trailing-LF rule.
    nonisolated static func bind(
        framing: MetadataExchangeFraming,
        targetCount: Int,
        clearBlankImportedValues: Bool
    ) -> MetadataExchangePositionalBinding {
        if let validationMessage = framing.validationMessage {
            return .invalid(validationMessage)
        }

        let records = framing.records
        let isCurrentGrammar = framing.profileVersion == MetadataExchangeProfile.currentVersion

        if records.count == targetCount {
            return .aligned(records)
        }

        if !isCurrentGrammar,
           records.count == targetCount + 1,
           framing.sourceEndedWithLineBreak,
           records.last?.rawText.isEmpty == true {
            return .aligned(Array(records.dropLast()))
        }

        if !isCurrentGrammar,
           !clearBlankImportedValues,
           targetCount == 1,
           let usableIndex = singleUsableRecordIndex(in: records) {
            return .legacyOneRecordPadding(targetIndex: 0, recordIndex: usableIndex)
        }

        return .countMismatch(records: records.count, targets: targetCount)
    }

    /// CSV positional imports are framed by the quote-aware parser, so the only
    /// valid one-to-one mapping is an exact count match. A trailing empty CSV row
    /// is a real record once the exporter quotes a sole empty cell.
    nonisolated static func bindCSV(
        dataRowCount: Int,
        targetCount: Int
    ) -> MetadataExchangePositionalBinding {
        if dataRowCount == targetCount {
            return .aligned(
                (0..<dataRowCount).map { index in
                    MetadataExchangeFramedRecord(sourceIndex: index, rawText: "")
                }
            )
        }
        return .countMismatch(records: dataRowCount, targets: targetCount)
    }

    nonisolated private static func singleUsableRecordIndex(
        in records: [MetadataExchangeFramedRecord]
    ) -> Int? {
        var usableIndex: Int?
        for record in records {
            if record.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            guard usableIndex == nil else { return nil }
            usableIndex = record.sourceIndex
        }
        return usableIndex
    }
}

// MARK: – Number spelling

/// Strict spelling validation for imported number components.
///
/// Callers pass only non-empty lexical text; blank/explicit-removal captures are
/// classified before this helper. The result distinguishes a positive component
/// from the established zero-as-removal spelling so the planner can build typed
/// per-component operations instead of clamping malformed input to zero.
nonisolated enum MetadataExchangeNumberSpelling {
    nonisolated enum Component: Equatable, Sendable {
        case value(text: String, value: Int)
        case removal
    }

    nonisolated enum SpellingError: Error, Equatable, Sendable {
        case negativeMagnitude
        case notAnInteger
        case overflowsDeclaredMaximum
        case emptySlashComponent
        case multipleSlashes
        case pairInTotalColumn
    }

    nonisolated enum NumberColumn: Equatable, Sendable {
        case number(Component, embeddedTotal: Component?)
    }

    /// Parses one component (number or total) or a number column pair.
    ///
    /// - `allowsPair`: number columns accept one slash with two non-empty
    ///   components; total columns and transfer destinations do not.
    nonisolated static func parseComponent(
        _ rawText: String,
        maximum: Int
    ) -> Result<Component, SpellingError> {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.notAnInteger) }

        var digits = Substring(trimmed)
        if digits.first == "+" {
            digits = digits.dropFirst()
        } else if digits.first == "-" {
            return .failure(.negativeMagnitude)
        }
        guard !digits.isEmpty else { return .failure(.notAnInteger) }

        var value = 0
        for scalar in digits.unicodeScalars {
            guard scalar.value >= 48, scalar.value <= 57 else {
                return .failure(.notAnInteger)
            }
            let digit = Int(scalar.value - 48)
            let multiplied = value.multipliedReportingOverflow(by: 10)
            if multiplied.overflow { return .failure(.overflowsDeclaredMaximum) }
            let added = multiplied.partialValue.addingReportingOverflow(digit)
            if added.overflow { return .failure(.overflowsDeclaredMaximum) }
            value = added.partialValue
            if value > maximum { return .failure(.overflowsDeclaredMaximum) }
        }

        if value == 0 {
            return .success(.removal)
        }
        return .success(.value(text: trimmed, value: value))
    }

    nonisolated static func parseNumberColumn(
        _ rawText: String,
        maximum: Int
    ) -> Result<NumberColumn, SpellingError> {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return .failure(.multipleSlashes) }

        if parts.count == 1 {
            return parseComponent(trimmed, maximum: maximum)
                .map { .number($0, embeddedTotal: nil) }
        }

        let numberText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let totalText = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numberText.isEmpty, !totalText.isEmpty else {
            return .failure(.emptySlashComponent)
        }

        switch parseComponent(numberText, maximum: maximum) {
        case .failure(let error): return .failure(error)
        case .success(let number):
            switch parseComponent(totalText, maximum: maximum) {
            case .failure(let error): return .failure(error)
            case .success(let total):
                return .success(.number(number, embeddedTotal: total))
            }
        }
    }

    nonisolated static func parseTotalColumn(
        _ rawText: String,
        maximum: Int
    ) -> Result<Component, SpellingError> {
        if rawText.contains("/") { return .failure(.pairInTotalColumn) }
        return parseComponent(rawText, maximum: maximum)
    }
}

// MARK: – Profile-scoped CSV decoding

/// Application-level CSV decoding selected by the extracted exchange profile.
///
/// The lexical parser exposes raw field text and quoting only. Spreadsheet
/// protection reversal is an AudioMator export feature, so it applies only when a
/// recognized profile marker was present. Unmarked external cells stay literal.
nonisolated enum MetadataExchangeCSVCodec: Sendable, Equatable {
    case literal
    case profile(version: Int)

    nonisolated init(profileVersion: Int?) {
        if let profileVersion {
            self = .profile(version: profileVersion)
        } else {
            self = .literal
        }
    }

    nonisolated func decoded(_ field: MetadataExchangeCSVField) -> String {
        switch self {
        case .literal:
            return field.value
        case .profile:
            return MetadataExchangeCSV.decodeSpreadsheetProtectedValue(field.value)
        }
    }

    nonisolated func importedValue(_ field: MetadataExchangeCSVField) -> String {
        let decoded = decoded(field)
        return field.wasQuoted ? decoded : decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func hasImportContent(_ field: MetadataExchangeCSVField) -> Bool {
        field.wasQuoted ? !decoded(field).isEmpty : !importedValue(field).isEmpty
    }
}
