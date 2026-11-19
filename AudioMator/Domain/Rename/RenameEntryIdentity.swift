import Foundation

nonisolated enum FileEntryKind: String, Hashable, Sendable {
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
}
