import Foundation

/// Device/inode evidence for one filesystem entry, captured once while the
/// candidate is prepared off the main actor.
///
/// A later full read compares its observed fingerprint against this evidence so
/// a symlink retarget or a replaced parent entry is declined instead of being
/// published as the selected file.
nonisolated struct QuickImportEntryIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64

    nonisolated init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Evidence for the lexical parent directory of one Quick Import candidate.
///
/// Sharing one value between files in the same directory is what keeps parent
/// path-key work constant instead of per candidate.
nonisolated struct QuickImportParentEvidence: Hashable, Sendable {
    let parentURL: URL
    let parentKey: String
    let parentCanonicalPath: String
    let parentIsCaseSensitive: Bool
    let parentIdentity: QuickImportEntryIdentity?

    nonisolated init(
        parentURL: URL,
        parentKey: String,
        parentCanonicalPath: String,
        parentIsCaseSensitive: Bool,
        parentIdentity: QuickImportEntryIdentity?
    ) {
        self.parentURL = parentURL
        self.parentKey = parentKey
        self.parentCanonicalPath = parentCanonicalPath
        self.parentIsCaseSensitive = parentIsCaseSensitive
        self.parentIdentity = parentIdentity
    }
}

/// Immutable identity of one import candidate.
///
/// The operational URL is the exact lexical URL the user selected; it is never
/// replaced by the canonical URL. The canonical path and device/inode evidence
/// are verification inputs only and never grant write authority.
nonisolated struct QuickImportPathIdentity: Hashable, Sendable {
    let operationalURL: URL
    let canonicalPath: String
    let fileKey: String
    /// Rename-journal location identity derived from the captured parent
    /// evidence; no additional filesystem work is performed for it.
    let directoryEntryKey: String
    let parentEvidence: QuickImportParentEvidence
    let fileIdentity: QuickImportEntryIdentity?

    nonisolated init(
        operationalURL: URL,
        canonicalPath: String,
        fileKey: String,
        directoryEntryKey: String,
        parentEvidence: QuickImportParentEvidence,
        fileIdentity: QuickImportEntryIdentity?
    ) {
        self.operationalURL = operationalURL
        self.canonicalPath = canonicalPath
        self.fileKey = fileKey
        self.directoryEntryKey = directoryEntryKey
        self.parentEvidence = parentEvidence
        self.fileIdentity = fileIdentity
    }

    nonisolated var parentURL: URL { parentEvidence.parentURL }
    nonisolated var parentKey: String { parentEvidence.parentKey }
    nonisolated var parentIdentity: QuickImportEntryIdentity? { parentEvidence.parentIdentity }

    /// Journal reservation keys for this already-resolved location.
    nonisolated var reservationKeys: Set<String> {
        [fileKey, directoryEntryKey]
    }
}

/// One loaded Quick Import membership: the stable row ID plus the identity and
/// replacement token it was published with.
nonisolated struct QuickImportMembershipRecord: Hashable, Sendable {
    let id: UUID
    let identity: QuickImportPathIdentity
    let requestToken: UUID

    nonisolated init(id: UUID, identity: QuickImportPathIdentity, requestToken: UUID) {
        self.id = id
        self.identity = identity
        self.requestToken = requestToken
    }
}

/// The one-row change produced by an index mutation.
nonisolated enum QuickImportIndexChange: Hashable, Sendable {
    case inserted(id: UUID, at: Int)
    case replaced(id: UUID, at: Int)
    case removed(id: UUID, at: Int)

    nonisolated var id: UUID {
        switch self {
        case .inserted(let id, _), .replaced(let id, _), .removed(let id, _):
            return id
        }
    }

    nonisolated var position: Int {
        switch self {
        case .inserted(_, let position), .replaced(_, let position), .removed(_, let position):
            return position
        }
    }
}

/// Result of one index mutation, including the row it replaced so the caller can
/// release that row's leases without resolving its old path again.
nonisolated struct QuickImportIndexMutation: Sendable {
    let change: QuickImportIndexChange
    let previousRecord: QuickImportMembershipRecord?
}

/// Ordered-ID index for Quick Import memberships.
///
/// This is the bookkeeping source of truth: `orderedIDs` is the published row
/// order, `idByFileKey` maps a canonical file key to its stable row, and the file
/// and parent reference counts drive exactly-once scope leases. Mutations are
/// O(1) dictionary work plus one linear position lookup; no filesystem work is
/// performed here.
nonisolated struct QuickImportPathIndex: Sendable {
    private(set) var orderedIDs: [UUID] = []
    private(set) var recordsByID: [UUID: QuickImportMembershipRecord] = [:]
    private(set) var idByFileKey: [String: UUID] = [:]
    private(set) var fileKeyRefCounts: [String: Int] = [:]
    private(set) var parentKeyRefCounts: [String: Int] = [:]

    nonisolated init() {}

    nonisolated var count: Int { orderedIDs.count }

    nonisolated func record(forID id: UUID) -> QuickImportMembershipRecord? {
        recordsByID[id]
    }

    nonisolated func id(forFileKey fileKey: String) -> UUID? {
        idByFileKey[fileKey]
    }

    nonisolated func record(forFileKey fileKey: String) -> QuickImportMembershipRecord? {
        idByFileKey[fileKey].flatMap { recordsByID[$0] }
    }

    /// Immutable identity snapshot keyed by membership row ID.
    nonisolated func membershipIdentitiesByID() -> [UUID: QuickImportPathIdentity] {
        var identities: [UUID: QuickImportPathIdentity] = [:]
        identities.reserveCapacity(orderedIDs.count)
        for id in orderedIDs {
            if let record = recordsByID[id] {
                identities[id] = record.identity
            }
        }
        return identities
    }

    nonisolated func fileKeyRefCount(_ fileKey: String) -> Int {
        fileKeyRefCounts[fileKey] ?? 0
    }

    nonisolated func parentKeyRefCount(_ parentKey: String) -> Int {
        parentKeyRefCounts[parentKey] ?? 0
    }

    /// Inserts a new membership or replaces the payload for its file key in
    /// place. Replacement keeps the original row position; a key that currently
    /// belongs to another ID is re-pointed at the replacement in the same slot.
    nonisolated mutating func insertOrReplace(
        _ record: QuickImportMembershipRecord
    ) -> QuickImportIndexMutation {
        if let existingID = idByFileKey[record.identity.fileKey],
           let position = orderedIDs.firstIndex(of: existingID) {
            let previous = recordsByID[existingID]
            if existingID != record.id {
                recordsByID.removeValue(forKey: existingID)
                orderedIDs[position] = record.id
            }
            recordsByID[record.id] = record
            idByFileKey[record.identity.fileKey] = record.id
            applyRefCountTransition(from: previous?.identity, to: record.identity)
            return QuickImportIndexMutation(
                change: .replaced(id: record.id, at: position),
                previousRecord: previous
            )
        }

        if let position = orderedIDs.firstIndex(of: record.id) {
            // Same stable row ID, new file key (reimport after an observed move).
            let previous = recordsByID[record.id]
            if let previousKey = previous?.identity.fileKey,
               idByFileKey[previousKey] == record.id {
                idByFileKey.removeValue(forKey: previousKey)
            }
            recordsByID[record.id] = record
            idByFileKey[record.identity.fileKey] = record.id
            applyRefCountTransition(from: previous?.identity, to: record.identity)
            return QuickImportIndexMutation(
                change: .replaced(id: record.id, at: position),
                previousRecord: previous
            )
        }

        orderedIDs.append(record.id)
        recordsByID[record.id] = record
        idByFileKey[record.identity.fileKey] = record.id
        applyRefCountTransition(from: nil, to: record.identity)
        return QuickImportIndexMutation(
            change: .inserted(id: record.id, at: orderedIDs.count - 1),
            previousRecord: nil
        )
    }

    /// Removes one membership and compacts the ordered IDs. Returns `nil` when
    /// the ID is not present (no resurrection of a removed row).
    nonisolated mutating func remove(id: UUID) -> QuickImportIndexMutation? {
        guard let position = orderedIDs.firstIndex(of: id),
              let previous = recordsByID.removeValue(forKey: id) else {
            return nil
        }
        orderedIDs.remove(at: position)
        if idByFileKey[previous.identity.fileKey] == id {
            idByFileKey.removeValue(forKey: previous.identity.fileKey)
        }
        applyRefCountTransition(from: previous.identity, to: nil)
        return QuickImportIndexMutation(
            change: .removed(id: id, at: position),
            previousRecord: previous
        )
    }

    /// Moves one membership to a new identity without changing its order.
    nonisolated mutating func migrate(
        id: UUID,
        to identity: QuickImportPathIdentity
    ) -> QuickImportIndexMutation? {
        guard let position = orderedIDs.firstIndex(of: id),
              let previous = recordsByID[id] else {
            return nil
        }
        if idByFileKey[previous.identity.fileKey] == id,
           previous.identity.fileKey != identity.fileKey {
            idByFileKey.removeValue(forKey: previous.identity.fileKey)
        }
        let record = QuickImportMembershipRecord(
            id: id,
            identity: identity,
            requestToken: previous.requestToken
        )
        recordsByID[id] = record
        idByFileKey[identity.fileKey] = id
        applyRefCountTransition(from: previous.identity, to: identity)
        return QuickImportIndexMutation(
            change: .replaced(id: id, at: position),
            previousRecord: previous
        )
    }

    /// Replaces the published token for one membership (rename/reimport token
    /// rotation) without touching its keys or order.
    nonisolated mutating func updateRequestToken(id: UUID, token: UUID) {
        guard let record = recordsByID[id] else { return }
        recordsByID[id] = QuickImportMembershipRecord(
            id: record.id,
            identity: record.identity,
            requestToken: token
        )
    }

    nonisolated mutating func removeAll() {
        orderedIDs.removeAll()
        recordsByID.removeAll()
        idByFileKey.removeAll()
        fileKeyRefCounts.removeAll()
        parentKeyRefCounts.removeAll()
    }

    private nonisolated mutating func applyRefCountTransition(
        from previous: QuickImportPathIdentity?,
        to next: QuickImportPathIdentity?
    ) {
        if let previous {
            decrement(previous.fileKey, in: &fileKeyRefCounts)
            decrement(previous.parentKey, in: &parentKeyRefCounts)
        }
        if let next {
            increment(next.fileKey, in: &fileKeyRefCounts)
            increment(next.parentKey, in: &parentKeyRefCounts)
        }
    }

    private nonisolated func increment(_ key: String, in counts: inout [String: Int]) {
        counts[key, default: 0] += 1
    }

    private nonisolated func decrement(_ key: String, in counts: inout [String: Int]) {
        let remaining = (counts[key] ?? 0) - 1
        if remaining <= 0 {
            counts.removeValue(forKey: key)
        } else {
            counts[key] = remaining
        }
    }

    /// Test/debug seam: verifies the published order, record map and refcounts
    /// all describe the same memberships. Returns a list of inconsistencies.
    nonisolated func consistencyIssues() -> [String] {
        var issues: [String] = []
        if orderedIDs.count != recordsByID.count {
            issues.append("order count \(orderedIDs.count) != record count \(recordsByID.count)")
        }
        if Set(orderedIDs).count != orderedIDs.count {
            issues.append("duplicate IDs in orderedIDs")
        }
        for id in orderedIDs where recordsByID[id] == nil {
            issues.append("ordered ID \(id) has no record")
        }
        for (id, record) in recordsByID {
            if idByFileKey[record.identity.fileKey] != id {
                issues.append("file key \(record.identity.fileKey) does not map to \(id)")
            }
        }
        var expectedFileKeyCounts: [String: Int] = [:]
        var expectedParentKeyCounts: [String: Int] = [:]
        for record in recordsByID.values {
            expectedFileKeyCounts[record.identity.fileKey, default: 0] += 1
            expectedParentKeyCounts[record.identity.parentKey, default: 0] += 1
        }
        if expectedFileKeyCounts != fileKeyRefCounts {
            issues.append("file key refcounts \(fileKeyRefCounts) != expected \(expectedFileKeyCounts)")
        }
        if expectedParentKeyCounts != parentKeyRefCounts {
            issues.append("parent key refcounts \(parentKeyRefCounts) != expected \(expectedParentKeyCounts)")
        }
        return issues
    }
}

/// Produces one candidate identity per selected URL, off the main actor.
///
/// Implementations must perform exactly one file and one parent identity
/// computation per candidate; callers pass the parent evidence of a previously
/// prepared sibling so a directory is resolved once.
nonisolated protocol QuickImportPathIdentityProviding: Sendable {
    nonisolated func prepareIdentity(
        forFileURL url: URL,
        parent: QuickImportParentEvidence?
    ) -> QuickImportPathIdentity
}

/// Production provider: one canonical resolution and one volume-semantics query
/// for the file and for its lexical parent, plus two entry-identity captures
/// derived from the same canonical URLs. No comparison key is computed twice.
nonisolated struct FileSystemQuickImportPathIdentityProvider: QuickImportPathIdentityProviding {
    nonisolated init() {}

    nonisolated func prepareIdentity(
        forFileURL url: URL,
        parent: QuickImportParentEvidence?
    ) -> QuickImportPathIdentity {
        let standardizedURL = url.standardizedFileURL
        let fileResolution = FileSystemPathSemantics.identityResolution(for: standardizedURL)
        let parentEvidence = parent ?? prepareParentEvidence(forStandardizedFileURL: standardizedURL)
        let directoryEntryKey = FileSystemPathSemantics.directoryEntryKey(
            lexicalBasename: standardizedURL.lastPathComponent,
            parentCanonicalPath: parentEvidence.parentCanonicalPath,
            parentIsCaseSensitive: parentEvidence.parentIsCaseSensitive
        )
        return QuickImportPathIdentity(
            operationalURL: standardizedURL,
            canonicalPath: fileResolution.canonicalPath.precomposedStringWithCanonicalMapping,
            fileKey: fileResolution.key,
            directoryEntryKey: directoryEntryKey,
            parentEvidence: parentEvidence,
            fileIdentity: Self.entryIdentity(at: fileResolution.canonicalURL)
        )
    }

    /// Resolves the lexical parent directory once. Exposed so a caller can prepare
    /// the shared parent evidence before iterating siblings.
    nonisolated func prepareParentEvidence(forFileURL url: URL) -> QuickImportParentEvidence {
        prepareParentEvidence(forStandardizedFileURL: url.standardizedFileURL)
    }

    private nonisolated func prepareParentEvidence(
        forStandardizedFileURL url: URL
    ) -> QuickImportParentEvidence {
        let parentURL = url.deletingLastPathComponent()
        let resolution = FileSystemPathSemantics.identityResolution(for: parentURL)
        return QuickImportParentEvidence(
            parentURL: parentURL,
            parentKey: resolution.key,
            parentCanonicalPath: resolution.canonicalPath.precomposedStringWithCanonicalMapping,
            parentIsCaseSensitive: resolution.isCaseSensitive,
            parentIdentity: Self.entryIdentity(at: resolution.canonicalURL)
        )
    }

    private nonisolated static func entryIdentity(
        at canonicalURL: URL
    ) -> QuickImportEntryIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: canonicalURL.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            return nil
        }
        return QuickImportEntryIdentity(device: device, inode: inode)
    }
}

/// Batch cadence for the progressive Quick Import loader.
///
/// Tests inject the forced policies so batch counts are deterministic; production
/// keeps the shipped values.
nonisolated struct QuickImportLoadPolicy: Sendable, Equatable {
    let partialBatchSize: Int
    let forceFlushBatchSize: Int
    let minimumFlushInterval: TimeInterval

    nonisolated init(
        partialBatchSize: Int,
        forceFlushBatchSize: Int,
        minimumFlushInterval: TimeInterval
    ) {
        self.partialBatchSize = partialBatchSize
        self.forceFlushBatchSize = forceFlushBatchSize
        self.minimumFlushInterval = minimumFlushInterval
    }

    nonisolated static let production = QuickImportLoadPolicy(
        partialBatchSize: 24,
        forceFlushBatchSize: 48,
        minimumFlushInterval: 0.2
    )

    nonisolated static let forced24 = QuickImportLoadPolicy(
        partialBatchSize: 24,
        forceFlushBatchSize: 24,
        minimumFlushInterval: 0
    )

    nonisolated static let forced48 = QuickImportLoadPolicy(
        partialBatchSize: 48,
        forceFlushBatchSize: 48,
        minimumFlushInterval: 0
    )

    /// A forced policy flushes only at its fixed size. Setting the partial size
    /// equal to the force size keeps batch counts independent of loader timing;
    /// production keeps the smaller partial cadence for first-row latency.
}
