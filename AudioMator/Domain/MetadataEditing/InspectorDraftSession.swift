import Foundation
import TagLibAudioMetadata

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

/// Captured when a discard-capable confirmation is shown. Always non-optional
/// so a confirmation opened while clean cannot silently discard edits staged
/// asynchronously before affirmation, and a detached pending-review draft is
/// still validated against its captured session.
nonisolated struct InspectorDiscardConfirmationToken: Hashable, Sendable {
    let hadUnsavedChanges: Bool
    let draftIdentity: InspectorDraftIdentity?
    let pendingReviewSessionID: InspectorDraftSessionID?

    nonisolated init(
        hadUnsavedChanges: Bool,
        draftIdentity: InspectorDraftIdentity?,
        pendingReviewSessionID: InspectorDraftSessionID?
    ) {
        self.hadUnsavedChanges = hadUnsavedChanges
        self.draftIdentity = draftIdentity
        self.pendingReviewSessionID = pendingReviewSessionID
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

// MARK: - F3-b live draft session

/// Live Inspector draft session owned by `AudioViewModel`.
///
/// The session ID, target set, baselines and generations are the durable
/// identity of the draft; the editable payload itself remains the published
/// `edit`/`multiEdit` model so existing view bindings keep working. All
/// mutations flow through `AudioViewModel`'s named draft operations.
nonisolated struct InspectorDraftSession {
    let id: InspectorDraftSessionID
    private(set) var targetIDs: [UUID]
    private(set) var editGeneration: UInt64
    private(set) var artworkGeneration: UInt64
    /// Captured source observations the draft was created from. These are the
    /// conflict baselines; passive refresh must not replace a dirty draft's
    /// baseline.
    var baselinesByID: [UUID: AudioFile]
    /// Submitted intent per target that already completed in a partial batch.
    var completedByID: [UUID: MultiFileEditModel]
    /// Detached pending-review state when captured targets became unavailable.
    var pendingReview: InspectorPendingReview?
    /// Targets whose write committed but whose reload did not fabricate a new
    /// baseline; a later explicit reload is required before advancing them.
    var unverifiedReadbackIDs: Set<UUID>
    var saveReceipt: InspectorSaveReceipt?

    init(
        targetIDs: [UUID],
        baselinesByID: [UUID: AudioFile],
        id: InspectorDraftSessionID = InspectorDraftSessionID()
    ) {
        self.id = id
        self.targetIDs = targetIDs
        self.editGeneration = 1
        self.artworkGeneration = 1
        self.baselinesByID = baselinesByID
        self.completedByID = [:]
        self.pendingReview = nil
        self.unverifiedReadbackIDs = []
        self.saveReceipt = nil
    }

    var identity: InspectorDraftIdentity {
        InspectorDraftIdentity(
            sessionID: id,
            targetIDs: targetIDs,
            editGeneration: editGeneration,
            artworkGeneration: artworkGeneration
        )
    }

    var isSaveInFlight: Bool { saveReceipt != nil }
    var isPendingReview: Bool { pendingReview != nil }

    mutating func noteEditMutation() {
        editGeneration &+= 1
    }

    mutating func noteArtworkCommand() -> InspectorDraftIdentity {
        artworkGeneration &+= 1
        return identity
    }

    mutating func setTargets(_ ids: [UUID], baselines: [UUID: AudioFile]) {
        targetIDs = ids
        baselinesByID = baselines
        completedByID = [:]
        unverifiedReadbackIDs = []
        editGeneration &+= 1
    }

    mutating func advanceEditGenerationOnly() {
        editGeneration &+= 1
    }

    mutating func advanceGenerationAfterTransition() {
        editGeneration &+= 1
        artworkGeneration &+= 1
    }
}

/// One target's captured outcome inside an Inspector save.
nonisolated struct InspectorSavedTargetOutcome: Sendable {
    let targetID: UUID
    /// True when the committed write's readback was published and can advance
    /// the baseline; false means "committed but not refreshed".
    let didRefreshFileModel: Bool
    /// The coherent readback observation, when available.
    let readback: AudioFile?

    init(targetID: UUID, didRefreshFileModel: Bool, readback: AudioFile?) {
        self.targetID = targetID
        self.didRefreshFileModel = didRefreshFileModel
        self.readback = readback
    }
}

/// Captured at save start, before any suspension. Completion is accepted only
/// for the session/generation and target baselines captured here.
nonisolated struct InspectorSaveReceipt {
    let identity: InspectorDraftIdentity
    let targetIDs: [UUID]
    let submittedSingleEdit: SingleFileEditModel?
    let submittedMultiEdit: MultiFileEditModel?
    let submittedEditsByID: [UUID: SingleFileEditModel]
    let baselinesByID: [UUID: AudioFile]

    init(
        identity: InspectorDraftIdentity,
        targetIDs: [UUID],
        submittedSingleEdit: SingleFileEditModel?,
        submittedMultiEdit: MultiFileEditModel?,
        submittedEditsByID: [UUID: SingleFileEditModel],
        baselinesByID: [UUID: AudioFile]
    ) {
        self.identity = identity
        self.targetIDs = targetIDs
        self.submittedSingleEdit = submittedSingleEdit
        self.submittedMultiEdit = submittedMultiEdit
        self.submittedEditsByID = submittedEditsByID
        self.baselinesByID = baselinesByID
    }
}

/// Per-field draft delta helpers for own-save completion.
///
/// The accepted readback becomes the new baseline. Only fields whose live value
/// no longer equals the submitted value are treated as newer typed intent and
/// reapplied; every other field inherits the readback (including an intentional
/// revert to the pre-save value, which stays dirty against the readback).
nonisolated enum InspectorDraftDelta {
    /// Rebuilds a single-file draft from `readback`, then reapplies every field
    /// where `live` differs from `submitted`.
    @MainActor
    static func reappliedSingleDraft(
        live: SingleFileEditModel,
        submitted: SingleFileEditModel,
        readback: AudioFile
    ) -> SingleFileEditModel {
        var result = SingleFileEditModel(from: readback)

        // Text/metadata fields whose live intent is newer than the submission.
        if live.title != submitted.title { result.title = live.title }
        if live.artist != submitted.artist { result.artist = live.artist }
        if live.album != submitted.album { result.album = live.album }
        if live.composer != submitted.composer { result.composer = live.composer }
        if live.genre != submitted.genre { result.genre = live.genre }
        if live.comment != submitted.comment { result.comment = live.comment }
        if live.track != submitted.track { result.track = live.track }
        if live.trackTotal != submitted.trackTotal { result.trackTotal = live.trackTotal }
        if live.disc != submitted.disc { result.disc = live.disc }
        if live.discTotal != submitted.discTotal { result.discTotal = live.discTotal }
        if live.year != submitted.year { result.year = live.year }
        if live.date != submitted.date { result.date = live.date }
        if live.originalReleaseDate != submitted.originalReleaseDate {
            result.originalReleaseDate = live.originalReleaseDate
        }
        if live.contentGroup != submitted.contentGroup { result.contentGroup = live.contentGroup }
        if live.grouping != submitted.grouping { result.grouping = live.grouping }
        if live.work != submitted.work { result.work = live.work }
        if live.containerValues != submitted.containerValues {
            result.containerValues = live.containerValues
        }
        if live.trackNumberText != submitted.trackNumberText {
            result.trackNumberText = live.trackNumberText
        }
        if live.discNumberText != submitted.discNumberText {
            result.discNumberText = live.discNumberText
        }
        if live.albumArtist != submitted.albumArtist { result.albumArtist = live.albumArtist }
        if live.releaseDate != submitted.releaseDate { result.releaseDate = live.releaseDate }
        if live.publisher != submitted.publisher { result.publisher = live.publisher }
        if live.isrc != submitted.isrc { result.isrc = live.isrc }
        if live.barcode != submitted.barcode { result.barcode = live.barcode }
        if live.itunesAlbumID != submitted.itunesAlbumID {
            result.itunesAlbumID = live.itunesAlbumID
        }
        if live.itunesArtistID != submitted.itunesArtistID {
            result.itunesArtistID = live.itunesArtistID
        }
        if live.itunesCatalogID != submitted.itunesCatalogID {
            result.itunesCatalogID = live.itunesCatalogID
        }
        if live.musicBrainzAlbumID != submitted.musicBrainzAlbumID {
            result.musicBrainzAlbumID = live.musicBrainzAlbumID
        }
        if live.musicBrainzTrackID != submitted.musicBrainzTrackID {
            result.musicBrainzTrackID = live.musicBrainzTrackID
        }
        if live.musicBrainzReleaseGroupID != submitted.musicBrainzReleaseGroupID {
            result.musicBrainzReleaseGroupID = live.musicBrainzReleaseGroupID
        }
        if live.lyricist != submitted.lyricist { result.lyricist = live.lyricist }
        if live.remixer != submitted.remixer { result.remixer = live.remixer }
        if live.producer != submitted.producer { result.producer = live.producer }
        if live.engineer != submitted.engineer { result.engineer = live.engineer }
        if live.language != submitted.language { result.language = live.language }
        if live.mediaType != submitted.mediaType { result.mediaType = live.mediaType }
        if live.releaseType != submitted.releaseType { result.releaseType = live.releaseType }
        if live.catalogNumber != submitted.catalogNumber {
            result.catalogNumber = live.catalogNumber
        }
        if live.releaseCountry != submitted.releaseCountry {
            result.releaseCountry = live.releaseCountry
        }
        if live.copyright != submitted.copyright { result.copyright = live.copyright }
        if live.contentAdvisory != submitted.contentAdvisory {
            result.contentAdvisory = live.contentAdvisory
        }
        if live.clearsUnknownAdvisory != submitted.clearsUnknownAdvisory {
            result.clearsUnknownAdvisory = live.clearsUnknownAdvisory
        }
        if live.unsupportedAdvisoryImport != submitted.unsupportedAdvisoryImport {
            result.unsupportedAdvisoryImport = live.unsupportedAdvisoryImport
        }
        if live.artworkEditAction != submitted.artworkEditAction {
            result.artworkEditAction = live.artworkEditAction
        }
        return result
    }

    /// Rebuilds a multi-file draft from the accepted readbacks, then reapplies
    /// only the fields whose live intent differs from the submission.
    @MainActor
    static func reappliedMultiDraft(
        readbackFiles: [AudioFile],
        live: MultiFileEditModel,
        submitted: MultiFileEditModel,
        artworkState: MultiFileArtworkState?
    ) -> MultiFileEditModel {
        var result = MultiFileEditModel(files: readbackFiles, artworkState: artworkState)
        for field in MultiFileEditableTextField.allCases
        where live.text(for: field) != submitted.text(for: field) {
            result.setText(live.text(for: field), for: field)
        }
        for key in live.changedContainerFieldKeys(comparedTo: submitted) {
            if let value = live.containerValue(for: key) {
                result.setContainerValue(value, for: key)
            }
        }
        if live.explicitEditState != submitted.explicitEditState {
            result.explicitEditState = live.explicitEditState
        }
        if live.artworkEditAction != submitted.artworkEditAction {
            result.setArtworkEditAction(live.artworkEditAction)
        }
        return result
    }
}

/// F3-b helpers over the existing multi-file draft model.
nonisolated extension MultiFileEditModel {
    /// Container-field keys whose visible intent differs between two snapshots.
    func changedContainerFieldKeys(comparedTo other: MultiFileEditModel) -> Set<MetadataFieldKey> {
        modifiedContainerFields.union(other.modifiedContainerFields).filter {
            values.containerValues[$0] != other.values.containerValues[$0]
        }
    }

    func containerValue(for key: MetadataFieldKey) -> ContainerFieldValue? {
        values.containerValues[key]
    }
}

/// Why the Inspector draft payload is being rebuilt.
nonisolated enum InspectorDraftReconstructionReason {
    case selectionTransition
    case explicitSelectionSync
    case cleanRefresh
    case ownSaveCompletion
    case publication
    case pendingReview
}

/// Why the Inspector draft is being discarded.
nonisolated enum InspectorDraftDiscardReason {
    case explicitUserAction
    case pendingReviewDiscard
    case replacementSession
}
