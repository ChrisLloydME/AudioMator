import Foundation

nonisolated enum FileRenameMetadataField: CaseIterable, Hashable, Identifiable, Sendable {
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
    case date
    case originalReleaseDate
    case trackNumberText
    case discNumberText
    case comment
    case releaseDate
    case publisher
    case copyright
    case credits
    case ignore

    var id: String { placeholderName }

    var placeholderName: String {
        switch self {
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
        case .date:
            return "date"
        case .originalReleaseDate:
            return "originalReleaseDate"
        case .trackNumberText:
            return "trackNumber"
        case .discNumberText:
            return "discNumber"
        case .comment:
            return "comment"
        case .releaseDate:
            return "releaseDate"
        case .publisher:
            return "publisher"
        case .copyright:
            return "copyright"
        case .credits:
            return "credits"
        case .ignore:
            return "_ignore"
        }
    }

    var token: String {
        "{{\(placeholderName)}}"
    }

    static func field(forPlaceholderName placeholderName: String) -> Self? {
        allCases.first { $0.placeholderName == placeholderName }
    }
}

nonisolated enum FileRenameTemplateSegment: Equatable, Sendable {
    case literal(String)
    case field(FileRenameMetadataField)
}

nonisolated struct FileRenameTemplateDocument: Equatable, Sendable {
    let rawValue: String
    let segments: [FileRenameTemplateSegment]
    let unknownPlaceholderNames: [String]
    let hasUnterminatedPlaceholder: Bool

    init(rawValue: String) {
        let result = FileRenameTemplateParser.parse(rawValue)
        self.rawValue = rawValue
        self.segments = result.segments
        self.unknownPlaceholderNames = result.unknownPlaceholderNames
        self.hasUnterminatedPlaceholder = result.hasUnterminatedPlaceholder
    }

    var isVisuallyEmpty: Bool {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var containsFieldSegments: Bool {
        segments.contains { segment in
            if case .field = segment {
                return true
            }

            return false
        }
    }
}

nonisolated struct FileRenameTemplateParseResult: Equatable, Sendable {
    let segments: [FileRenameTemplateSegment]
    let unknownPlaceholderNames: [String]
    let hasUnterminatedPlaceholder: Bool
}

/// Maps the shared Foundation-only `{{placeholder}}` tokenizer onto rename fields.
///
/// The rename field mapping stays separate from the metadata-exchange mapping:
/// both consume `MetadataExchangeTemplateSyntaxParser`, but each resolves its own
/// field type and preserves the shared literal/unknown-placeholder semantics.
nonisolated enum FileRenameTemplateParser {
    static func parse(_ rawValue: String) -> FileRenameTemplateParseResult {
        let syntax = MetadataExchangeTemplateSyntaxParser.parse(rawValue)
        var segments: [FileRenameTemplateSegment] = []
        var unknownPlaceholderNames: [String] = []

        for syntaxSegment in syntax.segments {
            switch syntaxSegment {
            case .literal(let literal):
                appendLiteral(literal, to: &segments)
            case .placeholder(let placeholderName):
                if let field = FileRenameMetadataField.field(forPlaceholderName: placeholderName) {
                    segments.append(.field(field))
                } else {
                    unknownPlaceholderNames.append(placeholderName)
                    appendLiteral("{{\(placeholderName)}}", to: &segments)
                }
            }
        }

        return FileRenameTemplateParseResult(
            segments: segments,
            unknownPlaceholderNames: unknownPlaceholderNames,
            hasUnterminatedPlaceholder: syntax.hasUnterminatedPlaceholder
        )
    }

    private static func appendLiteral(_ literal: String, to segments: inout [FileRenameTemplateSegment]) {
        guard !literal.isEmpty else { return }

        if case .literal(let existing)? = segments.last {
            segments[segments.count - 1] = .literal(existing + literal)
        } else {
            segments.append(.literal(literal))
        }
    }
}

nonisolated struct FileRenameSanitizer: Sendable {
    /// Fixed, user-visible replacement policy: path-unsafe scalars become `-`,
    /// other control characters become a space, surrounding whitespace is
    /// trimmed, and an empty result is rejected. See `RENAME_AND_RENUMBERING.md`.
    func sanitizeBaseName(_ baseName: String) -> String? {
        let pathUnsafeScalars = CharacterSet(charactersIn: "/:\u{0000}")
        let controlCharacters = CharacterSet.controlCharacters

        let sanitized = String(baseName.unicodeScalars.map { scalar -> Character in
            if pathUnsafeScalars.contains(scalar) {
                return "-"
            }

            if controlCharacters.contains(scalar) {
                return " "
            }

            return Character(scalar)
        })
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? nil : sanitized
    }
}
