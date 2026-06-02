import Foundation

enum CoreMetadataExchangeField: String, CaseIterable, Hashable {
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
    case ignore = "_ignore"

    var token: String { "{{\(rawValue)}}" }

    var isWritableMetadataField: Bool {
        switch self {
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .discNumber, .comment, .releaseDate, .publisher, .copyright:
            return true
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            return false
        }
    }

    static func field(forExactToken token: String) -> Self? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.token == trimmed }
    }
}

struct CoreMetadataExchangeFile: Equatable, Hashable {
    let id: String
    let fileName: String
    let baseName: String
    let path: String
    let values: [CoreMetadataExchangeField: String]

    func value(for field: CoreMetadataExchangeField, index: Int, relativeBasePath: String?) -> String {
        switch field {
        case .fileName:
            return fileName
        case .baseName:
            return baseName
        case .path:
            return path
        case .relativePath:
            guard
                let relativeBasePath,
                let relative = CoreMetadataExchange.relativePath(path: path, basePath: relativeBasePath)
            else {
                return fileName
            }
            return relative
        case .index:
            return "\(index + 1)"
        case .ignore:
            return ""
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .discNumber, .comment, .releaseDate, .publisher, .copyright:
            return values[field] ?? ""
        }
    }
}

enum CoreMetadataExchangeStatus: Equatable {
    case ready
    case unchanged
    case noMatch
    case ambiguousMatch
    case parseError
    case missingExternalRecord
    case extraExternalRecord
    case noWritableFields
}

struct CoreMetadataExchangeImportRow: Equatable {
    let fileID: String?
    let fileName: String
    let externalRecord: String
    let status: CoreMetadataExchangeStatus
    let writeValues: [CoreMetadataExchangeField: String]
}

enum CoreMetadataExchange {
    static func parseCSVColumnTemplate(
        _ template: String
    ) -> (columns: [CoreMetadataExchangeField], delimiter: Character, validationMessage: String?) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let delimiter = MetadataExchangeCSV.detectDelimiter(in: trimmed)
        guard !trimmed.isEmpty else {
            return ([], delimiter, "Enter a comma-, semicolon-, pipe-, or tab-delimited column template.")
        }

        do {
            let rows = try MetadataExchangeCSV.parse(trimmed, delimiter: delimiter)
            guard rows.count == 1, let row = rows.first, !row.isEmpty else {
                return ([], delimiter, "Enter a single CSV template row.")
            }

            var columns: [CoreMetadataExchangeField] = []
            var seenFields = Set<CoreMetadataExchangeField>()
            for cell in row {
                guard let field = CoreMetadataExchangeField.field(forExactToken: cell) else {
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
                return (columns, delimiter, "Add at least one output field to the CSV template.")
            }

            return (columns, delimiter, nil)
        } catch {
            return ([], delimiter, (error as NSError).localizedDescription)
        }
    }

    static func textExportRows(
        fields: [CoreMetadataExchangeField],
        files: [CoreMetadataExchangeFile],
        separator: String
    ) -> [String] {
        let relativeBasePath = commonDirectoryPath(for: files)
        return files.enumerated().map { index, file in
            fields
                .map { $0 == .ignore ? "" : file.value(for: $0, index: index, relativeBasePath: relativeBasePath) }
                .joined(separator: separator)
        }
    }

    static func csvImportRows(
        columns: [CoreMetadataExchangeField],
        sourceText: String,
        firstRowIsHeader: Bool,
        targetFiles: [CoreMetadataExchangeFile],
        clearBlankImportedValues: Bool
    ) -> [CoreMetadataExchangeImportRow] {
        let delimiter = MetadataExchangeCSV.detectDelimiter(in: columns.map(\.token).joined(separator: ","))
        let parsedCSV: [[MetadataExchangeCSVField]]
        do {
            parsedCSV = try MetadataExchangeCSV.parseFields(
                sourceText,
                delimiter: delimiter,
                allowsBareQuotesInUnquotedFields: MetadataExchangeCSV.allowsBareQuotesInUnquotedFields(for: delimiter)
            )
        } catch {
            return [
                CoreMetadataExchangeImportRow(
                    fileID: nil,
                    fileName: "",
                    externalRecord: sourceText,
                    status: .parseError,
                    writeValues: [:]
                )
            ]
        }

        let dataRows = firstRowIsHeader && !parsedCSV.isEmpty ? Array(parsedCSV.dropFirst()) : parsedCSV
        let parsedRecords = dataRows.enumerated().map { index, cells -> ParsedRecord in
            let displayText = cells.map { $0.value.replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ")
            if cells.count < columns.count {
                return ParsedRecord(index: index, displayText: displayText, captures: nil, parseError: "\(columns.count - cells.count) missing CSV column(s).")
            }
            if cells.count > columns.count {
                return ParsedRecord(index: index, displayText: displayText, captures: nil, parseError: "\(cells.count - columns.count) extra CSV column(s).")
            }

            var captures: [CoreMetadataExchangeField: String] = [:]
            for (cellIndex, field) in columns.enumerated() where field != .ignore {
                captures[field] = cells[cellIndex].importedValue
            }
            return ParsedRecord(index: index, displayText: displayText, captures: captures, parseError: nil)
        }

        return importRows(
            parsedRecords: parsedRecords,
            fields: columns,
            targetFiles: targetFiles,
            clearBlankImportedValues: clearBlankImportedValues
        )
    }

    static func relativePath(path: String, basePath: String) -> String? {
        let filePath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedBasePath = URL(fileURLWithPath: basePath).standardizedFileURL.path

        if filePath == normalizedBasePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        let basePrefix = normalizedBasePath.hasSuffix("/") ? normalizedBasePath : normalizedBasePath + "/"
        guard filePath.hasPrefix(basePrefix) else { return nil }
        return String(filePath.dropFirst(basePrefix.count))
    }

    private static func importRows(
        parsedRecords: [ParsedRecord],
        fields: [CoreMetadataExchangeField],
        targetFiles: [CoreMetadataExchangeFile],
        clearBlankImportedValues: Bool
    ) -> [CoreMetadataExchangeImportRow] {
        if fields.contains(.fileName) || fields.contains(.baseName) {
            return matchedImportRows(
                parsedRecords: parsedRecords,
                matchingField: fields.contains(.fileName) ? .fileName : .baseName,
                targetFiles: targetFiles,
                clearBlankImportedValues: clearBlankImportedValues
            )
        }

        let count = max(parsedRecords.count, targetFiles.count)
        return (0..<count).map { index in
            let record = index < parsedRecords.count ? parsedRecords[index] : nil
            let file = index < targetFiles.count ? targetFiles[index] : nil

            guard let file else {
                return CoreMetadataExchangeImportRow(fileID: nil, fileName: "-", externalRecord: record?.displayText ?? "", status: .extraExternalRecord, writeValues: [:])
            }
            guard let record else {
                return CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: "", status: .missingExternalRecord, writeValues: [:])
            }
            return importRow(file: file, record: record, clearBlankImportedValues: clearBlankImportedValues)
        }
    }

    private static func matchedImportRows(
        parsedRecords: [ParsedRecord],
        matchingField: CoreMetadataExchangeField,
        targetFiles: [CoreMetadataExchangeFile],
        clearBlankImportedValues: Bool
    ) -> [CoreMetadataExchangeImportRow] {
        let filesByKey = Dictionary(grouping: targetFiles) { file in
            matchingKey(matchingField == .fileName ? file.fileName : file.baseName)
        }
        var matchedFileIDs = Set<String>()
        var rows: [CoreMetadataExchangeImportRow] = []

        for record in parsedRecords {
            guard let captures = record.captures else {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: "-", externalRecord: record.displayText, status: .parseError, writeValues: [:]))
                continue
            }
            guard let rawKey = captures[matchingField], !rawKey.isEmpty else {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: "-", externalRecord: record.displayText, status: .noMatch, writeValues: [:]))
                continue
            }

            let key = matchingKey(rawKey)
            let matches = filesByKey[key] ?? []
            if matches.isEmpty {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: key, externalRecord: record.displayText, status: .noMatch, writeValues: [:]))
            } else if matches.count > 1 {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: key, externalRecord: record.displayText, status: .ambiguousMatch, writeValues: [:]))
            } else if let file = matches.first {
                guard matchedFileIDs.insert(file.id).inserted else {
                    rows.append(CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: record.displayText, status: .ambiguousMatch, writeValues: [:]))
                    continue
                }
                rows.append(importRow(file: file, record: record, clearBlankImportedValues: clearBlankImportedValues))
            }
        }

        for file in targetFiles where !matchedFileIDs.contains(file.id) {
            rows.append(CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: "", status: .missingExternalRecord, writeValues: [:]))
        }

        return rows
    }

    private static func importRow(
        file: CoreMetadataExchangeFile,
        record: ParsedRecord,
        clearBlankImportedValues: Bool
    ) -> CoreMetadataExchangeImportRow {
        guard let captures = record.captures else {
            return CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: record.displayText, status: .parseError, writeValues: [:])
        }

        var writeValues: [CoreMetadataExchangeField: String] = [:]
        var sawWritableField = false
        for field in CoreMetadataExchangeField.allCases where field.isWritableMetadataField {
            guard let importedValue = captures[field] else { continue }
            sawWritableField = true
            let currentValue = file.values[field] ?? ""
            let shouldWriteBlank = clearBlankImportedValues && importedValue.isEmpty
            if (shouldWriteBlank || !importedValue.isEmpty), currentValue != importedValue {
                writeValues[field] = importedValue
            }
        }

        if !sawWritableField {
            return CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: record.displayText, status: .noWritableFields, writeValues: [:])
        }

        return CoreMetadataExchangeImportRow(
            fileID: file.id,
            fileName: file.fileName,
            externalRecord: record.displayText,
            status: writeValues.isEmpty ? .unchanged : .ready,
            writeValues: writeValues
        )
    }

    private static func matchingKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func commonDirectoryPath(for files: [CoreMetadataExchangeFile]) -> String? {
        guard let first = files.first?.path else { return nil }
        var components = URL(fileURLWithPath: first).deletingLastPathComponent().path.split(separator: "/").map(String.init)

        for file in files.dropFirst() {
            let pathComponents = URL(fileURLWithPath: file.path).deletingLastPathComponent().path.split(separator: "/").map(String.init)
            let sharedCount = zip(components, pathComponents).prefix { $0 == $1 }.count
            components = Array(components.prefix(sharedCount))
        }

        return "/" + components.joined(separator: "/")
    }

    private struct ParsedRecord {
        let index: Int
        let displayText: String
        let captures: [CoreMetadataExchangeField: String]?
        let parseError: String?
    }
}
