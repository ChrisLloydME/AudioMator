import Foundation

/// Stable identity of one LRCLIB browser session.
///
/// A session is created by `seed`/`closeWindowSession` and invalidated by every
/// reseed, close and Sources navigation. Completions compare it before publishing.
nonisolated struct LRCLIBLyricsSessionID: Hashable, Sendable {
    let rawValue: UUID

    nonisolated init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Identity of one search-to-write operation inside a session.
nonisolated struct LRCLIBLyricsOperationID: Hashable, Sendable {
    let rawValue: UUID

    nonisolated init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated enum LRCLIBLyricsOperationKind: Sendable, Equatable {
    case manualApply
    case autoApply
}

nonisolated enum LRCLIBLyricsOperationPhase: Sendable, Equatable {
    case searching
    case writing
    case finishing
}

nonisolated struct LRCLIBLyricsOperationProgress: Sendable, Equatable {
    let kind: LRCLIBLyricsOperationKind
    let phase: LRCLIBLyricsOperationPhase
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String

    nonisolated var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    nonisolated var progressLabel: String {
        "\(completedCount) / \(totalCount)"
    }
}

/// One session generation plus one operation identity.
///
/// The store hands this token to the writer; the writer uses it only for
/// progress ownership and cancellation checking. It never grants write
/// authority — the frozen `ReviewedMetadataWrite` inside the intent does.
nonisolated struct LRCLIBLyricsOperationToken: Sendable, Equatable {
    let sessionID: LRCLIBLyricsSessionID
    let generation: UInt64
    let operationID: LRCLIBLyricsOperationID
    let kind: LRCLIBLyricsOperationKind
}

/// One queued file: the metadata-only HTTP query input plus the write authority
/// captured from the exact `AudioFile` observation that supplied the query.
///
/// `target == nil` is legal: such a row stays searchable and previewable, but it
/// cannot authorize a write. `target` is captured once at seed; selecting
/// candidates, navigating, or a refreshed file observation never changes it.
nonisolated struct LRCLIBLyricsSessionRow: Identifiable, Sendable, Equatable {
    let input: LRCLIBFileSearchInput
    let target: ReviewedMetadataTarget?

    nonisolated var id: AudioFile.ID { input.id }

    nonisolated init(input: LRCLIBFileSearchInput, target: ReviewedMetadataTarget?) {
        self.input = input
        self.target = target
    }
}

/// Result of one manual (single-file) lyrics application.
nonisolated enum LRCLIBLyricsManualWriteOutcome: Equatable, Sendable {
    /// A commit crossed the admission boundary. Warnings are the real reload or
    /// durability warnings, if any.
    case applied(warnings: [String], refreshedFileModel: Bool)
    /// Rejected before any commit: no reviewed authority, unsupported format or
    /// capability, empty lyrics, stale revision, or a save failure.
    case rejected(String)
    /// Cancelled before the commit boundary. A started commit returns `.applied`
    /// or `.rejected`, never this case.
    case cancelled
}

/// One committed file accounted by the bulk writer.
nonisolated struct LRCLIBLyricsAppliedEntry: Equatable, Sendable {
    let fileID: AudioFile.ID
    let candidateID: LRCLIBLyricsCandidate.ID

    nonisolated init(fileID: AudioFile.ID, candidateID: LRCLIBLyricsCandidate.ID) {
        self.fileID = fileID
        self.candidateID = candidateID
    }
}

/// Result of one bulk application. Produced on the main actor so it may carry the
/// existing batch summary value without extra Sendable ceremony.
@MainActor
struct LRCLIBLyricsAutoWriteOutcome {
    let appliedEntries: [LRCLIBLyricsAppliedEntry]
    let summary: BatchMetadataOperationSummary
    let succeededCount: Int
    let didCancel: Bool
    let cancelledBeforeAnyStart: Bool

    var didCommitAnything: Bool { succeededCount > 0 }

    var realFailureCount: Int {
        summary.failureIssues.filter { $0.classification == .failure }.count
    }
}

/// The single write handoff surface the browser store drives.
///
/// Implemented by `AudioViewModel`; tests may substitute a recording spy. The
/// store never writes to disk itself, so every write still flows through the
/// shared strict reviewed-write route and its commit permit.
@MainActor
protocol LRCLIBLyricsWriting: Sendable {
    func applyLRCLIBLyrics(_ intent: LRCLIBLyricsManualWriteIntent) async -> LRCLIBLyricsManualWriteOutcome
    func applyLRCLIBLyricsAutoMatches(_ intent: LRCLIBLyricsAutoWriteIntent) async -> LRCLIBLyricsAutoWriteOutcome
}
