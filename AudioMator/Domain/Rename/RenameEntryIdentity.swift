import Foundation

nonisolated enum FileEntryKind: String, Codable, Hashable, Sendable {
    case regular
    case directory
    case symlink
    case other
}

/// Identity of one directory entry at a specific path.
///
/// Unlike `AudioFileFingerprint`, this deliberately does not resolve symlinks and
/// does not include the path. It records what `lstat` reported, so a move can be
/// verified as the same physical entry at its new location.
nonisolated struct RenameEntryIdentity: Hashable, Sendable {
    let device: UInt64?
    let inode: UInt64?
    let kind: FileEntryKind
    let size: UInt64
    let modificationDate: Date
    let creationDate: Date?
    /// Stable volume identifier reported by the volume, when available. `nil`
    /// means the evidence cannot distinguish an entry after a remount and must
    /// not be used for automatic recovery.
    let volumeIdentifier: String?
    /// Exact `readlink` target for a symlink entry. Evidence only; never resolved
    /// to choose a scope or a path.
    let linkTarget: String?

    /// Explicit initializer so the two optional evidence fields stay defaulted for
    /// the many existing call sites that only know the stat fields.
    nonisolated init(
        device: UInt64?,
        inode: UInt64?,
        kind: FileEntryKind,
        size: UInt64,
        modificationDate: Date,
        creationDate: Date?,
        volumeIdentifier: String? = nil,
        linkTarget: String? = nil
    ) {
        self.device = device
        self.inode = inode
        self.kind = kind
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.volumeIdentifier = volumeIdentifier
        self.linkTarget = linkTarget
    }
}
