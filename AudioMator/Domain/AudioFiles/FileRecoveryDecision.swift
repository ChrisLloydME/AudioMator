import Foundation

/// Device/inode pair used to decide whether a later read observed the same
/// directory entry. Nil components mean the volume did not report identity, in
/// which case a recovery decision cannot be cleared automatically.
nonisolated struct EntryIdentityKey: Hashable, Sendable {
    let device: UInt64?
    let inode: UInt64?

    nonisolated init(device: UInt64?, inode: UInt64?) {
        self.device = device
        self.inode = inode
    }

    nonisolated init(_ identity: RenameEntryIdentity?) {
        self.device = identity?.device
        self.inode = identity?.inode
    }

    nonisolated init(fingerprint: AudioFileFingerprint?) {
        self.device = fingerprint?.fileSystemNumber
        self.inode = fingerprint?.fileNumber
    }

    /// True when both sides are known and equal. Missing identity never counts as
    /// a match; callers must fall back to explicit review instead.
    nonisolated func matches(_ other: EntryIdentityKey) -> Bool {
        guard let device, let inode, let otherDevice = other.device, let otherInode = other.inode else {
            return false
        }
        return device == otherDevice && inode == otherInode
    }
}

/// One named reason a file's metadata writes are blocked after a move/recovery.
///
/// Decisions outlive individual observations. They are cleared only through a
/// named `FileRecoveryClearance` transition; automatic observations never clear
/// them.
nonisolated enum FileRecoveryDecision: Hashable, Sendable {
    /// A verified move was published; the moved file awaits the matching bounded
    /// full readback. Carries the receipt identity so a later explicit reload can
    /// only clear the decision when it observes the same entry.
    case moveReadbackPending(
        moveID: FileMoveID,
        destinationURL: URL,
        entryIdentity: EntryIdentityKey
    )

    /// Rollback recovery could not establish a single verified location, or the
    /// observed location identity is unknown. An explicit reload can clear it only
    /// with the same entry identity; a successor requires explicit acceptance.
    case recoveryLocationUnresolved(expectedIdentity: EntryIdentityKey?)

    /// Reserved for the F2 rename journal. F1 never sets it; normal reload must
    /// not clear it.
    case journalPending(UUID)
}

/// Named transitions that may clear recovery decisions.
nonisolated enum FileRecoveryClearance: Sendable, Equatable {
    /// The bounded full readback for a specific verified move observed the same
    /// destination entry and produced a coherent observation.
    case receiptMatchedReadback(moveID: FileMoveID)

    /// A user-requested Reload from Disk produced a coherent full observation.
    /// Clears a pending move decision for the same ID/URL/entry and a resolved-path
    /// failure only when the read observed the same entry identity.
    case explicitAuthorizedReload

    /// Reserved for F2: the journal identified a verified location, or the user
    /// explicitly resolved that operation.
    case verifiedJournalLocation(UUID)

    /// The user explicitly reviewed and accepted a different directory entry
    /// occupying the path after Reload from Disk surfaced a replacement.
    /// Clears matching-path `.moveReadbackPending` and `.recoveryLocationUnresolved`
    /// only when the freshly loaded observation matches `url` and
    /// `observedIdentity`. Never clears `.journalPending`.
    case explicitReplacementAcceptance(url: URL, observedIdentity: EntryIdentityKey)
}

/// One replacement file surfaced by an explicit Reload from Disk when a renamed
/// or recovery-paused path now holds a different directory entry.
nonisolated struct PendingReplacementFileReview: Identifiable, Equatable, Sendable {
    let fileID: AudioFile.ID
    let url: URL
    let fileName: String
    let observedIdentity: EntryIdentityKey
    let title: String
    let artist: String
    let album: String

    nonisolated var id: AudioFile.ID { fileID }
}
