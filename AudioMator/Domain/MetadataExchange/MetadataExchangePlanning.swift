import Foundation

struct MetadataTextExportRow: Identifiable {
    let id: AudioFile.ID
    let fileName: String
    let output: String
}
struct MetadataTextExportPlan {
    let validationMessage: String?
    let rows: [MetadataTextExportRow]

    var outputText: String {
        rows.map(\.output).joined(separator: "\n")
    }

    var canExport: Bool {
        validationMessage == nil && !rows.isEmpty
    }
}

struct MetadataCSVExportPlan {
    let validationMessage: String?
    let columns: [MetadataExchangeField]
    let rows: [[String]]
    let includeHeaderRow: Bool
    let delimiter: Character

    var outputText: String {
        var outputRows: [[String]] = []
        if includeHeaderRow {
            outputRows.append(columns.map(\.displayName))
        }
        outputRows.append(contentsOf: rows)
        return MetadataExchangeCSV.serialize(outputRows, delimiter: delimiter)
    }

    var canExport: Bool {
        validationMessage == nil && !rows.isEmpty
    }
}

enum MetadataExchangePreviewStatus: Equatable {
    case ready
    case unchanged
    case noMatch
    case ambiguousMatch
    case parseError
    case sourceUnavailable
    case missingExternalRecord
    case extraExternalRecord
    case noWritableFields

    var title: String {
        switch self {
        case .ready:
            return L10n.string("Ready")
        case .unchanged:
            return L10n.string("Unchanged")
        case .noMatch:
            return L10n.string("No Match")
        case .ambiguousMatch:
            return L10n.string("Ambiguous Match")
        case .parseError:
            return L10n.string("Parse Error")
        case .sourceUnavailable:
            return L10n.string("File Unavailable")
        case .missingExternalRecord:
            return L10n.string("Missing Record")
        case .extraExternalRecord:
            return L10n.string("Extra Record")
        case .noWritableFields:
            return L10n.string("No Writable Fields")
        }
    }

    var isIssue: Bool {
        switch self {
        case .ready, .unchanged:
            return false
        case .noMatch, .ambiguousMatch, .parseError, .sourceUnavailable, .missingExternalRecord,
                .extraExternalRecord, .noWritableFields:
            return true
        }
    }
}

struct MetadataExchangeFieldChange: Identifiable {
    let field: MetadataExchangeField
    let currentValue: String
    let importedValue: String
    let willWrite: Bool

    var id: String { field.placeholderName }
}

struct MetadataExchangeWriteEntry: Identifiable {
    let fileID: AudioFile.ID
    let fileName: String
    let values: [MetadataExchangeField: String]
    let expectedFileFingerprint: AudioFileFingerprint?

    init(
        fileID: AudioFile.ID,
        fileName: String,
        values: [MetadataExchangeField: String],
        expectedFileFingerprint: AudioFileFingerprint? = nil
    ) {
        self.fileID = fileID
        self.fileName = fileName
        self.values = values
        self.expectedFileFingerprint = expectedFileFingerprint
    }

    var id: AudioFile.ID { fileID }
}

struct MetadataExchangeImportPreviewRow: Identifiable {
    let id: UUID
    let fileID: AudioFile.ID?
    let fileName: String
    let externalRecord: String
    let status: MetadataExchangePreviewStatus
    let changes: [MetadataExchangeFieldChange]
    let issueMessage: String?
    let writeEntry: MetadataExchangeWriteEntry?
}

struct MetadataExchangeImportPlan {
    let validationMessage: String?
    let rows: [MetadataExchangeImportPreviewRow]

    var writeEntries: [MetadataExchangeWriteEntry] {
        rows.compactMap(\.writeEntry)
    }

    var canApply: Bool {
        validationMessage == nil && !writeEntries.isEmpty
    }

    var readyCount: Int {
        writeEntries.count
    }

    var issueCount: Int {
        rows.filter { $0.status.isIssue }.count + (validationMessage == nil ? 0 : 1)
    }
}

enum MetadataExchangePlanner {
    private static let maximumTemplateUTF8ByteCount = 16_384
    private static let maximumImportUTF8ByteCount = MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount
    private static let maximumImportRecordCount = MetadataExchangeResourceLimits.maximumRecordCount
    private static let maximumTextRecordUTF8ByteCount = MetadataExchangeResourceLimits.maximumTextRecordUTF8ByteCount
    private static let maximumCSVFieldUTF8ByteCount = MetadataExchangeResourceLimits.maximumCSVFieldUTF8ByteCount

    static func makeTextExportPlan(
        template: String,
        targetFiles: [AudioFile]
    ) -> MetadataTextExportPlan {
        guard template.utf8.count <= maximumTemplateUTF8ByteCount else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("The text template is too large."),
                rows: []
            )
        }

        let document = MetadataExchangeTemplateDocument(rawValue: template)
        if document.isEmpty {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("Enter a template to preview exported text."),
                rows: []
            )
        }

        if let validationMessage = validateTemplateSyntax(document, requiresSingleLine: true) {
            return MetadataTextExportPlan(validationMessage: validationMessage, rows: [])
        }

        guard document.fields.contains(where: { $0 != .ignore }) else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("Add at least one output field to the template."),
                rows: []
            )
        }

        let uniqueFiles = uniqueTargetFiles(targetFiles)
        guard uniqueFiles.count <= MetadataExchangeResourceLimits.maximumRecordCount else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("The export contains more than 100,000 files. Export a smaller selection."),
                rows: []
            )
        }

        let relativeBasePath = commonDirectoryPath(for: uniqueFiles)
        var rows: [MetadataTextExportRow] = []
        rows.reserveCapacity(uniqueFiles.count)
        var outputBudget = MetadataExchangeExportBudget(
            maximumUTF8ByteCount: MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount,
            recordSeparatorUTF8ByteCount: 1
        )
        var containsMultilineRecord = false

        for (index, file) in uniqueFiles.enumerated() {
            let output = render(
                document: document,
                file: file,
                index: index,
                relativeBasePath: relativeBasePath
            )
            let outputUTF8ByteCount = output.utf8.count
            guard outputUTF8ByteCount <= MetadataExchangeResourceLimits.maximumTextRecordUTF8ByteCount else {
                return MetadataTextExportPlan(
                    validationMessage: L10n.string("A rendered text record is larger than 256 KB. Use CSV export or shorten large metadata values."),
                    rows: []
                )
            }
            guard outputBudget.append(recordUTF8ByteCount: outputUTF8ByteCount) else {
                return MetadataTextExportPlan(
                    validationMessage: L10n.string("The export would be larger than 32 MB. Export a smaller selection."),
                    rows: []
                )
            }

            containsMultilineRecord = containsMultilineRecord || output.unicodeScalars.contains { scalar in
                scalar.value == 0x0A || scalar.value == 0x0D
            }
            rows.append(
                MetadataTextExportRow(
                    id: file.id,
                    fileName: file.url.lastPathComponent,
                    output: output
                )
            )
        }

        return MetadataTextExportPlan(
            validationMessage: containsMultilineRecord
                ? L10n.string("One or more values contain line breaks. Use CSV export to preserve multiline metadata safely.")
                : nil,
            rows: rows
        )
    }

    static func makeCSVExportPlan(
        template: String,
        includeHeaderRow: Bool,
        targetFiles: [AudioFile]
    ) -> MetadataCSVExportPlan {
        let result = parseCSVColumnTemplate(template)
        if let validationMessage = result.validationMessage {
            return MetadataCSVExportPlan(
                validationMessage: validationMessage,
                columns: result.columns,
                rows: [],
                includeHeaderRow: includeHeaderRow,
                delimiter: result.delimiter
            )
        }

        let uniqueFiles = uniqueTargetFiles(targetFiles)
        guard uniqueFiles.count <= MetadataExchangeResourceLimits.maximumRecordCount else {
            return MetadataCSVExportPlan(
                validationMessage: L10n.string("The export contains more than 100,000 files. Export a smaller selection."),
                columns: result.columns,
                rows: [],
                includeHeaderRow: includeHeaderRow,
                delimiter: result.delimiter
            )
        }

        let relativeBasePath = commonDirectoryPath(for: uniqueFiles)
        var rows: [[String]] = []
        rows.reserveCapacity(uniqueFiles.count)
        var outputBudget = MetadataExchangeExportBudget(
            maximumUTF8ByteCount: MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount,
            recordSeparatorUTF8ByteCount: 2
        )

        if includeHeaderRow {
            let header = result.columns.map(\.displayName)
            let serializedHeader = MetadataExchangeCSV.serialize([header], delimiter: result.delimiter)
            guard outputBudget.append(recordUTF8ByteCount: serializedHeader.utf8.count) else {
                return MetadataCSVExportPlan(
                    validationMessage: L10n.string("The export would be larger than 32 MB. Export a smaller selection."),
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }
        }

        for (index, file) in uniqueFiles.enumerated() {
            let row = result.columns.map { field in
                field.value(from: file, index: index, relativeBasePath: relativeBasePath)
            }
            let hasOversizedField = row.contains { value in
                MetadataExchangeCSV.spreadsheetProtectedValue(value).utf8.count >
                    MetadataExchangeResourceLimits.maximumCSVFieldUTF8ByteCount
            }
            guard !hasOversizedField else {
                return MetadataCSVExportPlan(
                    validationMessage: L10n.string("A CSV field is larger than 1 MB. Shorten that metadata value before exporting."),
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }

            let serializedRow = MetadataExchangeCSV.serialize([row], delimiter: result.delimiter)
            guard outputBudget.append(recordUTF8ByteCount: serializedRow.utf8.count) else {
                return MetadataCSVExportPlan(
                    validationMessage: L10n.string("The export would be larger than 32 MB. Export a smaller selection."),
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }
            rows.append(row)
        }

        return MetadataCSVExportPlan(
            validationMessage: nil,
            columns: result.columns,
            rows: rows,
            includeHeaderRow: includeHeaderRow,
            delimiter: result.delimiter
        )
    }

    static func makeTextImportPlan(
        template: String,
        sourceText: String,
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool
    ) -> MetadataExchangeImportPlan {
        guard template.utf8.count <= maximumTemplateUTF8ByteCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The text template is too large."),
                rows: []
            )
        }

        guard sourceText.utf8.count <= maximumImportUTF8ByteCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The import text is too large. Split it into files smaller than 32 MB."),
                rows: []
            )
        }

        let document = MetadataExchangeTemplateDocument(rawValue: template)
        if let validationMessage = validateImportTextTemplate(document) {
            return MetadataExchangeImportPlan(validationMessage: validationMessage, rows: [])
        }

        var normalizedSource = sourceText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalizedSource.hasPrefix("\u{FEFF}") {
            normalizedSource.removeFirst()
        }

        var records = normalizedSource.isEmpty
            ? []
            : normalizedSource.components(separatedBy: "\n")
        if clearBlankImportedValues {
            if normalizedSource.hasSuffix("\n"), records.last?.isEmpty == true {
                records.removeLast()
            }
        } else {
            records.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        guard !records.isEmpty else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one text record to import."),
                rows: []
            )
        }

        guard records.count <= maximumImportRecordCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The import contains more than 100,000 records. Split it into smaller batches."),
                rows: []
            )
        }

        guard !records.contains(where: { $0.utf8.count > maximumTextRecordUTF8ByteCount }) else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("A text record is larger than 256 KB. Use CSV import for multiline or very large values."),
                rows: []
            )
        }

        let matcher = MetadataExchangeTextMatcher(document: document)
        let parsedRecords = records.enumerated().map { index, record in
            ParsedExternalRecord(index: index, displayText: record, captures: matcher.match(record))
        }

        return makeImportPlan(
            parsedRecords: parsedRecords,
            fields: document.fields,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues
        )
    }

    static func makeCSVImportPlan(
        template: String,
        sourceText: String,
        firstRowIsHeader: Bool,
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool
    ) -> MetadataExchangeImportPlan {
        guard sourceText.utf8.count <= maximumImportUTF8ByteCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The CSV import is too large. Split it into files smaller than 32 MB."),
                rows: []
            )
        }

        let result = parseCSVColumnTemplate(template)
        if let validationMessage = result.validationMessage {
            return MetadataExchangeImportPlan(validationMessage: validationMessage, rows: [])
        }
        guard result.columns.contains(where: \.isWritableMetadataField) else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one writable metadata field to the CSV column template."),
                rows: []
            )
        }

        let parsedCSV: [[MetadataExchangeCSVField]]
        do {
            parsedCSV = try MetadataExchangeCSV.parseFields(
                sourceText,
                delimiter: result.delimiter,
                allowsBareQuotesInUnquotedFields: MetadataExchangeCSV.allowsBareQuotesInUnquotedFields(for: result.delimiter),
                maximumRowCount: maximumImportRecordCount + (firstRowIsHeader ? 1 : 0),
                maximumFieldCountPerRow: result.columns.count + 1,
                maximumFieldUTF8ByteCount: maximumCSVFieldUTF8ByteCount
            )
        } catch {
            return MetadataExchangeImportPlan(
                validationMessage: (error as NSError).localizedDescription,
                rows: []
            )
        }

        if firstRowIsHeader, let header = parsedCSV.first, header.count != result.columns.count {
            return MetadataExchangeImportPlan(
                validationMessage: "The CSV header has \(header.count) column(s), but the template has \(result.columns.count).",
                rows: []
            )
        }

        let dataRows = firstRowIsHeader && !parsedCSV.isEmpty ? Array(parsedCSV.dropFirst()) : parsedCSV
        guard !dataRows.isEmpty else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one CSV data row to import."),
                rows: []
            )
        }

        guard dataRows.count <= maximumImportRecordCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The CSV contains more than 100,000 data rows. Split it into smaller batches."),
                rows: []
            )
        }

        guard clearBlankImportedValues || dataRows.contains(where: isUsableCSVDataRow) else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one CSV data row with values to import."),
                rows: []
            )
        }

        let parsedRecords = dataRows.enumerated().map { index, cells in
            let displayText = cells.map {
                $0.decodedValue.replacingOccurrences(of: "\n", with: " ")
            }.joined(separator: " | ")
            if cells.count < result.columns.count {
                let missingCount = result.columns.count - cells.count
                return ParsedExternalRecord(
                    index: index,
                    displayText: displayText,
                    captures: .failure("\(missingCount) missing CSV column(s).")
                )
            }
            if cells.count > result.columns.count {
                let extraCount = cells.count - result.columns.count
                return ParsedExternalRecord(
                    index: index,
                    displayText: displayText,
                    captures: .failure("\(extraCount) extra CSV column(s).")
                )
            }

            return ParsedExternalRecord(
                index: index,
                displayText: displayText,
                captures: captures(from: cells, columns: result.columns)
            )
        }

        return makeImportPlan(
            parsedRecords: parsedRecords,
            fields: result.columns,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues
        )
    }

    static func parseCSVColumnTemplate(_ template: String) -> (columns: [MetadataExchangeField], delimiter: Character, validationMessage: String?) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ([], ",", L10n.string("Enter a comma-, semicolon-, pipe-, or tab-delimited column template."))
        }

        guard trimmed.utf8.count <= maximumTemplateUTF8ByteCount else {
            return ([], ",", L10n.string("The column template is too large."))
        }

        let delimiter = MetadataExchangeCSV.detectDelimiter(in: trimmed)
        do {
            let rows = try MetadataExchangeCSV.parse(trimmed, delimiter: delimiter)
            guard rows.count == 1, let row = rows.first, !row.isEmpty else {
                return ([], delimiter, L10n.string("Enter a single CSV template row."))
            }


            guard row.count <= MetadataExchangeField.allCases.count + 64 else {
                return ([], delimiter, L10n.string("The column template contains too many columns."))
            }

            var columns: [MetadataExchangeField] = []
            var seenFields = Set<MetadataExchangeField>()
            for cell in row {
                guard let field = MetadataExchangeField.field(forExactToken: cell) else {
                    return (columns, delimiter, "Each CSV template column must be one supported field token, such as {{title}}.")
                }

                if field != .ignore, seenFields.contains(field) {
                    return (columns, delimiter, "Use each CSV field at most once so imported values cannot conflict.")
                }

                seenFields.insert(field)
                columns.append(field)
            }

            guard columns.contains(where: { $0 != .ignore }) else {
                return (columns, delimiter, L10n.string("Add at least one output field to the CSV template."))
            }

            return (columns, delimiter, nil)
        } catch {
            return ([], delimiter, (error as NSError).localizedDescription)
        }
    }

    private static func render(
        document: MetadataExchangeTemplateDocument,
        file: AudioFile,
        index: Int,
        relativeBasePath: String?
    ) -> String {
        document.segments.map { segment in
            switch segment {
            case .literal(let literal):
                return literal
            case .field(let field):
                return field.value(from: file, index: index, relativeBasePath: relativeBasePath)
            }
        }.joined()
    }

    private static func validateImportTextTemplate(_ document: MetadataExchangeTemplateDocument) -> String? {
        if document.isEmpty {
            return L10n.string("Enter a text template to parse imported records.")
        }

        if let validationMessage = validateTemplateSyntax(document, requiresSingleLine: true) {
            return validationMessage
        }

        guard document.hasWritableMetadataFields else {
            return L10n.string("Add at least one writable metadata field to import.")
        }

        for index in document.segments.indices.dropLast() {
            guard case .field = document.segments[index],
                  case .field = document.segments[index + 1]
            else {
                continue
            }
            return L10n.string("Add literal separators between fields so each text line can be parsed unambiguously.")
        }

        return nil
    }

    private static func validateTemplateSyntax(
        _ document: MetadataExchangeTemplateDocument,
        requiresSingleLine: Bool
    ) -> String? {
        if document.rawValue.utf8.count > maximumTemplateUTF8ByteCount {
            return L10n.string("The text template is too large.")
        }

        if document.segments.count > 256 {
            return L10n.string("The text template contains too many segments.")
        }

        if document.hasUnterminatedPlaceholder {
            return L10n.string("Close every template field with }}.")
        }

        if let unknownPlaceholderName = document.unknownPlaceholderNames.first {
            let name = unknownPlaceholderName.isEmpty ? "{{}}" : "{{\(unknownPlaceholderName)}}"
            return "\(name) is not a supported metadata field."
        }

        if requiresSingleLine,
           document.rawValue.unicodeScalars.contains(where: { $0.value == 0x0A || $0.value == 0x0D }) {
            return L10n.string("Use a single-line template. Use CSV for multiline metadata.")
        }

        return nil
    }

    private static func captures(
        from cells: [MetadataExchangeCSVField],
        columns: [MetadataExchangeField]
    ) -> MetadataExchangeCaptureResult {
        var captures: [MetadataExchangeField: String] = [:]
        for (index, field) in columns.enumerated() {
            guard field != .ignore else { continue }
            let importedValue = field.canonicalImportedValue(cells[index].importedValue)
            if let validationMessage = field.importedValueValidationMessage(importedValue) {
                return .failure(validationMessage)
            }
            captures[field] = importedValue
        }
        return .success(captures)
    }

    nonisolated private static func isUsableCSVDataRow(_ cells: [MetadataExchangeCSVField]) -> Bool {
        cells.contains(where: \.hasImportContent)
    }

    private static func makeImportPlan(
        parsedRecords: [ParsedExternalRecord],
        fields: [MetadataExchangeField],
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool
    ) -> MetadataExchangeImportPlan {
        let uniqueFiles = uniqueTargetFiles(targetFiles)
        guard uniqueFiles.count <= maximumImportRecordCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The selection contains more than 100,000 files. Import into a smaller selection."),
                rows: []
            )
        }

        var seenLocatorFields = Set<MetadataExchangeField>()
        let locatorFields = fields.filter { field in
            field.isLocatorField && seenLocatorFields.insert(field).inserted
        }
        let rows: [MetadataExchangeImportPreviewRow]

        if !locatorFields.isEmpty {
            rows = makeMatchedImportRows(
                parsedRecords: parsedRecords,
                targetFiles: uniqueFiles,
                locatorFields: locatorFields,
                clearBlankImportedValues: clearBlankImportedValues
            )
        } else {
            rows = makeSelectionOrderImportRows(
                parsedRecords: parsedRecords,
                targetFiles: uniqueFiles,
                clearBlankImportedValues: clearBlankImportedValues
            )
        }

        return MetadataExchangeImportPlan(validationMessage: nil, rows: rows)
    }

    private static func makeSelectionOrderImportRows(
        parsedRecords: [ParsedExternalRecord],
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool
    ) -> [MetadataExchangeImportPreviewRow] {
        let count = max(parsedRecords.count, targetFiles.count)
        return (0..<count).map { index in
            let record = index < parsedRecords.count ? parsedRecords[index] : nil
            let file = index < targetFiles.count ? targetFiles[index] : nil

            guard let file else {
                return MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: nil,
                    fileName: "—",
                    externalRecord: record?.displayText ?? "",
                    status: .extraExternalRecord,
                    changes: [],
                    issueMessage: L10n.string("This record has no selected file at the same position."),
                    writeEntry: nil
                )
            }

            guard let record else {
                return MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    externalRecord: "",
                    status: .missingExternalRecord,
                    changes: [],
                    issueMessage: L10n.string("This selected file has no external record at the same position."),
                    writeEntry: nil
                )
            }

            return makeImportRow(
                file: file,
                record: record,
                clearBlankImportedValues: clearBlankImportedValues
            )
        }
    }

    private static func makeMatchedImportRows(
        parsedRecords: [ParsedExternalRecord],
        targetFiles: [AudioFile],
        locatorFields: [MetadataExchangeField],
        clearBlankImportedValues: Bool
    ) -> [MetadataExchangeImportPreviewRow] {
        let candidateIndex = MetadataExchangeLocatorCandidateIndex(
            itemCount: targetFiles.count,
            fields: locatorFields
        ) { field, fileIndex in
            locatorIndexKeys(
                field: field,
                file: targetFiles[fileIndex],
                fileIndex: fileIndex
            )
        }
        var matchCache: [LocatorSignature: LocatorMatch] = [:]

        let resolutions: [(record: ParsedExternalRecord, resolution: LocatorResolution)] = parsedRecords.map { record in
            switch record.captures {
            case .failure(let message):
                return (record, .parseError(message))
            case .success(let captures):
                let description = locatorDescription(captures: captures, locatorFields: locatorFields)
                guard let signature = locatorSignature(captures: captures, locatorFields: locatorFields) else {
                    return (record, .noMatch(description))
                }

                let match: LocatorMatch
                if let cachedMatch = matchCache[signature] {
                    match = cachedMatch
                } else {
                    let candidateIndices = candidateIndex.candidateIndices(fields: locatorFields) { field in
                        locatorLookupKey(captures[field] ?? "", field: field)
                    }
                    let matchingFiles = candidateIndices.compactMap { fileIndex -> AudioFile? in
                        let file = targetFiles[fileIndex]
                        return matchesAllLocators(
                            captures: captures,
                            locatorFields: locatorFields,
                            file: file,
                            fileIndex: fileIndex
                        ) ? file : nil
                    }

                    switch matchingFiles.count {
                    case 0:
                        match = .none
                    case 1:
                        match = .matched(matchingFiles[0])
                    default:
                        match = .ambiguous
                    }
                    matchCache[signature] = match
                }

                switch match {
                case .none:
                    return (record, .noMatch(description))
                case .ambiguous:
                    return (record, .ambiguous(description))
                case .matched(let file):
                    return (record, .matched(file))
                }
            }
        }

        var recordCountByFileID: [AudioFile.ID: Int] = [:]
        for item in resolutions {
            if case .matched(let file) = item.resolution {
                recordCountByFileID[file.id, default: 0] += 1
            }
        }

        var matchedFileIDs = Set<AudioFile.ID>()
        var rows: [MetadataExchangeImportPreviewRow] = []

        for item in resolutions {
            let record = item.record
            switch item.resolution {
            case .parseError(let message):
                rows.append(parseErrorRow(record: record, message: message))
            case .noMatch(let description):
                rows.append(
                    MetadataExchangeImportPreviewRow(
                        id: UUID(),
                        fileID: nil,
                        fileName: description,
                        externalRecord: record.displayText,
                        status: .noMatch,
                        changes: [],
                        issueMessage: L10n.string("No selected file matches all locator values in this record."),
                        writeEntry: nil
                    )
                )
            case .ambiguous(let description):
                rows.append(
                    MetadataExchangeImportPreviewRow(
                        id: UUID(),
                        fileID: nil,
                        fileName: description,
                        externalRecord: record.displayText,
                        status: .ambiguousMatch,
                        changes: [],
                        issueMessage: L10n.string("Multiple selected files match this record. Add Path or Relative Path to disambiguate them."),
                        writeEntry: nil
                    )
                )
            case .matched(let file):
                if recordCountByFileID[file.id, default: 0] > 1 {
                    rows.append(
                        MetadataExchangeImportPreviewRow(
                            id: UUID(),
                            fileID: file.id,
                            fileName: file.url.lastPathComponent,
                            externalRecord: record.displayText,
                            status: .ambiguousMatch,
                            changes: [],
                            issueMessage: L10n.string("Multiple external records identify this selected file. None of them will be written."),
                            writeEntry: nil
                        )
                    )
                } else {
                    matchedFileIDs.insert(file.id)
                    rows.append(makeImportRow(
                        file: file,
                        record: record,
                        clearBlankImportedValues: clearBlankImportedValues
                    ))
                }
            }
        }

        for file in targetFiles where !matchedFileIDs.contains(file.id) {
            rows.append(
                MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    externalRecord: "",
                    status: .missingExternalRecord,
                    changes: [],
                    issueMessage: L10n.string("No external record matched this selected file."),
                    writeEntry: nil
                )
            )
        }

        return rows
    }

    private static func matchesAllLocators(
        captures: [MetadataExchangeField: String],
        locatorFields: [MetadataExchangeField],
        file: AudioFile,
        fileIndex: Int
    ) -> Bool {
        locatorFields.allSatisfy { field in
            guard let importedValue = captures[field] else { return false }

            switch field {
            case .fileName:
                return nonEmptyMatchingKey(importedValue) == nonEmptyMatchingKey(file.url.lastPathComponent)
            case .baseName:
                return nonEmptyMatchingKey(importedValue) == nonEmptyMatchingKey(file.url.deletingPathExtension().lastPathComponent)
            case .path:
                guard let importedPath = normalizedAbsolutePath(importedValue) else { return false }
                return importedPath == normalizedAbsolutePath(file.url.path)
            case .relativePath:
                guard
                    let importedPath = normalizedRelativePath(importedValue),
                    let filePath = normalizedAbsolutePath(file.url.path)
                else {
                    return false
                }
                return filePath.hasSuffix("/\(importedPath)")
            case .index:
                return positiveIndex(importedValue) == fileIndex + 1
            case .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
                    .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal,
                    .discNumber, .discTotal, .comment, .releaseDate, .publisher,
                    .copyright, .isrc, .barcode, .language, .mediaType, .releaseType,
                    .catalogNumber, .releaseCountry, .itunesAlbumID, .itunesArtistID,
                    .itunesCatalogID, .musicBrainzAlbumID, .musicBrainzTrackID,
                    .musicBrainzReleaseGroupID, .contentAdvisory, .ignore:
                return false
            }
        }
    }

    private static func locatorSignature(
        captures: [MetadataExchangeField: String],
        locatorFields: [MetadataExchangeField]
    ) -> LocatorSignature? {
        var values: [String] = []
        values.reserveCapacity(locatorFields.count)
        for field in locatorFields {
            guard let value = captures[field], let key = locatorLookupKey(value, field: field) else {
                return nil
            }
            values.append(key)
        }
        return LocatorSignature(values: values)
    }

    private static func locatorIndexKeys(
        field: MetadataExchangeField,
        file: AudioFile,
        fileIndex: Int
    ) -> [String] {
        switch field {
        case .fileName:
            return nonEmptyMatchingKey(file.url.lastPathComponent).map { [$0] } ?? []
        case .baseName:
            return nonEmptyMatchingKey(file.url.deletingPathExtension().lastPathComponent).map { [$0] } ?? []
        case .path:
            return normalizedAbsolutePath(file.url.path).map { [$0] } ?? []
        case .relativePath:
            guard let path = normalizedAbsolutePath(file.url.path) else { return [] }
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.indices.map { index in
                components[index...].joined(separator: "/")
            }
        case .index:
            return [String(fileIndex + 1)]
        case .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
                .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal,
                .discNumber, .discTotal, .comment, .releaseDate, .publisher,
                .copyright, .isrc, .barcode, .language, .mediaType, .releaseType,
                .catalogNumber, .releaseCountry, .itunesAlbumID, .itunesArtistID,
                .itunesCatalogID, .musicBrainzAlbumID, .musicBrainzTrackID,
                .musicBrainzReleaseGroupID, .contentAdvisory, .ignore:
            return []
        }
    }

    private static func locatorLookupKey(
        _ value: String,
        field: MetadataExchangeField
    ) -> String? {
        switch field {
        case .fileName, .baseName:
            return nonEmptyMatchingKey(value)
        case .path:
            return normalizedAbsolutePath(value)
        case .relativePath:
            return normalizedRelativePath(value)
        case .index:
            return positiveIndex(value).map(String.init)
        case .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
                .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal,
                .discNumber, .discTotal, .comment, .releaseDate, .publisher,
                .copyright, .isrc, .barcode, .language, .mediaType, .releaseType,
                .catalogNumber, .releaseCountry, .itunesAlbumID, .itunesArtistID,
                .itunesCatalogID, .musicBrainzAlbumID, .musicBrainzTrackID,
                .musicBrainzReleaseGroupID, .contentAdvisory, .ignore:
            return nil
        }
    }

    private static func locatorDescription(
        captures: [MetadataExchangeField: String],
        locatorFields: [MetadataExchangeField]
    ) -> String {
        let values = locatorFields.compactMap { field -> String? in
            guard let value = captures[field]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }
        return values.isEmpty ? "—" : values.joined(separator: " | ")
    }

    private static func positiveIndex(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            trimmed.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
            let index = Int(trimmed),
            index > 0
        else {
            return nil
        }
        return index
    }

    private static func normalizedAbsolutePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let path: String
        if trimmed.lowercased().hasPrefix("file:") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            let host = url.host?.lowercased()
            guard host == nil || host == "" || host == "localhost" else { return nil }
            path = url.path
        } else {
            path = trimmed
        }

        guard (path as NSString).isAbsolutePath else { return nil }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            .precomposedStringWithCanonicalMapping
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedRelativePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            !(trimmed as NSString).isAbsolutePath,
            !trimmed.lowercased().hasPrefix("file:")
        else {
            return nil
        }

        let normalizedBasePath = "/__AudioMatorRelativePathRoot__"
        let baseURL = URL(fileURLWithPath: normalizedBasePath, isDirectory: true)
        let resolvedPath = URL(fileURLWithPath: trimmed, relativeTo: baseURL).standardizedFileURL.path
        let basePrefix = normalizedBasePath + "/"
        guard resolvedPath.hasPrefix(basePrefix) else { return nil }
        let relative = String(resolvedPath.dropFirst(basePrefix.count))
            .precomposedStringWithCanonicalMapping
        return relative.isEmpty ? nil : relative
    }

    private static func nonEmptyMatchingKey(_ value: String) -> String? {
        let key = matchingKey(value)
        return key.isEmpty ? nil : key
    }

    private static func matchingKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
    }

    private static func makeImportRow(
        file: AudioFile,
        record: ParsedExternalRecord,
        clearBlankImportedValues: Bool
    ) -> MetadataExchangeImportPreviewRow {
        switch record.captures {
        case .failure(let message):
            return parseErrorRow(record: record, file: file, message: message)
        case .success(let captures):
            for (field, importedValue) in captures where field.isWritableMetadataField {
                if let validationMessage = field.importedValueValidationMessage(importedValue) {
                    return parseErrorRow(record: record, file: file, message: validationMessage)
                }
            }

            let changes = MetadataExchangeField.allCases.compactMap { field -> MetadataExchangeFieldChange? in
                guard field.isWritableMetadataField, let importedValue = captures[field] else { return nil }
                let currentValue = field.value(from: file, index: 0, relativeBasePath: nil)
                let shouldWriteBlank = clearBlankImportedValues && importedValue.isEmpty
                let willWrite = (shouldWriteBlank || !importedValue.isEmpty) && currentValue != importedValue
                return MetadataExchangeFieldChange(
                    field: field,
                    currentValue: currentValue,
                    importedValue: importedValue,
                    willWrite: willWrite
                )
            }

            guard !changes.isEmpty else {
                return MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    externalRecord: record.displayText,
                    status: .noWritableFields,
                    changes: [],
                    issueMessage: L10n.string("This record did not contain writable metadata fields."),
                    writeEntry: nil
                )
            }

            let values = Dictionary(
                uniqueKeysWithValues: changes
                    .filter(\.willWrite)
                    .map { ($0.field, $0.importedValue) }
            )
            let writeEntry: MetadataExchangeWriteEntry?
            let status: MetadataExchangePreviewStatus
            let issueMessage: String?
            if values.isEmpty {
                writeEntry = nil
                status = .unchanged
                issueMessage = record.warning
            } else if let expectedFileFingerprint = file.fileFingerprint {
                writeEntry = MetadataExchangeWriteEntry(
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    values: values,
                    expectedFileFingerprint: expectedFileFingerprint
                )
                status = .ready
                issueMessage = record.warning
            } else {
                writeEntry = nil
                status = .sourceUnavailable
                issueMessage = L10n.string("The file version could not be verified. Reload the file and try again.")
            }
            return MetadataExchangeImportPreviewRow(
                id: UUID(),
                fileID: file.id,
                fileName: file.url.lastPathComponent,
                externalRecord: record.displayText,
                status: status,
                changes: changes,
                issueMessage: issueMessage,
                writeEntry: writeEntry
            )
        }
    }

    private static func parseErrorRow(
        record: ParsedExternalRecord,
        file: AudioFile? = nil,
        message: String
    ) -> MetadataExchangeImportPreviewRow {
        MetadataExchangeImportPreviewRow(
            id: UUID(),
            fileID: file?.id,
            fileName: file?.url.lastPathComponent ?? "—",
            externalRecord: record.displayText,
            status: .parseError,
            changes: [],
            issueMessage: message,
            writeEntry: nil
        )
    }

    private static func commonDirectoryPath(for files: [AudioFile]) -> String? {
        guard let first = files.first?.url.deletingLastPathComponent().path else { return nil }
        var components = first.split(separator: "/").map(String.init)

        for file in files.dropFirst() {
            let pathComponents = file.url.deletingLastPathComponent().path.split(separator: "/").map(String.init)
            let sharedCount = zip(components, pathComponents).prefix { $0 == $1 }.count
            components = Array(components.prefix(sharedCount))
        }

        return "/" + components.joined(separator: "/")
    }

    private static func uniqueTargetFiles(_ files: [AudioFile]) -> [AudioFile] {
        var seenIDs = Set<AudioFile.ID>()
        return files.filter { seenIDs.insert($0.id).inserted }
    }

    private enum LocatorResolution {
        case parseError(String)
        case noMatch(String)
        case ambiguous(String)
        case matched(AudioFile)
    }

    private enum LocatorMatch {
        case none
        case ambiguous
        case matched(AudioFile)
    }

    private struct LocatorSignature: Hashable {
        let values: [String]
    }
}

private struct ParsedExternalRecord {
    let index: Int
    let displayText: String
    let captures: MetadataExchangeCaptureResult
    var warning: String? = nil
}

private enum MetadataExchangeCaptureResult {
    case success([MetadataExchangeField: String])
    case failure(String)
}

private struct MetadataExchangeTextMatcher {
    let document: MetadataExchangeTemplateDocument

    private static let maximumMatchSteps = 50_000
    private static let maximumLiteralCandidates = 4_096

    private struct MatchBudget {
        var remainingSteps: Int

        mutating func consume() -> Bool {
            guard remainingSteps > 0 else { return false }
            remainingSteps -= 1
            return true
        }
    }

    private enum SearchResult {
        case success([MetadataExchangeField: String])
        case failure(String)
        case ambiguous
        case tooComplex
    }

    func match(_ source: String) -> MetadataExchangeCaptureResult {
        var budget = MatchBudget(remainingSteps: Self.maximumMatchSteps)
        switch matchSegments(
            document.segments,
            in: source,
            at: 0,
            sourceIndex: source.startIndex,
            captures: [:],
            budget: &budget
        ) {
        case .success(let captures):
            return .success(captures)
        case .failure(let message):
            return .failure(message)
        case .ambiguous:
            return .failure(L10n.string("The record matches the template in more than one way. Add more specific separators or use CSV import."))
        case .tooComplex:
            return .failure(L10n.string("The record is too complex to match safely. Use CSV import or a simpler template."))
        }
    }

    private func matchSegments(
        _ segments: [MetadataExchangeTemplateSegment],
        in source: String,
        at segmentIndex: Int,
        sourceIndex: String.Index,
        captures: [MetadataExchangeField: String],
        budget: inout MatchBudget
    ) -> SearchResult {
        guard budget.consume() else { return .tooComplex }

        if segmentIndex >= segments.count {
            return sourceIndex == source.endIndex
                ? .success(captures)
                : .failure(L10n.string("The record has trailing text that does not match the template."))
        }

        switch segments[segmentIndex] {
        case .literal(let literal):
            guard source[sourceIndex...].hasPrefix(literal) else {
                return .failure(L10n.string("The record did not match the template literals."))
            }
            let nextSourceIndex = source.index(sourceIndex, offsetBy: literal.count)
            return matchSegments(
                segments,
                in: source,
                at: segmentIndex + 1,
                sourceIndex: nextSourceIndex,
                captures: captures,
                budget: &budget
            )

        case .field(let field):
            let nextSegmentIndex = segmentIndex + 1
            guard nextSegmentIndex < segments.count else {
                switch captureValue(String(source[sourceIndex...]), for: field, into: captures) {
                case .success(let capturedValues):
                    return .success(capturedValues)
                case .failure(let message):
                    return .failure(message)
                }
            }

            guard case .literal(let nextLiteral) = segments[nextSegmentIndex] else {
                return .failure(L10n.string("Adjacent fields need a literal separator."))
            }

            guard let literalPositions = findLiteralPositions(
                nextLiteral,
                in: source,
                startingAt: sourceIndex
            ) else {
                return .tooComplex
            }

            var uniqueCapture: [MetadataExchangeField: String]?
            var lastFailure: String?
            for literalPosition in literalPositions.reversed() {
                switch captureValue(String(source[sourceIndex..<literalPosition]), for: field, into: captures) {
                case .failure(let message):
                    lastFailure = message
                    continue
                case .success(let updatedCaptures):
                    let result = matchSegments(
                        segments,
                        in: source,
                        at: nextSegmentIndex,
                        sourceIndex: literalPosition,
                        captures: updatedCaptures,
                        budget: &budget
                    )
                    switch result {
                    case .success(let capturedValues):
                        if let uniqueCapture, uniqueCapture != capturedValues {
                            return .ambiguous
                        }
                        uniqueCapture = capturedValues
                    case .failure(let message):
                        lastFailure = message
                    case .ambiguous:
                        return .ambiguous
                    case .tooComplex:
                        return .tooComplex
                    }
                }
            }

            if let uniqueCapture {
                return .success(uniqueCapture)
            }
            return .failure(lastFailure ?? L10n.string("The record did not match the template."))
        }
    }

    private func captureValue(
        _ rawValue: String,
        for field: MetadataExchangeField,
        into captures: [MetadataExchangeField: String]
    ) -> MetadataExchangeCaptureResult {
        guard field != .ignore else { return .success(captures) }

        let value = field.canonicalImportedValue(
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let validationMessage = field.importedValueValidationMessage(value) {
            return .failure(validationMessage)
        }
        if let existingValue = captures[field], existingValue != value {
            return .failure("The field \(field.displayName) was captured more than once with different values.")
        }

        var updatedCaptures = captures
        updatedCaptures[field] = value
        return .success(updatedCaptures)
    }

    private func findLiteralPositions(
        _ literal: String,
        in source: String,
        startingAt startIndex: String.Index
    ) -> [String.Index]? {
        guard !literal.isEmpty else { return [startIndex] }

        var positions: [String.Index] = []
        var searchStart = startIndex
        while searchStart < source.endIndex,
              let range = source[searchStart...].range(of: literal) {
            guard positions.count < Self.maximumLiteralCandidates else { return nil }
            positions.append(range.lowerBound)
            searchStart = source.index(after: range.lowerBound)
        }
        return positions
    }
}
