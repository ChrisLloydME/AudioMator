import Foundation
import TagLibAudioMetadata

/// Why a manual or bulk lyrics entry cannot authorize a write.
///
/// These are the only pre-write rejections the lyrics path introduces. The strict
/// reviewed-write route keeps its own failures (changed revision, removed
/// membership, recovery state, package error) and they are reported per file.
nonisolated enum LRCLIBLyricsWriteRejection: Error, Equatable, Sendable {
    /// The seeded `AudioFile` had no coherent observation, or it required a reload
    /// before writing. The row remains searchable/previewable.
    case noReviewedAuthority
    /// The extension is not tag-writable at all.
    case unsupportedFormat
    /// The format is tag-writable but its capability does not include `.lyrics`.
    case unsupportedLyricsCapability
    /// The synced lyrics were empty after trimming.
    case emptyLyrics
    /// The matched candidate lost its synced lyrics before the write was frozen.
    case noSyncedLyrics

    nonisolated var message: String {
        switch self {
        case .noReviewedAuthority:
            return String(localized: "This lyrics result wasn’t built from a reviewed copy of this file. Close and reopen LRCLIB, then review the current lyrics before applying them.")
        case .unsupportedFormat:
            return String(localized: "AudioMator doesn't support saving metadata to this file format.")
        case .unsupportedLyricsCapability:
            return String(localized: "This file format doesn't support saving lyrics in AudioMator. No changes were saved.")
        case .emptyLyrics:
            return String(localized: "This lyrics result is empty. Choose another result.")
        case .noSyncedLyrics:
            return String(localized: "This result doesn't include synced lyrics. Choose a result that has synced lyrics.")
        }
    }
}

/// One manual (single-file) lyrics write, bound to the target captured at seed.
///
/// Neither this type nor `LRCLIBLyricsAutoWriteIntent` can be built from a file ID
/// plus lyrics: they carry the reviewed target, candidate identity, lyrics and a
/// frozen `ReviewedMetadataWrite` (or an explicit rejection). The app-facing
/// `AudioViewModel` write entry points accept only these intents.
nonisolated struct LRCLIBLyricsManualWriteIntent: Sendable {
    let operation: LRCLIBLyricsOperationToken
    let fileID: AudioFile.ID
    let fileName: String
    let candidateID: LRCLIBLyricsCandidate.ID
    let lyrics: String
    let write: ReviewedMetadataWrite?
    let rejection: LRCLIBLyricsWriteRejection?

    nonisolated init(
        operation: LRCLIBLyricsOperationToken,
        fileID: AudioFile.ID,
        fileName: String,
        candidateID: LRCLIBLyricsCandidate.ID,
        lyrics: String,
        write: ReviewedMetadataWrite?,
        rejection: LRCLIBLyricsWriteRejection?
    ) {
        self.operation = operation
        self.fileID = fileID
        self.fileName = fileName
        self.candidateID = candidateID
        self.lyrics = lyrics
        self.write = write
        self.rejection = rejection
    }
}

/// One matched file in a bulk lyrics write.
nonisolated struct LRCLIBLyricsAutoWriteEntry: Sendable {
    let fileID: AudioFile.ID
    let fileName: String
    let candidateID: LRCLIBLyricsCandidate.ID
    let lyrics: String
    let write: ReviewedMetadataWrite?
    let rejection: LRCLIBLyricsWriteRejection?

    nonisolated init(
        fileID: AudioFile.ID,
        fileName: String,
        candidateID: LRCLIBLyricsCandidate.ID,
        lyrics: String,
        write: ReviewedMetadataWrite?,
        rejection: LRCLIBLyricsWriteRejection?
    ) {
        self.fileID = fileID
        self.fileName = fileName
        self.candidateID = candidateID
        self.lyrics = lyrics
        self.write = write
        self.rejection = rejection
    }
}

/// One captured bulk write queue. The store snapshots the queue rows before the
/// operation and freezes every decision here; a later search, selection change or
/// reseed cannot alter these entries.
nonisolated struct LRCLIBLyricsAutoWriteIntent: Sendable {
    let operation: LRCLIBLyricsOperationToken
    let entries: [LRCLIBLyricsAutoWriteEntry]

    nonisolated init(operation: LRCLIBLyricsOperationToken, entries: [LRCLIBLyricsAutoWriteEntry]) {
        self.operation = operation
        self.entries = entries
    }

    nonisolated var readyEntryCount: Int {
        entries.filter { $0.write != nil }.count
    }
}

/// Builds frozen lyrics writes from a captured reviewed target.
///
/// All capability and normalization decisions happen here, on the main actor,
/// before any authorization prompt. The projection comes from the adapter's
/// deterministic encoder, exactly like the other strict reviewed writes.
///
/// Package limitation (recorded in the design and docs): the adapter's raw-intent
/// projection only checks whether the container is tag-writable, not whether a
/// specific raw key is supported. This builder therefore performs the `.lyrics`
/// field capability preflight itself.
@MainActor
enum LRCLIBLyricsWriteIntentBuilder {
    private static let projectionAdapter = TagLibAudioMetadataPipeline()

    nonisolated static let rawLyricsKey = "LYRICS"

    /// The exact write shape the lyrics path has always used: one scoped raw
    /// `LYRICS` value, never a whole property-map rewrite.
    nonisolated static func rawLyricsPatch(_ lyrics: String) -> RawMetadataPatch {
        RawMetadataPatch(valuesToSet: [rawLyricsKey: [lyrics]])
    }

    /// Trims synced lyrics and rejects an empty value; keeps the candidate's text
    /// otherwise byte-for-byte so preview and disk agree.
    static func normalizedSyncedLyrics(
        _ candidate: LRCLIBLyricsCandidate
    ) -> String? {
        guard candidate.hasSyncedLyrics, let syncedLyrics = candidate.syncedLyrics else {
            return nil
        }
        let normalized = syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    /// Freezes a write from a target captured at seed. A target that is nil or a
    /// format/field capability gap returns a typed rejection instead of a write.
    static func reviewedLyricsWrite(
        lyrics: String,
        target: ReviewedMetadataTarget?
    ) -> Result<ReviewedMetadataWrite, LRCLIBLyricsWriteRejection> {
        guard let target else { return .failure(.noReviewedAuthority) }
        let normalized = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .failure(.emptyLyrics) }
        let fileExtension = target.url.pathExtension
        guard isTagWriteSupportedExtension(fileExtension) else {
            return .failure(.unsupportedFormat)
        }
        guard unsupportedMetadataWriteFields(
            [.lyrics],
            forFileExtension: fileExtension
        ).isEmpty else {
            return .failure(.unsupportedLyricsCapability)
        }

        let patch = rawLyricsPatch(normalized)
        guard let projection = try? projectionAdapter.projectMetadataWrite(
            .raw(patch),
            fileExtension: fileExtension
        ), projection.isExecutable else {
            return .failure(.unsupportedFormat)
        }
        return .success(
            ReviewedMetadataWrite(
                target: target,
                intent: .raw(patch),
                projection: projection
            )
        )
    }

    static func manualIntent(
        row: LRCLIBLyricsSessionRow,
        candidate: LRCLIBLyricsCandidate,
        operation: LRCLIBLyricsOperationToken
    ) -> LRCLIBLyricsManualWriteIntent {
        let fileName = row.input.fileName
        guard let lyrics = normalizedSyncedLyrics(candidate) else {
            return LRCLIBLyricsManualWriteIntent(
                operation: operation,
                fileID: row.id,
                fileName: fileName,
                candidateID: candidate.id,
                lyrics: "",
                write: nil,
                rejection: .noSyncedLyrics
            )
        }
        switch reviewedLyricsWrite(lyrics: lyrics, target: row.target) {
        case .success(let write):
            return LRCLIBLyricsManualWriteIntent(
                operation: operation,
                fileID: row.id,
                fileName: fileName,
                candidateID: candidate.id,
                lyrics: lyrics,
                write: write,
                rejection: nil
            )
        case .failure(let rejection):
            return LRCLIBLyricsManualWriteIntent(
                operation: operation,
                fileID: row.id,
                fileName: fileName,
                candidateID: candidate.id,
                lyrics: lyrics,
                write: nil,
                rejection: rejection
            )
        }
    }

    static func autoEntry(
        row: LRCLIBLyricsSessionRow,
        candidate: LRCLIBLyricsCandidate,
        operation: LRCLIBLyricsOperationToken
    ) -> LRCLIBLyricsAutoWriteEntry {
        let fileName = row.input.fileName
        guard let lyrics = normalizedSyncedLyrics(candidate) else {
            return LRCLIBLyricsAutoWriteEntry(
                fileID: row.id,
                fileName: fileName,
                candidateID: candidate.id,
                lyrics: "",
                write: nil,
                rejection: .noSyncedLyrics
            )
        }
        switch reviewedLyricsWrite(lyrics: lyrics, target: row.target) {
        case .success(let write):
            return LRCLIBLyricsAutoWriteEntry(
                fileID: row.id,
                fileName: fileName,
                candidateID: candidate.id,
                lyrics: lyrics,
                write: write,
                rejection: nil
            )
        case .failure(let rejection):
            return LRCLIBLyricsAutoWriteEntry(
                fileID: row.id,
                fileName: fileName,
                candidateID: candidate.id,
                lyrics: lyrics,
                write: nil,
                rejection: rejection
            )
        }
    }
}
