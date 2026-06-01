import Foundation

enum AudioTagNumberText {
    nonisolated static func components(from rawText: String) -> (number: String, total: String?) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let number = parts.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let total = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        return (number, total)
    }

    nonisolated static func parsedPair(from rawText: String) -> (number: Int, total: Int) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }

        let components = components(from: trimmed)
        return (
            clampedInteger(fromComponent: components.number),
            components.total.map(clampedInteger(fromComponent:)) ?? 0
        )
    }

    nonisolated static func clampedInteger(fromComponent rawText: String) -> Int {
        max(0, Int(rawText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    nonisolated static func positiveIndex(from rawText: String) -> Int? {
        let component = components(from: rawText).number
        guard !component.isEmpty else { return nil }

        let stripped = String(component.drop(while: { $0 == "0" }))
        let value = Int(stripped.isEmpty ? component : stripped)

        return value.flatMap { $0 > 0 ? $0 : nil }
    }
}
