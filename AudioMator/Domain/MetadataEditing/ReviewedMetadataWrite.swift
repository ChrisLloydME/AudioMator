import Foundation
import TagLibAudioMetadata

/// Immutable write authority captured from one coherent file observation.
///
/// The reviewed target is distinct from an `AudioFile` snapshot: it carries only
/// the logical ID, the operational URL and the two disk tokens that must still
/// match at commit. A target cannot be composed from a moved display model or a
/// lightweight stat probe; it can only be produced by `init?(verified:)` from a
/// successfully loaded observation.
nonisolated struct ReviewedMetadataTarget: Sendable, Equatable {
    let id: AudioFile.ID
    let url: URL
    let fingerprint: AudioFileFingerprint
    let version: MetadataFileVersion

    /// Creates write authority only from a coherent, successfully read file.
    ///
    /// The file must carry a user-selected URL, both disk tokens and no
    /// refresh-required recovery flag. A path rebind that retained stale
    /// metadata after a failed load therefore cannot produce a target.
    init?(verified file: AudioFile) {
        guard file.url.isFileURL,
              let fingerprint = file.fileFingerprint,
              let version = file.metadataFileVersion,
              !file.requiresMetadataRefreshBeforeWriting else {
            return nil
        }

        self.id = file.id
        self.url = file.url
        self.fingerprint = fingerprint
        self.version = version
    }

    /// Explicit construction used by the feature boundary for targets that were
    /// already captured from a coherent observation (for example the raw editor's
    /// `MetadataEditorTarget`). Production code should prefer `init?(verified:)`.
    nonisolated init(
        id: AudioFile.ID,
        url: URL,
        fingerprint: AudioFileFingerprint,
        version: MetadataFileVersion
    ) {
        self.id = id
        self.url = url
        self.fingerprint = fingerprint
        self.version = version
    }

    /// Association check used before prompts and inside the reservation.
    ///
    /// The logical ID must match and the separately captured URLs must alias the
    /// same physical location under the existing volume-aware path rules. The
    /// target keeps its own operational URL for sandbox authorization.
    nonisolated func associates(with file: AudioFile) -> Bool {
        guard file.id == id else { return false }
        return FileSystemPathSemantics.key(for: file.url) == FileSystemPathSemantics.key(for: url)
    }

    /// True when a refreshed observation still represents this exact target.
    ///
    /// Same path, fingerprint and package revision remain eligible. Reusing the
    /// logical ID for a different observation does not.
    nonisolated func matches(observation file: AudioFile) -> Bool {
        guard associates(with: file),
              !file.requiresMetadataRefreshBeforeWriting,
              let fingerprint = file.fileFingerprint,
              let version = file.metadataFileVersion else {
            return false
        }
        return fingerprint == self.fingerprint && version == self.version
    }
}

/// A reviewed write intent bound to an immutable target.
///
/// The payload is frozen from the reviewed observation and must not be rebuilt
/// from the live editor model at commit time. The projection is the adapter-owned
/// plan-time truth (effective operations, component operations, validation and
/// capability outcome); a planner must obtain it before creating a write and the
/// commit must not re-derive it from mutable state.
nonisolated struct ReviewedMetadataWrite: Sendable {
    enum Intent: Sendable {
        case semantic(MetadataEditPayload)
        case raw(RawMetadataPatch)
        case eraseAll
    }

    /// Capability classification for preflight. Raw patches keep their own
    /// low-level class and are never converted into a semantic write.
    enum CapabilityClass: Sendable {
        case semantic(Set<MetadataFieldKey>)
        case rawValues
        case eraseAll
    }

    let target: ReviewedMetadataTarget
    let intent: Intent
    let projection: MetadataWriteProjection

    nonisolated init(
        target: ReviewedMetadataTarget,
        intent: Intent,
        projection: MetadataWriteProjection
    ) {
        self.target = target
        self.intent = intent
        self.projection = projection
    }

    nonisolated var capabilityClass: CapabilityClass {
        switch intent {
        case .semantic(let payload):
            return .semantic(payload.requestedFields)
        case .raw:
            return .rawValues
        case .eraseAll:
            return .eraseAll
        }
    }

    /// True when the frozen intent requests no executable change. Execution of a
    /// no-op must not reach the package writer.
    nonisolated var isNoOp: Bool {
        switch intent {
        case .semantic:
            return projection.isNoOp
        case .raw(let patch):
            return patch.valuesToSet.isEmpty && patch.removingKeys.isEmpty
        case .eraseAll:
            return false
        }
    }

    /// True when planning rejected this intent; a rejected write must never reach
    /// the package writer even if a caller ignores it.
    nonisolated var isRejected: Bool {
        projection.isRejected
    }
}
