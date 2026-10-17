import Foundation

nonisolated struct AudioTagNumberPair: Equatable, Sendable {
    var rawText: String
    var number: Int
    var total: Int

    init(rawText: String, number: Int, total: Int) {
        self.rawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.number = max(0, number)
        self.total = max(0, total)
    }

    private var trimmedRawText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rawComponents: (number: String, total: String?) {
        AudioTagNumberText.components(from: trimmedRawText)
    }

    var displayedNumberText: String {
        let component = rawComponents.number
        if !component.isEmpty {
            return component
        }
        return number > 0 ? String(number) : ""
    }

    var displayedTotalText: String {
        if let component = rawComponents.total, !component.isEmpty {
            return component
        }
        return total > 0 ? String(total) : ""
    }

    var canonicalRawText: String {
        let trimmed = trimmedRawText
        if !trimmed.isEmpty {
            return trimmed
        }

        guard number > 0 else { return "" }
        return total > 0 ? "\(number)/\(total)" : "\(number)"
    }

    func replacingNumberText(_ text: String) -> AudioTagNumberPair {
        Self.make(numberText: text, totalText: displayedTotalText)
    }

    func replacingTotalText(_ text: String) -> AudioTagNumberPair {
        Self.make(numberText: displayedNumberText, totalText: text)
    }

    static func make(numberText: String, totalText: String) -> AudioTagNumberPair {
        let normalizedNumberText = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTotalText = totalText.trimmingCharacters(in: .whitespacesAndNewlines)

        // The individual inspector fields normally hold one component, but a
        // pasted value can contain a slash. Parse such input as a pair instead
        // of concatenating it into malformed text like "7/12/12".
        let numberComponents = AudioTagNumberText.components(from: normalizedNumberText)
        let totalComponents = AudioTagNumberText.components(from: normalizedTotalText)
        let numberComponent = numberComponents.number

        let totalComponent: String
        if let embeddedTotal = numberComponents.total, !embeddedTotal.isEmpty {
            totalComponent = embeddedTotal
        } else {
            totalComponent = (totalComponents.total ?? totalComponents.number)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let rawText: String
        if numberComponent.isEmpty {
            rawText = ""
        } else if totalComponent.isEmpty {
            rawText = numberComponent
        } else {
            rawText = "\(numberComponent)/\(totalComponent)"
        }

        return AudioTagNumberPair(
            rawText: rawText,
            number: AudioTagNumberText.clampedInteger(fromComponent: numberComponent),
            total: AudioTagNumberText.clampedInteger(fromComponent: totalComponent)
        )
    }
}
