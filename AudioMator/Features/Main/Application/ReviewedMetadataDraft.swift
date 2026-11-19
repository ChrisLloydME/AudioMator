import Foundation
import TagLibAudioMetadata

/// One prepared conflict-aware draft write bound to its reviewed observation.
///
/// The Inspector and Raw Metadata Editor keep their documented policy-driven
/// merge behaviour: the resolver validates file identity and audio continuity,
/// then may rebase to a fresh revision under the configured policy. The permit
/// still gates membership, protection and cancellation.
nonisolated struct ReviewedMetadataDraft: Sendable {
    let write: ReviewedMetadataWrite
    let baseline: MetadataConflictBaseline
    let policy: MetadataConflictPolicy
    /// Captured whole raw draft map for the conflict-aware raw route. The strict
    /// unchanged-revision path still uses the frozen exact delta in `write.intent`;
    /// the resolver needs the draft map only to merge under its documented policy.
    let rawDraft: RawMetadataValueMap?

    nonisolated init(
        write: ReviewedMetadataWrite,
        baseline: MetadataConflictBaseline,
        policy: MetadataConflictPolicy,
        rawDraft: RawMetadataValueMap? = nil
    ) {
        self.write = write
        self.baseline = baseline
        self.policy = policy
        self.rawDraft = rawDraft
    }
}

/// Builds frozen reviewed writes from a coherent loaded observation.
///
/// Planning happens on the main actor before any authorization prompt. The
/// projection comes from the adapter's deterministic encoder, so preview truth and
/// commit truth cannot diverge. A file without a coherent observation yields no
/// writable intent (fail closed).
@MainActor
enum ReviewedMetadataWriteFactory {
    private static let projectionAdapter = TagLibAudioMetadataPipeline()

    static func semanticWrite(
        edit: SingleFileEditModel,
        comparedTo file: AudioFile
    ) -> ReviewedMetadataWrite? {
        guard let target = ReviewedMetadataTarget(verified: file) else { return nil }
        let payload = MetadataEditPayload(edit, comparedTo: file)
        guard let projection = try? projectionAdapter.projectMetadataWrite(
            .semantic(payload),
            fileExtension: file.url.pathExtension
        ) else {
            return nil
        }
        return ReviewedMetadataWrite(
            target: target,
            intent: .semantic(payload),
            projection: projection
        )
    }

    static func eraseAllWrite(for file: AudioFile) -> ReviewedMetadataWrite? {
        guard let target = ReviewedMetadataTarget(verified: file) else { return nil }
        guard let projection = try? projectionAdapter.projectMetadataWrite(
            .eraseAll,
            fileExtension: file.url.pathExtension
        ) else {
            return nil
        }
        return ReviewedMetadataWrite(
            target: target,
            intent: .eraseAll,
            projection: projection
        )
    }

    static func rawWrite(
        _ patch: RawMetadataPatch,
        for file: AudioFile
    ) -> ReviewedMetadataWrite? {
        guard let target = ReviewedMetadataTarget(verified: file) else { return nil }
        guard let projection = try? projectionAdapter.projectMetadataWrite(
            .raw(patch),
            fileExtension: file.url.pathExtension
        ) else {
            return nil
        }
        return ReviewedMetadataWrite(
            target: target,
            intent: .raw(patch),
            projection: projection
        )
    }
}
