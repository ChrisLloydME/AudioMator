import Foundation

/// Identifies one per-file commit permit inside an operation.
///
/// The permit map is keyed by the file identity plus the owning operation token so
/// that membership, protection or cancellation invalidation can revoke exactly the
/// permits that are still pending for that file or operation.
nonisolated struct MetadataCommitPermitKey: Hashable, Sendable {
    let fileID: AudioFile.ID
    let operationID: UUID
}

/// MainActor-owned map of pending commit permits.
///
/// The registry itself performs no I/O and no actor work beyond dictionary access;
/// the permits it hands out are independently thread-safe so the detached write
/// worker can admit or observe them without hopping back to the main actor.
/// Registering the same file/operation pair twice returns the existing permit so a
/// retry cannot create a second admission gate for the same write.
@MainActor
final class MetadataCommitPermitRegistry {
    private var permitsByKey: [MetadataCommitPermitKey: MetadataCommitPermit] = [:]
    private var keysByOperationID: [UUID: Set<MetadataCommitPermitKey>] = [:]

    var activePermitCount: Int {
        permitsByKey.count
    }

    /// Registers one file for an operation, returning the existing permit on retry.
    @discardableResult
    func register(fileID: AudioFile.ID, operationID: UUID) -> MetadataCommitPermit {
        let key = MetadataCommitPermitKey(fileID: fileID, operationID: operationID)
        if let existing = permitsByKey[key] {
            return existing
        }
        let permit = MetadataCommitPermit()
        permitsByKey[key] = permit
        keysByOperationID[operationID, default: []].insert(key)
        return permit
    }

    func permit(forFileID fileID: AudioFile.ID, operationID: UUID) -> MetadataCommitPermit? {
        permitsByKey[MetadataCommitPermitKey(fileID: fileID, operationID: operationID)]
    }

    /// Revokes every pending permit for a file, across operations.
    ///
    /// This is the hook for removal from eligible source membership, recovery-state
    /// invalidation, an incompatible observed revision, or a revoked scope. It does
    /// not remove the entries; the owning operation unregisters on exit.
    func revoke(fileID: AudioFile.ID, reason: MetadataCommitPermit.PrecommitRejection) {
        for (key, permit) in permitsByKey where key.fileID == fileID {
            permit.revoke(reason: reason)
        }
    }

    /// Revokes every pending permit for one operation, across files.
    func revoke(operationID: UUID, reason: MetadataCommitPermit.PrecommitRejection) {
        for key in keysByOperationID[operationID] ?? [] {
            permitsByKey[key]?.revoke(reason: reason)
        }
    }

    /// Removes one file/operation entry on that write's exit.
    func unregister(fileID: AudioFile.ID, operationID: UUID) {
        let key = MetadataCommitPermitKey(fileID: fileID, operationID: operationID)
        guard permitsByKey.removeValue(forKey: key) != nil else { return }
        keysByOperationID[operationID]?.remove(key)
        if keysByOperationID[operationID]?.isEmpty == true {
            keysByOperationID.removeValue(forKey: operationID)
        }
    }

    /// Removes every entry for an operation on operation exit.
    func unregister(operationID: UUID) {
        guard let keys = keysByOperationID.removeValue(forKey: operationID) else { return }
        for key in keys {
            permitsByKey.removeValue(forKey: key)
        }
    }

    /// Clears the map on teardown. Callers that need to fail pending writes closed
    /// revoke first, then unregister.
    func removeAll() {
        permitsByKey.removeAll()
        keysByOperationID.removeAll()
    }
}
