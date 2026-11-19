import Foundation

/// Identity of one rename transaction move. Unique per file move, so a pending
/// readback decision can only be cleared by the readback for that same move.
nonisolated struct FileMoveID: Hashable, Sendable {
    let rawValue: UUID

    nonisolated init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// A rollback-recovery location whose directory entry identity was observed.
nonisolated struct VerifiedRenameLocation: Sendable, Equatable {
    let url: URL
    let identity: RenameEntryIdentity
}

/// What the rename transaction observed when a move finished successfully.
///
/// The claimed logical ID, the lexical old URL, the actual destination URL and the
/// filesystem entry identity captured at the end of the move travel together. A
/// display model is never allowed to reconstruct this value.
nonisolated struct FileRenameMoveReceipt: Sendable, Equatable {
    let moveID: FileMoveID
    let fileID: AudioFile.ID
    let sourceURL: URL
    let destinationURL: URL
    let entryIdentity: RenameEntryIdentity
}

/// Why a bounded post-move full readback did not restore write authority.
nonisolated enum MoveReadbackFailure: Error, Sendable, Equatable {
    case timedOut
    case readFailed(String)
    case destinationChanged
}

/// Display-only projection for navigation and recovery messaging.
///
/// `displayFile` never carries write authority: `AudioFile.projectingDisplay`
/// always clears the observation.
nonisolated struct AudioFileMoveProjection: Sendable {
    let fileID: AudioFile.ID
    let displayFile: AudioFile
    let previousURL: URL
    let destinationURL: URL
    let moveID: FileMoveID
    let entryIdentity: RenameEntryIdentity?
}
