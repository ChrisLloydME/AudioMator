import Foundation

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

    func normalizedExtractedValue(
        _ rawValue: String,
        replacingUnderscoresWithSpaces: Bool
    ) -> String {
        let normalized = replacingUnderscoresWithSpaces
            ? rawValue.replacingOccurrences(of: "_", with: " ")
            : rawValue

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func acceptsExtractedValue(_ value: String) -> Bool {
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

struct FilenameMetadataTemplateMatcher {
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
