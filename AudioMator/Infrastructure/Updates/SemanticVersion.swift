import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable {
    let numbers: [Int]

    init?(appVersion rawValue: String) {
        guard let parsedNumbers = Self.parseVersionCore(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.numbers = parsedNumbers
    }

    init?(releaseTag rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.hasPrefix("V"),
              let buildSeparator = normalized.firstIndex(of: "B")
        else {
            return nil
        }

        let versionCore = String(normalized[normalized.index(after: normalized.startIndex)..<buildSeparator])
        let buildNumber = normalized[normalized.index(after: buildSeparator)...]

        guard !buildNumber.isEmpty,
              buildNumber.allSatisfy(\.isNumber),
              let parsedNumbers = Self.parseVersionCore(versionCore)
        else {
            return nil
        }

        self.numbers = parsedNumbers
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.numbers.count, rhs.numbers.count)

        for index in 0..<maxCount {
            let lhsNumber = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let rhsNumber = index < rhs.numbers.count ? rhs.numbers[index] : 0

            if lhsNumber != rhsNumber {
                return lhsNumber < rhsNumber
            }
        }

        return false
    }

    private static func parseVersionCore(_ rawValue: String) -> [Int]? {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)

        guard !components.isEmpty else { return nil }

        let parsedNumbers = components.compactMap { component -> Int? in
            guard !component.isEmpty, component.allSatisfy(\.isNumber) else { return nil }
            return Int(component)
        }

        guard parsedNumbers.count == components.count else { return nil }
        return parsedNumbers
    }
}
