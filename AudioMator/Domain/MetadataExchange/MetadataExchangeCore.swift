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
    private static let maximumImportUTF8ByteCount = MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount
    private static let maximumImportRecordCount = MetadataExchangeResourceLimits.maximumRecordCount
    private static let maximumCSVFieldUTF8ByteCount = MetadataExchangeResourceLimits.maximumCSVFieldUTF8ByteCount

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
        guard targetFiles.count <= maximumImportRecordCount else {
            return [parseErrorRow(sourceText)]
        }

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

        let locatedRecords = parsedRecords.map { record -> LocatedRecord in
            guard let captures = record.captures else {
                return LocatedRecord(record: record, matches: [], locatorDescription: "-")
            }

            guard let signature = locatorSignature(captures: captures, locatorFields: locatorFields) else {
                return LocatedRecord(
                    record: record,
                    matches: [],
                    locatorDescription: locatorDescription(
                        captures: captures,
                        locatorFields: locatorFields
                    )
                )
            }

            let match: LocatorMatch
            if let cachedMatch = matchCache[signature] {
                match = cachedMatch
            } else {
                let candidateIndices = candidateIndex.candidateIndices(fields: locatorFields) { field in
                    locatorLookupKey(captures[field] ?? "", field: field)
                }
                let matches = candidateIndices.compactMap { fileIndex -> CoreMetadataExchangeFile? in
                    let file = targetFiles[fileIndex]
                    return matchesAllLocators(
                        captures: captures,
                        locatorFields: locatorFields,
                        file: file,
                        fileIndex: fileIndex
                    ) ? file : nil
                }
                switch matches.count {
                case 0:
                    match = .none
                case 1:
                    match = .matched(matches[0])
                default:
                    match = .ambiguous(Array(matches.prefix(2)))
                }
                matchCache[signature] = match
            }

            let matches: [CoreMetadataExchangeFile]
            switch match {
            case .none:
                matches = []
            case .ambiguous(let ambiguousMatches):
                matches = ambiguousMatches
            case .matched(let file):
                matches = [file]
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

    private static func locatorSignature(
        captures: [CoreMetadataExchangeField: String],
        locatorFields: [CoreMetadataExchangeField]
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
        field: CoreMetadataExchangeField,
        file: CoreMetadataExchangeFile,
        fileIndex: Int
    ) -> [String] {
        switch field {
        case .fileName:
            return nonEmptyMatchingKey(file.fileName).map { [$0] } ?? []
        case .baseName:
            return nonEmptyMatchingKey(file.baseName).map { [$0] } ?? []
        case .path:
            return normalizedAbsolutePath(file.path).map { [$0] } ?? []
        case .relativePath:
            guard let path = normalizedAbsolutePath(file.path) else { return [] }
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.indices.map { index in
                components[index...].joined(separator: "/")
            }
        case .index:
            return [String(fileIndex + 1)]
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .trackTotal, .discNumber, .discTotal, .comment,
                .releaseDate, .publisher, .copyright, .ignore:
            return []
        }
    }

    private static func locatorLookupKey(
        _ value: String,
        field: CoreMetadataExchangeField
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
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumber, .trackTotal, .discNumber, .discTotal, .comment,
                .releaseDate, .publisher, .copyright, .ignore:
            return nil
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

    private enum LocatorMatch {
        case none
        case ambiguous([CoreMetadataExchangeFile])
        case matched(CoreMetadataExchangeFile)
    }

    private struct LocatorSignature: Hashable {
        let values: [String]
    }
}
