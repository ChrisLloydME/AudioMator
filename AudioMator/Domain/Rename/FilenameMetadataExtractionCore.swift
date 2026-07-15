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
    private let matchingStepLimit: Int

    private static let maximumSourceUTF8ByteCount = 4_096
    private static let maximumTemplateSegmentCount = 256

    init(
        document: FileRenameTemplateDocument,
        replaceUnderscoresWithSpaces: Bool,
        matchingStepLimit: Int = 20_000
    ) {
        self.document = document
        self.replaceUnderscoresWithSpaces = replaceUnderscoresWithSpaces
        self.matchingStepLimit = matchingStepLimit
    }

    func match(_ source: String) -> [FileRenameMetadataField: String]? {
        guard
            matchingStepLimit > 0,
            source.utf8.count <= Self.maximumSourceUTF8ByteCount,
            document.segments.count <= Self.maximumTemplateSegmentCount
        else {
            return nil
        }

        var search = MatchSearch(remainingSteps: matchingStepLimit)
        findMatches(
            document.segments,
            in: source,
            at: 0,
            sourceIndex: source.startIndex,
            captures: [:],
            search: &search
        )

        guard !search.didExhaustBudget, search.distinctMatches.count == 1 else {
            return nil
        }
        return search.distinctMatches[0]
    }

    private func findMatches(
        _ segments: [FileRenameTemplateSegment],
        in source: String,
        at segmentIndex: Int,
        sourceIndex: String.Index,
        captures: [FileRenameMetadataField: String],
        search: inout MatchSearch
    ) {
        guard !search.shouldStop, search.consumeStep() else { return }

        if segmentIndex >= segments.count {
            if sourceIndex == source.endIndex {
                search.recordDistinctMatch(captures)
            }
            return
        }

        switch segments[segmentIndex] {
        case .literal(let literal):
            guard source[sourceIndex...].hasPrefix(literal) else { return }
            let nextSourceIndex = source.index(sourceIndex, offsetBy: literal.count)
            findMatches(
                segments,
                in: source,
                at: segmentIndex + 1,
                sourceIndex: nextSourceIndex,
                captures: captures,
                search: &search
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
                    return
                }

                search.recordDistinctMatch(updatedCaptures)
                return
            }

            guard case .literal(let nextLiteral) = segments[nextSegmentIndex] else {
                return
            }

            let literalPositions = findLiteralPositions(
                nextLiteral,
                in: source,
                startingAt: sourceIndex
            )

            for literalPosition in literalPositions.reversed() {
                guard !search.shouldStop, search.consumeStep() else { return }
                let rawCapture = String(source[sourceIndex..<literalPosition])
                guard let updatedCaptures = captureValue(
                    rawCapture,
                    for: field,
                    into: captures
                ) else {
                    continue
                }

                findMatches(
                    segments,
                    in: source,
                    at: nextSegmentIndex,
                    sourceIndex: literalPosition,
                    captures: updatedCaptures,
                    search: &search
                )
            }
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

    private struct MatchSearch {
        var remainingSteps: Int
        var didExhaustBudget = false
        var distinctMatches: [[FileRenameMetadataField: String]] = []

        var shouldStop: Bool {
            didExhaustBudget || distinctMatches.count > 1
        }

        mutating func consumeStep() -> Bool {
            guard remainingSteps > 0 else {
                didExhaustBudget = true
                return false
            }

            remainingSteps -= 1
            return true
        }

        mutating func recordDistinctMatch(_ captures: [FileRenameMetadataField: String]) {
            guard !distinctMatches.contains(where: { $0 == captures }) else { return }
            distinctMatches.append(captures)
        }
    }
}
