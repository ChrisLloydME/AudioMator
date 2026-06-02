import Foundation

enum FileRenameMetadataField: CaseIterable, Hashable, Identifiable {
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
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

enum FileRenameTemplateSegment: Equatable {
    case literal(String)
    case field(FileRenameMetadataField)
}

struct FileRenameTemplateDocument: Equatable {
    let rawValue: String
    let segments: [FileRenameTemplateSegment]

    init(rawValue: String) {
        self.rawValue = rawValue
        self.segments = FileRenameTemplateParser.parse(rawValue)
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

enum FileRenameTemplateParser {
    static func parse(_ rawValue: String) -> [FileRenameTemplateSegment] {
        guard !rawValue.isEmpty else { return [] }

        var segments: [FileRenameTemplateSegment] = []
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
            if let field = FileRenameMetadataField.field(forPlaceholderName: placeholderName) {
                segments.append(.field(field))
            } else {
                let unmatchedPlaceholder = String(rawValue[openingRange.lowerBound..<closingRange.upperBound])
                appendLiteral(unmatchedPlaceholder, to: &segments)
            }

            searchStart = closingRange.upperBound
            literalStart = searchStart
        }

        if literalStart < rawValue.endIndex {
            appendLiteral(String(rawValue[literalStart...]), to: &segments)
        }

        return segments
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

struct FileRenameCompatibilityOptions {
    let directorySeparatorReplacement: Character
    let colonReplacement: Character
    let invalidScalarReplacement: Character
    let controlCharacterReplacement: Character

    static let currentDefaults = FileRenameCompatibilityOptions(
        directorySeparatorReplacement: "-",
        colonReplacement: "-",
        invalidScalarReplacement: "-",
        controlCharacterReplacement: " "
    )
}

struct FileRenameSanitizer {
    let options: FileRenameCompatibilityOptions

    init(options: FileRenameCompatibilityOptions = .currentDefaults) {
        self.options = options
    }

    func sanitizeBaseName(_ baseName: String) -> String? {
        let invalidScalars = CharacterSet(charactersIn: "/:\u{0000}")
        let controlCharacters = CharacterSet.controlCharacters

        let sanitized = String(baseName.unicodeScalars.map { scalar -> Character in
            if invalidScalars.contains(scalar) {
                switch scalar {
                case "/":
                    return options.directorySeparatorReplacement
                case ":":
                    return options.colonReplacement
                default:
                    return options.invalidScalarReplacement
                }
            }

            if controlCharacters.contains(scalar) {
                return options.controlCharacterReplacement
            }

            return Character(scalar)
        })
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? nil : sanitized
    }
}
