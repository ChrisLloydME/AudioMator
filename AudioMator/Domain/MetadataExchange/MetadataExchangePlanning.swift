import Foundation
import TagLibAudioMetadata

nonisolated struct MetadataTextExportRow: Identifiable, Sendable {
    let id: AudioFile.ID
    let fileName: String
    let output: String
}
nonisolated struct MetadataTextExportPlan: Sendable {
    let validationMessage: String?
    let rows: [MetadataTextExportRow]

    var outputText: String {
        [MetadataExchangeProfile.markerLine(), rows.map(\.output).joined(separator: "\n")]
            .joined(separator: "\n")
    }

    var canExport: Bool {
        validationMessage == nil && !rows.isEmpty
    }
}

nonisolated struct MetadataCSVExportPlan: Sendable {
    let validationMessage: String?
    let columns: [MetadataExchangeField]
    let rows: [[String]]
    let includeHeaderRow: Bool
    let delimiter: Character
    let preencodedOutputText: String?

    init(
        validationMessage: String?,
        columns: [MetadataExchangeField],
        rows: [[String]],
        includeHeaderRow: Bool,
        delimiter: Character,
        preencodedOutputText: String? = nil
    ) {
        self.validationMessage = validationMessage
        self.columns = columns
        self.rows = rows
        self.includeHeaderRow = includeHeaderRow
        self.delimiter = delimiter
        self.preencodedOutputText = preencodedOutputText
    }

    var outputText: String {
        if let preencodedOutputText {
            return preencodedOutputText
        }
        var outputRows: [[String]] = []
        if includeHeaderRow {
            outputRows.append(columns.map(\.displayName))
        }
        outputRows.append(contentsOf: rows)
        return MetadataExchangeProfile.markerLine()
            + "\r\n"
            + MetadataExchangeCSV.serialize(outputRows, delimiter: delimiter)
    }

    var canExport: Bool {
        validationMessage == nil && !rows.isEmpty
    }
}

nonisolated enum MetadataExchangePreviewStatus: Equatable, Sendable {
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
            return L10n.string("No Match Found")
        case .ambiguousMatch:
            return L10n.string("More Than One Match")
        case .parseError:
            return L10n.string("Record Needs Review")
        case .sourceUnavailable:
            return L10n.string("Couldn't Check File")
        case .missingExternalRecord:
            return L10n.string("No Import Record")
        case .extraExternalRecord:
            return L10n.string("Record Without a File")
        case .noWritableFields:
            return L10n.string("No Editable Fields")
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

nonisolated struct MetadataExchangeFieldChange: Identifiable, Sendable {
    let field: MetadataExchangeField
    let currentValue: String
    let importedValue: String
    let willWrite: Bool
    /// True for a typed explicit removal (profile-v2 token, zero number
    /// component, or clear-enabled blank). Distinct from a literal value that
    /// happens to be empty.
    var isExplicitRemoval: Bool = false

    var id: String { field.placeholderName }

    /// Preview text for an explicit removal, distinct from a literal value.
    /// A literal value (even one matching the retired sentinel string) is never
    /// interpreted or displayed as `<remove>`.
    var displayImportedValue: String {
        isExplicitRemoval
            ? MetadataExchangeProfile.removalToken
            : importedValue
    }
}

nonisolated struct MetadataExchangeWriteEntry: Identifiable, Sendable {
    let fileName: String
    /// Frozen reviewed write captured during planning. This is the only value the
    /// strict Apply path consumes; it cannot be rebuilt from the live model.
    let write: ReviewedMetadataWrite
    /// Resolved typed intent kept for preview truth/tests. One intent, one write.
    let resolvedIntent: ExchangeResolvedIntent?

    var id: AudioFile.ID { write.target.id }
    var fileID: AudioFile.ID { write.target.id }

    var frozenPayload: MetadataEditPayload? {
        guard case .semantic(let payload) = write.intent else { return nil }
        return payload
    }

    var frozenProjection: MetadataWriteProjection { write.projection }
    var frozenTarget: ReviewedMetadataTarget { write.target }

    /// Presentation-only flattened values derived from the frozen intent and the
    /// adapter projection. Never used to build a commit.
    var previewValues: [MetadataExchangeField: String] {
        guard let resolvedIntent, let payload = frozenPayload else { return [:] }
        let effectiveFields = payload.requestedFields
        var values: [MetadataExchangeField: String] = [:]
        for operation in resolvedIntent.operations {
            switch operation {
            case .setText(let field, let text):
                guard effectiveFields.contains(field.semanticFieldKey ?? .title) else { continue }
                values[field] = field.canonicalImportedValue(text)
            case .removeText(let field):
                guard effectiveFields.contains(field.semanticFieldKey ?? .title) else { continue }
                values[field] = ""
            case .setNumber(let field, _, let literalText):
                values[field] = literalText
            case .removeNumber(let field):
                values[field] = ""
            }
        }
        return values
    }
}

nonisolated struct MetadataExchangeImportPreviewRow: Identifiable, Sendable {
    let id: UUID
    let fileID: AudioFile.ID?
    let fileName: String
    let externalRecord: String
    let status: MetadataExchangePreviewStatus
    let changes: [MetadataExchangeFieldChange]
    let issueMessage: String?
    let writeEntry: MetadataExchangeWriteEntry?
}

nonisolated struct MetadataExchangeImportPlan: Sendable {
    let validationMessage: String?
    let rows: [MetadataExchangeImportPreviewRow]
    /// Set when positional records cannot be mapped one-to-one to the reviewed
    /// ordered targets. The plan carries no writable entries in that case; Apply
    /// must stay blocked until the user fixes the records or uses a locator.
    let blockingMessage: String?

    init(
        validationMessage: String?,
        rows: [MetadataExchangeImportPreviewRow],
        blockingMessage: String? = nil
    ) {
        self.validationMessage = validationMessage
        self.rows = rows
        self.blockingMessage = blockingMessage
    }

    var writeEntries: [MetadataExchangeWriteEntry] {
        blockingMessage == nil && validationMessage == nil
            ? rows.compactMap(\.writeEntry)
            : []
    }

    var canApply: Bool {
        validationMessage == nil && blockingMessage == nil && !writeEntries.isEmpty
    }

    var readyCount: Int {
        writeEntries.count
    }

    var issueCount: Int {
        rows.filter { $0.status.isIssue }.count
            + (validationMessage == nil ? 0 : 1)
            + (blockingMessage == nil ? 0 : 1)
    }
}

nonisolated enum MetadataExchangePlanner {
    private static let maximumTemplateUTF8ByteCount = 16_384
    private static let maximumImportUTF8ByteCount = MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount
    private static let maximumImportRecordCount = MetadataExchangeResourceLimits.maximumRecordCount
    private static let maximumTextRecordUTF8ByteCount = MetadataExchangeResourceLimits.maximumTextRecordUTF8ByteCount
    private static let maximumCSVFieldUTF8ByteCount = MetadataExchangeResourceLimits.maximumCSVFieldUTF8ByteCount

    // MARK: – Export

    static func makeTextExportPlan(
        template: String,
        targetFiles: [AudioFile]
    ) -> MetadataTextExportPlan {
        guard template.utf8.count <= maximumTemplateUTF8ByteCount else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("This text template is too long. Shorten it before continuing."),
                rows: []
            )
        }

        let document = MetadataExchangeTemplateDocument(rawValue: template)
        if document.isEmpty {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("Enter a template to see an export preview."),
                rows: []
            )
        }

        if let validationMessage = validateTemplateSyntax(document, requiresSingleLine: true) {
            return MetadataTextExportPlan(validationMessage: validationMessage, rows: [])
        }

        guard document.fields.contains(where: { $0 != .ignore }) else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("Add at least one metadata field to the export template."),
                rows: []
            )
        }

        let uniqueFiles = uniqueTargetFiles(targetFiles)
        if document.fields.contains(where: \.isIndependentDateField),
           uniqueFiles.contains(where: { $0.hasUnverifiedIndependentDateProjection }) {
            return MetadataTextExportPlan(validationMessage: String(localized: "These separate date fields couldn’t be verified in ID3v2.3 tags. Leave them out of this export."), rows: [])
        }
        guard uniqueFiles.count <= MetadataExchangeResourceLimits.maximumRecordCount else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("You can export up to 100,000 files at a time. Select fewer files."),
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
        // Include the profile marker line in the 32 MB export budget so any
        // budgeted export fits within the import byte cap.
        guard outputBudget.append(recordUTF8ByteCount: MetadataExchangeProfile.markerLine().utf8.count) else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("This export would exceed 32 MB. Select fewer files."),
                rows: []
            )
        }
        var containsMultilineRecord = false

        for (index, file) in uniqueFiles.enumerated() {
            // Cancellation propagates into export rendering and encoding.
            if Task.isCancelled {
                return MetadataTextExportPlan(validationMessage: nil, rows: [])
            }
            let output = render(
                document: document,
                file: file,
                index: index,
                relativeBasePath: relativeBasePath
            )
            let outputUTF8ByteCount = output.utf8.count
            guard outputUTF8ByteCount <= MetadataExchangeResourceLimits.maximumTextRecordUTF8ByteCount else {
                return MetadataTextExportPlan(
                    validationMessage: L10n.string("One exported record would exceed 256 KB. Use CSV export or shorten the values in that record."),
                    rows: []
                )
            }
            guard outputBudget.append(recordUTF8ByteCount: outputUTF8ByteCount) else {
                return MetadataTextExportPlan(
                    validationMessage: L10n.string("This export would exceed 32 MB. Select fewer files."),
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
                ? L10n.string("Some values contain line breaks. Use CSV export to keep those values intact.")
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
        if result.columns.contains(where: \.isIndependentDateField),
           uniqueFiles.contains(where: { $0.hasUnverifiedIndependentDateProjection }) {
            return MetadataCSVExportPlan(validationMessage: String(localized: "These separate date fields couldn’t be verified in ID3v2.3 tags. Leave them out of this export."), columns: result.columns, rows: [], includeHeaderRow: includeHeaderRow, delimiter: result.delimiter)
        }
        guard uniqueFiles.count <= MetadataExchangeResourceLimits.maximumRecordCount else {
            return MetadataCSVExportPlan(
                validationMessage: L10n.string("You can export up to 100,000 files at a time. Select fewer files."),
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
        let markerLine = MetadataExchangeProfile.markerLine()
        guard outputBudget.append(recordUTF8ByteCount: markerLine.utf8.count) else {
            return MetadataCSVExportPlan(
                validationMessage: L10n.string("This export would exceed 32 MB. Select fewer files."),
                columns: result.columns,
                rows: [],
                includeHeaderRow: includeHeaderRow,
                delimiter: result.delimiter
            )
        }

        var serializedLines: [String] = [markerLine]
        serializedLines.reserveCapacity(uniqueFiles.count + (includeHeaderRow ? 2 : 1))

        if includeHeaderRow {
            let header = result.columns.map(\.displayName)
            let serializedHeader = MetadataExchangeCSV.serialize([header], delimiter: result.delimiter)
            guard outputBudget.append(recordUTF8ByteCount: serializedHeader.utf8.count) else {
                return MetadataCSVExportPlan(
                    validationMessage: L10n.string("This export would exceed 32 MB. Select fewer files."),
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }
            serializedLines.append(serializedHeader)
        }

        for (index, file) in uniqueFiles.enumerated() {
            // Cancellation propagates into export rendering and CSV encoding.
            if Task.isCancelled {
                return MetadataCSVExportPlan(
                    validationMessage: nil,
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }
            let row = result.columns.map { field in
                field.value(from: file, index: index, relativeBasePath: relativeBasePath)
            }
            let hasOversizedField = row.contains { value in
                MetadataExchangeCSV.spreadsheetProtectedValue(value).utf8.count >
                    MetadataExchangeResourceLimits.maximumCSVFieldUTF8ByteCount
            }
            guard !hasOversizedField else {
                return MetadataCSVExportPlan(
                    validationMessage: L10n.string("One CSV cell would exceed 1 MB. Shorten that field's value before exporting."),
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }

            let serializedRow = MetadataExchangeCSV.serialize([row], delimiter: result.delimiter)
            guard outputBudget.append(recordUTF8ByteCount: serializedRow.utf8.count) else {
                return MetadataCSVExportPlan(
                    validationMessage: L10n.string("This export would exceed 32 MB. Select fewer files."),
                    columns: result.columns,
                    rows: [],
                    includeHeaderRow: includeHeaderRow,
                    delimiter: result.delimiter
                )
            }
            serializedLines.append(serializedRow)
            rows.append(row)
        }

        return MetadataCSVExportPlan(
            validationMessage: nil,
            columns: result.columns,
            rows: rows,
            includeHeaderRow: includeHeaderRow,
            delimiter: result.delimiter,
            preencodedOutputText: serializedLines.joined(separator: "\r\n")
        )
    }

    // MARK: – Text import

    static func makeTextImportPlan(
        template: String,
        sourceText: String,
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool,
        projector: (any AudioMetadataPipeline)? = nil
    ) -> MetadataExchangeImportPlan {
        guard template.utf8.count <= maximumTemplateUTF8ByteCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("This text template is too long. Shorten it before continuing."),
                rows: []
            )
        }

        guard sourceText.utf8.count <= maximumImportUTF8ByteCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("The import text exceeds 32 MB. Split it into files smaller than 32 MB."),
                rows: []
            )
        }

        let document = MetadataExchangeTemplateDocument(rawValue: template)
        if let validationMessage = validateImportTextTemplate(document) {
            return MetadataExchangeImportPlan(validationMessage: validationMessage, rows: [])
        }

        let extraction = MetadataExchangeProfile.extract(from: sourceText)
        if let errorMessage = extraction.errorMessage {
            return MetadataExchangeImportPlan(validationMessage: errorMessage, rows: [])
        }

        let framing = MetadataExchangeTextFramer.frame(sourceText, extraction: extraction)
        if let validationMessage = framing.validationMessage {
            return MetadataExchangeImportPlan(validationMessage: validationMessage, rows: [])
        }

        guard !framing.records.isEmpty else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one record to import."),
                rows: []
            )
        }

        guard framing.records.count <= maximumImportRecordCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("You can import up to 100,000 records at a time. Split the records into smaller batches."),
                rows: []
            )
        }

        guard !framing.records.contains(where: { $0.rawText.utf8.count > maximumTextRecordUTF8ByteCount }) else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("One text record exceeds 256 KB. Use CSV import for very long values or values with line breaks."),
                rows: []
            )
        }

        let matcher = MetadataExchangeTextMatcher(
            document: document,
            profileVersion: framing.profileVersion
        )
        var parsedRecords: [ParsedExternalRecord] = []
        parsedRecords.reserveCapacity(framing.records.count)
        for record in framing.records {
            // Cancellation stops text matching cheaply; the worker rechecks
            // before publishing.
            if Task.isCancelled {
                return MetadataExchangeImportPlan(validationMessage: nil, rows: [])
            }
            parsedRecords.append(
                ParsedExternalRecord(
                    sourceIndex: record.sourceIndex,
                    displayText: record.rawText,
                    captures: matcher.match(record.rawText)
                )
            )
        }

        return makeImportPlan(
            parsedRecords: parsedRecords,
            fields: document.fields,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues,
            positionalLayout: .text(framing),
            projector: projector
        )
    }

    // MARK: – CSV import

    static func makeCSVImportPlan(
        template: String,
        sourceText: String,
        firstRowIsHeader: Bool,
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool,
        projector: (any AudioMetadataPipeline)? = nil
    ) -> MetadataExchangeImportPlan {
        guard sourceText.utf8.count <= maximumImportUTF8ByteCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("This CSV exceeds 32 MB. Split it into files smaller than 32 MB."),
                rows: []
            )
        }

        let result = parseCSVColumnTemplate(template)
        if let validationMessage = result.validationMessage {
            return MetadataExchangeImportPlan(validationMessage: validationMessage, rows: [])
        }
        guard result.columns.contains(where: \.isWritableMetadataField) else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one editable metadata field to the CSV column template."),
                rows: []
            )
        }

        let extraction = MetadataExchangeProfile.extract(from: sourceText)
        if let errorMessage = extraction.errorMessage {
            return MetadataExchangeImportPlan(validationMessage: errorMessage, rows: [])
        }
        let codec = MetadataExchangeCSVCodec(profileVersion: extraction.version)

        let parsedCSV: [[MetadataExchangeCSVField]]
        do {
            parsedCSV = try MetadataExchangeCSV.parseFields(
                extraction.source,
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

        if firstRowIsHeader, let header = parsedCSV.first {
            guard header.count == result.columns.count else {
                return MetadataExchangeImportPlan(
                    validationMessage: String(localized: "The CSV header and template have different column counts (\(header.count) and \(result.columns.count)). Make them match before importing."),
                    rows: []
                )
            }
            for (index, cell) in header.enumerated() {
                let field = result.columns[index]
                guard field == .ignore || headerCell(cell, matches: field, codec: codec) else {
                    return MetadataExchangeImportPlan(
                        validationMessage: String(localized: "CSV column \(index + 1) is “\(codec.decoded(cell))”, but the template expects \(field.displayName). Reorder the CSV columns or change the template to match."),
                        rows: []
                    )
                }
            }
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
                validationMessage: L10n.string("You can import up to 100,000 CSV data rows at a time. Split the rows into smaller files."),
                rows: []
            )
        }

        let allowsRemoval = (extraction.version ?? MetadataExchangeProfile.legacyVersion)
            >= MetadataExchangeProfile.currentVersion
        var parsedRecords: [ParsedExternalRecord] = []
        parsedRecords.reserveCapacity(dataRows.count)
        for (index, cells) in dataRows.enumerated() {
            if Task.isCancelled {
                return MetadataExchangeImportPlan(validationMessage: nil, rows: [])
            }
            let displayText = cells.map {
                codec.decoded($0).replacingOccurrences(of: "\n", with: " ")
            }.joined(separator: " | ")
            if cells.count < result.columns.count {
                let missingCount = result.columns.count - cells.count
                parsedRecords.append(
                    ParsedExternalRecord(
                        sourceIndex: index,
                        displayText: displayText,
                        captures: .failure(String(localized: "Missing CSV columns: \(missingCount). Add the missing columns to match the template."))
                    )
                )
                continue
            }
            if cells.count > result.columns.count {
                let extraCount = cells.count - result.columns.count
                parsedRecords.append(
                    ParsedExternalRecord(
                        sourceIndex: index,
                        displayText: displayText,
                        captures: .failure(String(localized: "Extra CSV columns: \(extraCount). Remove them or add corresponding fields to the template."))
                    )
                )
                continue
            }

            parsedRecords.append(
                ParsedExternalRecord(
                    sourceIndex: index,
                    displayText: displayText,
                    captures: captures(
                        from: cells,
                        columns: result.columns,
                        codec: codec,
                        allowsRemoval: allowsRemoval
                    )
                )
            )
        }

        return makeImportPlan(
            parsedRecords: parsedRecords,
            fields: result.columns,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues,
            positionalLayout: .csv(dataRowCount: dataRows.count),
            projector: projector
        )
    }

    static func parseCSVColumnTemplate(_ template: String) -> (columns: [MetadataExchangeField], delimiter: Character, validationMessage: String?) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ([], ",", L10n.string("Enter a column template using commas, semicolons, vertical bars, or tabs between fields."))
        }

        guard trimmed.utf8.count <= maximumTemplateUTF8ByteCount else {
            return ([], ",", L10n.string("This column template is too long. Shorten it before continuing."))
        }

        let delimiter = MetadataExchangeCSV.detectDelimiter(in: trimmed)
        do {
            let rows = try MetadataExchangeCSV.parse(trimmed, delimiter: delimiter)
            guard rows.count == 1, let row = rows.first, !row.isEmpty else {
                return ([], delimiter, L10n.string("Use one row for the CSV column template."))
            }

            guard row.count <= MetadataExchangeField.allCases.count + 64 else {
                return ([], delimiter, L10n.string("This template has too many columns. Remove some columns before continuing."))
            }

            var columns: [MetadataExchangeField] = []
            var seenFields = Set<MetadataExchangeField>()
            for cell in row {
                guard let field = MetadataExchangeField.field(forExactToken: cell) else {
                    return (columns, delimiter, String(localized: "Use one supported field per CSV template column, such as {{title}}."))
                }

                if field != .ignore, seenFields.contains(field) {
                    return (columns, delimiter, String(localized: "The CSV template includes the same field more than once. Keep only one column for each field."))
                }

                seenFields.insert(field)
                columns.append(field)
            }

            guard columns.contains(where: { $0 != .ignore }) else {
                return (columns, delimiter, L10n.string("Add at least one field to the CSV export template."))
            }

            return (columns, delimiter, nil)
        } catch {
            return ([], delimiter, (error as NSError).localizedDescription)
        }
    }

    // MARK: – Import row construction

    private enum PositionalImportLayout {
        case text(MetadataExchangeFraming)
        case csv(dataRowCount: Int)
    }

    private static func makeImportPlan(
        parsedRecords: [ParsedExternalRecord],
        fields: [MetadataExchangeField],
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool,
        positionalLayout: PositionalImportLayout,
        projector: (any AudioMetadataPipeline)?
    ) -> MetadataExchangeImportPlan {
        let uniqueFiles = uniqueTargetFiles(targetFiles)
        guard uniqueFiles.count <= maximumImportRecordCount else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("You can import into up to 100,000 files at a time. Select fewer files."),
                rows: []
            )
        }

        var seenLocatorFields = Set<MetadataExchangeField>()
        let locatorFields = fields.filter { field in
            field.isLocatorField && seenLocatorFields.insert(field).inserted
        }

        if !locatorFields.isEmpty {
            // Explicit locators determine identity independent of input order.
            // Incidental all-blank lines cannot identify a file and are skipped,
            // preserving the legacy tolerant behavior for locator imports.
            let locatorRecords = parsedRecords.filter { record in
                !record.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return MetadataExchangeImportPlan(
                validationMessage: nil,
                rows: makeMatchedImportRows(
                    parsedRecords: locatorRecords,
                    targetFiles: uniqueFiles,
                    locatorFields: locatorFields,
                    clearBlankImportedValues: clearBlankImportedValues,
                    projector: projector
                )
            )
        }

        return makePositionalImportPlan(
            parsedRecords: parsedRecords,
            targetFiles: uniqueFiles,
            clearBlankImportedValues: clearBlankImportedValues,
            layout: positionalLayout,
            projector: projector
        )
    }

    private static func makePositionalImportPlan(
        parsedRecords: [ParsedExternalRecord],
        targetFiles: [AudioFile],
        clearBlankImportedValues: Bool,
        layout: PositionalImportLayout,
        projector: (any AudioMetadataPipeline)?
    ) -> MetadataExchangeImportPlan {
        let binding: MetadataExchangePositionalBinding
        switch layout {
        case .text(let framing):
            binding = MetadataExchangePositionalBinder.bind(
                framing: framing,
                targetCount: targetFiles.count,
                clearBlankImportedValues: clearBlankImportedValues
            )
        case .csv(let dataRowCount):
            binding = MetadataExchangePositionalBinder.bindCSV(
                dataRowCount: dataRowCount,
                targetCount: targetFiles.count
            )
        }

        switch binding {
        case .invalid(let message):
            return MetadataExchangeImportPlan(validationMessage: message, rows: [])

        case .aligned(let records):
            var rows: [MetadataExchangeImportPreviewRow] = []
            rows.reserveCapacity(targetFiles.count)
            for (index, file) in targetFiles.enumerated() {
                // Cancellation stops positional matching and frozen-write
                // construction; the worker rechecks before publishing.
                if Task.isCancelled {
                    return MetadataExchangeImportPlan(validationMessage: nil, rows: [])
                }
                let record = record(
                    atSourceIndex: records[index].sourceIndex,
                    in: parsedRecords
                ) ?? parsedRecords[index]
                rows.append(
                    makeImportRow(
                        file: file,
                        record: record,
                        clearBlankImportedValues: clearBlankImportedValues,
                        allowsWriteEntry: true,
                        projector: projector
                    )
                )
            }
            return MetadataExchangeImportPlan(validationMessage: nil, rows: rows)

        case .legacyOneRecordPadding(_, let recordIndex):
            guard targetFiles.count == 1,
                  let record = record(atParsedIndex: recordIndex, in: parsedRecords) else {
                return MetadataExchangeImportPlan(
                    validationMessage: nil,
                    rows: [],
                    blockingMessage: String(localized: "The import records can’t be matched to the selected files.")
                )
            }
            return MetadataExchangeImportPlan(
                validationMessage: nil,
                rows: [
                    makeImportRow(
                        file: targetFiles[0],
                        record: record,
                        clearBlankImportedValues: clearBlankImportedValues,
                        allowsWriteEntry: true,
                        projector: projector
                    )
                ]
            )

        case .countMismatch(let recordCount, let targetCount):
            let blockingMessage = positionalBlockingMessage(
                records: recordCount,
                targets: targetCount
            )
            let rowCount = max(parsedRecords.count, targetFiles.count)
            var rows: [MetadataExchangeImportPreviewRow] = []
            rows.reserveCapacity(rowCount)
            for index in 0..<rowCount {
                if Task.isCancelled {
                    return MetadataExchangeImportPlan(
                        validationMessage: nil,
                        rows: [],
                        blockingMessage: blockingMessage
                    )
                }
                let file = index < targetFiles.count ? targetFiles[index] : nil
                let record = index < parsedRecords.count ? parsedRecords[index] : nil

                guard let record else {
                    rows.append(
                        MetadataExchangeImportPreviewRow(
                            id: UUID(),
                            fileID: file?.id,
                            fileName: file?.url.lastPathComponent ?? "—",
                            externalRecord: "",
                            status: .missingExternalRecord,
                            changes: [],
                            issueMessage: L10n.string("No import record corresponds to this file's position. Add the matching record or leave this file out of the selection."),
                            writeEntry: nil
                        )
                    )
                    continue
                }
                guard let file else {
                    rows.append(
                        MetadataExchangeImportPreviewRow(
                        id: UUID(),
                        fileID: nil,
                        fileName: "—",
                        externalRecord: record.displayText,
                        status: .extraExternalRecord,
                        changes: [],
                            issueMessage: L10n.string("No selected file corresponds to this record's position. Select the matching file or remove the record."),
                            writeEntry: nil
                        )
                    )
                    continue
                }
                rows.append(
                    makeImportRow(
                        file: file,
                        record: record,
                        clearBlankImportedValues: clearBlankImportedValues,
                        allowsWriteEntry: false,
                        projector: projector
                    )
                )
            }
            return MetadataExchangeImportPlan(
                validationMessage: nil,
                rows: rows,
                blockingMessage: blockingMessage
            )
        }
    }

    private static func record(
        atSourceIndex sourceIndex: Int,
        in records: [ParsedExternalRecord]
    ) -> ParsedExternalRecord? {
        records.first { $0.sourceIndex == sourceIndex }
    }

    private static func record(
        atParsedIndex index: Int,
        in records: [ParsedExternalRecord]
    ) -> ParsedExternalRecord? {
        guard index >= 0, index < records.count else { return nil }
        return records[index]
    }

    private static func positionalBlockingMessage(records: Int, targets: Int) -> String {
        if records > targets {
            let extra = records - targets
            return String(localized: "This import has \(records) records but \(targets) files are selected. Remove \(extra) extra record(s), or use a file name, path, or index locator. A trailing empty line after the last record counts as an extra record.")
        }
        let missing = targets - records
        return String(localized: "This import has \(records) records but \(targets) files are selected. Add \(missing) missing record(s), or use a file name, path, or index locator.")
    }

    private static func makeImportRow(
        file: AudioFile,
        record: ParsedExternalRecord,
        clearBlankImportedValues: Bool,
        allowsWriteEntry: Bool,
        projector: (any AudioMetadataPipeline)?
    ) -> MetadataExchangeImportPreviewRow {
        switch record.captures {
        case .failure(let message):
            return parseErrorRow(record: record, file: file, message: message)
        case .success(let captures):
            if file.hasUnverifiedIndependentDateProjection,
               captures.keys.contains(where: \.isIndependentDateField) {
                return parseErrorRow(
                    record: record,
                    file: file,
                    message: String(localized: "These date fields can't be edited separately in ID3v2.3 tags.")
                )
            }

            let writableCaptureCount = captures.keys.filter(\.isWritableMetadataField).count
            guard writableCaptureCount > 0 else {
                return MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    externalRecord: record.displayText,
                    status: .noWritableFields,
                    changes: [],
                    issueMessage: L10n.string("This record has no editable metadata fields to import."),
                    writeEntry: nil
                )
            }

            let intent: ExchangeResolvedIntent
            switch ExchangeIntentResolver.resolveImportedRow(
                captures: captures,
                clearBlankImportedValues: clearBlankImportedValues,
                reviewedFile: file,
                maximumComponentValue: AudioFormatNumberBounds.componentMaximum(
                    forFileExtension: file.url.pathExtension
                )
            ) {
            case .failure(let rejection):
                return parseErrorRow(record: record, file: file, message: rejection.message)
            case .success(let resolved):
                intent = resolved
            }

            let outcome = ExchangeWriteTranslator.makeFrozenWrite(
                from: file,
                intent: intent,
                projector: projector
            )

            switch outcome {
            case .unavailable(let message):
                return sourceUnavailableRow(record: record, file: file, message: message)
            case .rejected(let message):
                return parseErrorRow(record: record, file: file, message: message)
            case .unchanged:
                return MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    externalRecord: record.displayText,
                    status: .unchanged,
                    changes: displayChanges(intent: intent, file: file, effectiveFields: []),
                    issueMessage: record.warning,
                    writeEntry: nil
                )
            case .executable(let frozen):
                let changes = displayChanges(
                    intent: intent,
                    file: file,
                    effectiveFields: frozen.payload.requestedFields
                )
                let entry: MetadataExchangeWriteEntry? = allowsWriteEntry
                    ? MetadataExchangeWriteEntry(
                        fileName: file.url.lastPathComponent,
                        write: frozen.reviewedWrite,
                        resolvedIntent: intent
                      )
                    : nil
                return MetadataExchangeImportPreviewRow(
                    id: UUID(),
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    externalRecord: record.displayText,
                    status: .ready,
                    changes: changes,
                    issueMessage: record.warning,
                    writeEntry: entry
                )
            }
        }
    }

    private static func displayChanges(
        intent: ExchangeResolvedIntent,
        file: AudioFile,
        effectiveFields: Set<MetadataFieldKey>
    ) -> [MetadataExchangeFieldChange] {
        var changesByField: [MetadataExchangeField: MetadataExchangeFieldChange] = [:]
        for operation in intent.operations {
            let change: MetadataExchangeFieldChange
            switch operation {
            case .setText(let field, let text):
                let canonical = field.canonicalImportedValue(text)
                change = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: canonical,
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title)
                )
            case .removeText(let field):
                change = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: "",
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title),
                    isExplicitRemoval: true
                )
            case .setNumber(let field, _, let literalText):
                change = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: literalText,
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title)
                )
            case .removeNumber(let field):
                change = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: "",
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title),
                    isExplicitRemoval: true
                )
            }
            changesByField[change.field] = change
        }
        return MetadataExchangeField.allCases.compactMap { changesByField[$0] }
    }

    // MARK: – Locator matching

    private static func makeMatchedImportRows(
        parsedRecords: [ParsedExternalRecord],
        targetFiles: [AudioFile],
        locatorFields: [MetadataExchangeField],
        clearBlankImportedValues: Bool,
        projector: (any AudioMetadataPipeline)?
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

        var resolutions: [(record: ParsedExternalRecord, resolution: LocatorResolution)] = []
        resolutions.reserveCapacity(parsedRecords.count)
        for record in parsedRecords {
            if Task.isCancelled { return [] }
            switch record.captures {
            case .failure(let message):
                resolutions.append((record, .parseError(message)))
                continue
            case .success(let captures):
                let locatorValues = locatorValues(from: captures)
                let description = locatorDescription(captures: locatorValues, locatorFields: locatorFields)
                guard let signature = locatorSignature(captures: locatorValues, locatorFields: locatorFields) else {
                    resolutions.append((record, .noMatch(description)))
                    continue
                }

                let match: LocatorMatch
                if let cachedMatch = matchCache[signature] {
                    match = cachedMatch
                } else {
                    let candidateIndices = candidateIndex.candidateIndices(fields: locatorFields) { field in
                        locatorLookupKey(locatorValues[field] ?? "", field: field)
                    }
                    var matchingFiles: [AudioFile] = []
                    for fileIndex in candidateIndices {
                        if Task.isCancelled { return [] }
                        let file = targetFiles[fileIndex]
                        if matchesAllLocators(
                            captures: locatorValues,
                            locatorFields: locatorFields,
                            file: file,
                            fileIndex: fileIndex
                        ) {
                            matchingFiles.append(file)
                        }
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
                    resolutions.append((record, .noMatch(description)))
                case .ambiguous:
                    resolutions.append((record, .ambiguous(description)))
                case .matched(let file):
                    resolutions.append((record, .matched(file)))
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
                        issueMessage: L10n.string("No selected file matches this record's identifying values. Check its filename or path and your file selection."),
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
                        issueMessage: L10n.string("This record matches more than one selected file. Add Path or Relative Path so each file can be identified."),
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
                            issueMessage: L10n.string("More than one import record points to this file. Keep one record for it. None of these records will be applied."),
                            writeEntry: nil
                        )
                    )
                } else {
                    matchedFileIDs.insert(file.id)
                    rows.append(makeImportRow(
                        file: file,
                        record: record,
                        clearBlankImportedValues: clearBlankImportedValues,
                        allowsWriteEntry: true,
                        projector: projector
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
                    issueMessage: L10n.string("No import record matches this selected file. Check the records or leave this file out of the selection."),
                    writeEntry: nil
                )
            )
        }

        return rows
    }

    private static func locatorValues(
        from captures: [MetadataExchangeField: ExchangeCapture]
    ) -> [MetadataExchangeField: String] {
        var values: [MetadataExchangeField: String] = [:]
        for (field, capture) in captures where field.isLocatorField {
            if case .locator(let text) = capture {
                values[field] = text
            }
        }
        return values
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
                    .engineer, .remixer, .genre, .year, .date, .originalReleaseDate, .trackNumber, .trackTotal,
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
                .engineer, .remixer, .genre, .year, .date, .originalReleaseDate, .trackNumber, .trackTotal,
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
                .engineer, .remixer, .genre, .year, .date, .originalReleaseDate, .trackNumber, .trackTotal,
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

    private static func sourceUnavailableRow(
        record: ParsedExternalRecord,
        file: AudioFile,
        message: String
    ) -> MetadataExchangeImportPreviewRow {
        MetadataExchangeImportPreviewRow(
            id: UUID(),
            fileID: file.id,
            fileName: file.url.lastPathComponent,
            externalRecord: record.displayText,
            status: .sourceUnavailable,
            changes: [],
            issueMessage: message,
            writeEntry: nil
        )
    }

    // MARK: – CSV capture

    private static func captures(
        from cells: [MetadataExchangeCSVField],
        columns: [MetadataExchangeField],
        codec: MetadataExchangeCSVCodec,
        allowsRemoval: Bool
    ) -> MetadataExchangeCaptureResult {
        var captures: [MetadataExchangeField: ExchangeCapture] = [:]
        for (index, field) in columns.enumerated() {
            guard field != .ignore else { continue }
            let cell = cells[index]
            let importedValue = codec.importedValue(cell)
            if importedValue.unicodeScalars.contains(where: { $0.value == 0 }) {
                return .failure(
                    String(localized: "\(field.displayName) contains a hidden character that can’t be saved. Remove it before importing.\nDetails: null character (U+0000).")
                )
            }
            let trimmedCell = importedValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if field.isLocatorField {
                if allowsRemoval, !cell.wasQuoted, trimmedCell == MetadataExchangeProfile.removalToken {
                    return .failure(
                        String(localized: "A removal token can’t identify a file. Enter the file’s name, path, or index, or quote the token as literal text.")
                    )
                }
                captures[field] = .locator(importedValue)
                continue
            }

            guard field.isWritableMetadataField else { continue }

            if allowsRemoval, !cell.wasQuoted, trimmedCell == MetadataExchangeProfile.removalToken {
                captures[field] = .explicitRemoval
            } else if trimmedCell.isEmpty {
                captures[field] = .blank
            } else {
                captures[field] = .literal(importedValue)
            }
        }
        return .success(captures)
    }

    // MARK: – Template helpers

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
                let value = field.value(from: file, index: index, relativeBasePath: relativeBasePath)
                // Reserve the bare token for removal, and escape every leading
                // backslash run so both literal tokens and escapes round-trip.
                return value.drop(while: { $0 == "\\" }) == MetadataExchangeProfile.removalToken
                    ? "\\" + value : value
            }
        }.joined()
    }

    private static func validateImportTextTemplate(_ document: MetadataExchangeTemplateDocument) -> String? {
        if document.isEmpty {
            return L10n.string("Enter a template that matches the records you want to import.")
        }

        if let validationMessage = validateTemplateSyntax(document, requiresSingleLine: true) {
            return validationMessage
        }

        guard document.hasWritableMetadataFields else {
            return L10n.string("Add at least one editable metadata field to the import template.")
        }

        for index in document.segments.indices.dropLast() {
            guard case .field = document.segments[index],
                  case .field = document.segments[index + 1]
            else {
                continue
            }
            return L10n.string("Add text between adjacent fields so AudioMator can tell their values apart.")
        }

        return nil
    }

    private static func validateTemplateSyntax(
        _ document: MetadataExchangeTemplateDocument,
        requiresSingleLine: Bool
    ) -> String? {
        if document.rawValue.utf8.count > maximumTemplateUTF8ByteCount {
            return L10n.string("This text template is too long. Shorten it before continuing.")
        }

        if document.segments.count > 256 {
            return L10n.string("This text template has too many parts. Remove some fields or separators.")
        }

        if document.hasUnterminatedPlaceholder {
            return L10n.string("A field is missing its closing }}. Complete it, for example {{title}}.")
        }

        if let unknownPlaceholderName = document.unknownPlaceholderNames.first {
            let name = unknownPlaceholderName.isEmpty ? "{{}}" : "{{\(unknownPlaceholderName)}}"
            return String(localized: "“\(name)” isn't a supported field. Choose a field from the available list.")
        }

        if requiresSingleLine,
           document.rawValue.unicodeScalars.contains(where: { $0.value == 0x0A || $0.value == 0x0D }) {
            return L10n.string("Keep this template on one line. Use CSV for metadata that contains line breaks.")
        }

        return nil
    }

    private static func headerCell(
        _ cell: MetadataExchangeCSVField,
        matches field: MetadataExchangeField,
        codec: MetadataExchangeCSVCodec
    ) -> Bool {
        let decoded = codec.decoded(cell)
        let normalizedCell = normalizedHeaderToken(decoded)
        guard !normalizedCell.isEmpty else { return false }

        // A legacy `DATE` header means the native YEAR slot. It must never be
        // silently reinterpreted as the independent semantic Date column.
        if field == .date,
           decoded.trimmingCharacters(in: .whitespacesAndNewlines) == "DATE" {
            return false
        }

        let externalAliases: [String]
        switch field {
        case .fileName: externalAliases = ["Name", "File Name", "Filename"]
        case .comment: externalAliases = ["Comments", "Comment"]
        case .trackNumber: externalAliases = ["Track #", "Track", "Track Number"]
        case .discNumber: externalAliases = ["Disc #", "Disc", "Disc Number", "Disk Number"]
        default: externalAliases = []
        }
        let aliases = externalAliases + [
            field.displayName,
            field.placeholderName,
            field.propertyMapKey ?? "",
            String(describing: field),
            "{{" + field.placeholderName + "}}"
        ]
        return aliases.contains { alias in
            normalizedHeaderToken(alias) == normalizedCell
        }
    }

    private static func normalizedHeaderToken(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}"), trimmed.count >= 4 {
            trimmed.removeFirst(2)
            trimmed.removeLast(2)
        }
        let folded = trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
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

nonisolated private struct ParsedExternalRecord {
    let sourceIndex: Int
    let displayText: String
    let captures: MetadataExchangeCaptureResult
    var warning: String? = nil
}

nonisolated private enum MetadataExchangeCaptureResult {
    case success([MetadataExchangeField: ExchangeCapture])
    case failure(String)
}

nonisolated private struct MetadataExchangeTextMatcher {
    let document: MetadataExchangeTemplateDocument
    let profileVersion: Int?

    private static let maximumMatchSteps = 50_000
    private static let maximumLiteralCandidates = 4_096

    private var profileAllowsRemoval: Bool {
        (profileVersion ?? MetadataExchangeProfile.legacyVersion) >= MetadataExchangeProfile.currentVersion
    }

    private struct MatchBudget {
        var remainingSteps: Int

        mutating func consume() -> Bool {
            guard remainingSteps > 0 else { return false }
            remainingSteps -= 1
            return true
        }
    }

    private enum SearchResult {
        case success([MetadataExchangeField: ExchangeCapture])
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
            return .failure(L10n.string("This record fits the template in more than one way. Add clearer separators or use CSV import."))
        case .tooComplex:
            return .failure(L10n.string("This record couldn’t be matched within the processing limit. Simplify the template or use CSV import."))
        }
    }

    private func matchSegments(
        _ segments: [MetadataExchangeTemplateSegment],
        in source: String,
        at segmentIndex: Int,
        sourceIndex: String.Index,
        captures: [MetadataExchangeField: ExchangeCapture],
        budget: inout MatchBudget
    ) -> SearchResult {
        guard budget.consume() else { return .tooComplex }

        if segmentIndex >= segments.count {
            return sourceIndex == source.endIndex
                ? .success(captures)
                : .failure(L10n.string("This record has extra text at the end. Remove it or update the template to include it."))
        }

        switch segments[segmentIndex] {
        case .literal(let literal):
            guard source[sourceIndex...].hasPrefix(literal) else {
                return .failure(L10n.string("The fixed text in this record doesn't match the template. Check the text and separators."))
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
                return .failure(L10n.string("Add text between these fields so their values can be read separately."))
            }

            guard let literalPositions = findLiteralPositions(
                nextLiteral,
                in: source,
                startingAt: sourceIndex
            ) else {
                return .tooComplex
            }

            var uniqueCapture: [MetadataExchangeField: ExchangeCapture]?
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
            return .failure(lastFailure ?? L10n.string("This record doesn't match the template. Check the field order and separators."))
        }
    }

    private func captureValue(
        _ rawValue: String,
        for field: MetadataExchangeField,
        into captures: [MetadataExchangeField: ExchangeCapture]
    ) -> MetadataExchangeCaptureResult {
        guard field != .ignore else { return .success(captures) }

        if rawValue.unicodeScalars.contains(where: { $0.value == 0 }) {
            return .failure(
                String(localized: "\(field.displayName) contains a hidden character that can’t be saved. Remove it before importing.\nDetails: null character (U+0000).")
            )
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let capture: ExchangeCapture

        if field.isLocatorField {
            if profileAllowsRemoval, trimmed == MetadataExchangeProfile.removalToken {
                return .failure(
                    String(localized: "A removal token can’t identify a file. Enter the file’s name, path, or index, or escape the token as literal text.")
                )
            }
            if profileAllowsRemoval, let escaped = unescapeRemovalToken(trimmed) {
                capture = .locator(escaped)
            } else {
                capture = .locator(trimmed)
            }
        } else {
            if profileAllowsRemoval, trimmed == MetadataExchangeProfile.removalToken {
                // Typed removal wins before any value validation.
                capture = .explicitRemoval
            } else if trimmed.isEmpty {
                capture = .blank
            } else {
                let literal = (profileAllowsRemoval ? unescapeRemovalToken(trimmed) : nil) ?? trimmed
                if let validationMessage = field.importedValueValidationMessage(literal) {
                    return .failure(validationMessage)
                }
                capture = .literal(literal)
            }
        }

        if let existing = captures[field] {
            let sameMeaning: Bool = switch (existing, capture) {
            case (.locator(let left), .locator(let right)): left == right
            default: ExchangeIntentResolver.capturesHaveSameTypedMeaning(
                field: field,
                lhs: existing,
                rhs: capture
            )
            }
            if sameMeaning {
                return .success(captures)
            }
            return .failure(
                String(localized: "This record gives more than one value for \(field.displayName). Keep one value or use CSV import.")
            )
        }

        var updatedCaptures = captures
        updatedCaptures[field] = capture
        return .success(updatedCaptures)
    }

    /// Text export reserves `<remove>` and escapes a literal token by adding one
    /// backslash to its leading backslash run. Import removes exactly one.
    private func unescapeRemovalToken(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("\\") else { return nil }
        let withoutLeadingBackslashes = trimmed.drop(while: { $0 == "\\" })
        guard withoutLeadingBackslashes == Substring(MetadataExchangeProfile.removalToken) else {
            return nil
        }
        return String(trimmed.dropFirst())
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
