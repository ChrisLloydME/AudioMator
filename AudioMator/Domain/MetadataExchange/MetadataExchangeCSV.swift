import Foundation

struct MetadataExchangeCSVField {
    let value: String
    let wasQuoted: Bool

    nonisolated var importedValue: String {
        wasQuoted ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var hasImportContent: Bool {
        wasQuoted ? !value.isEmpty : !importedValue.isEmpty
    }
}

enum MetadataExchangeCSV {
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

    nonisolated static func parse(_ source: String, delimiter: Character = ",") throws -> [[String]] {
        try parseFields(source, delimiter: delimiter).map { row in
            row.map(\.value)
        }
    }

    nonisolated static func parseFields(
        _ source: String,
        delimiter: Character = ",",
        allowsBareQuotesInUnquotedFields: Bool = false
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

        func appendField() {
            row.append(MetadataExchangeCSVField(value: field, wasQuoted: fieldWasQuoted))
            field = ""
            fieldHasContent = false
            fieldWasQuoted = false
            didCloseQuotedField = false
        }

        func appendRow() {
            appendField()
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]

            if isQuoted {
                if character == "\"" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex, text[nextIndex] == "\"" {
                        field.append("\"")
                        fieldHasContent = true
                        index = text.index(after: nextIndex)
                    } else {
                        isQuoted = false
                        didCloseQuotedField = true
                        index = nextIndex
                    }
                } else {
                    field.append(character)
                    fieldHasContent = true
                    index = text.index(after: index)
                }
                continue
            }

            switch character {
            case "\"":
                if fieldHasContent {
                    if allowsBareQuotesInUnquotedFields {
                        field.append(character)
                        index = text.index(after: index)
                        continue
                    }
                    throw NSError(
                        domain: "MetadataExchangeCSV",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected quote in an unquoted CSV field."]
                    )
                }
                isQuoted = true
                fieldHasContent = true
                fieldWasQuoted = true
                didCloseQuotedField = false
                index = text.index(after: index)
            case delimiter:
                appendField()
                index = text.index(after: index)
            case "\n", "\r\n":
                appendRow()
                index = text.index(after: index)
            case "\r":
                appendRow()
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
                            userInfo: [NSLocalizedDescriptionKey: "Unexpected text after a closing CSV quote."]
                        )
                    }
                    index = text.index(after: index)
                    continue
                }

                field.append(character)
                fieldHasContent = true
                index = text.index(after: index)
            }
        }

        if isQuoted {
            throw NSError(
                domain: "MetadataExchangeCSV",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "CSV input ended inside a quoted field."]
            )
        }

        if fieldHasContent || !field.isEmpty || !row.isEmpty {
            appendRow()
        }

        return rows
    }

    nonisolated static func serialize(_ rows: [[String]], delimiter: Character = ",") -> String {
        rows
            .map { row in row.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }
            .joined(separator: "\r\n")
    }

    nonisolated private static func escape(_ value: String, delimiter: Character) -> String {
        let containsRecordSeparator = value.unicodeScalars.contains { scalar in
            scalar.value == 0x0A || scalar.value == 0x0D
        }
        let hasBoundaryWhitespace = value.first?.isWhitespace == true || value.last?.isWhitespace == true

        guard value.contains(delimiter) || value.contains("\"") || containsRecordSeparator || hasBoundaryWhitespace else {
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
