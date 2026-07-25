import Foundation

enum MetadataExchangeTemplateSyntaxSegment: Equatable {
    case literal(String)
    case placeholder(String)
}

struct MetadataExchangeTemplateSyntaxResult: Equatable {
    let segments: [MetadataExchangeTemplateSyntaxSegment]
    let hasUnterminatedPlaceholder: Bool
}

enum MetadataExchangeTemplateSyntaxParser {
    static func parse(_ rawValue: String) -> MetadataExchangeTemplateSyntaxResult {
        guard !rawValue.isEmpty else {
            return MetadataExchangeTemplateSyntaxResult(
                segments: [],
                hasUnterminatedPlaceholder: false
            )
        }

        var segments: [MetadataExchangeTemplateSyntaxSegment] = []
        var hasUnterminatedPlaceholder = false
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
                hasUnterminatedPlaceholder = true
                break
            }

            let placeholderName = String(rawValue[openingRange.upperBound..<closingRange.lowerBound])
            segments.append(.placeholder(placeholderName))
            searchStart = closingRange.upperBound
            literalStart = searchStart
        }

        if literalStart < rawValue.endIndex {
            appendLiteral(String(rawValue[literalStart...]), to: &segments)
        }

        return MetadataExchangeTemplateSyntaxResult(
            segments: segments,
            hasUnterminatedPlaceholder: hasUnterminatedPlaceholder
        )
    }

    private static func appendLiteral(
        _ literal: String,
        to segments: inout [MetadataExchangeTemplateSyntaxSegment]
    ) {
        guard !literal.isEmpty else { return }
        if case .literal(let existing)? = segments.last {
            segments[segments.count - 1] = .literal(existing + literal)
        } else {
            segments.append(.literal(literal))
        }
    }
}
