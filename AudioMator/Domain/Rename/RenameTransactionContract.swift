import Foundation

/// Deterministic hidden stage name for one planned move.
///
/// The name is bound to the operation UUID and the entry index so a later
/// process can validate a manifest without trusting a persisted random name.
/// The leading dot keeps the stage hidden from folder enumeration; the original
/// extension is preserved.
nonisolated enum RenameStagingName {
    static let prefix = ".audiomator-rename"

    static func url(for sourceURL: URL, operationID: UUID, index: Int) -> URL {
        let name = baseName(for: sourceURL, operationID: operationID, index: index)
        return sourceURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
    }

    static func baseName(for sourceURL: URL, operationID: UUID, index: Int) -> String {
        let name = baseNameWithoutExtension(operationID: operationID, index: index)
        let extensionText = sourceURL.pathExtension
        return extensionText.isEmpty ? name : name + "." + extensionText
    }

    static func baseNameWithoutExtension(operationID: UUID, index: Int) -> String {
        let indexText = String(format: "%04d", index)
        return "\(prefix).\(operationID.uuidString.lowercased()).\(indexText)"
    }

    static func validates(
        _ temporaryURL: URL,
        for sourceURL: URL,
        operationID: UUID,
        index: Int
    ) -> Bool {
        temporaryURL.absoluteString
            == url(for: sourceURL, operationID: operationID, index: index).absoluteString
    }
}

nonisolated struct PreparedRenameTransaction: Sendable, Equatable {
    let operationID: UUID
    let entries: [PreparedRenameEntry]
}

nonisolated struct PreparedRenameEntry: Sendable, Equatable {
    /// Position in the batch, contiguous from zero.
    let index: Int
    /// In-memory `AudioFile.ID` correlation only; never persisted by the journal.
    let fileID: UUID
    let originalURL: URL
    let temporaryURL: URL
    let intendedURL: URL
    /// Preview fingerprint. Used for the preflight staleness check only; the
    /// journal records the stronger directory-entry identity captured under the
    /// journal lock.
    let expectedSourceFingerprint: AudioFileFingerprint
}

nonisolated struct RenameExecutedMove: Equatable, Sendable {
    let index: Int
    let fileID: UUID
    let originalURL: URL
    let intendedURL: URL
    let entryIdentity: RenameEntryIdentity
}

nonisolated enum RenameFailureReason: Error, Equatable, Sendable {
    case sourceChanged(index: Int)
    case sourceMissing(index: Int)
    case parentUnavailable(index: Int)
    case destinationOccupied(index: Int)
    case entryIdentityMismatch(index: Int)
    case moveFailed(index: Int, code: String)
    case directorySyncFailed(code: String)
    case journalUnavailable
    case committedRecordFailed
}

nonisolated enum RenamePlanValidationFailure: String, Error, Equatable, Sendable {
    case emptyBatch
    case tooManyEntries
    case invalidIndex
    case duplicateFileID
    case notAFileURL
    case notAbsoluteURL
    case mixedParent
    case temporaryNameMismatch
    case unchangedEntry
    case duplicateSource
    case duplicateTarget
    case invalidRoleCollision
    case invalidExtension
}

nonisolated enum RenamePreflightRejection: Error, Equatable, Sendable {
    case invalidPlan(RenamePlanValidationFailure)
    case sourceChanged(index: Int)
    case sourceMissing(index: Int)
    case unexpectedEntryKind(index: Int)
    case sourceIdentityUnavailable(index: Int)
    case parentUnavailable(index: Int)
    case stageNameOccupied(index: Int)
    case stageNameTooLong(index: Int)
    case destinationOccupied(index: Int)
    case exclusiveRenameUnsupported(folderName: String)
    case journalUnavailable
    case overlappingPreparedOperation(operationID: UUID)
    case duplicateOperation(operationID: UUID)
}

nonisolated enum RenameJournalOperationStatus: String, Equatable, Sendable {
    case preparedNoFilesMoved
    case preparedNeedsRestore
    case preparedAllAtIntended
    case preparedUnresolved
    case preparedUnavailable
    case committedConfirmed
    case committedUncertain
    case busy
}

nonisolated enum RenameEntryRole: String, Equatable, Sendable {
    case original
    case staged
    case intended
    case missing
    case foreign
    case ambiguous
    case unavailable
}

nonisolated enum RenameClassificationIssueCode: String, Equatable, Sendable {
    case busy
    case journalLockUnavailable
    case foreignEntry
    case missingEntry
    case ambiguousEntry
    case directoryUnavailable
    case volumeIdentityUnavailable
}

nonisolated struct RenameEntryClassification: Equatable, Sendable {
    let index: Int
    let role: RenameEntryRole
    let expectedIdentity: RenameJournalEntryIdentity
    let observedURL: URL?
    let observedIdentity: RenameEntryIdentity?
}

nonisolated struct RenameJournalClassification: Equatable, Sendable {
    let operationID: UUID
    let phase: RenameJournalPhase
    let status: RenameJournalOperationStatus
    let entries: [RenameEntryClassification]
    let issueCodes: [RenameClassificationIssueCode]
}

nonisolated enum RenameExecutionOutcome: Equatable, Sendable {
    case committed(
        operationID: UUID,
        moves: [RenameExecutedMove],
        diagnostics: [RenameJournalDiagnosticCode]
    )
    case rolledBack(operationID: UUID, reason: RenameFailureReason)
    case cancelledBeforeStaging(operationID: UUID)
    case unresolved(
        operationID: UUID,
        classification: RenameJournalClassification,
        reason: RenameFailureReason?
    )
    case rejected(RenamePreflightRejection)
    case busy
}

nonisolated struct RenameRestoredMove: Equatable, Sendable {
    let index: Int
    let originalURL: URL
    let entryIdentity: RenameEntryIdentity
}

nonisolated enum RenameRestoreRejection: Error, Equatable, Sendable {
    case committedRecordFinal
    case recordMissing
    case journalUnavailable
    case exclusiveRenameUnsupported(folderName: String)
}

nonisolated enum RenameRestoreOutcome: Equatable, Sendable {
    case restored(
        operationID: UUID,
        moves: [RenameRestoredMove],
        retainedRecord: Bool
    )
    case unresolved(
        operationID: UUID,
        classification: RenameJournalClassification,
        reason: RenameFailureReason?
    )
    case rejected(RenameRestoreRejection)
    case busy
}
