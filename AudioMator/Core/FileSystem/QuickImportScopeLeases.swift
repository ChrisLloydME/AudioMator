import Foundation

/// One security-scoped access operation for one URL.
///
/// The production adapter calls the bookmark scope APIs; tests inject a scripted
/// adapter so grant/not-required/revocation transitions can be asserted without a
/// signed sandboxed app.
nonisolated protocol QuickImportScopeAccessing: Sendable {
    nonisolated func startAccessingScope(for url: URL) -> Bool
    nonisolated func stopAccessingScope(for url: URL)
}

/// Production implementation. `startAccessingSecurityScopedResource` returning
/// `false` is ambiguous (no scope required vs. failure); the lease manager keeps
/// that state distinct from a revoked previously-granted scope.
nonisolated struct SystemQuickImportScopeAccess: QuickImportScopeAccessing {
    nonisolated init() {}

    nonisolated func startAccessingScope(for url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    nonisolated func stopAccessingScope(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

/// Who is keeping one scope alive. A key grants access once for the first owner;
/// later owners only join the owner set. Removal releases only that owner.
nonisolated enum QuickImportScopeOwner: Hashable, Sendable {
    /// One `importQuickFiles` request. Holds file scopes for candidates whose
    /// reads are still in flight and parent scopes until the request terminates.
    case job(UUID)
    /// One published Quick Import row.
    case membership(UUID)
}

nonisolated enum QuickImportScopeLeaseState: Equatable, Sendable {
    case granted(url: URL)
    /// The first start attempt reported no scope required (or was refused) and
    /// has not been retried. Passive batch sync never retries this state.
    case notRequired(url: URL)
    /// The scope was granted before and a later start attempt failed (unmounted
    /// volume, provider teardown, revoked authorization). Retried only at an
    /// explicit authorization event.
    case revoked(url: URL)

    nonisolated var url: URL {
        switch self {
        case .granted(let url), .notRequired(let url), .revoked(let url):
            return url
        }
    }
}

/// Refcounted security-scope leases for Quick Import file and parent keys.
///
/// Owned by the main actor through `AudioViewModel` bookkeeping. The internal lock
/// exists only so process teardown (`deinit`) and test adapters can release scopes
/// without an isolation hand-off; every production mutation is on the main actor.
///
/// Invariants:
/// - `startAccessingScope` runs at most once per continuous lease on a key.
/// - Every granted start is stopped exactly once, on the last owner's release.
/// - `.notRequired` never stops and is never retried by passive batch sync.
/// - `.revoked` is retried only when the caller passes a newer explicit
///   authorization epoch.
nonisolated final class QuickImportScopeLeases: @unchecked Sendable {
    nonisolated struct Metrics: Equatable, Sendable {
        var startCount = 0
        var stopCount = 0
        var grantedCount = 0
        var notRequiredCount = 0
        var revokedCount = 0
        /// Start attempts suppressed because the key was already known not to
        /// require a scope. Passive batch sync must never call the adapter again.
        var suppressedStartAttempts = 0
        var authorizationRetryCount = 0
        var liveLeaseCount = 0
        /// A live grant was carried from an unshared source key to an unshared
        /// destination key without a second start.
        var transferCount = 0
        /// A duplicated live grant was stopped once when the destination key
        /// already held its own live grant (key-safe de-duplication).
        var dedupedGrantTransferStopCount = 0
        /// An outstanding source grant was stopped once because the destination
        /// key's own evidence says it does not need a scope.
        var unusedGrantStopCount = 0
    }

    private nonisolated struct Entry {
        var state: QuickImportScopeLeaseState
        var owners: Set<QuickImportScopeOwner>
        /// Authorization epoch at which the current non-granted state was
        /// recorded; `nil` for a live granted lease.
        var failedAtEpoch: UInt64?
        /// The lease was granted at least once. A later failed start is `.revoked`
        /// rather than `.notRequired`.
        var wasGranted = false

        nonisolated var isLiveGranted: Bool {
            if case .granted = state { return !owners.isEmpty }
            return false
        }
    }

    private let lock = NSLock()
    private let access: any QuickImportScopeAccessing
    private var entries: [String: Entry] = [:]
    private var metrics = Metrics()
    private var authorizationEpoch: UInt64 = 0

    nonisolated init(access: any QuickImportScopeAccessing) {
        self.access = access
    }

    /// Records an explicit authorization event (new user import request or
    /// relaunch). Returns the new epoch for callers that pass it to `acquire`.
    @discardableResult
    nonisolated func beginAuthorizationEpoch() -> UInt64 {
        lock.withLock {
            authorizationEpoch &+= 1
            return authorizationEpoch
        }
    }

    nonisolated var currentAuthorizationEpoch: UInt64 {
        lock.withLock { authorizationEpoch }
    }

    /// Acquires the lease for `key`. The first owner of a stopped key starts the
    /// scope; later owners only join while it is live. Passing an authorization
    /// epoch newer than the epoch that recorded a failed state permits one retry
    /// (an explicit user import, never passive batch sync).
    @discardableResult
    nonisolated func acquire(
        url: URL,
        key: String,
        owner: QuickImportScopeOwner,
        authorizationEpoch: UInt64? = nil
    ) -> QuickImportScopeLeaseState {
        lock.withLock {
            acquireLocked(
                url: url,
                key: key,
                owner: owner,
                authorizationEpoch: authorizationEpoch
            )
        }
    }

    /// Acquisition body; callers must already hold `lock`.
    private nonisolated func acquireLocked(
        url: URL,
        key: String,
        owner: QuickImportScopeOwner,
        authorizationEpoch: UInt64?
    ) -> QuickImportScopeLeaseState {
        if var entry = entries[key] {
            // Idempotent per owner: a repeated acquire (for example the same
            // import job readying a shared parent directory for each sibling)
            // must neither start the scope again nor count as a failed retry.
            if entry.owners.contains(owner) {
                entries[key] = entry
                refreshLiveLeaseCountLocked()
                return entry.state
            }
            entry.owners.insert(owner)
            switch entry.state {
            case .granted:
                if entry.owners.count > 1 {
                    entries[key] = entry
                    refreshLiveLeaseCountLocked()
                    return entry.state
                }
                // The previous owners all released, so this is a fresh lease
                // on a key that granted access before. Start it again.
                metrics.startCount += 1
                if access.startAccessingScope(for: url) {
                    metrics.grantedCount += 1
                    entry.state = .granted(url: url)
                    entry.failedAtEpoch = nil
                    entry.wasGranted = true
                } else {
                    metrics.revokedCount += 1
                    entry.state = .revoked(url: url)
                    entry.failedAtEpoch = authorizationEpoch ?? currentEpochLocked
                }
                entries[key] = entry
                refreshLiveLeaseCountLocked()
                return entry.state

            case .notRequired, .revoked:
                let mayRetry = authorizationEpoch.map { epoch in
                    guard let failedAtEpoch = entry.failedAtEpoch else { return false }
                    return epoch > failedAtEpoch
                } ?? false
                guard mayRetry else {
                    metrics.suppressedStartAttempts += 1
                    entries[key] = entry
                    refreshLiveLeaseCountLocked()
                    return entry.state
                }
                metrics.authorizationRetryCount += 1
                metrics.startCount += 1
                if access.startAccessingScope(for: url) {
                    metrics.grantedCount += 1
                    entry.state = .granted(url: url)
                    entry.failedAtEpoch = nil
                    entry.wasGranted = true
                } else if entry.wasGranted {
                    metrics.revokedCount += 1
                    entry.state = .revoked(url: url)
                    entry.failedAtEpoch = authorizationEpoch ?? currentEpochLocked
                } else {
                    entry.failedAtEpoch = authorizationEpoch ?? currentEpochLocked
                }
                entries[key] = entry
                refreshLiveLeaseCountLocked()
                return entry.state
            }
        }

        metrics.startCount += 1
        if access.startAccessingScope(for: url) {
            metrics.grantedCount += 1
            entries[key] = Entry(
                state: .granted(url: url),
                owners: [owner],
                failedAtEpoch: nil,
                wasGranted: true
            )
        } else {
            metrics.notRequiredCount += 1
            entries[key] = Entry(
                state: .notRequired(url: url),
                owners: [owner],
                failedAtEpoch: authorizationEpoch ?? currentEpochLocked,
                wasGranted: false
            )
        }
        refreshLiveLeaseCountLocked()
        return entries[key]?.state ?? .notRequired(url: url)
    }

    /// Migrates one owner's lease from an old key (a source path) to a new key
    /// (a destination path) without fabricating destination authority.
    ///
    /// Grant ownership is key-safe: one `startAccessingScope` call may back only
    /// one live granted entry. The grant moves with the owner only when the
    /// moving owner was the last owner of the old key and the destination does
    /// not already hold its own grant. If the old key still has owners the grant
    /// stays with them and the destination is acquired through the ordinary
    /// start/retry rules. If both keys hold live grants the redundant source
    /// grant is stopped exactly once.
    nonisolated func migrateKey(
        from oldKey: String,
        to newKey: String,
        url: URL,
        owner: QuickImportScopeOwner
    ) {
        if oldKey == newKey {
            lock.withLock {
                guard var entry = entries[oldKey] else { return }
                entry.state = Self.stateKeepingGrant(entry.state, url: url)
                entries[oldKey] = entry
            }
            return
        }

        lock.withLock {
            guard let oldEntryBefore = entries[oldKey],
                  oldEntryBefore.owners.contains(owner) else {
                // Idempotent repeat: the owner may already hold the destination.
                if var destination = entries[newKey], destination.owners.contains(owner) {
                    destination.state = Self.stateKeepingGrant(destination.state, url: url)
                    entries[newKey] = destination
                }
                return
            }

            let movingState = oldEntryBefore.state
            let movingIsGranted: Bool
            if case .granted = movingState { movingIsGranted = true } else { movingIsGranted = false }
            let movingWasGranted = oldEntryBefore.wasGranted
            let movingFailedAtEpoch = oldEntryBefore.failedAtEpoch

            var oldEntry = oldEntryBefore
            oldEntry.owners.remove(owner)
            let oldKeyStillOwned = !oldEntry.owners.isEmpty
            if oldKeyStillOwned {
                entries[oldKey] = oldEntry
            } else {
                entries.removeValue(forKey: oldKey)
            }

            if movingIsGranted && oldKeyStillOwned {
                // The single old grant must stay with its remaining owners. The
                // moved owner acquires the destination for real (start attempt
                // follows the normal authorized-retry rules; no copied grant).
                _ = acquireLocked(
                    url: url,
                    key: newKey,
                    owner: owner,
                    authorizationEpoch: nil
                )
                refreshLiveLeaseCountLocked()
                return
            }

            // At this point a granted moving state means the old key had exactly
            // this owner, so the grant obligation travels with the owner.
            let movingGrantOutstanding = movingIsGranted
            let destination = entries[newKey]
            let destinationIsLiveGranted = destination?.isLiveGranted ?? false

            if movingGrantOutstanding, destinationIsLiveGranted {
                // The destination holds its own start; a copied grant would plan
                // a second stop for one start, so stop the redundant source start
                // exactly once instead of duplicating it.
                access.stopAccessingScope(for: movingState.url)
                metrics.stopCount += 1
                metrics.dedupedGrantTransferStopCount += 1
            }

            if let destinationBefore = destination {
                if movingGrantOutstanding {
                    var destination = destinationBefore
                    switch destination.state {
                    case .granted:
                        if !destinationIsLiveGranted {
                            // Destination previously granted and stopped: carry the
                            // outstanding grant (and its single stop) to this key.
                            destination.state = .granted(url: movingState.url)
                            destination.wasGranted = true
                            destination.failedAtEpoch = nil
                            metrics.transferCount += 1
                        }
                    case .notRequired, .revoked:
                        // The destination's own evidence says it does not need a
                        // usable scope. Keep that evidence and stop the now
                        // ownerless source grant exactly once so no stop leaks.
                        access.stopAccessingScope(for: movingState.url)
                        metrics.stopCount += 1
                        metrics.unusedGrantStopCount += 1
                    }
                    destination.owners.insert(owner)
                    entries[newKey] = destination
                } else if destinationIsLiveGranted {
                    // The destination grant is genuinely live (started by another
                    // owner): join it without touching its stop obligation.
                    var destination = destinationBefore
                    destination.owners.insert(owner)
                    entries[newKey] = destination
                } else if case .granted = destinationBefore.state {
                    // A retained-but-stopped `.granted` entry already balanced its
                    // single start with a stop. Resurrecting it as a live lease
                    // would fabricate a grant and plan a second stop, so acquire a
                    // real destination start (or record its authorized failure).
                    _ = acquireLocked(
                        url: url,
                        key: newKey,
                        owner: owner,
                        authorizationEpoch: nil
                    )
                } else if !destinationBefore.wasGranted {
                    var destination = destinationBefore
                    destination.state = Self.stateKeepingGrant(movingState, url: url)
                    destination.failedAtEpoch = movingFailedAtEpoch
                    destination.wasGranted = movingWasGranted
                    destination.owners.insert(owner)
                    entries[newKey] = destination
                } else {
                    // Destination owns revoked/notRequired evidence; keep it.
                    var destination = destinationBefore
                    destination.owners.insert(owner)
                    entries[newKey] = destination
                }
            } else {
                entries[newKey] = Entry(
                    state: Self.stateKeepingGrant(movingState, url: url),
                    owners: [owner],
                    failedAtEpoch: movingFailedAtEpoch,
                    wasGranted: movingWasGranted
                )
                if movingGrantOutstanding {
                    metrics.transferCount += 1
                }
            }
            refreshLiveLeaseCountLocked()
        }
    }

    /// Releases one owner for one key, stopping the scope only when the last owner
    /// leaves and the lease is actually granted.
    nonisolated func release(key: String, owner: QuickImportScopeOwner) {
        lock.withLock {
            guard var entry = entries[key], entry.owners.remove(owner) != nil else { return }
            if entry.owners.isEmpty, case .granted(let url) = entry.state {
                access.stopAccessingScope(for: url)
                metrics.stopCount += 1
            }
            entries[key] = entry
            refreshLiveLeaseCountLocked()
        }
    }

    /// Releases every key held by one owner. Exactly-once per job terminal.
    nonisolated func release(owner: QuickImportScopeOwner) {
        lock.withLock {
            for key in Array(entries.keys) {
                guard var entry = entries[key], entry.owners.remove(owner) != nil else { continue }
                if entry.owners.isEmpty, case .granted(let url) = entry.state {
                    access.stopAccessingScope(for: url)
                    metrics.stopCount += 1
                }
                entries[key] = entry
            }
            refreshLiveLeaseCountLocked()
        }
    }

    /// Stops every live granted lease. Used by `deinit` and by Clear Quick Import.
    nonisolated func releaseAll() {
        lock.withLock {
            for key in Array(entries.keys) {
                guard var entry = entries[key] else { continue }
                if case .granted(let url) = entry.state, !entry.owners.isEmpty {
                    access.stopAccessingScope(for: url)
                    metrics.stopCount += 1
                }
                entry.owners.removeAll()
                entries[key] = entry
            }
            refreshLiveLeaseCountLocked()
        }
    }

    nonisolated func isLiveGranted(forKey key: String) -> Bool {
        lock.withLock { entries[key]?.isLiveGranted ?? false }
    }

    nonisolated func state(forKey key: String) -> QuickImportScopeLeaseState? {
        lock.withLock { entries[key]?.state }
    }

    nonisolated func owners(forKey key: String) -> Set<QuickImportScopeOwner> {
        lock.withLock { entries[key]?.owners ?? [] }
    }

    nonisolated func keys(forOwner owner: QuickImportScopeOwner) -> Set<String> {
        lock.withLock {
            Set(entries.compactMap { key, entry in
                entry.owners.contains(owner) ? key : nil
            })
        }
    }

    nonisolated func liveGrantedURLs() -> [URL] {
        lock.withLock {
            entries.values.compactMap { entry in
                guard entry.isLiveGranted, case .granted(let url) = entry.state else { return nil }
                return url
            }
        }
    }

    nonisolated func leaseSnapshot() -> [String: (state: QuickImportScopeLeaseState, owners: Set<QuickImportScopeOwner>)] {
        lock.withLock {
            entries.mapValues { (state: $0.state, owners: $0.owners) }
        }
    }

    nonisolated func metricsSnapshot() -> Metrics {
        lock.withLock { metrics }
    }

    private nonisolated var currentEpochLocked: UInt64 { authorizationEpoch }

    private nonisolated static func stateKeepingGrant(
        _ state: QuickImportScopeLeaseState,
        url: URL
    ) -> QuickImportScopeLeaseState {
        switch state {
        case .granted:
            // Keep the URL that actually started the scope: it is the exact URL
            // the later stop must balance.
            return state
        case .notRequired:
            return .notRequired(url: url)
        case .revoked:
            return .revoked(url: url)
        }
    }

    private nonisolated func refreshLiveLeaseCountLocked() {
        metrics.liveLeaseCount = entries.values.reduce(into: 0) { count, entry in
            if entry.isLiveGranted { count += 1 }
        }
    }
}
