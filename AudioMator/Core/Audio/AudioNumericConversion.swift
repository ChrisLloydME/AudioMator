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

    nonisolated static func boundedDistance(
        _ lhs: Int,
        _ rhs: Int,
        maximum: Int
    ) -> Int? {
        guard maximum >= 0 else { return nil }
        let (difference, overflowed) = lhs.subtractingReportingOverflow(rhs)
        guard !overflowed, difference != .min else { return nil }

        let distance = abs(difference)
        return distance <= maximum ? distance : nil
    }

    nonisolated static func saturatingNonnegativeSum(_ lhs: Int, _ rhs: Int) -> Int {
        let safeLHS = max(0, lhs)
        let safeRHS = max(0, rhs)
        let (sum, overflowed) = safeLHS.addingReportingOverflow(safeRHS)
        return overflowed ? .max : sum
    }
}
