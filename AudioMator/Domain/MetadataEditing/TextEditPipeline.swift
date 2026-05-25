import Foundation

enum TextInsertionPosition: String, CaseIterable, Sendable, Hashable {
    case prefix
    case suffix
}

enum TextTrimCharacterSet: String, CaseIterable, Sendable, Hashable {
    case whitespaces
    case whitespacesAndNewlines

    var characterSet: CharacterSet {
        switch self {
        case .whitespaces:
            return .whitespaces
        case .whitespacesAndNewlines:
            return .whitespacesAndNewlines
        }
    }
}

enum TextCaseTransformation: String, CaseIterable, Sendable, Hashable {
    case uppercase
    case lowercase
    case titleCase
    case capitalizeFirstLetter
    case sentenceCase

    func applied(to text: String, locale: Locale = .current) -> String {
        switch self {
        case .uppercase:
            return text.uppercased(with: locale)
        case .lowercase:
            return text.lowercased(with: locale)
        case .titleCase:
            return text.capitalized(with: locale)
        case .capitalizeFirstLetter:
            return text.replacingFirstLetter(locale: locale) { letter in
                letter.uppercased(with: locale)
            }
        case .sentenceCase:
            let lowercaseText = text.lowercased(with: locale)
            return lowercaseText.replacingFirstLetter(locale: locale) { letter in
                letter.uppercased(with: locale)
            }
        }
    }
}

struct TextFindReplacementOptions: Sendable, Hashable {
    var matchesCase: Bool
    var matchesWholeText: Bool

    init(matchesCase: Bool = false, matchesWholeText: Bool = false) {
        self.matchesCase = matchesCase
        self.matchesWholeText = matchesWholeText
    }

    var compareOptions: String.CompareOptions {
        var options: String.CompareOptions = [.literal]

        if !matchesCase {
            options.insert(.caseInsensitive)
        }

        return options
    }
}

struct TextFindReplacement: Sendable, Hashable {
    var findText: String
    var replacementText: String
    var options: TextFindReplacementOptions

    init(
        findText: String,
        replacementText: String,
        options: TextFindReplacementOptions = TextFindReplacementOptions()
    ) {
        self.findText = findText
        self.replacementText = replacementText
        self.options = options
    }

    func applied(to text: String, locale: Locale = .current) -> String {
        guard !findText.isEmpty else { return text }

        if options.matchesWholeText {
            return text.compare(findText, options: options.compareOptions, locale: locale) == .orderedSame
                ? replacementText
                : text
        }

        var result = ""
        var searchStartIndex = text.startIndex

        while searchStartIndex < text.endIndex,
              let matchedRange = text.range(
                of: findText,
                options: options.compareOptions,
                range: searchStartIndex..<text.endIndex,
                locale: locale
              ) {
            result += text[searchStartIndex..<matchedRange.lowerBound]
            result += replacementText
            searchStartIndex = matchedRange.upperBound
        }

        result += text[searchStartIndex..<text.endIndex]
        return result
    }
}

enum TextEditPipelineStep: Sendable, Hashable {
    case insertText(String, position: TextInsertionPosition)
    case replaceText(TextFindReplacement)
    case transformCase(TextCaseTransformation)
    case trimEdges(TextTrimCharacterSet)

    func applied(to text: String, context: TextEditPipelineContext = .default) -> String {
        switch self {
        case .insertText(let insertedText, let position):
            switch position {
            case .prefix:
                return insertedText + text
            case .suffix:
                return text + insertedText
            }
        case .replaceText(let replacement):
            return replacement.applied(to: text, locale: context.locale)
        case .transformCase(let transformation):
            return transformation.applied(to: text, locale: context.locale)
        case .trimEdges(let characterSet):
            return text.trimmingCharacters(in: characterSet.characterSet)
        }
    }
}

struct TextEditPipelineContext: Sendable, Hashable {
    static let `default` = TextEditPipelineContext(locale: .current)

    var locale: Locale
}

struct TextEditPipeline: Sendable, Hashable {
    var steps: [TextEditPipelineStep]

    init(steps: [TextEditPipelineStep] = []) {
        self.steps = steps
    }

    func applying(to text: String, context: TextEditPipelineContext = .default) -> String {
        steps.reduce(text) { currentText, step in
            step.applied(to: currentText, context: context)
        }
    }
}

private extension String {
    func replacingFirstLetter(
        locale: Locale,
        transform: (String) -> String
    ) -> String {
        guard let firstLetterRange = rangeOfFirstLetter else {
            return self
        }

        var result = self
        let letter = String(result[firstLetterRange])
        result.replaceSubrange(firstLetterRange, with: transform(letter))
        return result
    }

    var rangeOfFirstLetter: Range<String.Index>? {
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let nextIndex = index(after: currentIndex)
            let character = self[currentIndex..<nextIndex]

            if character.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
                return currentIndex..<nextIndex
            }

            currentIndex = nextIndex
        }

        return nil
    }
}
