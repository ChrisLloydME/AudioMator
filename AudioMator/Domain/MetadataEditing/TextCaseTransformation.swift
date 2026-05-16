import Foundation

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

enum TextEditPipelineStep: Sendable, Hashable {
    case transformCase(TextCaseTransformation)

    func applied(to text: String, context: TextEditPipelineContext = .default) -> String {
        switch self {
        case .transformCase(let transformation):
            return transformation.applied(to: text, locale: context.locale)
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
