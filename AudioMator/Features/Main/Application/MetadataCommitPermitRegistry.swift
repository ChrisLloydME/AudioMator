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
    private struct Entry {
        let permit: MetadataCommitPermit
        /// Present for reviewed writes; used to decide whether a published
        /// observation is compatible with the queued write.
        let target: ReviewedMetadataTarget?
        /// True for conflict-aware Inspector/Raw draft writes, which stay
        /// eligible for policy-driven conflict resolution when only the
        /// observed disk revision changes (same path/ID, no recovery block).
        let allowsChangedRevision: Bool
    }

    private var entriesByKey: [MetadataCommitPermitKey: Entry] = [:]
    private var keysByOperationID: [UUID: Set<MetadataCommitPermitKey>] = [:]

    var activePermitCount: Int {
        entriesByKey.count
    }

    /// Registers one reviewed file for an operation, returning the existing permit
    /// on retry.
    @discardableResult
    func register(
        target: ReviewedMetadataTarget,
        allowsChangedRevision: Bool = false,
        operationID: UUID
    ) -> MetadataCommitPermit {
        register(
            fileID: target.id,
            target: target,
            allowsChangedRevision: allowsChangedRevision,
            operationID: operationID
        )
    }

    /// Registers one file for an operation without a strict target (conflict-aware
    /// drafts or tests that only need admission).
    @discardableResult
    func register(fileID: AudioFile.ID, operationID: UUID) -> MetadataCommitPermit {
        register(
            fileID: fileID,
            target: nil,
            allowsChangedRevision: true,
            operationID: operationID
        )
    }

    private func register(
        fileID: AudioFile.ID,
        target: ReviewedMetadataTarget?,
        allowsChangedRevision: Bool,
        operationID: UUID
    ) -> MetadataCommitPermit {
        let key = MetadataCommitPermitKey(fileID: fileID, operationID: operationID)
        if let existing = entriesByKey[key] {
            return existing.permit
        }
        let permit = MetadataCommitPermit()
        entriesByKey[key] = Entry(
            permit: permit,
            target: target,
            allowsChangedRevision: allowsChangedRevision
        )
        keysByOperationID[operationID, default: []].insert(key)
        return permit
    }

    func permit(forFileID fileID: AudioFile.ID, operationID: UUID) -> MetadataCommitPermit? {
        entriesByKey[MetadataCommitPermitKey(fileID: fileID, operationID: operationID)]?.permit
    }

    /// Revokes every pending permit for a file, across operations.
    ///
    /// This is the hook for removal from eligible source membership, recovery-state
    /// invalidation, an incompatible observed revision, or a revoked scope. It does
    /// not remove the entries; the owning operation unregisters on exit.
    func revoke(fileID: AudioFile.ID, reason: MetadataCommitPermit.PrecommitRejection) {
        for (key, entry) in entriesByKey where key.fileID == fileID {
            entry.permit.revoke(reason: reason)
        }
    }

    func revoke(fileIDs: Set<AudioFile.ID>, reason: MetadataCommitPermit.PrecommitRejection) {
        guard !fileIDs.isEmpty else { return }
        for (key, entry) in entriesByKey where fileIDs.contains(key.fileID) {
            entry.permit.revoke(reason: reason)
        }
    }

    /// Revokes every pending permit for one operation, across files.
    func revoke(operationID: UUID, reason: MetadataCommitPermit.PrecommitRejection) {
        for key in keysByOperationID[operationID] ?? [] {
            entriesByKey[key]?.permit.revoke(reason: reason)
        }
    }

    /// Revokes every pending permit. Used when a shared authorization scope is
    /// revoked; an operation-specific caller should prefer `revoke(operationID:)`.
    func revokeAll(reason: MetadataCommitPermit.PrecommitRejection) {
        for entry in entriesByKey.values {
            entry.permit.revoke(reason: reason)
        }
    }

    /// Revokes permits whose reviewed observation no longer matches a published
    /// observation. Republishing an equal observation (same path, fingerprint and
    /// revision) does not revoke. Conflict-aware draft permits tolerate a coherent
    /// revision-only update at the same path so the conflict resolver can apply
    /// merge/prefer-disk policies, while still revoking on path changes or
    /// recovery-required states.
    func revokeIncompatibleObservation(
        _ file: AudioFile,
        reason: MetadataCommitPermit.PrecommitRejection
    ) {
        for (key, entry) in entriesByKey where key.fileID == file.id {
            guard let target = entry.target else { continue }
            if entry.allowsChangedRevision {
                if !target.associates(with: file) || file.requiresMetadataRefreshBeforeWriting {
                    entry.permit.revoke(reason: reason)
                }
            } else if !target.matches(observation: file) {
                entry.permit.revoke(reason: reason)
            }
        }
    }

    /// Removes one file/operation entry on that write's exit.
    func unregister(fileID: AudioFile.ID, operationID: UUID) {
        let key = MetadataCommitPermitKey(fileID: fileID, operationID: operationID)
        guard entriesByKey.removeValue(forKey: key) != nil else { return }
        keysByOperationID[operationID]?.remove(key)
        if keysByOperationID[operationID]?.isEmpty == true {
            keysByOperationID.removeValue(forKey: operationID)
        }
    }

    /// Removes every entry for an operation on operation exit.
    func unregister(operationID: UUID) {
        guard let keys = keysByOperationID.removeValue(forKey: operationID) else { return }
        for key in keys {
            entriesByKey.removeValue(forKey: key)
        }
    }

    /// Clears the map on teardown. Callers that need to fail pending writes closed
    /// revoke first, then unregister.
    func removeAll() {
        entriesByKey.removeAll()
        keysByOperationID.removeAll()
    }
}
