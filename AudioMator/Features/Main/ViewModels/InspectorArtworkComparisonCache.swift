import Foundation

/// Memoizes exact comparisons between immutable snapshots while a user extends
/// or revisits a multi-selection. Never substitutes a sampled image fingerprint.
@MainActor
final class InspectorArtworkComparisonCache {
    private struct Pair: Hashable {
        let first: UUID
        let other: UUID
    }

    private var results: [Pair: Bool] = [:]
    private var evictionOrder: [Pair] = []
    private var evictionIndex = 0
    private let capacity = 2_048
    private let areEqual: (Data, Data) -> Bool

    init(areEqual: @escaping (Data, Data) -> Bool = { $0 == $1 }) {
        self.areEqual = areEqual
    }

    func resolve(_ files: [AudioFile]) -> MultiFileArtworkState {
        guard let first = files.first else { return .none }
        guard let data = first.artworkData else {
            return files.allSatisfy { $0.artworkData == nil } ? .none : .mixed
        }
        for other in files.dropFirst() {
            guard let otherData = other.artworkData else { return .mixed }
            let pair = Pair(first: first.snapshotID, other: other.snapshotID)
            let equal: Bool
            if let cached = results[pair] {
                equal = cached
            } else {
                equal = areEqual(data, otherData)
                if evictionOrder.count == capacity {
                    results.removeValue(forKey: evictionOrder[evictionIndex])
                    evictionOrder[evictionIndex] = pair
                    evictionIndex = (evictionIndex + 1) % capacity
                } else {
                    evictionOrder.append(pair)
                }
                results[pair] = equal
            }
            guard equal else { return .mixed }
        }
        return .shared(data)
    }
}
