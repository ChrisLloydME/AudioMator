import Foundation

enum MetadataExchangeTemplateSegment: Equatable {
    case literal(String)
    case field(MetadataExchangeField)
}

struct MetadataExchangeTemplateDocument: Equatable {
    let rawValue: String
    let segments: [MetadataExchangeTemplateSegment]
    let unknownPlaceholderNames: [String]
    let hasUnterminatedPlaceholder: Bool

    init(rawValue: String) {
        let result = MetadataExchangeTemplateParser.parse(rawValue)
        self.rawValue = rawValue
        self.segments = result.segments
        self.unknownPlaceholderNames = result.unknownPlaceholderNames
        self.hasUnterminatedPlaceholder = result.hasUnterminatedPlaceholder
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

struct MetadataExchangeTemplateParseResult: Equatable {
    let segments: [MetadataExchangeTemplateSegment]
    let unknownPlaceholderNames: [String]
    let hasUnterminatedPlaceholder: Bool
}

enum MetadataExchangeTemplateParser {
    static func parse(_ rawValue: String) -> MetadataExchangeTemplateParseResult {
        let syntax = MetadataExchangeTemplateSyntaxParser.parse(rawValue)
        var segments: [MetadataExchangeTemplateSegment] = []
        var unknownPlaceholderNames: [String] = []

        for syntaxSegment in syntax.segments {
            switch syntaxSegment {
            case .literal(let literal):
                appendLiteral(literal, to: &segments)
            case .placeholder(let placeholderName):
                if let field = MetadataExchangeField.field(forPlaceholderName: placeholderName) {
                    segments.append(.field(field))
                } else {
                    unknownPlaceholderNames.append(placeholderName)
                    appendLiteral("{{\(placeholderName)}}", to: &segments)
                }
            }
        }

        return MetadataExchangeTemplateParseResult(
            segments: segments,
            unknownPlaceholderNames: unknownPlaceholderNames,
            hasUnterminatedPlaceholder: syntax.hasUnterminatedPlaceholder
        )
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
