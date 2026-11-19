import Foundation

// MARK: - F3 raw Metadata Editor session identity

/// Identity of one Metadata Editor presentation/session. A new value is created
/// for every explicit presentation. Completions, closes and load results are
/// accepted only while their captured identity is still current.
struct MetadataEditorPresentationID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var description: String { rawValue.uuidString }
}

/// Identity of one raw-metadata apply operation inside a presentation.
struct MetadataEditorApplyID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var description: String { rawValue.uuidString }
}

/// Store-owned state of the currently presented editing session.
///
/// A closed window ends the presented session but an admitted apply may keep
/// draining; that drain is tracked separately from this state so a reopened
/// window can prepare data without admitting a second raw write.
enum MetadataEditorSessionState: Equatable, Sendable {
    case idle
    case loading(presentationID: MetadataEditorPresentationID, loadGeneration: UInt64)
    case ready(presentationID: MetadataEditorPresentationID)
    case applying(
        presentationID: MetadataEditorPresentationID,
        applyID: MetadataEditorApplyID
    )

    var presentationID: MetadataEditorPresentationID? {
        switch self {
        case .idle:
            return nil
        case .loading(let presentationID, _), .ready(let presentationID),
             .applying(let presentationID, _):
            return presentationID
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }
}

/// Captured once per presentation start. A detached raw-metadata load may publish
/// only when its context is still the current one.
struct MetadataEditorLoadContext: Equatable, Sendable {
    let presentationID: MetadataEditorPresentationID
    let loadGeneration: UInt64
}

/// What the main window should do when a Metadata Editor open is requested.
///
/// Repeated opens while the window is still presented must never reset live
/// store state. A different target selection needs an explicit discard decision
/// when the current raw draft is dirty.
enum MetadataEditorOpenDecision: Equatable, Sendable {
    /// No usable session exists; present the requested targets.
    case presentNew
    /// The current presentation already owns the window; raise it without reset.
    case focusExisting(presentationID: MetadataEditorPresentationID)
    /// The current draft is dirty and the request is for different targets.
    /// Confirm against `presentationID`, then call `discardAndOpen`.
    case confirmDiscardAndOpen(presentationID: MetadataEditorPresentationID)
    /// An earlier apply is still draining and the window is closed. A new
    /// presentation may load for inspection, but no apply may start until the
    /// drain finishes.
    case presentWhileDraining(presentationID: MetadataEditorPresentationID)
}

/// Immutable snapshot captured when Done starts applying. It freezes the exact
/// targets, baselines and raw maps that the operation is allowed to complete.
struct MetadataEditorApplyRequest {
    let presentationID: MetadataEditorPresentationID
    let applyID: MetadataEditorApplyID
    let targets: [MetadataEditorTarget]
    let pendingTargets: [MetadataEditorTarget]
    let submittedPropertyMaps: [AudioFile.ID: RawMetadataValueMap]
    /// Draft generation at capture. A later mutation means a newer edit exists.
    let draftGeneration: UInt64
}

/// Result of a raw apply, scoped to the apply/session that began it.
struct MetadataEditorApplyOutcome {
    let presentationID: MetadataEditorPresentationID
    let applyID: MetadataEditorApplyID
    let succeededTargetIDs: Set<AudioFile.ID>
    let failedTargetIDs: Set<AudioFile.ID>
    let didApplyAllChanges: Bool
    /// True when cancellation stopped unprocessed targets before any commit.
    let wasCancelled: Bool

    init(
        presentationID: MetadataEditorPresentationID,
        applyID: MetadataEditorApplyID,
        succeededTargetIDs: Set<AudioFile.ID>,
        failedTargetIDs: Set<AudioFile.ID>,
        didApplyAllChanges: Bool,
        wasCancelled: Bool = false
    ) {
        self.presentationID = presentationID
        self.applyID = applyID
        self.succeededTargetIDs = succeededTargetIDs
        self.failedTargetIDs = failedTargetIDs
        self.didApplyAllChanges = didApplyAllChanges
        self.wasCancelled = wasCancelled
    }
}

/// What the window should do after a completion was accepted.
enum MetadataEditorApplyCompletion: Equatable, Sendable {
    /// The owning presentation may dismiss (all applied, nothing newer).
    case dismiss
    /// Successful targets were removed; failures or newer edits remain.
    case remainReady
    /// The completion belonged to a closed/draining session or a stale session;
    /// no current presentation state was mutated.
    case sessionClosed
}
