import Foundation

enum TrackRenumberDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
}

struct TrackRenumberOptions: Equatable {
    var direction: TrackRenumberDirection = .ascending
    var startNumber: Int = 1
    var padWithZeros: Bool = true
}

let maximumTrackRenumberStartNumber = 9_999

func normalizedTrackRenumberStartNumber(_ value: Int) -> Int {
    min(max(value, 0), maximumTrackRenumberStartNumber)
}

func trackRenumberPadWidth(maxNumber: Int, padWithZeros: Bool) -> Int {
    guard padWithZeros else { return 0 }
    return max(2, String(maxNumber.magnitude).count)
}

struct TrackRenumberFailure: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let reason: String
}

struct TrackRenumberWarning: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let messages: [String]
}

struct TrackRenumberResult: Equatable {
    var totalTargets: Int
    var succeeded: Int
    var skippedUnsupported: Int
    var failed: Int
    var failures: [TrackRenumberFailure]
    var warnings: [TrackRenumberWarning]

    static let empty = TrackRenumberResult(
        totalTargets: 0,
        succeeded: 0,
        skippedUnsupported: 0,
        failed: 0,
        failures: [],
        warnings: []
    )
}
