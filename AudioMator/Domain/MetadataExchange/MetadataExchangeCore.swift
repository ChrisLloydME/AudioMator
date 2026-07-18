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
    case trackTotal
    case discNumber
    case discTotal
    case comment
    case releaseDate
    case publisher
    case copyright
    case ignore = "_ignore"

    var token: String { "{{\(rawValue)}}" }

    var isWritableMetadataField: Bool {
        switch self {
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .trackTotal, .discNumber, .discTotal, .comment,
                .releaseDate, .publisher, .copyright:
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
                .trackNumber, .trackTotal, .discNumber, .discTotal, .comment,
                .releaseDate, .publisher, .copyright, .ignore:
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
                .trackNumber, .trackTotal, .discNumber, .discTotal, .comment,
                .releaseDate, .publisher, .copyright:
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
    private static let maximumTemplateUTF8ByteCount = 16_384
    private static let maximumImportUTF8ByteCount = 32 * 1_024 * 1_024
    private static let maximumImportRecordCount = 100_000
    private static let maximumCSVFieldUTF8ByteCount = 1_048_576

    static func parseCSVColumnTemplate(
        _ template: String
    ) -> (columns: [CoreMetadataExchangeField], delimiter: Character, validationMessage: String?) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let delimiter = MetadataExchangeCSV.detectDelimiter(in: trimmed)
        guard !trimmed.isEmpty else {
            return ([], delimiter, "Enter a comma-, semicolon-, pipe-, or tab-delimited column template.")
        }

        guard trimmed.utf8.count <= maximumTemplateUTF8ByteCount else {
            return ([], delimiter, "The column template is too large.")
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
        delimiter: Character = ",",
        firstRowIsHeader: Bool,
        targetFiles: [CoreMetadataExchangeFile],
        clearBlankImportedValues: Bool
    ) -> [CoreMetadataExchangeImportRow] {
        guard sourceText.utf8.count <= maximumImportUTF8ByteCount else {
            return [parseErrorRow(sourceText)]
        }

        let parsedCSV: [[MetadataExchangeCSVField]]
        do {
            parsedCSV = try MetadataExchangeCSV.parseFields(
                sourceText,
                delimiter: delimiter,
                allowsBareQuotesInUnquotedFields: MetadataExchangeCSV.allowsBareQuotesInUnquotedFields(for: delimiter),
                maximumRowCount: maximumImportRecordCount + (firstRowIsHeader ? 1 : 0),
                maximumFieldCountPerRow: columns.count + 1,
                maximumFieldUTF8ByteCount: maximumCSVFieldUTF8ByteCount
            )
        } catch {
            return [parseErrorRow(sourceText)]
        }

        let dataRows = firstRowIsHeader && !parsedCSV.isEmpty ? Array(parsedCSV.dropFirst()) : parsedCSV
        let parsedRecords = dataRows.enumerated().map { index, cells -> ParsedRecord in
            let displayText = cells.map {
                $0.decodedValue.replacingOccurrences(of: "\n", with: " ")
            }.joined(separator: " | ")
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

    private static func parseErrorRow(_ sourceText: String) -> CoreMetadataExchangeImportRow {
        CoreMetadataExchangeImportRow(
            fileID: nil,
            fileName: "",
            externalRecord: String(sourceText.prefix(4_096)),
            status: .parseError,
            writeValues: [:]
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
        var seenLocatorFields = Set<CoreMetadataExchangeField>()
        let locatorFields = fields.filter { field in
            field.isLocatorField && seenLocatorFields.insert(field).inserted
        }
        if !locatorFields.isEmpty {
            return matchedImportRows(
                parsedRecords: parsedRecords,
                locatorFields: locatorFields,
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
        locatorFields: [CoreMetadataExchangeField],
        targetFiles: [CoreMetadataExchangeFile],
        clearBlankImportedValues: Bool
    ) -> [CoreMetadataExchangeImportRow] {
        let locatedRecords = parsedRecords.map { record -> LocatedRecord in
            guard let captures = record.captures else {
                return LocatedRecord(record: record, matches: [], locatorDescription: "-")
            }

            let matches = targetFiles.enumerated().compactMap { index, file in
                matchesAllLocators(
                    captures: captures,
                    locatorFields: locatorFields,
                    file: file,
                    fileIndex: index
                ) ? file : nil
            }
            return LocatedRecord(
                record: record,
                matches: matches,
                locatorDescription: locatorDescription(
                    captures: captures,
                    locatorFields: locatorFields
                )
            )
        }
        let uniqueMatchCounts = locatedRecords.reduce(into: [String: Int]()) { counts, locatedRecord in
            guard locatedRecord.record.captures != nil, locatedRecord.matches.count == 1,
                  let fileID = locatedRecord.matches.first?.id
            else {
                return
            }
            counts[fileID, default: 0] += 1
        }
        var matchedFileIDs = Set<String>()
        var rows: [CoreMetadataExchangeImportRow] = []

        for locatedRecord in locatedRecords {
            let record = locatedRecord.record
            guard record.captures != nil else {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: "-", externalRecord: record.displayText, status: .parseError, writeValues: [:]))
                continue
            }
            if locatedRecord.matches.isEmpty {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: locatedRecord.locatorDescription, externalRecord: record.displayText, status: .noMatch, writeValues: [:]))
            } else if locatedRecord.matches.count > 1 {
                rows.append(CoreMetadataExchangeImportRow(fileID: nil, fileName: locatedRecord.locatorDescription, externalRecord: record.displayText, status: .ambiguousMatch, writeValues: [:]))
            } else if let file = locatedRecord.matches.first {
                guard uniqueMatchCounts[file.id] == 1 else {
                    rows.append(CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: record.displayText, status: .ambiguousMatch, writeValues: [:]))
                    continue
                }

                matchedFileIDs.insert(file.id)
                rows.append(importRow(file: file, record: record, clearBlankImportedValues: clearBlankImportedValues))
            }
        }

        for file in targetFiles where !matchedFileIDs.contains(file.id) {
            rows.append(CoreMetadataExchangeImportRow(fileID: file.id, fileName: file.fileName, externalRecord: "", status: .missingExternalRecord, writeValues: [:]))
        }

        return rows
    }

    private static func matchesAllLocators(
        captures: [CoreMetadataExchangeField: String],
        locatorFields: [CoreMetadataExchangeField],
        file: CoreMetadataExchangeFile,
        fileIndex: Int
    ) -> Bool {
        locatorFields.allSatisfy { field in
            guard let importedValue = captures[field] else { return false }

            switch field {
            case .fileName:
                return nonEmptyMatchingKey(importedValue) == nonEmptyMatchingKey(file.fileName)
            case .baseName:
                return nonEmptyMatchingKey(importedValue) == nonEmptyMatchingKey(file.baseName)
            case .path:
                guard let importedPath = normalizedAbsolutePath(importedValue) else { return false }
                return importedPath == normalizedAbsolutePath(file.path)
            case .relativePath:
                guard
                    let importedPath = normalizedRelativePath(importedValue),
                    let filePath = normalizedAbsolutePath(file.path)
                else {
                    return false
                }
                return filePath.hasSuffix("/\(importedPath)")
            case .index:
                guard let importedIndex = positiveIndex(importedValue) else { return false }
                return importedIndex == fileIndex + 1
            case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                    .trackNumber, .trackTotal, .discNumber, .discTotal, .comment,
                    .releaseDate, .publisher, .copyright, .ignore:
                return false
            }
        }
    }

    private static func locatorDescription(
        captures: [CoreMetadataExchangeField: String],
        locatorFields: [CoreMetadataExchangeField]
    ) -> String {
        let values = locatorFields.compactMap { field -> String? in
            guard let value = captures[field]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }
        return values.isEmpty ? "-" : values.joined(separator: " | ")
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
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
    }

    private static func commonDirectoryPath(for files: [CoreMetadataExchangeFile]) -> String? {
        guard let first = files.first?.path else { return nil }
        var components = URL(fileURLWithPath: first).standardizedFileURL.deletingLastPathComponent().path.split(separator: "/").map(String.init)

        for file in files.dropFirst() {
            let pathComponents = URL(fileURLWithPath: file.path).standardizedFileURL.deletingLastPathComponent().path.split(separator: "/").map(String.init)
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

    private struct LocatedRecord {
        let record: ParsedRecord
        let matches: [CoreMetadataExchangeFile]
        let locatorDescription: String
    }
}
