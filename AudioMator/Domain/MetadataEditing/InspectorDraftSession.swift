import Foundation

// MARK: - F3 Inspector draft session value types (F3-b foundation)

/// Stable identity of one Inspector draft session. The Inspector draft keeps
/// this identity independently of the current selection and of any single disk
/// observation, so a completion can be accepted only for the session that
/// started it.
nonisolated struct InspectorDraftSessionID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    nonisolated init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    nonisolated var description: String { rawValue.uuidString }
}

/// Identity plus monotonic generations of one Inspector draft session.
///
/// `editGeneration` advances whenever the draft payload changes (including an
/// explicit cancel/discard), so a save or refresh completion can be rejected
/// when the live draft changed while it was in flight.
///
/// `artworkGeneration` advances independently when an artwork command is issued
/// (Replace/Clear/Keep, local or remote). Editing another field in the same
/// draft does not invalidate an artwork handoff.
nonisolated struct InspectorDraftIdentity: Hashable, Sendable {
    let sessionID: InspectorDraftSessionID
    let targetIDs: [UUID]
    let editGeneration: UInt64
    let artworkGeneration: UInt64

    nonisolated init(
        sessionID: InspectorDraftSessionID,
        targetIDs: [UUID],
        editGeneration: UInt64,
        artworkGeneration: UInt64
    ) {
        self.sessionID = sessionID
        self.targetIDs = targetIDs
        self.editGeneration = editGeneration
        self.artworkGeneration = artworkGeneration
    }
}

/// Why captured Inspector edits are being retained instead of published.
nonisolated enum InspectorPendingReviewReason: Hashable, Sendable {
    /// One or more captured targets are no longer present in any source
    /// membership (passive watch/import prune, or an intentional removal that
    /// did not first discard the draft).
    case targetsBecameUnavailable
    /// The membership was removed deliberately (Quick Import clear, watched
    /// folder removal) while captured edits still existed.
    case membershipRemoved
    /// A rename/recovery decision left a captured target without a coherent
    /// writable observation; the values remain reviewable until an explicit
    /// reload or discard.
    case targetRequiresRecovery
}

/// A dirty Inspector draft whose captured targets are not all available.
///
/// The payload and baselines stay in the Inspector draft owner (F3-b); this
/// value describes why publication is suspended and which captured targets are
/// missing. Save stays suspended until every captured target is available and
/// the user resumes, or until the user discards the review.
nonisolated struct InspectorPendingReview: Hashable, Sendable {
    let identity: InspectorDraftIdentity
    let capturedTargetIDs: [UUID]
    let unavailableTargetIDs: Set<UUID>
    let reason: InspectorPendingReviewReason

    nonisolated init(
        identity: InspectorDraftIdentity,
        capturedTargetIDs: [UUID],
        unavailableTargetIDs: Set<UUID>,
        reason: InspectorPendingReviewReason
    ) {
        self.identity = identity
        self.capturedTargetIDs = capturedTargetIDs
        self.unavailableTargetIDs = unavailableTargetIDs
        self.reason = reason
    }

    nonisolated var canResume: Bool { unavailableTargetIDs.isEmpty }
}

/// Captured when an unsaved-discard confirmation is shown. The response is
/// applied only if the draft identity is still current; otherwise the decision
/// is repeated or aborted instead of discarding a newer draft.
nonisolated struct InspectorDiscardConfirmationToken: Hashable, Sendable {
    let identity: InspectorDraftIdentity

    nonisolated init(identity: InspectorDraftIdentity) {
        self.identity = identity
    }
}

/// Captured when an artwork command is issued so an async handoff can verify the
/// same draft session/command generation before staging the image.
nonisolated struct ArtworkCommandToken: Hashable, Sendable {
    let sessionID: InspectorDraftSessionID
    let artworkGeneration: UInt64
    let targetIDs: [UUID]

    nonisolated init(
        sessionID: InspectorDraftSessionID,
        artworkGeneration: UInt64,
        targetIDs: [UUID]
    ) {
        self.sessionID = sessionID
        self.artworkGeneration = artworkGeneration
        self.targetIDs = targetIDs
    }
}
