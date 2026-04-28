import Foundation

struct AudioTagNumberPair: Equatable {
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
        let parts = trimmedRawText.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let left = parts.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let right = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        return (left, right)
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

        let rawText: String
        if normalizedNumberText.isEmpty {
            rawText = ""
        } else if normalizedTotalText.isEmpty {
            rawText = normalizedNumberText
        } else {
            rawText = "\(normalizedNumberText)/\(normalizedTotalText)"
        }

        return AudioTagNumberPair(
            rawText: rawText,
            number: Int(normalizedNumberText) ?? 0,
            total: Int(normalizedTotalText) ?? 0
        )
    }
}
