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
    // All these immutable snapshots have been compared exactly and share one
    // artwork payload. Retain the current group so selections larger than the
    // pair-cache capacity do not evict and reread every cover on each click.
    private var sharedSnapshotIDs: Set<UUID> = []

    init(areEqual: @escaping (Data, Data) -> Bool = { $0 == $1 }) {
        self.areEqual = areEqual
    }

    func resolve(_ files: [AudioFile]) -> MultiFileArtworkState {
        guard let first = files.first else { return .none }
        guard let data = first.artworkData else {
            return files.allSatisfy { $0.artworkData == nil } ? .none : .mixed
        }
        if !sharedSnapshotIDs.contains(first.snapshotID) {
            sharedSnapshotIDs = [first.snapshotID]
        }
        defer {
            // Allow the ordinary cache budget in addition to the active group,
            // so removing then restoring its first row does not discard proof
            // of equality. Unrelated selections cannot grow this forever.
            if sharedSnapshotIDs.count > capacity + files.count {
                sharedSnapshotIDs.formIntersection(files.map(\.snapshotID))
            }
        }
        for other in files.dropFirst() {
            guard let otherData = other.artworkData else { return .mixed }
            if sharedSnapshotIDs.contains(other.snapshotID) { continue }
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
            sharedSnapshotIDs.insert(other.snapshotID)
        }
        return .shared(data)
    }
}
