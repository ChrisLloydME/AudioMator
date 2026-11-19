import Foundation

/// Versioned AudioMator exchange profile.
///
/// Version 2 carries YEAR, DATE, RELEASEDATE and ORIGINALDATE as independent
/// columns. A leading marker line identifies the profile; files without it are
/// read with the legacy v1 column meanings. Unknown newer versions are rejected
/// before any write.
nonisolated enum MetadataExchangeProfile {
    static let currentVersion = 2
    static let legacyVersion = 1
    static let markerPrefix = "# AudioMator-Metadata-Profile:"
    /// Unquoted cell value that requests an explicit removal. A quoted literal
    /// with the same text is data, so literal values stay expressible.
    static let removalToken = "<remove>"
    /// Internal, non-empty carrier for an explicit removal through the import
    /// plan. Quoted literal text never becomes this sentinel.
    static let removalSentinel = "\u{1F}AudioMatorRemove\u{1F}"

    nonisolated static func displayValue(_ value: String) -> String {
        value == removalSentinel ? removalToken : value
    }

    nonisolated struct Extraction {
        /// Source without the marker line.
        let source: String
        /// `nil` when no marker was present: the legacy v1 profile.
        let version: Int?
        /// True when a leading marker line (or a malformed label attempt) was
        /// present. Text framing needs this to distinguish the exporter's single
        /// empty record from empty unmarked input.
        let hadMarker: Bool
        /// False when a marker line was recognized but is not terminated by its
        /// own line break. That is an incomplete marker line, not an empty import.
        let markerLineTerminated: Bool
        let errorMessage: String?
    }

    nonisolated static func markerLine() -> String {
        "\(markerPrefix) \(currentVersion)"
    }

    nonisolated static func extract(from source: String) -> Extraction {
        var text = source
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        let trimmedLeading = text.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmedLeading.hasPrefix(markerPrefix) else {
            return Extraction(
                source: source,
                version: nil,
                hadMarker: false,
                markerLineTerminated: false,
                errorMessage: nil
            )
        }

        let markerAndRest = trimmedLeading
        // Swift treats CRLF as one extended grapheme cluster, so it must be
        // matched explicitly as a single Character.
        let lineEnd = markerAndRest.firstIndex(where: {
            $0 == "\n" || $0 == "\r" || $0 == "\r\n"
        })
        let markerLineTerminated = lineEnd != nil
        let markerLine = markerAndRest[..<(lineEnd ?? markerAndRest.endIndex)]
        let versionText = markerLine.dropFirst(markerPrefix.count)
            .trimmingCharacters(in: .whitespaces)
        guard let version = Int(versionText) else {
            return Extraction(
                source: source,
                version: nil,
                hadMarker: true,
                markerLineTerminated: markerLineTerminated,
                errorMessage: String(localized: "The import file's AudioMator version label isn't valid. Check the label or export the file again from AudioMator.")
            )
        }
        guard version >= legacyVersion, version <= currentVersion else {
            return Extraction(
                source: source,
                version: version,
                hadMarker: true,
                markerLineTerminated: markerLineTerminated,
                errorMessage: String(localized: "This file was exported with a newer metadata profile (\(version)). This version of AudioMator supports up to \(currentVersion). Update AudioMator before importing it.")
            )
        }

        guard let lineEnd else {
            return Extraction(
                source: source,
                version: version,
                hadMarker: true,
                markerLineTerminated: false,
                errorMessage: nil
            )
        }

        var remainder = String(markerAndRest[lineEnd...])
        if remainder.hasPrefix("\r\n") || remainder.hasPrefix("\n") || remainder.hasPrefix("\r") {
            remainder.removeFirst()
        }
        return Extraction(
            source: remainder,
            version: version,
            hadMarker: true,
            markerLineTerminated: true,
            errorMessage: nil
        )
    }
}

nonisolated enum MetadataExchangeResourceLimits {
    static let maximumRecordCount = 100_000
    static let maximumDocumentUTF8ByteCount = 32 * 1_024 * 1_024
    static let maximumTextRecordUTF8ByteCount = 262_144
    static let maximumCSVFieldUTF8ByteCount = 1_048_576
}

nonisolated struct MetadataExchangeExportBudget {
    let maximumUTF8ByteCount: Int
    let recordSeparatorUTF8ByteCount: Int

    private(set) var recordCount = 0
    private(set) var usedUTF8ByteCount = 0

    mutating func append(recordUTF8ByteCount: Int) -> Bool {
        guard
            maximumUTF8ByteCount >= 0,
            recordUTF8ByteCount >= 0,
            recordSeparatorUTF8ByteCount >= 0,
            usedUTF8ByteCount >= 0,
            usedUTF8ByteCount <= maximumUTF8ByteCount
        else { return false }

        let separatorByteCount = recordCount == 0 ? 0 : recordSeparatorUTF8ByteCount
        guard separatorByteCount <= maximumUTF8ByteCount - usedUTF8ByteCount else { return false }
        let remainingByteCount = maximumUTF8ByteCount - usedUTF8ByteCount - separatorByteCount
        guard recordUTF8ByteCount <= remainingByteCount else { return false }

        usedUTF8ByteCount += separatorByteCount + recordUTF8ByteCount
        recordCount += 1
        return true
    }
}

nonisolated struct MetadataExchangeLocatorCandidateIndex<Field: Hashable> {
    private let candidateIndicesByFieldAndKey: [Field: [String: [Int]]]

    init(
        itemCount: Int,
        fields: [Field],
        keysForItem: (Field, Int) -> [String]
    ) {
        var indexes: [Field: [String: [Int]]] = [:]
        for field in fields {
            var candidatesByKey: [String: [Int]] = [:]
            for itemIndex in 0..<max(itemCount, 0) {
                // Bounded index work stops promptly on cancellation; the plan
                // worker also rechecks before publishing.
                if Task.isCancelled { break }
                for key in Set(keysForItem(field, itemIndex)) where !key.isEmpty {
                    candidatesByKey[key, default: []].append(itemIndex)
                }
            }
            indexes[field] = candidatesByKey
        }
        candidateIndicesByFieldAndKey = indexes
    }

    func candidateIndices(
        fields: [Field],
        lookupKey: (Field) -> String?
    ) -> [Int] {
        var narrowestCandidates: [Int]?

        for field in fields {
            guard
                let key = lookupKey(field),
                let candidates = candidateIndicesByFieldAndKey[field]?[key],
                !candidates.isEmpty
            else {
                return []
            }

            if let narrowestCandidates, candidates.count >= narrowestCandidates.count {
                continue
            } else {
                narrowestCandidates = candidates
            }
        }

        return narrowestCandidates ?? []
    }
}

nonisolated struct MetadataExchangeCSVField: Sendable {
    /// Lexical cell text as it appeared in the document (after quote removal and
    /// doubled-quote unescaping, before any application-level decoding).
    let value: String
    let wasQuoted: Bool
}

nonisolated enum MetadataExchangeCSV {
    nonisolated private static let delimiterCandidates: [Character] = ["\t", ",", ";", "|"]

    nonisolated static func allowsBareQuotesInUnquotedFields(for delimiter: Character) -> Bool {
        delimiter == "\t" || delimiter == "|"
    }

    nonisolated static func detectDelimiter(in source: String) -> Character {
        let counts = delimiterCountsOutsideQuotes(in: source)
        let bestCandidate = delimiterCandidates.max { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            if lhsCount == rhsCount {
                return delimiterPriority(lhs) > delimiterPriority(rhs)
            }
            return lhsCount < rhsCount
        }

        guard let bestCandidate, counts[bestCandidate, default: 0] > 0 else {
            return ","
        }
        return bestCandidate
    }

    nonisolated private static func delimiterPriority(_ delimiter: Character) -> Int {
        delimiterCandidates.firstIndex(of: delimiter) ?? delimiterCandidates.count
    }

    /// Returns lexical row text only (raw cell values and quoting are preserved
    /// by `parseFields`). Spreadsheet-protection reversal is an application-level
    /// concern selected by the exchange profile; see `MetadataExchangeCSVCodec`.
    nonisolated static func parse(_ source: String, delimiter: Character = ",") throws -> [[String]] {
        try parseFields(source, delimiter: delimiter).map { row in
            row.map(\.value)
        }
    }

    nonisolated static func parseFields(
        _ source: String,
        delimiter: Character = ",",
        allowsBareQuotesInUnquotedFields: Bool = false,
        maximumRowCount: Int? = nil,
        maximumFieldCountPerRow: Int? = nil,
        maximumFieldUTF8ByteCount: Int? = nil
    ) throws -> [[MetadataExchangeCSVField]] {
        var text = source
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        guard !text.isEmpty else { return [] }

        var rows: [[MetadataExchangeCSVField]] = []
        var row: [MetadataExchangeCSVField] = []
        var field = ""
        var index = text.startIndex
        var isQuoted = false
        var didCloseQuotedField = false
        var fieldHasContent = false
        var fieldWasQuoted = false
        var fieldUTF8ByteCount = 0

        func limitError(_ description: String) -> NSError {
            NSError(
                domain: "MetadataExchangeCSV",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }

        func appendToField(_ character: Character) throws {
            let additionalByteCount = String(character).utf8.count
            if let maximumFieldUTF8ByteCount,
               (additionalByteCount > maximumFieldUTF8ByteCount ||
                fieldUTF8ByteCount > maximumFieldUTF8ByteCount - additionalByteCount) {
                throw limitError(String(localized: "A CSV cell is too large to import. Shorten its value or split the data into smaller parts."))
            }
            field.append(character)
            fieldUTF8ByteCount += additionalByteCount
            fieldHasContent = true
        }

        func appendField() throws {
            if let maximumFieldCountPerRow, row.count >= maximumFieldCountPerRow {
                throw limitError(String(localized: "This CSV row has more columns than the template. Remove the extra columns or add the corresponding fields to the template."))
            }
            row.append(MetadataExchangeCSVField(value: field, wasQuoted: fieldWasQuoted))
            field = ""
            fieldUTF8ByteCount = 0
            fieldHasContent = false
            fieldWasQuoted = false
            didCloseQuotedField = false
        }

        func appendRow() throws {
            if let maximumRowCount, rows.count >= maximumRowCount {
                throw limitError(String(localized: "This CSV has too many rows to import at once. Split it into smaller files."))
            }
            try appendField()
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            if Task.isCancelled {
                throw CancellationError()
            }
            let character = text[index]

            if isQuoted {
                if character == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        try appendToField("\"")
                        index = text.index(after: nextIndex)
                    } else {
                        isQuoted = false
                        didCloseQuotedField = true
                        index = nextIndex
                    }
                } else {
                    try appendToField(character)
                    index = text.index(after: index)
                }
                continue
            }

            switch character {
            case "\"":
                if fieldHasContent {
                    if allowsBareQuotesInUnquotedFields {
                        try appendToField(character)
                        index = text.index(after: index)
                        continue
                    }
                    throw NSError(
                        domain: "MetadataExchangeCSV",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "A CSV cell contains a quote in the wrong place. Enclose the whole cell in quotes and write quotes inside it as two double quotes.")]
                    )
                }
                isQuoted = true
                fieldHasContent = true
                fieldWasQuoted = true
                didCloseQuotedField = false
                index = text.index(after: index)
            case delimiter:
                try appendField()
                index = text.index(after: index)
            case "\n", "\r\n":
                try appendRow()
                index = text.index(after: index)
            case "\r":
                try appendRow()
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = text.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
            default:
                if didCloseQuotedField {
                    guard character.isWhitespace else {
                        throw NSError(
                            domain: "MetadataExchangeCSV",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: String(localized: "A CSV cell has text after its closing quote. Move that text inside the quotes or into another column.")]
                        )
                    }
                    index = text.index(after: index)
                    continue
                }

                try appendToField(character)
                index = text.index(after: index)
            }
        }

        if isQuoted {
            throw NSError(
                domain: "MetadataExchangeCSV",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "A quoted CSV cell is missing its closing quote. Add the closing quote before importing.")]
            )
        }

        if fieldHasContent || !field.isEmpty || !row.isEmpty {
            try appendRow()
        }

        return rows
    }

    nonisolated static func serialize(_ rows: [[String]], delimiter: Character = ",") -> String {
        rows
            .map { row in
                row.map { value in
                    // A sole empty cell is the export representation of a
                    // structurally empty record. Quote it so the parser can tell
                    // that record apart from the end of the document.
                    let isSoleEmptyCell = row.count == 1 && value.isEmpty
                    return escape(
                        spreadsheetProtectedValue(value),
                        delimiter: delimiter,
                        forceQuote: isSoleEmptyCell
                            || value.trimmingCharacters(in: .whitespacesAndNewlines) == MetadataExchangeProfile.removalToken
                            || value.first?.isWhitespace == true
                            || value.last?.isWhitespace == true
                    )
                }
                .joined(separator: String(delimiter))
            }
            .joined(separator: "\r\n")
    }

    /// Prefixes formula-like values with an apostrophe so spreadsheet apps treat them as text.
    /// A genuine leading apostrophe is doubled when needed, making AudioMator export/import reversible.
    nonisolated static func spreadsheetProtectedValue(_ value: String) -> String {
        guard !value.isEmpty else { return value }

        if value.first == "'" {
            // Protect any run of leading apostrophes followed by a formula
            // character. Doubling the whole value keeps encode/decode
            // symmetric for values such as "''=A1".
            let withoutLeadingApostrophes = String(value.drop(while: { $0 == "'" }))
            guard startsSpreadsheetFormula(withoutLeadingApostrophes) else { return value }
            return "'" + value
        }

        guard startsSpreadsheetFormula(value) else { return value }
        return "'" + value
    }

    nonisolated static func decodeSpreadsheetProtectedValue(_ value: String) -> String {
        guard value.first == "'" else { return value }

        let remainder = String(value.dropFirst())
        if startsSpreadsheetFormula(remainder) {
            return remainder
        }
        if remainder.first == "'" {
            let withoutLeadingApostrophes = String(remainder.drop(while: { $0 == "'" }))
            if startsSpreadsheetFormula(withoutLeadingApostrophes) {
                return remainder
            }
        }
        return value
    }

    nonisolated private static func startsSpreadsheetFormula(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if scalar.value <= 0x20 ||
                scalar.value == 0xFEFF ||
                CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            return scalar == "=" || scalar == "+" || scalar == "-" || scalar == "@"
        }
        return false
    }

    nonisolated private static func escape(
        _ value: String,
        delimiter: Character,
        forceQuote: Bool = false
    ) -> String {
        let containsRecordSeparator = value.unicodeScalars.contains { scalar in
            scalar.value == 0x0A || scalar.value == 0x0D
        }
        let hasBoundaryWhitespace = value.first?.isWhitespace == true || value.last?.isWhitespace == true

        guard forceQuote || value.contains(delimiter) || value.contains("\"") || containsRecordSeparator || hasBoundaryWhitespace else {
            return value
        }

        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    nonisolated private static func delimiterCountsOutsideQuotes(in source: String) -> [Character: Int] {
        var counts: [Character: Int] = [:]
        var index = source.startIndex
        var isQuoted = false

        while index < source.endIndex {
            let character = source[index]

            if character == "\"" {
                let nextIndex = source.index(after: index)
                if isQuoted, nextIndex < source.endIndex, source[nextIndex] == "\"" {
                    index = source.index(after: nextIndex)
                } else {
                    isQuoted.toggle()
                    index = nextIndex
                }
                continue
            }

            if !isQuoted, delimiterCandidates.contains(character) {
                counts[character, default: 0] += 1
            }

            index = source.index(after: index)
        }

        return counts
    }
}
