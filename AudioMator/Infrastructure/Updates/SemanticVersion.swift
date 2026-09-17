import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable {
    let numbers: [Int]

    nonisolated init?(_ rawValue: String) {
        guard let parsedNumbers = Self.parseVersionCore(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.numbers = parsedNumbers
    }

    nonisolated static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    nonisolated static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
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

    nonisolated private static func parseVersionCore(_ rawValue: String) -> [Int]? {
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

struct ReleaseVersion: Comparable, Equatable, Sendable {
    let marketingVersion: SemanticVersion
    let buildNumber: Int

    nonisolated init?(marketingVersion: String, buildNumber: String) {
        let normalizedBuild = buildNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marketingVersion = SemanticVersion(marketingVersion),
              !normalizedBuild.isEmpty,
              normalizedBuild.allSatisfy(\.isNumber),
              let parsedBuildNumber = Int(normalizedBuild)
        else {
            return nil
        }

        self.marketingVersion = marketingVersion
        self.buildNumber = parsedBuildNumber
    }

    nonisolated init?(releaseTag rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("V"),
              let buildSeparator = normalized.firstIndex(of: "B")
        else {
            return nil
        }

        let marketingVersion = String(normalized[normalized.index(after: normalized.startIndex)..<buildSeparator])
        let buildNumber = String(normalized[normalized.index(after: buildSeparator)...])
        self.init(marketingVersion: marketingVersion, buildNumber: buildNumber)
    }

    nonisolated static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.marketingVersion != rhs.marketingVersion {
            return lhs.marketingVersion < rhs.marketingVersion
        }
        return lhs.buildNumber < rhs.buildNumber
    }
}
