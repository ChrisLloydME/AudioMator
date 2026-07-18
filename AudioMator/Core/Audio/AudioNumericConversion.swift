import Foundation

enum AudioNumericConversion {
    nonisolated static func roundedInt(
        _ value: Double,
        rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded(rule))
    }

    nonisolated static func positiveDurationMilliseconds(_ seconds: Double) -> Int? {
        guard seconds > 0 else { return nil }
        return roundedInt(seconds * 1_000)
    }

    nonisolated static func positiveDurationSeconds(_ seconds: Double) -> Int? {
        guard seconds > 0 else { return nil }
        return roundedInt(seconds)
    }
}
