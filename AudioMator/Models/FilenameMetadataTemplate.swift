import Foundation
import Combine

extension FileRenameMetadataField {
    static let metadataToFilenameFields: [Self] = [
        .title,
        .artist,
        .album,
        .albumArtist,
        .composer,
        .genre,
        .year,
        .trackNumberText,
        .discNumberText,
        .comment,
        .releaseDate,
        .publisher,
        .copyright,
        .credits
    ]

    static let filenameToMetadataFields: [Self] = [
        .title,
        .artist,
        .album,
        .albumArtist,
        .composer,
        .genre,
        .year,
        .trackNumberText,
        .discNumberText,
        .comment,
        .releaseDate,
        .publisher,
        .copyright,
        .ignore
    ]

    var isHiddenExtractionField: Bool {
        self == .ignore
    }

    var supportsFilenameToMetadataWriting: Bool {
        switch self {
        case .ignore, .credits:
            return false
        case .title, .artist, .album, .albumArtist, .composer, .genre, .year,
                .trackNumberText, .discNumberText, .comment, .releaseDate,
                .publisher, .copyright:
            return true
        }
    }

    func currentMetadataValue(from file: AudioFile) -> String {
        switch self {
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
        case .trackNumberText:
            return file.trackNumberText
        case .discNumberText:
            return file.discNumberText
        case .comment:
            return file.comment
        case .releaseDate:
            return file.releaseDate
        case .publisher:
            return file.publisher
        case .copyright:
            return file.copyright
        case .credits:
            return file.credits
        case .ignore:
            return ""
        }
    }

    func applyExtractedValue(_ value: String, to edit: inout SingleFileEditModel) {
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
        case .trackNumberText:
            edit.trackNumberText = value
        case .discNumberText:
            edit.discNumberText = value
        case .comment:
            edit.comment = value
        case .releaseDate:
            edit.releaseDate = value
        case .publisher:
            edit.publisher = value
        case .copyright:
            edit.copyright = value
        case .credits, .ignore:
            break
        }
    }

    fileprivate func normalizedExtractedValue(
        _ rawValue: String,
        replacingUnderscoresWithSpaces: Bool
    ) -> String {
        let normalized = replacingUnderscoresWithSpaces
            ? rawValue.replacingOccurrences(of: "_", with: " ")
            : rawValue

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate func acceptsExtractedValue(_ value: String) -> Bool {
        switch self {
        case .ignore:
            return true
        case .trackNumberText, .discNumberText:
            return value.range(
                of: #"^\d+(?:\s*/\s*\d+)?$"#,
                options: .regularExpression
            ) != nil
        case .year:
            return value.range(
                of: #"^\d{4}$"#,
                options: .regularExpression
            ) != nil
        case .releaseDate:
            return value.range(
                of: #"^\d{4}(?:-\d{2}(?:-\d{2})?)?$"#,
                options: .regularExpression
            ) != nil
        case .title, .artist, .album, .albumArtist, .composer, .genre,
                .comment, .publisher, .copyright, .credits:
            return !value.isEmpty
        }
    }
}

enum FilenameMetadataFieldChangeStatus: Equatable {
    case same
    case different
}

struct FilenameMetadataFieldChange: Identifiable {
    let field: FileRenameMetadataField
    let currentValue: String
    let extractedValue: String
    let status: FilenameMetadataFieldChangeStatus
    let willWrite: Bool

    var id: String { field.placeholderName }
}

enum FilenameMetadataPreviewStatus: Equatable {
    case ready
    case unchanged
    case noMatch
    case noWritableFields

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .unchanged:
            return "Unchanged"
        case .noMatch:
            return "No Match"
        case .noWritableFields:
            return "No Writable Fields"
        }
    }

    var message: String {
        switch self {
        case .ready:
            return "The filename matched and extracted metadata can be written."
        case .unchanged:
            return "The extracted metadata already matches the file's current tags."
        case .noMatch:
            return "The filename did not fully match the template."
        case .noWritableFields:
            return "The template matched, but it did not extract any writable metadata fields."
        }
    }

    var isError: Bool {
        self == .noMatch
    }
}

struct FilenameMetadataWriteEntry: Identifiable {
    let fileID: UUID
    let fileName: String
    let values: [FileRenameMetadataField: String]

    var id: UUID { fileID }
}

struct FilenameMetadataPreviewRow: Identifiable {
    let id: AudioFile.ID
    let currentName: String
    let sourceBaseName: String
    let status: FilenameMetadataPreviewStatus
    let changes: [FilenameMetadataFieldChange]
    let issueMessage: String?
    let writeEntry: FilenameMetadataWriteEntry?
}

struct FilenameMetadataPlan {
    let template: String
    let replaceUnderscoresWithSpaces: Bool
    let validationMessage: String?
    let rows: [FilenameMetadataPreviewRow]

    var writeEntries: [FilenameMetadataWriteEntry] {
        rows.compactMap(\.writeEntry)
    }

    var readyCount: Int {
        writeEntries.count
    }

    var unchangedCount: Int {
        rows.filter { $0.status == .unchanged }.count
    }

    var noWritableCount: Int {
        rows.filter { $0.status == .noWritableFields }.count
    }

    var noMatchCount: Int {
        rows.filter { $0.status == .noMatch }.count
    }

    var issueCount: Int {
        let rowIssues = rows.filter { $0.status.isError }.count
        return rowIssues + (validationMessage == nil ? 0 : 1)
    }

    var hasIssues: Bool {
        issueCount > 0
    }

    var canApply: Bool {
        validationMessage == nil && !writeEntries.isEmpty
    }
}

func makeFilenameMetadataPlan(
    template: String,
    targetFiles: [AudioFile],
    replaceUnderscoresWithSpaces: Bool
) -> FilenameMetadataPlan {
    let document = FileRenameTemplateDocument(rawValue: template)

    guard !document.isVisuallyEmpty, !targetFiles.isEmpty else {
        return FilenameMetadataPlan(
            template: template,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
            validationMessage: nil,
            rows: []
        )
    }

    let builder = FilenameMetadataPlanBuilder(
        replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces
    )
    return builder.makePlan(document: document, targetFiles: targetFiles)
}

private struct FilenameMetadataPlanBuilder {
    let replaceUnderscoresWithSpaces: Bool

    func makePlan(
        document: FileRenameTemplateDocument,
        targetFiles: [AudioFile]
    ) -> FilenameMetadataPlan {
        if let validationMessage = validate(document: document) {
            return FilenameMetadataPlan(
                template: document.rawValue,
                replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
                validationMessage: validationMessage,
                rows: []
            )
        }

        let matcher = FilenameMetadataTemplateMatcher(
            document: document,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces
        )

        let rows = targetFiles.map { file in
            makeRow(for: file, matcher: matcher, document: document)
        }

        return FilenameMetadataPlan(
            template: document.rawValue,
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
            validationMessage: nil,
            rows: rows
        )
    }

    private func validate(document: FileRenameTemplateDocument) -> String? {
        let hasExtractionField = document.segments.contains { segment in
            guard case .field(let field) = segment else { return false }
            return !field.isHiddenExtractionField
        }

        guard hasExtractionField else {
            return "Add at least one metadata field to extract from the filename."
        }

        for index in document.segments.indices.dropLast() {
            guard case .field = document.segments[index] else { continue }
            guard case .field = document.segments[index + 1] else { continue }
            return "Add literal separators between metadata fields so AudioMator can parse the filename unambiguously."
        }

        return nil
    }

    private func makeRow(
        for file: AudioFile,
        matcher: FilenameMetadataTemplateMatcher,
        document: FileRenameTemplateDocument
    ) -> FilenameMetadataPreviewRow {
        let sourceBaseName = file.url.deletingPathExtension().lastPathComponent

        guard let extractedValues = matcher.match(sourceBaseName) else {
            return FilenameMetadataPreviewRow(
                id: file.id,
                currentName: file.url.lastPathComponent,
                sourceBaseName: sourceBaseName,
                status: .noMatch,
                changes: [],
                issueMessage: FilenameMetadataPreviewStatus.noMatch.message,
                writeEntry: nil
            )
        }

        let orderedFields = uniqueOrderedFields(from: document)
        let changes = orderedFields.compactMap { field -> FilenameMetadataFieldChange? in
            guard !field.isHiddenExtractionField else { return nil }
            guard let extractedValue = extractedValues[field] else { return nil }

            let currentValue = field.currentMetadataValue(from: file)
            let status: FilenameMetadataFieldChangeStatus = currentValue == extractedValue ? .same : .different
            let willWrite = field.supportsFilenameToMetadataWriting && status == .different

            return FilenameMetadataFieldChange(
                field: field,
                currentValue: currentValue,
                extractedValue: extractedValue,
                status: status,
                willWrite: willWrite
            )
        }

        let writeValues = Dictionary(
            uniqueKeysWithValues: changes
                .filter(\.willWrite)
                .map { ($0.field, $0.extractedValue) }
        )

        let capturedWritableFieldCount = changes.filter { $0.field.supportsFilenameToMetadataWriting }.count
        let status: FilenameMetadataPreviewStatus
        let issueMessage: String?

        if capturedWritableFieldCount == 0 {
            status = .noWritableFields
            issueMessage = FilenameMetadataPreviewStatus.noWritableFields.message
        } else if writeValues.isEmpty {
            status = .unchanged
            issueMessage = nil
        } else {
            status = .ready
            issueMessage = nil
        }

        let writeEntry = writeValues.isEmpty
            ? nil
            : FilenameMetadataWriteEntry(
                fileID: file.id,
                fileName: file.url.lastPathComponent,
                values: writeValues
            )

        return FilenameMetadataPreviewRow(
            id: file.id,
            currentName: file.url.lastPathComponent,
            sourceBaseName: sourceBaseName,
            status: status,
            changes: changes,
            issueMessage: issueMessage,
            writeEntry: writeEntry
        )
    }

    private func uniqueOrderedFields(from document: FileRenameTemplateDocument) -> [FileRenameMetadataField] {
        var orderedFields: [FileRenameMetadataField] = []
        var seen = Set<FileRenameMetadataField>()

        for segment in document.segments {
            guard case .field(let field) = segment else { continue }
            guard !seen.contains(field) else { continue }
            seen.insert(field)
            orderedFields.append(field)
        }

        return orderedFields
    }
}

private struct FilenameMetadataTemplateMatcher {
    let document: FileRenameTemplateDocument
    let replaceUnderscoresWithSpaces: Bool

    func match(_ source: String) -> [FileRenameMetadataField: String]? {
        matchSegments(
            document.segments,
            in: source,
            at: 0,
            sourceIndex: source.startIndex,
            captures: [:]
        )
    }

    private func matchSegments(
        _ segments: [FileRenameTemplateSegment],
        in source: String,
        at segmentIndex: Int,
        sourceIndex: String.Index,
        captures: [FileRenameMetadataField: String]
    ) -> [FileRenameMetadataField: String]? {
        if segmentIndex >= segments.count {
            return sourceIndex == source.endIndex ? captures : nil
        }

        switch segments[segmentIndex] {
        case .literal(let literal):
            guard source[sourceIndex...].hasPrefix(literal) else { return nil }
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
                let rawCapture = String(source[sourceIndex...])
                guard let updatedCaptures = captureValue(
                    rawCapture,
                    for: field,
                    into: captures
                ) else {
                    return nil
                }

                return updatedCaptures
            }

            guard case .literal(let nextLiteral) = segments[nextSegmentIndex] else {
                return nil
            }

            let literalPositions = findLiteralPositions(
                nextLiteral,
                in: source,
                startingAt: sourceIndex
            )

            for literalPosition in literalPositions.reversed() {
                let rawCapture = String(source[sourceIndex..<literalPosition])
                guard let updatedCaptures = captureValue(
                    rawCapture,
                    for: field,
                    into: captures
                ) else {
                    continue
                }

                if let match = matchSegments(
                    segments,
                    in: source,
                    at: nextSegmentIndex,
                    sourceIndex: literalPosition,
                    captures: updatedCaptures
                ) {
                    return match
                }
            }

            return nil
        }
    }

    private func captureValue(
        _ rawValue: String,
        for field: FileRenameMetadataField,
        into captures: [FileRenameMetadataField: String]
    ) -> [FileRenameMetadataField: String]? {
        let normalizedValue = field.normalizedExtractedValue(
            rawValue,
            replacingUnderscoresWithSpaces: replaceUnderscoresWithSpaces
        )

        guard field.acceptsExtractedValue(normalizedValue) else {
            return nil
        }

        guard !field.isHiddenExtractionField else {
            return captures
        }

        if let existingValue = captures[field] {
            return existingValue == normalizedValue ? captures : nil
        }

        var updatedCaptures = captures
        updatedCaptures[field] = normalizedValue
        return updatedCaptures
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

        if source[startIndex...].hasPrefix(literal) {
            if positions.first != startIndex {
                positions.insert(startIndex, at: 0)
            }
        }

        return positions
    }
}
