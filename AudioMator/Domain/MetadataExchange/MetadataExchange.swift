import Foundation

enum MetadataConverterMode: String, CaseIterable, Identifiable {
    case metadataToFilename
    case filenameToMetadata
    case metadataToText
    case textToMetadata
    case metadataToCSV
    case csvToMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Metadata to Filename")
        case .filenameToMetadata:
            return L10n.string("Filename to Metadata")
        case .metadataToText:
            return L10n.string("Metadata to Text")
        case .textToMetadata:
            return L10n.string("Text to Metadata")
        case .metadataToCSV:
            return L10n.string("Metadata to CSV")
        case .csvToMetadata:
            return L10n.string("CSV to Metadata")
        }
    }

    var subtitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Build filenames from tags, keeping each file extension.")
        case .filenameToMetadata:
            return L10n.string("Parse the current filename stem into editable tags.")
        case .metadataToText:
            return L10n.string("Render one custom text record per selected file.")
        case .textToMetadata:
            return L10n.string("Parse one text record per line and write matched tag values.")
        case .metadataToCSV:
            return L10n.string("Export selected files as a column-based CSV.")
        case .csvToMetadata:
            return L10n.string("Import CSV columns into selected file metadata.")
        }
    }

    var symbolName: String {
        switch self {
        case .metadataToFilename:
            return "character.cursor.ibeam"
        case .filenameToMetadata:
            return "character.textbox.badge.sparkles"
        case .metadataToText:
            return "text.page"
        case .textToMetadata:
            return "long.text.page.and.pencil"
        case .metadataToCSV:
            return "tablecells"
        case .csvToMetadata:
            return "tablecells.badge.ellipsis"
        }
    }

    var actionTitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Rename")
        case .filenameToMetadata, .textToMetadata, .csvToMetadata:
            return L10n.string("Write Metadata")
        case .metadataToText, .metadataToCSV:
            return L10n.string("Export")
        }
    }
}

enum MetadataExchangeField: CaseIterable, Hashable, Identifiable {
    case fileName
    case baseName
    case path
    case relativePath
    case index
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
    case trackNumber
    case discNumber
    case comment
    case releaseDate
    case publisher
    case copyright
    case ignore

    var id: String { placeholderName }

    var displayName: String {
        switch self {
        case .fileName:
            return L10n.string("File Name")
        case .baseName:
            return L10n.string("Base Name")
        case .path:
            return L10n.string("Path")
        case .relativePath:
            return L10n.string("Relative Path")
        case .index:
            return L10n.string("Index")
        case .title:
            return L10n.string("Title")
        case .artist:
            return L10n.string("Artist")
        case .album:
            return L10n.string("Album")
        case .albumArtist:
            return L10n.string("Album Artist")
        case .composer:
            return L10n.string("Composer")
        case .genre:
            return L10n.string("Genre")
        case .year:
            return L10n.string("Year")
        case .trackNumber:
            return L10n.string("Track Number")
        case .discNumber:
            return L10n.string("Disc Number")
        case .comment:
            return L10n.string("Comment")
        case .releaseDate:
            return L10n.string("Release Date")
        case .publisher:
            return L10n.string("Publisher")
        case .copyright:
            return L10n.string("Copyright")
        case .ignore:
            return L10n.string("Ignore")
        }
    }

    var placeholderName: String {
        switch self {
        case .fileName:
            return "fileName"
        case .baseName:
            return "baseName"
        case .path:
            return "path"
        case .relativePath:
            return "relativePath"
        case .index:
            return "index"
        case .title:
            return "title"
        case .artist:
            return "artist"
        case .album:
            return "album"
        case .albumArtist:
            return "albumArtist"
        case .composer:
            return "composer"
        case .genre:
            return "genre"
        case .year:
            return "year"
        case .trackNumber:
            return "trackNumber"
        case .discNumber:
            return "discNumber"
        case .comment:
            return "comment"
        case .releaseDate:
            return "releaseDate"
        case .publisher:
            return "publisher"
        case .copyright:
            return "copyright"
        case .ignore:
            return "_ignore"
        }
    }

    var token: String {
        "{{\(placeholderName)}}"
    }

    var isWritableMetadataField: Bool {
        switch self {
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .discNumber, .comment, .releaseDate, .publisher, .copyright:
            return true
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            return false
        }
    }

    var isLocatorField: Bool {
        switch self {
        case .fileName, .baseName, .path, .relativePath, .index:
            return true
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .discNumber, .comment, .releaseDate, .publisher,
                .copyright, .ignore:
            return false
        }
    }

    var propertyMapKey: String? {
        switch self {
        case .title:
            return "TITLE"
        case .artist:
            return "ARTIST"
        case .album:
            return "ALBUM"
        case .albumArtist:
            return "ALBUMARTIST"
        case .composer:
            return "COMPOSER"
        case .genre:
            return "GENRE"
        case .year:
            return "DATE"
        case .trackNumber:
            return "TRACKNUMBER"
        case .discNumber:
            return "DISCNUMBER"
        case .comment:
            return "COMMENT"
        case .releaseDate:
            return "RELEASEDATE"
        case .publisher:
            return "PUBLISHER"
        case .copyright:
            return "COPYRIGHT"
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            return nil
        }
    }

    static let exportPalette: [Self] = [
        .fileName, .baseName, .path, .relativePath, .index,
        .title, .artist, .album, .albumArtist, .composer, .genre, .year,
        .trackNumber, .discNumber, .comment, .releaseDate, .publisher, .copyright
    ]

    static let importPalette: [Self] = [
        .fileName, .baseName, .index,
        .title, .artist, .album, .albumArtist, .composer, .genre, .year,
        .trackNumber, .discNumber, .comment, .releaseDate, .publisher, .copyright,
        .ignore
    ]

    static func field(forPlaceholderName placeholderName: String) -> Self? {
        allCases.first { $0.placeholderName == placeholderName }
    }

    static func field(forExactToken token: String) -> Self? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.token == trimmed }
    }

    func value(from file: AudioFile, index: Int, relativeBasePath: String?) -> String {
        switch self {
        case .fileName:
            return file.url.lastPathComponent
        case .baseName:
            return file.url.deletingPathExtension().lastPathComponent
        case .path:
            return file.url.path
        case .relativePath:
            guard
                let relativeBasePath,
                let relativePath = makeRelativePath(for: file.url, basePath: relativeBasePath)
            else {
                return file.url.lastPathComponent
            }
            return relativePath
        case .index:
            return "\(index + 1)"
        case .title:
            return file.title
        case .artist:
            return file.artist
        case .album:
            return file.album
        case .albumArtist:
            return file.albumArtist
        case .composer:
            return file.composer
        case .genre:
            return file.genre
        case .year:
            return file.year
        case .trackNumber:
            return file.trackNumberText.isEmpty ? formatTrackIndex(file.track, total: file.trackTotal) : file.trackNumberText
        case .discNumber:
            return file.discNumberText.isEmpty ? formatTrackIndex(file.disc, total: file.discTotal) : file.discNumberText
        case .comment:
            return file.comment
        case .releaseDate:
            return file.releaseDate
        case .publisher:
            return file.publisher
        case .copyright:
            return file.copyright
        case .ignore:
            return ""
        }
    }

    func applyImportedValue(_ value: String, to edit: inout SingleFileEditModel) {
        switch self {
        case .title:
            edit.title = value
        case .artist:
            edit.artist = value
        case .album:
            edit.album = value
        case .albumArtist:
            edit.albumArtist = value
        case .composer:
            edit.composer = value
        case .genre:
            edit.genre = value
        case .year:
            edit.year = value
        case .trackNumber:
            edit.setTrackNumberText(value)
        case .discNumber:
            edit.setDiscNumberText(value)
        case .comment:
            edit.comment = value
        case .releaseDate:
            edit.releaseDate = value
        case .publisher:
            edit.publisher = value
        case .copyright:
            edit.copyright = value
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            break
        }
    }

    private func makeRelativePath(for url: URL, basePath: String) -> String? {
        let filePath = url.standardizedFileURL.path
        let normalizedBasePath = URL(fileURLWithPath: basePath).standardizedFileURL.path

        if filePath == normalizedBasePath {
            return url.lastPathComponent
        }

        let basePrefix = normalizedBasePath.hasSuffix("/") ? normalizedBasePath : normalizedBasePath + "/"
        guard filePath.hasPrefix(basePrefix) else { return nil }
        return String(filePath.dropFirst(basePrefix.count))
    }
}

enum MetadataExchangeTemplateSegment: Equatable {
    case literal(String)
    case field(MetadataExchangeField)
}

struct MetadataExchangeTemplateDocument: Equatable {
    let rawValue: String
    let segments: [MetadataExchangeTemplateSegment]

    init(rawValue: String) {
        self.rawValue = rawValue
        self.segments = MetadataExchangeTemplateParser.parse(rawValue)
    }

    var isEmpty: Bool {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var fields: [MetadataExchangeField] {
        segments.compactMap { segment in
            guard case .field(let field) = segment else { return nil }
            return field
        }
    }

    var hasWritableMetadataFields: Bool {
        fields.contains(where: \.isWritableMetadataField)
    }

    var usesFileNameMatching: Bool {
        fields.contains(.fileName)
    }

    var usesBaseNameMatching: Bool {
        fields.contains(.baseName)
    }
}

enum MetadataExchangeTemplateParser {
    static func parse(_ rawValue: String) -> [MetadataExchangeTemplateSegment] {
        guard !rawValue.isEmpty else { return [] }

        var segments: [MetadataExchangeTemplateSegment] = []
        var searchStart = rawValue.startIndex
        var literalStart = rawValue.startIndex

        while searchStart < rawValue.endIndex,
              let openingRange = rawValue[searchStart...].range(of: "{{") {
            if openingRange.lowerBound > literalStart {
                appendLiteral(String(rawValue[literalStart..<openingRange.lowerBound]), to: &segments)
            }

            guard let closingRange = rawValue[openingRange.upperBound...].range(of: "}}") else {
                literalStart = openingRange.lowerBound
                searchStart = rawValue.endIndex
                break
            }

            let placeholderName = String(rawValue[openingRange.upperBound..<closingRange.lowerBound])
            if let field = MetadataExchangeField.field(forPlaceholderName: placeholderName) {
                segments.append(.field(field))
            } else {
                appendLiteral(String(rawValue[openingRange.lowerBound..<closingRange.upperBound]), to: &segments)
            }

            searchStart = closingRange.upperBound
            literalStart = searchStart
        }

        if literalStart < rawValue.endIndex {
            appendLiteral(String(rawValue[literalStart...]), to: &segments)
        }

        return segments
    }

    private static func appendLiteral(_ literal: String, to segments: inout [MetadataExchangeTemplateSegment]) {
        guard !literal.isEmpty else { return }
        if case .literal(let existing)? = segments.last {
            segments[segments.count - 1] = .literal(existing + literal)
        } else {
            segments.append(.literal(literal))
        }
    }
}

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
        case .noMatch, .ambiguousMatch, .parseError, .missingExternalRecord,
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

fileprivate struct MetadataExchangeCSVField {
    let value: String
    let wasQuoted: Bool

    nonisolated var importedValue: String {
        wasQuoted ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var hasImportContent: Bool {
        wasQuoted ? !value.isEmpty : !importedValue.isEmpty
    }
}

enum MetadataExchangePlanner {
    static func makeTextExportPlan(
        template: String,
        targetFiles: [AudioFile]
    ) -> MetadataTextExportPlan {
        let document = MetadataExchangeTemplateDocument(rawValue: template)
        if document.isEmpty {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("Enter a template to preview exported text."),
                rows: []
            )
        }

        guard document.fields.contains(where: { $0 != .ignore }) else {
            return MetadataTextExportPlan(
                validationMessage: L10n.string("Add at least one output field to the template."),
                rows: []
            )
        }

        let relativeBasePath = commonDirectoryPath(for: targetFiles)
        let rows = targetFiles.enumerated().map { index, file in
            MetadataTextExportRow(
                id: file.id,
                fileName: file.url.lastPathComponent,
                output: render(document: document, file: file, index: index, relativeBasePath: relativeBasePath)
            )
        }

        return MetadataTextExportPlan(validationMessage: nil, rows: rows)
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

        let relativeBasePath = commonDirectoryPath(for: targetFiles)
        let rows = targetFiles.enumerated().map { index, file in
            result.columns.map { field in
                field.value(from: file, index: index, relativeBasePath: relativeBasePath)
            }
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
        let document = MetadataExchangeTemplateDocument(rawValue: template)
        if let validationMessage = validateImportTextTemplate(document) {
            return MetadataExchangeImportPlan(validationMessage: validationMessage, rows: [])
        }

        let records = sourceText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
                allowsBareQuotesInUnquotedFields: MetadataExchangeCSV.allowsBareQuotesInUnquotedFields(for: result.delimiter)
            )
        } catch {
            return MetadataExchangeImportPlan(
                validationMessage: (error as NSError).localizedDescription,
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

        guard dataRows.contains(where: isUsableCSVDataRow) else {
            return MetadataExchangeImportPlan(
                validationMessage: L10n.string("Add at least one CSV data row with values to import."),
                rows: []
            )
        }

        let parsedRecords = dataRows.enumerated().map { index, cells in
            let displayText = cells.map { $0.value.replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ")
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

            let captures = captures(from: cells, columns: result.columns)
            return ParsedExternalRecord(index: index, displayText: displayText, captures: .success(captures))
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
        let delimiter = MetadataExchangeCSV.detectDelimiter(in: trimmed)
        guard !trimmed.isEmpty else {
            return ([], delimiter, L10n.string("Enter a comma-, semicolon-, pipe-, or tab-delimited column template."))
        }

        do {
            let rows = try MetadataExchangeCSV.parse(trimmed, delimiter: delimiter)
            guard rows.count == 1, let row = rows.first, !row.isEmpty else {
                return ([], delimiter, L10n.string("Enter a single CSV template row."))
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

            if columns.contains(.fileName), columns.contains(.baseName) {
                return (columns, delimiter, "Use either {{fileName}} or {{baseName}} for matching, not both.")
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

    private static func captures(
        from cells: [MetadataExchangeCSVField],
        columns: [MetadataExchangeField]
    ) -> [MetadataExchangeField: String] {
        var captures: [MetadataExchangeField: String] = [:]
        for (index, field) in columns.enumerated() {
            guard field != .ignore else { continue }
            captures[field] = cells[index].importedValue
        }
        return captures
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
        let usesFileName = fields.contains(.fileName)
        let usesBaseName = fields.contains(.baseName)
        let rows: [MetadataExchangeImportPreviewRow]

        if usesFileName || usesBaseName {
            rows = makeMatchedImportRows(
                parsedRecords: parsedRecords,
                targetFiles: targetFiles,
                matchingField: usesFileName ? .fileName : .baseName,
                clearBlankImportedValues: clearBlankImportedValues
            )
        } else {
            rows = makeSelectionOrderImportRows(
                parsedRecords: parsedRecords,
                targetFiles: targetFiles,
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
        matchingField: MetadataExchangeField,
        clearBlankImportedValues: Bool
    ) -> [MetadataExchangeImportPreviewRow] {
        let filesByKey = Dictionary(grouping: targetFiles) { file in
            matchingKey(
                matchingField == .fileName
                    ? file.url.lastPathComponent
                    : file.url.deletingPathExtension().lastPathComponent
            )
        }
        var matchedFileIDs = Set<AudioFile.ID>()
        var rows: [MetadataExchangeImportPreviewRow] = []

        for record in parsedRecords {
            switch record.captures {
            case .failure(let message):
                rows.append(parseErrorRow(record: record, message: message))
            case .success(let captures):
                guard let rawKey = captures[matchingField], !rawKey.isEmpty else {
                    rows.append(
                        MetadataExchangeImportPreviewRow(
                            id: UUID(),
                            fileID: nil,
                            fileName: "—",
                            externalRecord: record.displayText,
                            status: .noMatch,
                            changes: [],
                            issueMessage: "This record did not provide a \(matchingField.displayName) value.",
                            writeEntry: nil
                        )
                    )
                    continue
                }

                let key = matchingKey(rawKey)
                let matches = filesByKey[key] ?? []
                if matches.isEmpty {
                    rows.append(
                        MetadataExchangeImportPreviewRow(
                            id: UUID(),
                            fileID: nil,
                            fileName: key,
                            externalRecord: record.displayText,
                            status: .noMatch,
                            changes: [],
                            issueMessage: L10n.string("No selected file matches this record."),
                            writeEntry: nil
                        )
                    )
                } else if matches.count > 1 {
                    rows.append(
                        MetadataExchangeImportPreviewRow(
                            id: UUID(),
                            fileID: nil,
                            fileName: key,
                            externalRecord: record.displayText,
                            status: .ambiguousMatch,
                            changes: [],
                            issueMessage: L10n.string("Multiple selected files match this record."),
                            writeEntry: nil
                        )
                    )
                } else if let file = matches.first {
                    guard !matchedFileIDs.contains(file.id) else {
                        rows.append(
                            MetadataExchangeImportPreviewRow(
                                id: UUID(),
                                fileID: file.id,
                                fileName: file.url.lastPathComponent,
                                externalRecord: record.displayText,
                                status: .ambiguousMatch,
                                changes: [],
                                issueMessage: L10n.string("Another external record already matched this selected file."),
                                writeEntry: nil
                            )
                        )
                        continue
                    }

                    matchedFileIDs.insert(file.id)
                    rows.append(
                        makeImportRow(
                            file: file,
                            record: record,
                            clearBlankImportedValues: clearBlankImportedValues
                        )
                    )
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

    private static func matchingKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
            let writeEntry = values.isEmpty
                ? nil
                : MetadataExchangeWriteEntry(
                    fileID: file.id,
                    fileName: file.url.lastPathComponent,
                    values: values
                )

            let status: MetadataExchangePreviewStatus = values.isEmpty ? .unchanged : .ready
            return MetadataExchangeImportPreviewRow(
                id: UUID(),
                fileID: file.id,
                fileName: file.url.lastPathComponent,
                externalRecord: record.displayText,
                status: status,
                changes: changes,
                issueMessage: record.warning,
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

    func match(_ source: String) -> MetadataExchangeCaptureResult {
        switch matchSegments(document.segments, in: source, at: 0, sourceIndex: source.startIndex, captures: [:]) {
        case .success(let captures):
            return .success(captures)
        case .failure(let message):
            return .failure(message)
        }
    }

    private func matchSegments(
        _ segments: [MetadataExchangeTemplateSegment],
        in source: String,
        at segmentIndex: Int,
        sourceIndex: String.Index,
        captures: [MetadataExchangeField: String]
    ) -> MetadataExchangeCaptureResult {
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
                captures: captures
            )

        case .field(let field):
            let nextSegmentIndex = segmentIndex + 1
            guard nextSegmentIndex < segments.count else {
                return captureValue(String(source[sourceIndex...]), for: field, into: captures)
            }

            guard case .literal(let nextLiteral) = segments[nextSegmentIndex] else {
                return .failure(L10n.string("Adjacent fields need a literal separator."))
            }

            var lastFailure: String?
            for literalPosition in findLiteralPositions(nextLiteral, in: source, startingAt: sourceIndex).reversed() {
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
                        captures: updatedCaptures
                    )
                    if case .success = result {
                        return result
                    }
                    if case .failure(let message) = result {
                        lastFailure = message
                    }
                }
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

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
    ) -> [String.Index] {
        guard !literal.isEmpty else { return [startIndex] }

        var positions: [String.Index] = []
        var searchStart = startIndex
        while searchStart < source.endIndex,
              let range = source[searchStart...].range(of: literal) {
            positions.append(range.lowerBound)
            searchStart = source.index(after: range.lowerBound)
        }
        return positions
    }
}

enum MetadataExchangeCSV {
    private static let delimiterCandidates: [Character] = ["\t", ",", ";", "|"]

    nonisolated static func allowsBareQuotesInUnquotedFields(for delimiter: Character) -> Bool {
        delimiter == "\t" || delimiter == "|"
    }

    static func detectDelimiter(in source: String) -> Character {
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

    static func parse(_ source: String, delimiter: Character = ",") throws -> [[String]] {
        try parseFields(source, delimiter: delimiter).map { row in
            row.map(\.value)
        }
    }

    fileprivate static func parseFields(
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
        guard value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func delimiterCountsOutsideQuotes(in source: String) -> [Character: Int] {
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
