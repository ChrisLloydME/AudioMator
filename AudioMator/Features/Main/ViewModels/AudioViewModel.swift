//
//  AudioViewModel.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
import AppKit
import TagLibAudioMetadata

enum MetadataWriteHUDStyle: Equatable {
    case success
    case warning
    case failure
}

struct MetadataWriteHUD: Identifiable, Equatable {
    let id = UUID()
    let style: MetadataWriteHUDStyle
    let title: String
    let subtitle: String
    let summary: String
    let details: String

    init(style: MetadataWriteHUDStyle, title: String, subtitle: String,
         summary: String? = nil, details: String? = nil) {
        self.style = style
        self.title = title
        self.subtitle = subtitle
        let lines = subtitle.components(separatedBy: .newlines)
        self.summary = summary ?? lines.first ?? ""
        self.details = details ?? lines.dropFirst().joined(separator: "\n")
    }

    private var normalizedDetails: String {
        details.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewGroups: [String] {
        let groups = normalizedDetails.components(separatedBy: "\n\n")
        var shown: [String] = []
        for group in groups {
            let candidate = (shown + [group]).joined(separator: "\n\n")
            guard candidate.count <= 1000, candidate.components(separatedBy: .newlines).count <= 14 else { break }
            shown.append(group)
        }
        return shown
    }

    var detailPreview: String {
        if previewGroups.isEmpty {
            let lines = normalizedDetails.components(separatedBy: .newlines).prefix(14)
            return String(lines.joined(separator: "\n").prefix(1000))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return previewGroups.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasOmittedDetails: Bool {
        detailPreview != normalizedDetails
    }

    var omissionNotice: String {
        if previewGroups.isEmpty {
            return String(localized: "Additional detail characters not shown: \(max(0, normalizedDetails.count - detailPreview.count)).")
        }
        let omitted = normalizedDetails.components(separatedBy: "\n\n").dropFirst(previewGroups.count)
        let headings = omitted.prefix(3).map { group in
            let heading = group.components(separatedBy: .newlines).first ?? ""
            return String(heading.prefix(40)) + (heading.count > 40 ? "…" : "")
        }
        let remaining = omitted.count - headings.count
        var notice = String(localized: "Additional detail groups not shown: \(omitted.count). \(headings.joined(separator: "; "))")
        if remaining > 0 {
            notice += " " + String(localized: "And \(remaining) more groups.")
        }
        return notice
    }

    var displayDuration: Duration {
        switch style {
        case .success: return .seconds(3)
        case .warning: return .seconds(8)
        case .failure: return .seconds(10)
        }
    }
}

struct MetadataSaveProgress: Equatable {
    let title: String
    let subtitle: String
    let completedUnitCount: Int
    let totalUnitCount: Int

    var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }

    var progressLabel: String {
        "\(completedUnitCount) / \(totalUnitCount)"
    }
}

struct ConfirmedSelectionActionCapture: Sendable {
    let files: [AudioFile]
    let capturedSelectionIDs: Set<AudioFile.ID>
    let capturedSidebarSelection: SidebarSelection

    var isEmpty: Bool { files.isEmpty }
}

@MainActor
final class AudioViewModel: ObservableObject, LRCLIBLyricsWriting {
    nonisolated private static let readableAudioExtensions = AudioFormatSupport.readableExtensions
    nonisolated private static let maximumDirectoryMonitorsPerFolder = 128

    // All audio files currently loaded into the middle list.
    @Published var files: [AudioFile] = [] {
        didSet {
            filesRevision = UUID()
            visibleFilesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        }
    }
    private(set) var filesRevision = UUID()
    private var visibleFilesByID: [AudioFile.ID: AudioFile] = [:]
    @Published private(set) var watchedFolders: [WatchedFolder] = []
    // Current selection in the middle list. Single-file and multi-file inspector editing both use this selection.
    @Published private(set) var selectedAudioIDs: Set<UUID> = [] {
        didSet {
            if oldValue != selectedAudioIDs { lastAutomaticReloadFailures = [] }
        }
    }
    // Inspector edit models bound to the right-side inspector.
    @Published var editSourceFileID: UUID?
    @Published var edit: SingleFileEditModel? {
        didSet {
            if edit == nil {
                editSourceFileID = nil
            }
            if !isPublishingInspectorDraft {
                inspectorDraft?.noteEditMutation()
                noteInspectorArtworkActionChange(oldValue: oldValue?.artworkEditAction, newValue: edit?.artworkEditAction)
            }
            refreshInspectorArtworkPreview()
        }
    }
    @Published var multiEdit: MultiFileEditModel? {
        didSet {
            if !isPublishingInspectorDraft {
                inspectorDraft?.noteEditMutation()
                noteInspectorArtworkActionChange(
                    oldValue: oldValue?.artworkEditAction,
                    newValue: multiEdit?.artworkEditAction
                )
            }
            refreshInspectorArtworkPreview()
        }
    }
    /// Detached pending-review state for a dirty Inspector draft whose captured
    /// targets became unavailable. The draft payload stays published; selection
    /// stays pruned; Save is suspended until the user resumes or discards.
    @Published private(set) var inspectorPendingReview: InspectorPendingReview?
    /// Live draft identity/generations/baselines. Metadata only; payload remains
    /// `edit`/`multiEdit` so existing views and tests keep their bindings.
    private(set) var inspectorDraft: InspectorDraftSession?
    private var isPublishingInspectorDraft = false
    let inspectorArtworkPreview = InspectorArtworkPreview()
    private let inspectorArtworkComparisons = InspectorArtworkComparisonCache()
    @Published var metadataWriteHUD: MetadataWriteHUD?
    @Published var artworkLookupSession: ArtworkLookupSession?
    @Published var metadataSaveProgress: MetadataSaveProgress?
    var metadataSaveProgressToken: UUID?

    @Published var isReloadingSelectedFiles = false
    @Published private(set) var directoryMonitoringStatuses: [UUID: DirectoryMonitoringStatus] = [:]
    @Published private(set) var watchedFolderHierarchies: [UUID: WatchedFolderHierarchy] = [:]
    @Published private(set) var fileAccessGrants: [FileAccessGrant] = []
    @Published private(set) var bookmarkPersistenceWarnings: [String] = []

    private let watchedFolderStore: WatchedFolderStore
    private let fileAccessGrantStore: FileAccessGrantStore
    let conflictPolicyDefaults: UserDefaults
    let metadataPipeline: any AudioMetadataPipeline
    let saveIssueLogStore: SaveIssueLogStore
    let fileMutationCoordinator = FileMutationCoordinator()
    /// Per-file commit admission permits. See AudioViewModel+ReviewedMetadataWrite.
    let metadataCommitPermits = MetadataCommitPermitRegistry()
    let artworkLookupService: any iTunesArtworkServicing
    let artworkLookupOperationTimeout: Duration
    private var metadataWriteHUDDismissTask: Task<Void, Never>?
    var artworkLookupTask: Task<Void, Never>?
    private var pendingMetadataWriteHUDs: [MetadataWriteHUD] = []
    // The disk snapshots the current inspector drafts were created from. Keep
    // these separate from `files`, which can be refreshed while a draft is open.
    var inspectorEditSourceFilesByID: [UUID: AudioFile] = [:]
    // Successfully submitted intent per target, retained across a partial batch
    // failure so retrying does not reapply already handled conflicts.
    var completedInspectorEditsByID: [UUID: MultiFileEditModel] = [:]
    // Published ordered Quick Import rows. `quickImportBookkeeping.index` is the
    // parallel ordered index that owns row IDs, replacement tokens and scope
    // leases; the array stays the published projection of that order (F5).
    var quickImportFiles: [AudioFile] = []
    var quickImportFilesByID: [AudioFile.ID: AudioFile] = [:]
    var quickImportGeneration: UInt64 = 0
    var quickImportTasks: [UUID: Task<Void, Never>] = [:]
    var inFlightQuickImportTaskIDs: Set<UUID> = []
    var quickImportLoadingURLs: [UUID: [URL]] = [:]
    let quickImportEnvironment: QuickImportEnvironment
    var quickImportBookkeeping: QuickImportBookkeeping
    private var watchedFolderFiles: [UUID: [AudioFile]] = [:]
    private var watchedFolderRowOffsetsByFileID: [AudioFile.ID: [UUID: [Int]]] = [:]
    @Published var activeSidebarSelection: SidebarSelection = .quickImport
    // Session-wide stable-ID promise: selecting the same path again reuses the
    // existing UUID, including after remove/clear (documented in USER_GUIDE).
    var fileIDsByKey: [String: UUID] = [:]
    private var folderRescanTasks: [UUID: Task<Void, Never>] = [:]
    // One identity-aware reconciliation controller per watched folder. Each
    // controller owns that folder's descriptors; reconciliation itself runs off
    // the main actor. See AudioViewModel+... `DirectoryMonitorController`.
    private var folderDirectoryMonitors: [UUID: DirectoryMonitorController] = [:]
    private var publishedDirectoryMonitorGenerations: [UUID: UInt64] = [:]
    private var watchedFolderScanFailureCounts: [UUID: Int] = [:]
    private var watchedFolderMetadataReadFailureCounts: [UUID: Int] = [:]
    private var securityScopedFolderURLs: [UUID: URL] = [:]
    private var securityScopedFileAccessGrantURLs: [UUID: URL] = [:]
    private var folderScanTokens: [UUID: UUID] = [:]
    // Incremented when a committed mutation changes a file that belongs to a
    // watched folder. A rescan that started before the mutation must not
    // publish its older snapshot over the mutation's reload.
    private var watchedFolderMutationEpochs: [UUID: UInt64] = [:]
    private var nextFileModelRefreshGeneration: UInt64 = 0
    var appliedFileModelRefreshGenerations: [AudioFile.ID: UInt64] = [:]
    var pendingMetadataReloadsByID: [AudioFile.ID: (file: AudioFile, generation: UInt64)] = [:]
    // Recovery decisions outlive individual metadata observations. They are
    // cleared only through named FileRecoveryClearance transitions.
    var recoveryDecisionsByID: [AudioFile.ID: Set<FileRecoveryDecision>] = [:]

    // Durable rename-journal state (F2). Path-keyed blocks protect recorded
    // locations even when no session file ID is loaded; the presentation state is
    // rebuilt from read-only classification and never moves files by itself.
    let renameFileSystem: any RenameFileSystem
    let renameJournalStore: any RenameJournalStoring
    @Published var renameJournalRecovery: RenameJournalRecoveryState = .empty
    @Published var renameJournalActionInProgress: UUID?
    @Published private(set) var pendingReplacementFileReviews: [PendingReplacementFileReview] = []
    var renameJournalManifests: [RenameJournalManifest] = []
    var renameJournalPathBlocks: Set<String> = []
    var renameJournalOperationByPathKey: [String: UUID] = [:]
    var renameJournalFileIDsByOperation: [UUID: Set<AudioFile.ID>] = [:]
    var renameJournalClaimedFileIDs: [AudioFile.ID: UUID] = [:]
    var didPresentRenameJournalStartupWarning = false
    var renameJournalRefreshTask: Task<Void, Never>?
    var renameJournalRefreshGeneration: UInt64 = 0

    let moveReadbackTimeout: Duration
    var mutationDirectoryAccessRequester: ((URL) -> String?)?
    var lastMetadataProgressPublication = ContinuousClock.now

    convenience init() {
        self.init(
            watchedFolderStore: WatchedFolderStore(),
            fileAccessGrantStore: FileAccessGrantStore(),
            metadataPipeline: TagLibAudioMetadataPipeline(),
            saveIssueLogStore: SaveIssueLogStore()
        )
    }

    init(
        watchedFolderStore: WatchedFolderStore,
        fileAccessGrantStore: FileAccessGrantStore,
        metadataPipeline: any AudioMetadataPipeline,
        saveIssueLogStore: SaveIssueLogStore,
        artworkLookupService: any iTunesArtworkServicing = iTunesArtworkService(),
        artworkLookupOperationTimeout: Duration = .seconds(30),
        conflictPolicyDefaults: UserDefaults = .standard,
        moveReadbackTimeout: Duration = .seconds(60),
        renameFileSystem: any RenameFileSystem = LocalRenameFileSystem(),
        renameJournalStore: any RenameJournalStoring = AudioViewModel.defaultRenameJournalStore(),
        renameJournalAutoClassification: Bool = true,
        quickImportEnvironment: QuickImportEnvironment = .production
    ) {
        self.watchedFolderStore = watchedFolderStore
        self.fileAccessGrantStore = fileAccessGrantStore
        self.metadataPipeline = metadataPipeline
        self.conflictPolicyDefaults = conflictPolicyDefaults
        self.saveIssueLogStore = saveIssueLogStore
        self.artworkLookupService = artworkLookupService
        self.artworkLookupOperationTimeout = artworkLookupOperationTimeout
        self.moveReadbackTimeout = moveReadbackTimeout
        self.renameFileSystem = renameFileSystem
        self.renameJournalStore = renameJournalStore
        self.quickImportEnvironment = quickImportEnvironment
        self.quickImportBookkeeping = QuickImportBookkeeping(environment: quickImportEnvironment)

        let restoredFolders = watchedFolderStore.loadFolders()
        self.watchedFolders = restoredFolders

        let restoredFileAccessGrants = fileAccessGrantStore.loadGrants()
        self.fileAccessGrants = restoredFileAccessGrants

        if watchedFolderStore.loadState == .corrupt {
            bookmarkPersistenceWarnings.append(
                String(localized: "Your watched folder list couldn’t be loaded. The saved list has been kept and won’t be overwritten.")
            )
        }
        if fileAccessGrantStore.loadState == .corrupt {
            bookmarkPersistenceWarnings.append(
                String(localized: "Your saved folder permissions couldn’t be loaded. The saved records have been kept and won’t be overwritten.")
            )
        }

        for grant in restoredFileAccessGrants {
            beginAccessingFileAccessGrant(grant)
        }

        // Read-only journal bootstrap after authorized folders are available and
        // before scans/mutations can publish. Loading manifests installs
        // path-keyed blocks immediately; classification is deferred and never
        // moves files.
        bootstrapRenameJournalRecovery(scheduleClassification: renameJournalAutoClassification)

        for folder in restoredFolders {
            beginAccessingWatchedFolder(folder)
            startDirectoryMonitoring(for: folder)
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }

        rebuildVisibleFiles()
    }

    deinit {
        artworkImportTask?.cancel()
        artworkLookupTask?.cancel()
        metadataWriteHUDDismissTask?.cancel()
        renameJournalRefreshTask?.cancel()
        quickImportTasks.values.forEach { $0.cancel() }
        folderRescanTasks.values.forEach { $0.cancel() }
        folderDirectoryMonitors.values.forEach { $0.stop() }
        folderDirectoryMonitors.removeAll()
        publishedDirectoryMonitorGenerations.removeAll()
        securityScopedFolderURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
        quickImportBookkeeping.leases.releaseAll()
        securityScopedFileAccessGrantURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var currentFileSourceMode: FileSourceMode {
        normalizedSidebarSelection(activeSidebarSelection).sourceMode
    }

    var activeQuickImportTaskCount: Int {
        inFlightQuickImportTaskIDs.count
    }

    var hasUnsavedInspectorChanges: Bool {
        if inspectorPendingReview != nil { return true }
        if selectedAudioIDs.count > 1 {
            guard let multiEdit else { return false }
            return selectedAudioIDs.contains { id in
                guard let source = inspectorDraft?.baselinesByID[id]
                    ?? inspectorEditSourceFilesByID[id]
                    ?? files.first(where: { $0.id == id }) else { return true }
                return multiEdit.hasPendingChanges(comparedTo: source, excluding: completedInspectorEditsByID[id])
            }
        }

        guard
            selectedAudioIDs.count == 1,
            let id = selectedAudioIDs.first,
            let sourceFile = inspectorDraft?.baselinesByID[id]
                ?? inspectorEditSourceFilesByID[id]
                ?? files.first(where: { $0.id == id }),
            let edit,
            editSourceFileID == id
        else {
            return false
        }

        return edit.hasUnsavedChanges(comparedTo: sourceFile)
    }

    /// Draft-payload dirtiness independent of the current selection, so a
    /// passive prune can detect captured edits after selection was already
    /// pruned for the visible collection.
    private var isInspectorDraftPayloadDirty: Bool {
        guard let session = inspectorDraft else { return false }
        if session.pendingReview != nil { return true }
        if session.targetIDs.count > 1 {
            guard let multiEdit else { return false }
            return session.targetIDs.contains { id in
                guard let source = session.baselinesByID[id] else { return true }
                return multiEdit.hasPendingChanges(
                    comparedTo: source,
                    excluding: session.completedByID[id]
                )
            }
        }
        guard let id = session.targetIDs.first,
              editSourceFileID == id,
              let edit,
              let source = session.baselinesByID[id] else { return false }
        return edit.hasUnsavedChanges(comparedTo: source)
    }

    var hasInspectorPendingReview: Bool {
        inspectorPendingReview != nil
    }

    var isInspectorSaveSuspended: Bool {
        inspectorPendingReview != nil || inspectorDraft?.isSaveInFlight == true
    }

    var inspectorDraftIdentity: InspectorDraftIdentity? {
        inspectorDraft?.identity
    }

    var isInspectorDraftDirty: Bool {
        guard inspectorPendingReview == nil, inspectorDraft != nil else {
            return inspectorPendingReview != nil
        }
        return hasUnsavedInspectorChanges
    }

    func setSidebarSelection(_ selection: SidebarSelection?) {
        let normalized = normalizedSidebarSelection(selection ?? .quickImport)
        if activeSidebarSelection != normalized {
            activeSidebarSelection = normalized
        }
        rebuildVisibleFiles()
    }

    func watchedFolderHierarchy(for folderID: UUID) -> WatchedFolderHierarchy? {
        watchedFolderHierarchies[folderID]
    }

    func watchedSubfolderNode(rootFolderID: UUID, relativePathKey: String) -> WatchedFolderNode? {
        watchedFolderHierarchies[rootFolderID]?.node(forRelativePathKey: relativePathKey)
    }

    // MARK: - Selection and Edit Sync

    var selectedFiles: [AudioFile] {
        if selectedAudioIDs.count == 1, let id = selectedAudioIDs.first {
            return visibleFilesByID[id].map { [$0] } ?? []
        }
        guard !selectedAudioIDs.isEmpty else { return [] }
        return files.filter { selectedAudioIDs.contains($0.id) }
    }

    /// Explicit selection-synchronization seam. Retained for ContentPane's
    /// confirmed discard-and-reload path and for tests; production draft
    /// publications use the named operations below instead.
    func updateEditForSelection() {
        beginInspectorDraftSessionForCurrentSelection(reason: .explicitSelectionSync)
    }

    func setSelectedAudioIDs(_ selection: Set<AudioFile.ID>) {
        let normalizedSelection = selection.filter { visibleFilesByID[$0] != nil }
        guard normalizedSelection != selectedAudioIDs else { return }

        selectedAudioIDs = normalizedSelection
        beginInspectorDraftSessionForCurrentSelection(reason: .selectionTransition)
    }

    /// Discard the current edits (including a detached pending review) and
    /// restore the latest tags from disk. The Inspector keeps a clean draft for
    /// the current selection so its rows still reflect the file.
    func cancelEditing() {
        discardInspectorDraft(reason: .explicitUserAction)
        beginInspectorDraftSessionForCurrentSelection(reason: .explicitSelectionSync)
    }

    // MARK: - Inspector draft session lifecycle (F3-b)

    /// Clean refresh after an accepted external publication. Never discards a
    /// dirty or pending draft; a no-op unless the draft still represents the
    /// current selection and has no unsaved changes.
    func refreshInspectorDraftAfterAcceptedPublication() {
        guard inspectorPendingReview == nil,
              let session = inspectorDraft,
              !session.isSaveInFlight,
              Set(session.targetIDs) == selectedAudioIDs,
              !hasUnsavedInspectorChanges else { return }
        reconstructInspectorDraft(
            preservingSessionID: session.id,
            baselines: selectedFiles,
            reason: .cleanRefresh
        )
    }

    /// Rebuilds a new draft session for the current selection. Used by explicit
    /// selection transitions and tests; the old payload is discarded.
    private func beginInspectorDraftSessionForCurrentSelection(reason: InspectorDraftReconstructionReason) {
        artworkImportTask?.cancel()
        let baselines = selectedFiles
        reconstructInspectorDraft(preservingSessionID: nil, baselines: baselines, reason: reason)
    }

    /// The only place that changes `edit`/`multiEdit` payload shape. Views and
    /// completion paths mutate field values; this rebuilds the models.
    private func reconstructInspectorDraft(
        preservingSessionID: InspectorDraftSessionID?,
        baselines: [AudioFile],
        reason: InspectorDraftReconstructionReason
    ) {
        isPublishingInspectorDraft = true
        defer { isPublishingInspectorDraft = false }

        completedInspectorEditsByID = [:]
        if baselines.isEmpty {
            edit = nil
            editSourceFileID = nil
            multiEdit = nil
            inspectorEditSourceFilesByID = [:]
            inspectorDraft = nil
            inspectorPendingReview = nil
            return
        }

        let baselinesByID = Dictionary(uniqueKeysWithValues: baselines.map { ($0.id, $0) })
        inspectorEditSourceFilesByID = baselinesByID
        let targetIDs = baselines.map(\.id)
        if preservingSessionID != nil, var session = inspectorDraft {
            session.baselinesByID = baselinesByID
            session.setTargets(targetIDs, baselines: baselinesByID)
            if reason == .cleanRefresh {
                // Clean refresh on an untouched selection updates displayed
                // baselines without cancelling an in-flight artwork handoff.
                session.advanceEditGenerationOnly()
            } else {
                session.advanceGenerationAfterTransition()
            }
            inspectorDraft = session
            inspectorPendingReview = nil
        } else {
            inspectorDraft = InspectorDraftSession(targetIDs: targetIDs, baselinesByID: baselinesByID)
            inspectorPendingReview = nil
        }

        if baselines.count == 1, let file = baselines.first {
            inspectorDraft?.noteEditMutation()
            edit = SingleFileEditModel(from: file)
            editSourceFileID = file.id
            multiEdit = nil
            return
        }

        edit = nil
        editSourceFileID = nil
        multiEdit = MultiFileEditModel(
            files: baselines,
            artworkState: inspectorArtworkComparisons.resolve(baselines)
        )
    }

    /// Detached pending-review session for captured targets that disappeared
    /// from every source membership. The draft payload and baselines are kept;
    /// selection is pruned by the caller; Save stays suspended.
    private func enterInspectorPendingReview(unavailableTargetIDs: Set<UUID>) {
        guard var session = inspectorDraft else { return }
        let missing = Set(session.targetIDs.filter { committedFile(withID: $0) == nil })
        let review = InspectorPendingReview(
            identity: session.identity,
            capturedTargetIDs: session.targetIDs,
            unavailableTargetIDs: unavailableTargetIDs.union(missing),
            reason: .targetsBecameUnavailable
        )
        session.pendingReview = review
        inspectorDraft = session
        inspectorPendingReview = review
        // Keep the published payload unchanged so the review is inspectable.
        inspectorEditSourceFilesByID = session.baselinesByID
        completedInspectorEditsByID = session.completedByID
    }

    var isInspectorPendingReviewResumable: Bool {
        guard let session = inspectorDraft, session.pendingReview != nil else { return false }
        return session.targetIDs.allSatisfy { id in
            committedFile(withID: id) != nil && visibleFilesByID[id] != nil
        }
    }

    /// Resumes the captured draft while preserving its original conflict
    /// baselines. Only the original captured target IDs are restored; values are
    /// never transferred to surviving/new targets, and a same-path replacement
    /// stays subject to ordinary conflict and audio-identity checks on Save.
    @discardableResult
    func resumeInspectorPendingReview() -> Bool {
        guard let session = inspectorDraft,
              session.pendingReview != nil,
              isInspectorPendingReviewResumable else { return false }
        let capturedTargets = session.targetIDs.compactMap { visibleFilesByID[$0] }
        guard capturedTargets.count == session.targetIDs.count else { return false }

        selectedAudioIDs = Set(session.targetIDs).filter { visibleFilesByID[$0] != nil }
        // Preserve the original captured conflict baselines so a same-path
        // replacement at the resumed UUID cannot bypass MetadataConflictResolver.
        inspectorEditSourceFilesByID = session.baselinesByID
        var resumed = session
        resumed.pendingReview = nil
        resumed.noteEditMutation()
        inspectorDraft = resumed
        inspectorPendingReview = nil
        completedInspectorEditsByID = resumed.completedByID
        return true
    }

    func captureInspectorDiscardConfirmationToken() -> InspectorDiscardConfirmationToken {
        InspectorDiscardConfirmationToken(
            hadUnsavedChanges: hasUnsavedInspectorChanges,
            draftIdentity: inspectorDraft?.identity,
            pendingReviewSessionID: inspectorPendingReview?.identity.sessionID
        )
    }

    func isInspectorDiscardConfirmationCurrent(_ token: InspectorDiscardConfirmationToken) -> Bool {
        if !token.hadUnsavedChanges {
            // The confirmation opened while the Inspector was clean: any edit or
            // async artwork handoff that made the draft dirty since then was
            // never approved for discard.
            return !hasUnsavedInspectorChanges
        }
        guard hasUnsavedInspectorChanges else { return true }
        return inspectorDraft?.identity == token.draftIdentity
            && inspectorPendingReview?.identity.sessionID == token.pendingReviewSessionID
    }

    /// Frozen selection snapshot captured when a destructive confirmation dialog
    /// (Erase All Tags or Create MuseAmp IDs) opens so affirmation acts only on
    /// the exact reviewed file observations the user approved.
    func captureConfirmedSelectionAction() -> ConfirmedSelectionActionCapture {
        ConfirmedSelectionActionCapture(
            files: selectedFiles,
            capturedSelectionIDs: selectedAudioIDs,
            capturedSidebarSelection: normalizedSidebarSelection(activeSidebarSelection)
        )
    }

    func executeConfirmedEraseAllMetadata(_ capture: ConfirmedSelectionActionCapture) {
        guard !capture.isEmpty else { return }
        eraseAllMetadata(capture.files)
    }

    func executeConfirmedCreateMuseAmpIDs(_ capture: ConfirmedSelectionActionCapture) {
        guard !capture.isEmpty else { return }
        createMuseAmpIDs(for: capture.files)
    }

    func removingWatchedFoldersAffectsUnsavedInspectorEdits(ids: Set<UUID>) -> Bool {
        guard hasUnsavedInspectorChanges, let session = inspectorDraft else { return false }
        let targetIDs = Set(session.targetIDs)
        var removedFileIDs: Set<UUID> = []
        for folderID in ids {
            if let folderFiles = watchedFolderFiles[folderID] {
                removedFileIDs.formUnion(folderFiles.map(\.id))
            }
        }
        return !targetIDs.isDisjoint(with: removedFileIDs)
    }

    func discardInspectorPendingReview() {
        discardInspectorDraft(reason: .pendingReviewDiscard)
        beginInspectorDraftSessionForCurrentSelection(reason: .explicitSelectionSync)
    }

    private func discardInspectorDraft(reason: InspectorDraftDiscardReason) {
        artworkImportTask?.cancel()
        isPublishingInspectorDraft = true
        defer { isPublishingInspectorDraft = false }
        edit = nil
        editSourceFileID = nil
        multiEdit = nil
        inspectorEditSourceFilesByID = [:]
        completedInspectorEditsByID = [:]
        inspectorDraft = nil
        inspectorPendingReview = nil
    }

    /// Captures the Inspector save intent before work starts. Returns nil when
    /// Save is suspended (pending review, replacement session, no dirty draft).
    func captureInspectorSaveReceipt() -> InspectorSaveReceipt? {
        guard inspectorPendingReview == nil,
              var session = inspectorDraft,
              !session.isSaveInFlight,
              Set(session.targetIDs) == selectedAudioIDs,
              hasUnsavedInspectorChanges else { return nil }

        var submittedByID: [UUID: SingleFileEditModel] = [:]
        for targetID in session.targetIDs {
            guard let baseline = session.baselinesByID[targetID] else { continue }
            if selectedAudioIDs.count > 1, let multiEdit {
                submittedByID[targetID] = multiEdit.applyingChanges(
                    to: baseline,
                    excluding: completedInspectorEditsByID[targetID]
                )
            } else if let edit {
                submittedByID[targetID] = edit
            }
        }
        let receipt = InspectorSaveReceipt(
            identity: session.identity,
            targetIDs: session.targetIDs,
            submittedSingleEdit: selectedAudioIDs.count == 1 ? edit : nil,
            submittedMultiEdit: selectedAudioIDs.count > 1 ? multiEdit : nil,
            submittedEditsByID: submittedByID,
            baselinesByID: session.baselinesByID
        )
        session.saveReceipt = receipt
        inspectorDraft = session
        return receipt
    }

    /// Records one target's captured save outcome. Successful reads advance the
    /// per-field baseline and reapplied newer edits; an unavailable readback
    /// never fabricates a baseline.
    func recordInspectorSaveTargetCompletion(_ outcome: InspectorSavedTargetOutcome) {
        guard var session = inspectorDraft,
              let receipt = session.saveReceipt,
              receipt.identity.sessionID == session.id,
              receipt.targetIDs.contains(outcome.targetID),
              receipt.baselinesByID[outcome.targetID] != nil else { return }

        if outcome.didRefreshFileModel,
           let readback = outcome.readback,
           readback.id == outcome.targetID {
            session.baselinesByID[outcome.targetID] = readback
            inspectorEditSourceFilesByID[outcome.targetID] = readback
            session.unverifiedReadbackIDs.remove(outcome.targetID)
            if receipt.submittedMultiEdit != nil {
                if let submittedMultiEdit = receipt.submittedMultiEdit {
                    session.completedByID[outcome.targetID] = submittedMultiEdit
                }
            }
            inspectorDraft = session
            completedInspectorEditsByID = session.completedByID
            // Single-file own-save applies the per-field readback delta to the
            // live draft. Multi-file batches advance baselines and the
            // completed-target ledger only; the shared merged payload keeps the
            // pending targets' intent until every captured target completes.
            if receipt.targetIDs.count == 1 {
                applyInspectorReadbackToLiveDraft(
                    targetID: outcome.targetID,
                    readback: readback,
                    receipt: receipt,
                    session: session
                )
            }
        } else {
            session.unverifiedReadbackIDs.insert(outcome.targetID)
            inspectorDraft = session
        }
    }

    private func applyInspectorReadbackToLiveDraft(
        targetID: UUID,
        readback: AudioFile,
        receipt: InspectorSaveReceipt,
        session: InspectorDraftSession
    ) {
        guard receipt.identity.sessionID == inspectorDraft?.id else { return }
        isPublishingInspectorDraft = true
        defer { isPublishingInspectorDraft = false }

        if receipt.targetIDs.count == 1,
           let live = edit,
           let submitted = receipt.submittedSingleEdit {
            edit = InspectorDraftDelta.reappliedSingleDraft(
                live: live,
                submitted: submitted,
                readback: readback
            )
            editSourceFileID = targetID
            return
        }

        guard let live = multiEdit,
              let submitted = receipt.submittedMultiEdit else { return }
        let files = session.targetIDs.compactMap { session.baselinesByID[$0] }
        guard files.count == session.targetIDs.count else { return }
        multiEdit = InspectorDraftDelta.reappliedMultiDraft(
            readbackFiles: files,
            live: live,
            submitted: submitted,
            artworkState: inspectorArtworkComparisons.resolve(files)
        )
    }

    /// Ends an Inspector save capture. The caller has recorded every outcome.
    /// When a multi-file batch finishes with verified readbacks across all
    /// targets, reapplies any newer live edits onto the verified readbacks so
    /// normalized values and artwork states stay synchronized.
    func finishInspectorSave(didCompleteAllMultiTargets: Bool = false) {
        guard var session = inspectorDraft else { return }
        let receipt = session.saveReceipt
        if didCompleteAllMultiTargets,
           let receipt,
           receipt.targetIDs.count > 1,
           session.unverifiedReadbackIDs.isEmpty,
           let representativeID = receipt.targetIDs.first,
           let representativeReadback = session.baselinesByID[representativeID] {
            session.completedByID = [:]
            completedInspectorEditsByID = [:]
            inspectorDraft = session
            applyInspectorReadbackToLiveDraft(
                targetID: representativeID,
                readback: representativeReadback,
                receipt: receipt,
                session: session
            )
            session = inspectorDraft ?? session
        }
        session.saveReceipt = nil
        inspectorDraft = session
        if !session.unverifiedReadbackIDs.isEmpty, hasUnsavedInspectorChanges {
            // Keep the live draft; the caller reports the reload warning.
        }
    }

    // MARK: - Artwork command generation (N4b hook points)

    /// Begins an independent artwork command for the current draft. N4b consumes
    /// this token at the async handoff; editing another field preserves it.
    func beginArtworkCommand(for targetIDs: [UUID]? = nil) -> ArtworkCommandToken? {
        guard var session = inspectorDraft,
              inspectorPendingReview == nil,
              !session.isSaveInFlight else { return nil }
        let requestedIDs = targetIDs ?? session.targetIDs
        guard Set(requestedIDs) == Set(session.targetIDs) else { return nil }
        let identity = session.noteArtworkCommand()
        inspectorDraft = session
        return ArtworkCommandToken(
            sessionID: identity.sessionID,
            artworkGeneration: identity.artworkGeneration,
            targetIDs: identity.targetIDs
        )
    }

    func isCurrentArtworkCommand(_ token: ArtworkCommandToken) -> Bool {
        guard let session = inspectorDraft, inspectorPendingReview == nil else { return false }
        return session.id == token.sessionID
            && session.artworkGeneration == token.artworkGeneration
            && Set(session.targetIDs) == Set(token.targetIDs)
    }

    /// Guarded staging boundary for artwork handoffs. Returns false for a stale
    /// command/session; callers report a localized stale-selection message.
    @discardableResult
    func completeArtworkHandoff(
        _ token: ArtworkCommandToken,
        action: ArtworkEditAction
    ) -> Bool {
        guard isCurrentArtworkCommand(token) else { return false }
        isPublishingInspectorDraft = true
        defer { isPublishingInspectorDraft = false }
        if selectedAudioIDs.count == 1, var current = edit {
            current.artworkEditAction = action
            edit = current
        } else if var current = multiEdit {
            current.setArtworkEditAction(action)
            multiEdit = current
        } else {
            return false
        }
        return true
    }

    private func noteInspectorArtworkActionChange(
        oldValue: ArtworkEditAction?,
        newValue: ArtworkEditAction?
    ) {
        guard oldValue != newValue,
              newValue != nil,
              var session = inspectorDraft else { return }
        _ = session.noteArtworkCommand()
        inspectorDraft = session
    }

    /// Human-readable captured values for the pending-review inspection sheet.
    func inspectorPendingReviewCapturedSummaries() -> [(fileName: String, values: [String])] {
        guard let session = inspectorDraft, session.pendingReview != nil else { return [] }
        return session.targetIDs.map { targetID in
            let fileName = session.baselinesByID[targetID]?.url.lastPathComponent
                ?? committedFile(withID: targetID)?.url.lastPathComponent
                ?? targetID.uuidString
            var values: [String] = []
            if let baseline = session.baselinesByID[targetID] {
                let submitted = session.saveReceipt?.submittedEditsByID[targetID]
                let effective: SingleFileEditModel
                if let editSourceFileID, editSourceFileID == targetID, let edit {
                    effective = edit
                } else if let multiEdit {
                    effective = multiEdit.applyingChanges(
                        to: baseline,
                        excluding: session.completedByID[targetID]
                    )
                } else if let submitted {
                    effective = submitted
                } else {
                    effective = SingleFileEditModel(from: baseline)
                }
                let submission = session.saveReceipt?.submittedEditsByID[targetID]
                    ?? SingleFileEditModel(from: baseline)
                values = Self.changedFieldSummaries(
                    live: effective,
                    submitted: submission,
                    baseline: baseline
                )
            }
            return (fileName, values)
        }
    }

    private static func changedFieldSummaries(
        live: SingleFileEditModel,
        submitted: SingleFileEditModel,
        baseline: AudioFile
    ) -> [String] {
        var lines: [String] = []
        let baselineModel = SingleFileEditModel(from: baseline)
        let pairs: [(String, String, String)] = [
            ("Title", live.title, baselineModel.title),
            ("Artist", live.artist, baselineModel.artist),
            ("Album", live.album, baselineModel.album),
            ("Album Artist", live.albumArtist, baselineModel.albumArtist),
            ("Composer", live.composer, baselineModel.composer),
            ("Genre", live.genre, baselineModel.genre),
            ("Comment", live.comment, baselineModel.comment),
            ("Year", live.year, baselineModel.year),
            ("Date", live.date, baselineModel.date),
            ("Track", live.trackNumberFieldText, baselineModel.trackNumberFieldText),
            ("Track Total", live.trackTotalFieldText, baselineModel.trackTotalFieldText),
            ("Disc", live.discNumberFieldText, baselineModel.discNumberFieldText),
            ("Disc Total", live.discTotalFieldText, baselineModel.discTotalFieldText)
        ]
        for (label, liveValue, baseValue) in pairs where liveValue != baseValue {
            lines.append("\(label): \(liveValue)")
        }
        if live.artworkEditAction != baselineModel.artworkEditAction {
            lines.append(String(localized: "Artwork: changed"))
        }
        return lines
    }

    func presentMetadataWriteHUD(
        style: MetadataWriteHUDStyle,
        title: String,
        subtitle: String,
        summary: String? = nil,
        details: String? = nil
    ) {
        enqueueMetadataWriteHUD(
            style: style,
            title: title,
            subtitle: subtitle,
            summary: summary,
            details: details
        )
    }

    func presentMetadataWriteSuccess(for fileName: String) {
        presentMetadataWriteHUD(
            style: .success,
            title: "Saved to Disk",
            subtitle: fileName,
            summary: fileName,
            details: ""
        )
    }

    func presentMetadataWriteWarning(
        title: String,
        fileName: String,
        warnings: [String],
        operation: BatchMetadataOperationKind = .write
    ) {
        let details = warnings.joined(separator: "\n")
        let subtitle = fileName + "\n" + details
        saveIssueLogStore.recordSingleIssue(
            title: title, subtitle: subtitle, fileName: fileName,
            messages: warnings, severity: .warning, operation: operation
        )
        presentMetadataWriteHUD(style: .warning, title: title, subtitle: subtitle,
                                summary: fileName, details: details)
    }

    func presentMetadataWriteFailure(
        for fileName: String, reason: String,
        title: String = String(localized: "Changes Couldn’t Be Saved"),
        operation: BatchMetadataOperationKind = .write
    ) {
        if MetadataCancellation.isMessage(reason) {
            presentMetadataWriteHUD(style: .warning, title: String(localized: "Operation Cancelled"),
                                    subtitle: fileName + "\n" + reason, summary: fileName, details: reason)
            return
        }
        let subtitle = [fileName, reason]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        saveIssueLogStore.recordSingleIssue(
            title: title,
            subtitle: subtitle,
            fileName: fileName,
            messages: [reason],
            severity: .failure,
            operation: operation
        )

        presentMetadataWriteHUD(
            style: .failure,
            title: title,
            subtitle: subtitle,
            summary: fileName,
            details: reason
        )
    }

    private func enqueueMetadataWriteHUD(
        style: MetadataWriteHUDStyle,
        title: String,
        subtitle: String,
        summary: String? = nil,
        details: String? = nil
    ) {
        let hud = MetadataWriteHUD(
            style: style,
            title: title,
            subtitle: subtitle,
            summary: summary,
            details: details
        )
        pendingMetadataWriteHUDs.append(hud)

        guard metadataWriteHUD == nil else { return }
        showNextMetadataWriteHUD()
    }

    private func showNextMetadataWriteHUD() {
        guard metadataWriteHUD == nil, !pendingMetadataWriteHUDs.isEmpty else { return }

        metadataWriteHUDDismissTask?.cancel()

        let hud = pendingMetadataWriteHUDs.removeFirst()
        metadataWriteHUD = hud

        metadataWriteHUDDismissTask = Task { [weak self, hudID = hud.id] in
            try? await Task.sleep(for: hud.displayDuration)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.metadataWriteHUD?.id == hudID else { return }
                self.metadataWriteHUD = nil
            }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.showNextMetadataWriteHUD()
            }
        }
    }

    @discardableResult
    func addWatchedFolders() -> SidebarSelection? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.title = "Choose Folders to Watch"
        panel.prompt = "Watch"
        panel.message = "AudioMator will keep these folders in the sidebar and refresh them when their contents change."

        guard panel.runModal() == .OK else { return nil }

        var addedFolders: [WatchedFolder] = []
        var failedFolderNames: [String] = []
        var duplicateSelection: SidebarSelection?
        var seenFolderKeys = Set<String>()
        var existingFoldersByKey: [String: WatchedFolder] = [:]
        for folder in watchedFolders where existingFoldersByKey[Self.urlKey(for: folder.url)] == nil {
            existingFoldersByKey[Self.urlKey(for: folder.url)] = folder
        }

        for url in panel.urls {
            let key = Self.urlKey(for: url)
            guard seenFolderKeys.insert(key).inserted else { continue }

            if let existingFolder = existingFoldersByKey[key] {
                duplicateSelection = .watchedFolder(existingFolder.id)
                continue
            }

            do {
                let folder = try watchedFolderStore.makeFolder(from: url)
                addedFolders.append(folder)
            } catch {
                failedFolderNames.append(FileManager.default.displayName(atPath: url.path))
            }
        }

        if !failedFolderNames.isEmpty {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Folder Not Added"),
                subtitle: Self.watchedFolderAccessFailureMessage(for: failedFolderNames)
            )
        }

        guard !addedFolders.isEmpty else {
            return duplicateSelection ?? .watchedLibrary
        }

        watchedFolders.append(contentsOf: addedFolders)
        guard persistWatchedFolders() else {
            let addedIDs = Set(addedFolders.map(\.id))
            watchedFolders.removeAll { addedIDs.contains($0.id) }
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Folder Not Added"),
                subtitle: String(localized: "The saved folder records couldn't be read. AudioMator has kept the original records without overwriting them.")
            )
            return duplicateSelection ?? .watchedLibrary
        }

        for folder in addedFolders {
            beginAccessingWatchedFolder(folder)
            startDirectoryMonitoring(for: folder)
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }

        rebuildVisibleFiles()

        if addedFolders.count == 1, let folder = addedFolders.first {
            return .watchedFolder(folder.id)
        }

        return .watchedLibrary
    }

    nonisolated static func watchedFolderAccessFailureMessage(for displayNames: [String]) -> String {
        guard let firstName = displayNames.first else { return "" }
        if displayNames.count == 1 {
            return String(localized: "Access to “\(firstName)” couldn’t be saved for future use.")
        }
        return String(localized: "Access to \(displayNames.count) selected folders couldn’t be saved for future use.")
    }

    func removeWatchedFolder(id: UUID) {
        removeWatchedFolders(ids: [id])
    }

    func removeWatchedFolders(ids: Set<UUID>) {
        let existingIDs = ids.intersection(watchedFolders.map(\.id))
        guard !existingIDs.isEmpty else { return }

        let removedFileIDs = Set(existingIDs.flatMap { watchedFolderFiles[$0]?.map(\.id) ?? [] })
        for id in existingIDs {
            stopWatchingFolder(id: id)
            setWatchedFolderFiles(nil, for: id)
            watchedFolderHierarchies[id] = nil
            watchedFolderScanFailureCounts[id] = nil
            watchedFolderMetadataReadFailureCounts[id] = nil
            folderScanTokens[id] = nil
            watchedFolderMutationEpochs[id] = nil
            publishedDirectoryMonitorGenerations[id] = nil
        }
        watchedFolders.removeAll { existingIDs.contains($0.id) }

        persistWatchedFolders()
        revokeCommitPermitsForRemovedSourceFiles(removedFileIDs)
        prunePendingReplacementFileReviews(removingIDs: removedFileIDs)

        let resolvedSelection = normalizedSidebarSelection(activeSidebarSelection)
        if activeSidebarSelection != resolvedSelection {
            activeSidebarSelection = resolvedSelection
        }
        rebuildVisibleFiles()
    }

    func replaceLoadedFile(_ reloaded: AudioFile) {
        replaceLoadedFile(reloaded, refreshGeneration: makeFileModelRefreshGeneration())
    }

    private func applyingRecoveryProjection(_ file: AudioFile) -> AudioFile {
        guard hasRecoveryDecision(for: file.id) else { return file }
        return file.projectingRecoveryState()
    }

    func hasRecoveryDecision(for id: AudioFile.ID) -> Bool {
        !(recoveryDecisionsByID[id]?.isEmpty ?? true)
    }

    func recoveryDecision(for id: AudioFile.ID) -> FileRecoveryDecision? {
        recoveryDecisionsByID[id]?.first
    }

    func hasJournalRecoveryDecision(for id: AudioFile.ID) -> Bool {
        recoveryDecisionsByID[id]?.contains { decision in
            if case .journalPending = decision { return true }
            return false
        } ?? false
    }

    func makePendingReplacementFileReviewIfNeeded(for file: AudioFile) -> PendingReplacementFileReview? {
        guard let decisions = recoveryDecisionsByID[file.id],
              !decisions.isEmpty,
              !hasJournalRecoveryDecision(for: file.id),
              let target = ReviewedMetadataTarget(verified: file),
              target.fingerprint.fileNumber != nil,
              target.fingerprint.fileSystemNumber != nil else { return nil }
        return PendingReplacementFileReview(
            target: target,
            recoveryDecisions: decisions,
            title: file.title,
            artist: file.artist,
            album: file.album
        )
    }

    func setPendingReplacementFileReviews(_ reviews: [PendingReplacementFileReview]) {
        pendingReplacementFileReviews = reviews
    }

    func dismissPendingReplacementFileReviews(_ reviews: [PendingReplacementFileReview]) {
        guard pendingReplacementFileReviews == reviews else { return }
        setPendingReplacementFileReviews([])
    }

    func isReplacementFileReviewCurrent(_ review: PendingReplacementFileReview) -> Bool {
        guard let current = committedFile(withID: review.fileID),
              review.target.associates(with: current),
              recoveryDecisionsByID[review.fileID] == review.recoveryDecisions,
              !isRenameJournalBlocked(url: review.url) else { return false }
        return true
    }

    func prunePendingReplacementFileReviews(removingIDs ids: Set<AudioFile.ID>) {
        guard !pendingReplacementFileReviews.isEmpty, !ids.isEmpty else { return }
        let remainingCommittedIDs = committedSourceFileIDs()
        pendingReplacementFileReviews.removeAll { review in
            ids.contains(review.fileID) && !remainingCommittedIDs.contains(review.fileID)
        }
    }

    /// All observations, including scans, must be accepted before publication.
    ///
    /// Quick Import passes the candidate identity it already verified off the main
    /// actor, so journal matching and publication add no path-key work.
    func acceptFileObservation(
        _ file: AudioFile,
        generation: UInt64,
        clearing: FileRecoveryClearance? = nil,
        pathIdentity: QuickImportPathIdentity? = nil
    ) -> AudioFile? {
        guard generation > (appliedFileModelRefreshGenerations[file.id] ?? 0) else { return nil }
        appliedFileModelRefreshGenerations[file.id] = generation
        pendingMetadataReloadsByID.removeValue(forKey: file.id)
        if let clearing, let observation = file.observation {
            clearRecoveryDecisions(for: file.id, clearing: clearing, observation: observation)
        }
        if let pathIdentity {
            attachRenameJournalDecisionIfNeeded(
                fileID: file.id,
                reservationKeys: pathIdentity.reservationKeys
            )
        } else {
            attachRenameJournalDecisionIfNeeded(fileID: file.id, url: file.url)
        }
        let accepted = applyingRecoveryProjection(file)
        revokeCommitPermitsIfObservationIncompatible(accepted)
        return accepted
    }

    func makeFileModelRefreshGeneration() -> UInt64 {
        nextFileModelRefreshGeneration &+= 1
        return nextFileModelRefreshGeneration
    }

    /// Accepted-observation generation for one file.
    ///
    /// Display and recovery projections create a new `snapshotID`, so a late
    /// reload cannot compare snapshot tokens to decide whether a newer
    /// observation landed. This monotonic generation is the stable comparison.
    func fileModelRefreshGeneration(for id: AudioFile.ID) -> UInt64 {
        appliedFileModelRefreshGenerations[id] ?? 0
    }

    /// Applies mutation reloads monotonically. An older mutation can finish its
    /// UI handoff after a newer one; its snapshot must not replace newer state.
    @discardableResult
    func replaceLoadedFile(
        _ reloaded: AudioFile,
        refreshGeneration: UInt64,
        deferVisibleRefresh: Bool = false,
        clearing: FileRecoveryClearance? = nil
    ) -> Bool {
        guard let accepted = acceptFileObservation(
            reloaded, generation: refreshGeneration, clearing: clearing
        ) else { return false }
        invalidateWatchedFolderScans(containingFileID: accepted.id)
        if deferVisibleRefresh {
            pendingMetadataReloadsByID[accepted.id] = (accepted, refreshGeneration)
            // Bound publication work for batches: flush every fixed number of
            // accepted reloads instead of on elapsed wall time, so a slow
            // MainActor cannot turn a batch into one full collection rebuild per
            // file. The summary completion flushes the tail.
            if pendingMetadataReloadsByID.count >= 32 {
                flushPendingMetadataReloads()
            }
        } else {
            publishAcceptedFiles([accepted])
        }
        return true
    }

    /// Keeps the last known URL but disables writes when a rename recovery
    /// could not establish a single verified location. The HUD lists the
    /// observed locations for manual recovery.
    func markFileRequiresRefresh(id: AudioFile.ID) {
        let expectedIdentity = EntryIdentityKey(
            fingerprint: committedFile(withID: id)?.fileFingerprint
        )
        recordRecoveryDecision(
            .recoveryLocationUnresolved(expectedIdentity: expectedIdentity),
            for: id
        )
    }

    /// Records a named recovery reason, invalidates in-flight work for the file and
    /// publishes an authority-free projection to every source membership.
    func recordRecoveryDecision(_ decision: FileRecoveryDecision, for id: AudioFile.ID) {
        recoveryDecisionsByID[id, default: []].insert(decision)
        invalidateWatchedFolderScans(containingFileID: id)
        pendingMetadataReloadsByID.removeValue(forKey: id)
        appliedFileModelRefreshGenerations[id] = makeFileModelRefreshGeneration()
        if let current = committedFile(withID: id) {
            replaceSourceMembershipEntry(current.projectingRecoveryState())
        }
        revokeCommitPermitsForRecoveryDecision(id)
        rebuildVisibleFiles()
    }

    func validateMetadataWriteRecovery(id: AudioFile.ID, url: URL) throws {
        // A recovery decision blocks every route, including a queued writer that
        // acquires the reservation after the decision was recorded. Display
        // projections are published together with a decision, so this is the
        // single production guard.
        guard !hasRecoveryDecision(for: id) else {
            throw AudioFileFingerprintValidationError.recoveryRequired(fileName: url.lastPathComponent)
        }
        guard !isRenameJournalBlocked(url: url) else {
            throw RenameJournalRecoveryError(fileName: url.lastPathComponent)
        }
    }

    /// Clears `.journalPending` decisions for the known file IDs of one journal
    /// operation after a verified restore or explicit acknowledgement. Path blocks
    /// are rebuilt from the manifests by the recovery refresh.
    func clearJournalRecoveryDecisions(
        forFileIDs fileIDs: Set<AudioFile.ID>,
        operationID: UUID
    ) {
        guard !fileIDs.isEmpty else { return }
        for id in fileIDs {
            renameJournalClaimedFileIDs.removeValue(forKey: id)
            guard var decisions = recoveryDecisionsByID[id] else { continue }
            decisions.remove(.journalPending(operationID))
            recoveryDecisionsByID[id] = decisions.isEmpty ? nil : decisions
            if let current = committedFile(withID: id) {
                replaceSourceMembershipEntry(current.projectingRecoveryState())
            }
        }
        renameJournalFileIDsByOperation[operationID] = nil
        rebuildVisibleFiles()
    }

    /// Records `.journalPending` decisions for the known file IDs of an unresolved
    /// rename and republishes their authority-free projections. Used after a
    /// rename outcome refreshes the journal path index.
    func applyRenameJournalPendingDecisions(
        fileIDs: [AudioFile.ID],
        operationID: UUID
    ) {
        guard !fileIDs.isEmpty else { return }
        for fileID in fileIDs {
            renameJournalClaimedFileIDs[fileID] = operationID
            renameJournalFileIDsByOperation[operationID, default: []].insert(fileID)
            recoveryDecisionsByID[fileID, default: []].insert(.journalPending(operationID))
            revokeCommitPermitsForRecoveryDecision(fileID)
        }
        for fileID in fileIDs {
            if let current = committedFile(withID: fileID) {
                replaceSourceMembershipEntry(current.projectingRecoveryState())
            }
        }
        rebuildVisibleFiles()
    }

    /// Attaches the named journal decision for a loaded observation whose path is
    /// recorded by an unresolved prepared operation. Called while the observation
    /// is being accepted, before projection/publication.
    ///
    /// The empty-journal guard keeps the common case a boolean test: no path
    /// reservation keys are computed when no recovery record is installed.
    func attachRenameJournalDecisionIfNeeded(fileID: AudioFile.ID, url: URL) {
        guard !renameJournalPathBlocks.isEmpty || !renameJournalOperationByPathKey.isEmpty else {
            return
        }
        guard let operationID = renameJournalOperationID(for: url) else { return }
        attachRenameJournalDecision(fileID: fileID, operationID: operationID)
    }

    /// Carrier overload for callers that already have the candidate's reservation
    /// keys (Quick Import). Journal matching performs no filesystem work.
    func attachRenameJournalDecisionIfNeeded(
        fileID: AudioFile.ID,
        reservationKeys: Set<String>
    ) {
        guard !renameJournalPathBlocks.isEmpty || !renameJournalOperationByPathKey.isEmpty else {
            return
        }
        guard let operationID = renameJournalOperationID(forReservationKeys: reservationKeys) else {
            return
        }
        attachRenameJournalDecision(fileID: fileID, operationID: operationID)
    }

    private func attachRenameJournalDecision(fileID: AudioFile.ID, operationID: UUID) {
        renameJournalClaimedFileIDs[fileID] = operationID
        renameJournalFileIDsByOperation[operationID, default: []].insert(fileID)
        guard !recoveryDecisionsByID[fileID, default: []].contains(.journalPending(operationID)) else {
            return
        }
        recoveryDecisionsByID[fileID, default: []].insert(.journalPending(operationID))
        revokeCommitPermitsForRecoveryDecision(fileID)
    }

    /// Invalidates in-flight scans for file IDs rebound by a verified journal
    /// restore so an older pre-restore page cannot republish.
    func invalidateWatchedFolderScansForRestoredJournalFiles(_ fileIDs: Set<AudioFile.ID>) {
        for id in fileIDs {
            invalidateWatchedFolderScans(containingFileID: id)
        }
    }

    /// Default journal store for production and the app-hosted test host. The test
    /// host never reads or writes the developer's Application Support journal.
    nonisolated static func defaultRenameJournalStore() -> any RenameJournalStoring {
        if AudioMatorTestHost.isEnabled {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorTestRenameJournal-\(UUID().uuidString)", isDirectory: true)
            return LocalRenameJournalStore(directoryURL: directoryURL)
        }
        return LocalRenameJournalStore()
    }

    func loadedFile(withID id: AudioFile.ID) -> AudioFile? {
        committedFile(withID: id) ?? visibleFilesByID[id]
    }

    /// Source-membership lookup independent of the visible sidebar projection.
    func committedFile(withID id: AudioFile.ID) -> AudioFile? {
        if let pending = pendingMetadataReloadsByID[id]?.file { return pending }
        if let file = quickImportFilesByID[id] { return file }
        guard let offsetsByFolder = watchedFolderRowOffsetsByFileID[id] else { return nil }
        for folder in watchedFolders {
            if let offset = offsetsByFolder[folder.id]?.first,
               let file = watchedFolderFiles[folder.id]?[offset] {
                return file
            }
        }
        guard let (folderID, offsets) = offsetsByFolder.first, let offset = offsets.first else { return nil }
        return watchedFolderFiles[folderID]?[offset]
    }

    /// Stable IDs currently present in the authoritative source collections.
    ///
    /// Availability checks use one set build instead of a linear membership scan
    /// per captured target, which would otherwise be quadratic in batch size.
    func committedSourceFileIDs() -> Set<AudioFile.ID> {
        var ids = Set(quickImportFilesByID.keys)
        ids.formUnion(watchedFolderRowOffsetsByFileID.keys)
        return ids
    }

    /// Updates every source membership that already contains the ID. Never adds a
    /// missing ID (no resurrection).
    @discardableResult
    func replaceSourceMembershipEntry(_ replacement: AudioFile) -> Bool {
        var updated = false
        if let index = quickImportFiles.firstIndex(where: { $0.id == replacement.id }) {
            quickImportFiles[index] = replacement
            quickImportFilesByID[replacement.id] = replacement
            updated = true
        }
        return updateWatchedFolderRows(for: replacement) > 0 || updated
    }

    func flushPendingMetadataReloads() {
        guard !pendingMetadataReloadsByID.isEmpty else { return }
        let reloadedFiles = pendingMetadataReloadsByID.values.compactMap { pending in
            appliedFileModelRefreshGenerations[pending.file.id] == pending.generation
                ? applyingRecoveryProjection(pending.file) : nil
        }
        pendingMetadataReloadsByID.removeAll(keepingCapacity: true)
        publishAcceptedFiles(reloadedFiles)
    }

    /// Propagates newly accepted observations to every other source collection
    /// that already contains the same stable file ID without resurrecting
    /// removed memberships or performing main-actor path work.
    func syncAcceptedObservationsToOtherSources(
        _ acceptedFiles: [AudioFile],
        includeQuickImport: Bool,
        excludingWatchedFolderID: UUID? = nil
    ) {
        guard !acceptedFiles.isEmpty else { return }
        let hasQuickImportTargets = includeQuickImport && !quickImportFilesByID.isEmpty
        var acceptedByID: [AudioFile.ID: AudioFile] = [:]
        for file in acceptedFiles {
            let updatedRows = updateWatchedFolderRows(for: file, excluding: excludingWatchedFolderID)
            if !includeQuickImport {
                quickImportBookkeeping.metrics.watchedObservationLookups += 1
                quickImportBookkeeping.metrics.watchedObservationRowsUpdated += updatedRows
            }
            if hasQuickImportTargets, quickImportFilesByID[file.id] != nil {
                quickImportFilesByID[file.id] = file
                acceptedByID[file.id] = file
            }
        }
        if !acceptedByID.isEmpty {
            quickImportFiles = quickImportFiles.map { acceptedByID[$0.id] ?? $0 }
        }
    }

    /// Only a rescan or removal changes row positions. Duplicate IDs can occur
    /// for aliased paths, so each membership keeps all its positions.
    private func setWatchedFolderFiles(_ files: [AudioFile]?, for folderID: UUID) {
        let previous = watchedFolderFiles[folderID] ?? []
        for id in Set(previous.map(\.id)) {
            watchedFolderRowOffsetsByFileID[id]?[folderID] = nil
            if watchedFolderRowOffsetsByFileID[id]?.isEmpty == true {
                watchedFolderRowOffsetsByFileID[id] = nil
            }
        }
        watchedFolderFiles[folderID] = files
        for (offset, file) in (files ?? []).enumerated() {
            watchedFolderRowOffsetsByFileID[file.id, default: [:]][folderID, default: []].append(offset)
        }
    }

    @discardableResult
    private func updateWatchedFolderRows(for file: AudioFile, excluding excludedFolderID: UUID? = nil) -> Int {
        guard let memberships = watchedFolderRowOffsetsByFileID[file.id] else { return 0 }
        var updatedRows = 0
        for (folderID, offsets) in memberships where folderID != excludedFolderID {
            for offset in offsets {
                watchedFolderFiles[folderID]?[offset] = file
            }
            updatedRows += offsets.count
        }
        return updatedRows
    }

    private func publishAcceptedFiles(_ reloadedFiles: [AudioFile], rebuildVisible: Bool = true) {
        guard !reloadedFiles.isEmpty else { return }
        syncAcceptedObservationsToOtherSources(reloadedFiles, includeQuickImport: true)
        if rebuildVisible { rebuildVisibleFiles() }
    }

    var lastAutomaticReloadFailures: [SelectedFileReloadFailure] = []

    var artworkImportTask: Task<Void, Never>?

    /// True while a multi-file Inspector save owns the merged draft.
    var isInspectorBatchSaveActive = false

    func withSecurityScopedAccessForQuickImportURLs<T>(
        _ urls: [URL],
        perform body: () async throws -> T
    ) async rethrows -> T {
        var accessedURLs: [URL] = []
        let fileURLs = Self.urlsByKey(urls).values
        let directoryURLs = Self.parentDirectoryURLsByKey(for: urls).values

        for url in fileURLs {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }

        for directoryURL in directoryURLs {
            if directoryURL.startAccessingSecurityScopedResource() {
                accessedURLs.append(directoryURL)
            }
        }

        defer {
            for accessedURL in accessedURLs.reversed() {
                accessedURL.stopAccessingSecurityScopedResource()
            }
        }

        return try await body()
    }

    func ensureMutationDirectoryAccess(
        for urls: [URL],
        whileCurrent: () -> Bool = { true },
        needsDirectory: (URL) -> Bool = { _ in true }
    ) -> String? {
        guard !urls.isEmpty else { return nil }
        var activeDirectories = activeMutationDirectoryURLs
        for directoryURL in FileMutationDirectoryAccessPlan.directories(for: urls) {
            guard !Task.isCancelled, whileCurrent() else { return nil }
            guard !activeDirectories.contains(where: {
                FileSystemPathSemantics.isSameOrDescendant(directoryURL, of: $0)
            }), needsDirectory(directoryURL) else { continue }
            if let failure = requestMutationDirectoryAccess(for: directoryURL) {
                return failure
            }
            // Each native prompt can re-enter the app and change live grants.
            activeDirectories = activeMutationDirectoryURLs
        }

        return nil
    }

    var primaryFileAccessGrantPath: String? {
        securityScopedFileAccessGrantURLs.values
            .sorted(by: Self.compareURLs)
            .first?
            .path
    }

    func authorizeDefaultFileAccessFolder() -> FileAccessAuthorizationOutcome {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = homeURL
        panel.title = String(localized: "Allow File Access")
        panel.prompt = String(localized: "Allow")
        panel.message = String(
            localized: "Select one or more folders containing the audio files you edit, such as your user folder."
        )

        guard panel.runModal() == .OK else {
            return .cancelled
        }

        let selectedURLs = panel.urls.map(\.standardizedFileURL)
        guard !selectedURLs.isEmpty else { return .cancelled }

        var firstGrant: FileAccessGrant?
        for selectedURL in selectedURLs {
            do {
                let grant = try registerFileAccessGrant(for: selectedURL)
                firstGrant = firstGrant ?? grant
            } catch {
                return .failure((error as NSError).localizedDescription)
            }
        }

        return .authorized(path: firstGrant?.url.path ?? selectedURLs[0].path)
    }

    func removeFileAccessGrant(id: UUID) {
        removeFileAccessGrants(ids: [id])
    }

    func removeFileAccessGrants(ids: Set<UUID>) {
        let existingIDs = ids.intersection(fileAccessGrants.map(\.id))
        guard !existingIDs.isEmpty else { return }

        for id in existingIDs {
            securityScopedFileAccessGrantURLs.removeValue(forKey: id)?
                .stopAccessingSecurityScopedResource()
        }
        fileAccessGrants.removeAll { existingIDs.contains($0.id) }
        fileAccessGrantStore.saveGrants(fileAccessGrants)
        revokeCommitPermitsForAccessScopeLoss()
    }

    func scheduleWatchedFolderRescan(for id: UUID, debounceMilliseconds: UInt64 = 350) {
        folderRescanTasks[id]?.cancel()

        folderRescanTasks[id] = Task { [weak self] in
            guard let self else { return }

            if debounceMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceMilliseconds * 1_000_000)
            }

            guard !Task.isCancelled else { return }
            await self.rescanWatchedFolder(id: id)
        }
    }

    private func rescanWatchedFolder(id: UUID) async {
        guard let folder = watchedFolders.first(where: { $0.id == id }) else { return }

        let scanToken = UUID()
        folderScanTokens[id] = scanToken
        let mutationEpoch = watchedFolderMutationEpochs[id] ?? 0
        let refreshGeneration = makeFileModelRefreshGeneration()

        // Attach a descriptor for the authorized root before enumeration. A
        // first scan whose attachment races the enumeration would otherwise
        // report a scan-before-attach gap and schedule a redundant follow-up.
        await attachDirectoryMonitorsBeforeScanIfNeeded(for: id, scanToken: scanToken)
        guard !Task.isCancelled, folderScanTokens[id] == scanToken else { return }

        let scanTask = Task.detached(priority: .utility) {
            Self.scanFolderSnapshot(for: folder.url, folderID: id)
        }
        let snapshot = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }
        guard !Task.isCancelled else { return }
        guard folderScanTokens[id] == scanToken else { return }
        guard (watchedFolderMutationEpochs[id] ?? 0) == mutationEpoch else {
            scheduleWatchedFolderRescan(for: id, debounceMilliseconds: 500)
            return
        }

        if snapshot.scanFailureCount > 0 {
            watchedFolderScanFailureCounts[id] = snapshot.scanFailureCount
            // Keep the previous file list where appropriate, but do not count
            // inaccessible or pre-replacement descriptors as active: the
            // identity-aware reconciliation closes those that no longer match.
            await reconcileDirectoryMonitors(
                for: id,
                directories: snapshot.directoryURLs + directoryMonitorBindingURLs(for: id),
                scanToken: scanToken,
                allowsFollowUpScan: false
            )
            rebuildVisibleFiles()
            return
        }

        watchedFolderScanFailureCounts[id] = 0

        // One path key per scanned URL for the stable ID entries; the shared
        // keyed loader below performs no path work of its own.
        let entries = prepareStableIDEntries(for: snapshot.audioURLs)
        let previousFilesByKey = Self.audioFilesByURLKey(watchedFolderFiles[id] ?? [])
        let metadataPipeline = self.metadataPipeline
        let inputs = entries.enumerated().map { offset, entry in
            AudioFileLoadInput(
                index: offset,
                url: entry.url,
                id: entry.id,
                previousFile: previousFilesByKey[entry.key],
                expected: nil
            )
        }

        let loadTask = Task.detached(priority: .userInitiated) {
            await Self.loadAudioFiles(
                inputs: inputs,
                metadataPipeline: metadataPipeline,
                policy: .production
            )
        }
        let loadResult = await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }

        guard !Task.isCancelled else { return }
        guard folderScanTokens[id] == scanToken else { return }
        guard (watchedFolderMutationEpochs[id] ?? 0) == mutationEpoch else {
            scheduleWatchedFolderRescan(for: id, debounceMilliseconds: 500)
            return
        }

        var refreshedFilesByKey: [String: AudioFile] = [:]
        var failedKeys = Set<String>()
        for outcome in loadResult.outcomes {
            guard outcome.input.index >= 0, outcome.input.index < entries.count else { continue }
            let entry = entries[outcome.input.index]
            if let file = outcome.file {
                refreshedFilesByKey[entry.key] = file
            } else if outcome.failureReason != nil {
                failedKeys.insert(entry.key)
                if let previousFile = previousFilesByKey[entry.key] {
                    refreshedFilesByKey[entry.key] = previousFile
                }
            }
        }

        let previousIDs = Set((watchedFolderFiles[id] ?? []).map(\.id))
        var newlyAcceptedFiles: [AudioFile] = []
        let refreshedList: [AudioFile] = entries.compactMap { entry in
            if failedKeys.contains(entry.key), let previous = previousFilesByKey[entry.key] {
                // A failed read is not a newer observation of metadata. Keep an
                // accepted pending commit rather than invalidating it with a fallback.
                return loadedFile(withID: previous.id) ?? previous
            }
            guard let file = refreshedFilesByKey[entry.key] else { return nil }
            if let accepted = acceptFileObservation(file, generation: refreshGeneration) {
                newlyAcceptedFiles.append(accepted)
                return accepted
            }
            return loadedFile(withID: file.id)
                ?? previousFilesByKey[entry.key]
        }
        setWatchedFolderFiles(refreshedList, for: id)
        if watchedFolderHierarchies[id] != snapshot.hierarchy {
            watchedFolderHierarchies[id] = snapshot.hierarchy
        }
        if !newlyAcceptedFiles.isEmpty {
            syncAcceptedObservationsToOtherSources(
                newlyAcceptedFiles,
                includeQuickImport: true,
                excludingWatchedFolderID: id
            )
        }
        let removedIDs = previousIDs.subtracting(refreshedList.map(\.id))
        if !removedIDs.isEmpty {
            revokeCommitPermitsForRemovedSourceFiles(removedIDs)
        }
        watchedFolderMetadataReadFailureCounts[id] = loadResult.outcomes.filter {
            $0.failureReason != nil
        }.count
        await reconcileDirectoryMonitors(
            for: id,
            directories: snapshot.directoryURLs,
            scanToken: scanToken,
            allowsFollowUpScan: true
        )
        rebuildVisibleFiles()
    }

    /// Invalidates any in-flight rescan for folders that currently contain
    /// `id`. The mutation reload itself is the authoritative newer snapshot;
    /// a rescan that captured the pre-mutation epoch must not replace it.
    func invalidateWatchedFolderScans(containingFileID id: AudioFile.ID) {
        guard let memberships = watchedFolderRowOffsetsByFileID[id] else { return }
        for folderID in memberships.keys {
            watchedFolderMutationEpochs[folderID, default: 0] &+= 1
        }
    }

    func rebuildVisibleFiles() {
        let selection = normalizedSidebarSelection(activeSidebarSelection)
        if activeSidebarSelection != selection {
            activeSidebarSelection = selection
        }

        let sourceFiles: [AudioFile]
        switch selection {
        case .quickImport:
            sourceFiles = quickImportFiles
        case .watchedLibrary:
            sourceFiles = mergedWatchedFiles()
        case .watchedFolder(let id):
            sourceFiles = watchedFolderFiles[id] ?? []
        case .watchedSubfolder(let rootFolderID, let relativePathKey):
            sourceFiles = watchedSubfolderFiles(
                rootFolderID: rootFolderID,
                relativePathKey: relativePathKey
            )
        }

        files = sourceFiles.map { applyingRecoveryProjection($0) }
        let validIDs = Set(files.map(\.id))
        let prunedSelection = selectedAudioIDs.intersection(validIDs)
        let selectionChanged = prunedSelection != selectedAudioIDs
        if selectionChanged {
            selectedAudioIDs = prunedSelection
        }

        // A multi-file Inspector batch save owns draft transitions through its
        // per-target completions; re-evaluating the merged draft on every
        // publication is both stale and quadratic in batch size. Reload and
        // other progress-owning flows still need the clean refresh below.
        if isInspectorBatchSaveActive {
            return
        }

        if let session = inspectorDraft {
            if session.pendingReview != nil {
                updateInspectorPendingReviewAvailability()
                return
            }

            let unavailableCapturedIDs = Set(
                session.targetIDs.filter { quickImportFilesByID[$0] == nil && watchedFolderRowOffsetsByFileID[$0] == nil }
            )
            if !unavailableCapturedIDs.isEmpty,
               isInspectorDraftPayloadDirty || !session.completedByID.isEmpty {
                enterInspectorPendingReview(unavailableTargetIDs: unavailableCapturedIDs)
                return
            }

            if selectionChanged || Set(session.targetIDs) != selectedAudioIDs {
                beginInspectorDraftSessionForCurrentSelection(reason: .selectionTransition)
                return
            }

            if !session.isSaveInFlight, !hasUnsavedInspectorChanges {
                reconstructInspectorDraft(
                    preservingSessionID: session.id,
                    baselines: selectedFiles,
                    reason: .cleanRefresh
                )
            }
            return
        }

        if selectionChanged || !selectedAudioIDs.isEmpty {
            beginInspectorDraftSessionForCurrentSelection(reason: .selectionTransition)
        }
    }

    private func updateInspectorPendingReviewAvailability() {
        guard var session = inspectorDraft, let current = session.pendingReview else { return }
        let committedIDs = committedSourceFileIDs()
        let unavailable = Set(session.targetIDs.filter { !committedIDs.contains($0) })
        let updated = InspectorPendingReview(
            identity: session.identity,
            capturedTargetIDs: current.capturedTargetIDs,
            unavailableTargetIDs: unavailable,
            reason: current.reason
        )
        session.pendingReview = updated
        inspectorDraft = session
        inspectorPendingReview = updated
    }

    func normalizedSidebarSelection(_ selection: SidebarSelection) -> SidebarSelection {
        switch selection {
        case .watchedFolder(let folderID):
            if watchedFolders.contains(where: { $0.id == folderID }) {
                return selection
            }
            return .watchedLibrary
        case .watchedSubfolder(let rootFolderID, let relativePathKey):
            guard watchedFolders.contains(where: { $0.id == rootFolderID }) else {
                return .watchedLibrary
            }
            guard let hierarchy = watchedFolderHierarchies[rootFolderID] else {
                return selection
            }
            return hierarchy.nearestSurvivingSelection(for: relativePathKey)
        case .watchedLibrary:
            return .watchedLibrary
        case .quickImport:
            return .quickImport
        }
    }

    private func watchedSubfolderFiles(
        rootFolderID: UUID,
        relativePathKey: String
    ) -> [AudioFile] {
        guard let folderFiles = watchedFolderFiles[rootFolderID],
              !folderFiles.isEmpty else {
            return []
        }

        if let hierarchy = watchedFolderHierarchies[rootFolderID] {
            return folderFiles.filter { file in
                hierarchy.containsFile(at: file.url, withinRelativePathKey: relativePathKey)
            }
        }

        guard let folder = watchedFolders.first(where: { $0.id == rootFolderID }) else {
            return []
        }

        let fallbackHierarchy = WatchedFolderHierarchy.build(
            rootFolderID: rootFolderID,
            rootURL: folder.url,
            directoryURLs: [],
            audioFileURLs: folderFiles.map(\.url)
        )
        return folderFiles.filter { file in
            fallbackHierarchy.containsFile(at: file.url, withinRelativePathKey: relativePathKey)
        }
    }

    private func mergedWatchedFiles() -> [AudioFile] {
        var seenKeys = Set<String>()
        var result: [AudioFile] = []

        for folder in watchedFolders {
            for file in watchedFolderFiles[folder.id] ?? [] {
                let key = Self.urlKey(for: file.url)
                guard seenKeys.insert(key).inserted else { continue }
                result.append(file)
            }
        }

        return result.sorted(by: Self.compareAudioFiles)
    }

    /// Allocates the session-wide stable ID for each scanned URL while computing
    /// its path key exactly once. The returned entries feed the keyed loader, so
    /// the loader does not resolve the same paths again.
    func prepareStableIDEntries(for urls: [URL]) -> [(url: URL, key: String, id: UUID)] {
        var entries: [(url: URL, key: String, id: UUID)] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            let key = Self.urlKey(for: standardizedURL)
            let id = fileIDsByKey[key] ?? UUID()
            fileIDsByKey[key] = id
            entries.append((standardizedURL, key, id))
        }

        return entries
    }

    private func beginAccessingWatchedFolder(_ folder: WatchedFolder) {
        guard securityScopedFolderURLs[folder.id] == nil else { return }

        if folder.url.startAccessingSecurityScopedResource() {
            securityScopedFolderURLs[folder.id] = folder.url
        }
    }

    private func beginAccessingFileAccessGrant(_ grant: FileAccessGrant) {
        guard securityScopedFileAccessGrantURLs[grant.id] == nil else { return }

        if grant.url.startAccessingSecurityScopedResource() {
            securityScopedFileAccessGrantURLs[grant.id] = grant.url
        }
    }

    private func stopAccessingWatchedFolder(_ id: UUID) {
        guard let url = securityScopedFolderURLs.removeValue(forKey: id) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func stopWatchingFolder(id: UUID) {
        folderRescanTasks[id]?.cancel()
        folderRescanTasks[id] = nil

        folderDirectoryMonitors.removeValue(forKey: id)?.stop()
        publishedDirectoryMonitorGenerations[id] = nil
        directoryMonitoringStatuses[id] = nil

        stopAccessingWatchedFolder(id)
    }

    func presentQuickImportFailures(_ failures: [AudioFileLoadFailure]) {
        guard !failures.isEmpty else { return }

        var lines = failures.prefix(3).map { failure in
            let fileName = failure.url.lastPathComponent
            let reason = failure.reason.replacingOccurrences(of: failure.url.path, with: fileName)
            return "\(fileName): \(reason)"
        }
        if failures.count > lines.count {
            lines.append(String(localized: "Additional files couldn’t be imported: \(failures.count - lines.count)."))
        }

        presentMetadataWriteHUD(
            style: .warning,
            title: failures.count == 1 ? String(localized: "This File Couldn’t Be Imported") : String(localized: "Some Files Couldn’t Be Imported"),
            subtitle: lines.joined(separator: "\n"),
            summary: String(localized: "Files that couldn’t be imported: \(failures.count)."),
            details: lines.joined(separator: "\n\n")
        )
    }

    private var activeMutationDirectoryURLs: [URL] {
        // Quick Import parents come from the membership index (no stale
        // full-collection URL map is retained); watched folders and saved grants
        // keep their own authorized roots.
        var quickImportParentURLs: [URL] = []
        var seenParentPaths = Set<String>()
        for id in quickImportBookkeeping.index.orderedIDs {
            guard let record = quickImportBookkeeping.index.record(forID: id) else { continue }
            guard quickImportBookkeeping.leases.isLiveGranted(forKey: record.identity.parentKey) else {
                continue
            }
            let parentURL = record.identity.parentURL
            guard seenParentPaths.insert(parentURL.path).inserted else { continue }
            quickImportParentURLs.append(parentURL)
        }
        return quickImportParentURLs
            + Array(securityScopedFolderURLs.values)
            + Array(securityScopedFileAccessGrantURLs.values)
    }

    private func requestMutationDirectoryAccess(for directoryURL: URL) -> String? {
        if let mutationDirectoryAccessRequester {
            return mutationDirectoryAccessRequester(directoryURL)
        }

        if AudioMatorTestHost.isEnabled {
            return "Missing test authorization for mutation directory: \(directoryURL.path)"
        }

        let displayName = FileManager.default.displayName(atPath: directoryURL.path)
        let key = Self.urlKey(for: directoryURL)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = directoryURL.deletingLastPathComponent()
        panel.title = String(localized: "Allow Folder Access")
        panel.prompt = String(localized: "Allow")
        panel.message = String(
            localized: "To safely modify these audio files, select the folder “\(displayName)”."
        )

        guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
            return String(localized: "Allow access to “\(displayName)” to change files inside it.")
        }

        guard Self.urlKey(for: selectedURL) == key else {
            return String(localized: "Select the exact folder “\(displayName)” to continue.")
        }

        do {
            _ = try registerFileAccessGrant(for: selectedURL)
            return nil
        } catch {
            return String(
                localized: "Access to “\(displayName)” couldn’t be saved for future use.\nDetails: \((error as NSError).localizedDescription)"
            )
        }
    }

    private func registerFileAccessGrant(for url: URL) throws -> FileAccessGrant {
        let normalizedURL = url.standardizedFileURL
        let key = Self.urlKey(for: normalizedURL)

        if let existingGrant = fileAccessGrants.first(where: { Self.urlKey(for: $0.url) == key }),
           securityScopedFileAccessGrantURLs[existingGrant.id] != nil {
            return existingGrant
        }

        let grant = try fileAccessGrantStore.makeGrant(from: normalizedURL)
        guard normalizedURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }

        let redundantGrants = fileAccessGrants.filter {
            Self.isSameOrDescendant($0.url, of: normalizedURL)
        }
        for redundantGrant in redundantGrants {
            securityScopedFileAccessGrantURLs.removeValue(forKey: redundantGrant.id)?
                .stopAccessingSecurityScopedResource()
        }
        fileAccessGrants.removeAll { candidate in
            redundantGrants.contains(where: { $0.id == candidate.id })
        }

        fileAccessGrants.append(grant)
        fileAccessGrants.sort { Self.compareURLs($0.url, $1.url) }
        securityScopedFileAccessGrantURLs[grant.id] = normalizedURL
        guard fileAccessGrantStore.saveGrants(fileAccessGrants) else {
            fileAccessGrants.removeAll { $0.id == grant.id }
            securityScopedFileAccessGrantURLs.removeValue(forKey: grant.id)?
                .stopAccessingSecurityScopedResource()
            throw CocoaError(.fileWriteUnknown)
        }
        return grant
    }

    // MARK: - Identity-aware directory monitoring (F4)

    /// Internal test seam: the controller that currently owns this folder's
    /// descriptors.
    func directoryMonitorController(for folderID: UUID) -> DirectoryMonitorController? {
        folderDirectoryMonitors[folderID]
    }

    private func startDirectoryMonitoring(for folder: WatchedFolder) {
        guard folderDirectoryMonitors[folder.id] == nil else { return }
        let folderID = folder.id
        let controller = DirectoryMonitorController(
            rootURL: folder.url,
            limit: Self.maximumDirectoryMonitorsPerFolder,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleDirectoryMonitorEvent(folderID: folderID, event: event)
                }
            }
        )
        folderDirectoryMonitors[folderID] = controller
        publishedDirectoryMonitorGenerations[folderID] = 0
    }

    /// A terminal instance detached itself because its directory was renamed,
    /// replaced or revoked. Reschedule the scan. A replacement binding may
    /// already be active; that stale event must not degrade the replacement.
    func handleDirectoryMonitorEvent(folderID: UUID, event: DirectoryMonitorControllerEvent) {
        guard watchedFolders.contains(where: { $0.id == folderID }),
              let controller = folderDirectoryMonitors[folderID] else { return }

        if event.isTerminal {
            if let current = controller.binding(forKey: event.key),
               current.instanceToken != event.instanceToken {
                return
            }
            scheduleWatchedFolderRescan(for: folderID)
            return
        }

        guard controller.isCurrent(event.instanceToken, forKey: event.key) else { return }
        scheduleWatchedFolderRescan(for: folderID)
    }

    private func attachDirectoryMonitorsBeforeScanIfNeeded(for folderID: UUID, scanToken: UUID) async {
        guard let folder = watchedFolders.first(where: { $0.id == folderID }),
              let controller = folderDirectoryMonitors[folderID],
              controller.snapshot().bindings.isEmpty else {
            return
        }
        await reconcileDirectoryMonitors(
            for: folderID,
            directories: [folder.url],
            scanToken: scanToken,
            allowsFollowUpScan: false
        )
    }

    private func directoryMonitorBindingURLs(for folderID: UUID) -> [URL] {
        folderDirectoryMonitors[folderID]?.snapshot().bindings.map(\.url) ?? []
    }

    private func scheduleDirectoryMonitorFollowUpScan(for folderID: UUID) {
        guard watchedFolders.contains(where: { $0.id == folderID }) else { return }
        scheduleWatchedFolderRescan(for: folderID, debounceMilliseconds: 350)
    }

    /// Reconciles descriptors off the main actor and publishes status only when
    /// this folder still owns the same controller and the result is newer than
    /// the last published reconciliation (and still belongs to `scanToken`).
    private func reconcileDirectoryMonitors(
        for folderID: UUID,
        directories: [URL],
        scanToken: UUID?,
        allowsFollowUpScan: Bool
    ) async {
        guard let controller = folderDirectoryMonitors[folderID],
              watchedFolders.contains(where: { $0.id == folderID }) else {
            return
        }

        let result = await Task.detached(priority: .utility) {
            controller.reconcile(directories: directories)
        }.value

        guard !Task.isCancelled else { return }
        guard watchedFolders.contains(where: { $0.id == folderID }),
              let currentController = folderDirectoryMonitors[folderID],
              currentController === controller else {
            return
        }
        if let scanToken, folderScanTokens[folderID] != scanToken { return }
        let publishedGeneration = publishedDirectoryMonitorGenerations[folderID] ?? 0
        guard result.reconciliationGeneration > publishedGeneration else { return }
        publishedDirectoryMonitorGenerations[folderID] = result.reconciliationGeneration

        let status = DirectoryMonitoringStatus(
            totalDirectoryCount: result.totalDirectoryCount,
            monitoredDirectoryCount: result.activeDirectoryCount,
            omittedByLimitCount: result.omittedByLimitCount,
            failedToOpenCount: result.failedToOpenCount,
            identityMismatchCount: result.identityMismatchCount,
            scanFailureCount: watchedFolderScanFailureCounts[folderID] ?? 0,
            metadataReadFailureCount: watchedFolderMetadataReadFailureCounts[folderID] ?? 0
        )
        if directoryMonitoringStatuses[folderID] != status {
            directoryMonitoringStatuses[folderID] = status
        }

        if allowsFollowUpScan, result.needsFollowUpScan {
            scheduleDirectoryMonitorFollowUpScan(for: folderID)
        }
    }

    // MARK: - User-requested watched-folder refresh

    /// User-requested refresh for one watched folder: revalidate access, then
    /// run the ordinary scan pipeline so the file list and descriptors
    /// reconcile together.
    func refreshWatchedFolder(id: UUID) {
        refreshWatchedFolders(ids: [id])
    }

    /// User-requested refresh for every watched folder.
    func refreshWatchedFolders() {
        refreshWatchedFolders(ids: Set(watchedFolders.map(\.id)))
    }

    func refreshWatchedFolders(ids: Set<UUID>) {
        let targets = watchedFolders.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        var unavailableNames: [String] = []
        for folder in targets {
            if !ensureWatchedFolderAccess(folder) {
                unavailableNames.append(folder.displayName)
            }
            // Always rescan: an inaccessible root must surface as degraded
            // status rather than keeping a stale active status.
            scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        }

        if !unavailableNames.isEmpty {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Watched Folder Unavailable"),
                subtitle: Self.watchedFolderUnavailableMessage(for: unavailableNames)
            )
        }
    }

    nonisolated static func watchedFolderUnavailableMessage(for displayNames: [String]) -> String {
        if displayNames.count == 1, let name = displayNames.first {
            return String(localized: "“\(name)” can’t be reached right now. Reauthorize it in Settings → Folders, then refresh again.")
        }
        return String(localized: "\(displayNames.count) watched folders can’t be reached right now. Reauthorize them in Settings → Folders, then refresh again.")
    }

    /// Re-establish a security scope macOS dropped (unmounted volume, provider
    /// teardown) without re-adding the folder. A moved folder keeps its recorded
    /// URL until the user reauthorizes it explicitly.
    private func ensureWatchedFolderAccess(_ folder: WatchedFolder) -> Bool {
        if let activeURL = securityScopedFolderURLs[folder.id] {
            if FileManager.default.fileExists(atPath: activeURL.path) {
                return true
            }
            activeURL.stopAccessingSecurityScopedResource()
            securityScopedFolderURLs.removeValue(forKey: folder.id)
        }
        if folder.url.startAccessingSecurityScopedResource() {
            if FileManager.default.fileExists(atPath: folder.url.path) {
                securityScopedFolderURLs[folder.id] = folder.url
                return true
            }
            folder.url.stopAccessingSecurityScopedResource()
        }
        if let restored = watchedFolderStore.loadFolders().first(where: { $0.id == folder.id }),
           restored.url.standardizedFileURL == folder.url.standardizedFileURL,
           restored.url.startAccessingSecurityScopedResource() {
            if FileManager.default.fileExists(atPath: restored.url.path) {
                securityScopedFolderURLs[folder.id] = restored.url
                return true
            }
            restored.url.stopAccessingSecurityScopedResource()
        }
        // Non-security-scoped URLs (tests, non-sandboxed builds) and scopes macOS
        // grants transparently still work; let the scan surface a degraded state
        // if the path is genuinely unreachable.
        return FileManager.default.fileExists(atPath: folder.url.path)
    }

    @discardableResult
    private func persistWatchedFolders() -> Bool {
        watchedFolderStore.saveFolders(watchedFolders)
    }

    nonisolated private static func scanFolderSnapshot(
        for folderURL: URL,
        folderID: UUID
    ) -> FolderScanSnapshot {
        var audioURLs: [URL] = []
        var directoryURLs: [URL] = [folderURL.standardizedFileURL]
        var hierarchyDirectoryURLs: [URL] = [folderURL.standardizedFileURL]
        var scanFailureCount = 0
        var seenAudioKeys = Set<String>()
        var seenDirectoryKeys = Set([urlKey(for: folderURL)])

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { _, _ in
                scanFailureCount += 1
                return true
            }
        ) else {
            return FolderScanSnapshot(
                audioURLs: audioURLs,
                directoryURLs: directoryURLs,
                hierarchy: WatchedFolderHierarchy.build(
                    rootFolderID: folderID,
                    rootURL: folderURL,
                    directoryURLs: hierarchyDirectoryURLs,
                    audioFileURLs: audioURLs
                ),
                scanFailureCount: 1
            )
        }

        for case let url as URL in enumerator {
            guard !Task.isCancelled else { break }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                scanFailureCount += 1
                continue
            }

            if values.isDirectory == true {
                let key = urlKey(for: url)
                if seenDirectoryKeys.insert(key).inserted {
                    let standardizedURL = url.standardizedFileURL
                    directoryURLs.append(standardizedURL)
                    if values.isPackage != true {
                        hierarchyDirectoryURLs.append(standardizedURL)
                    }
                }
                continue
            }

            guard values.isRegularFile == true else { continue }
            guard readableAudioExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let key = urlKey(for: url)
            guard seenAudioKeys.insert(key).inserted else { continue }
            audioURLs.append(url.standardizedFileURL)
        }

        audioURLs.sort(by: compareURLs)
        directoryURLs.sort(by: compareURLs)

        let hierarchy = WatchedFolderHierarchy.build(
            rootFolderID: folderID,
            rootURL: folderURL,
            directoryURLs: hierarchyDirectoryURLs,
            audioFileURLs: audioURLs
        )

        return FolderScanSnapshot(
            audioURLs: audioURLs,
            directoryURLs: directoryURLs,
            hierarchy: hierarchy,
            scanFailureCount: scanFailureCount
        )
    }

    nonisolated private static func urlsByKey(_ urls: [URL]) -> [String: URL] {
        var urlsByKey: [String: URL] = [:]

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            urlsByKey[urlKey(for: standardizedURL)] = standardizedURL
        }

        return urlsByKey
    }

    nonisolated private static func parentDirectoryURLsByKey(for urls: [URL]) -> [String: URL] {
        var directoryURLsByKey: [String: URL] = [:]

        for url in urls {
            let directoryURL = url.standardizedFileURL.deletingLastPathComponent()
            directoryURLsByKey[urlKey(for: directoryURL)] = directoryURL
        }

        return directoryURLsByKey
    }

    nonisolated private static func isSameOrDescendant(_ url: URL, of ancestorURL: URL) -> Bool {
        FileSystemPathSemantics.isSameOrDescendant(url, of: ancestorURL)
    }

    nonisolated static func urlKey(for url: URL) -> String {
        FileSystemPathSemantics.key(for: url)
    }

    nonisolated static func compareAudioFiles(_ lhs: AudioFile, _ rhs: AudioFile) -> Bool {
        compareURLs(lhs.url, rhs.url)
    }

    nonisolated static func compareURLs(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent)
        if lhsName != .orderedSame {
            return lhsName == .orderedAscending
        }

        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    nonisolated static func audioFilesByURLKey(_ files: [AudioFile]) -> [String: AudioFile] {
        var filesByKey: [String: AudioFile] = [:]
        for file in files where filesByKey[urlKey(for: file.url)] == nil {
            filesByKey[urlKey(for: file.url)] = file
        }
        return filesByKey
    }
}

private struct FolderScanSnapshot {
    let audioURLs: [URL]
    let directoryURLs: [URL]
    let hierarchy: WatchedFolderHierarchy
    let scanFailureCount: Int
}

// MARK: – F1 move publication and bounded readback

extension AudioViewModel {
    /// Phase B: reacquire each destination for one bounded full read. A read that
    /// times out, fails, or observes a different directory entry cannot publish;
    /// the projection and pending decision stay in place.
    func readBackMovedFiles(_ receipts: [FileRenameMoveReceipt]) async -> [String] {
        guard !receipts.isEmpty else { return [] }
        let limiter = MoveReadbackLaneLimiter(maximum: MetadataBatchExecutor.maximumConcurrentMutations)
        var warnings: [String] = []
        await withTaskGroup(of: String?.self) { group in
            for receipt in receipts {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.readBackMovedFile(receipt, limiter: limiter)
                }
            }
            for await warning in group {
                if let warning { warnings.append(warning) }
            }
        }
        return warnings
    }

    private func readBackMovedFile(
        _ receipt: FileRenameMoveReceipt,
        limiter: MoveReadbackLaneLimiter
    ) async -> String? {
        guard let leaseID = await limiter.acquire() else {
            return String(localized: "“\(receipt.destinationURL.lastPathComponent)” was renamed but hasn’t been checked at its new location yet. Choose Reload from Disk from its context menu.")
        }

        let generation = makeFileModelRefreshGeneration()
        let pipeline = metadataPipeline
        let coordinator = fileMutationCoordinator
        let timeout = moveReadbackTimeout
        let scopedLease = MoveReadbackScopedAccessLease(urls: [receipt.destinationURL])
        let reservationAcquired = MoveReadbackSignal()

        // The worker owns the lane, scoped access lease, and destination
        // reservation until the underlying read actually unwinds. The read
        // deadline starts only after the destination reservation is acquired;
        // a timed-out worker cannot publish and stays counted as overdue until
        // it unwinds.
        let worker = Task.detached(priority: .userInitiated) { [limiter, leaseID, receipt, pipeline, coordinator, scopedLease, reservationAcquired] () async -> Result<AudioFile, MoveReadbackFailure> in
            defer {
                scopedLease.release()
                Task { await limiter.release(leaseID) }
            }
            do {
                return try await coordinator.withExclusiveAccess(to: [receipt.destinationURL]) {
                    reservationAcquired.signal()
                    let before = try? FileEntryIdentityCapture.capture(at: receipt.destinationURL)
                    guard let before,
                          before.isSameDirectoryEntry(as: receipt.entryIdentity) else {
                        return Result<AudioFile, MoveReadbackFailure>.failure(.destinationChanged)
                    }
                    let loaded: AudioFile
                    do {
                        loaded = try await pipeline.loadAudioFile(at: receipt.destinationURL, id: receipt.fileID)
                    } catch is CancellationError {
                        return .failure(.timedOut)
                    } catch {
                        return .failure(.readFailed((error as NSError).localizedDescription))
                    }
                    let after = try? FileEntryIdentityCapture.capture(at: receipt.destinationURL)
                    guard loaded.url == receipt.destinationURL,
                          loaded.observation != nil,
                          after?.isSameDirectoryEntry(as: receipt.entryIdentity) == true else {
                        return .failure(.destinationChanged)
                    }
                    return .success(loaded)
                }
            } catch is CancellationError {
                reservationAcquired.signal()
                return .failure(.readFailed(String(localized: "Reading the renamed file was cancelled.")))
            } catch {
                reservationAcquired.signal()
                return .failure(.readFailed((error as NSError).localizedDescription))
            }
        }

        await reservationAcquired.wait()

        guard let outcome = await Self.waitForMoveReadback(worker, timeout: timeout) else {
            await limiter.markOverdue(leaseID)
            worker.cancel()
            return String(localized: "“\(receipt.destinationURL.lastPathComponent)” was renamed, but checking its metadata timed out. Choose Reload from Disk from its context menu before editing.")
        }

        switch outcome {
        case .success(let loaded):
            _ = replaceLoadedFile(
                loaded,
                refreshGeneration: generation,
                clearing: .receiptMatchedReadback(moveID: receipt.moveID)
            )
            return nil
        case .failure(.destinationChanged):
            return String(localized: "“\(receipt.destinationURL.lastPathComponent)” was renamed, but a different file now has that name. Metadata editing stays paused until you choose Reload from Disk and confirm whether to accept the replacement file.")
        case .failure(.timedOut):
            return String(localized: "“\(receipt.destinationURL.lastPathComponent)” was renamed, but checking its metadata timed out. Choose Reload from Disk from its context menu before editing.")
        case .failure(.readFailed(let detail)):
            return String(localized: "“\(receipt.destinationURL.lastPathComponent)” was renamed, but its metadata couldn’t be reloaded. Choose Reload from Disk from its context menu.\nDetails: \(detail)")
        }
    }

    nonisolated private static func waitForMoveReadback(
        _ task: Task<Result<AudioFile, MoveReadbackFailure>, Never>,
        timeout: Duration
    ) async -> Result<AudioFile, MoveReadbackFailure>? {
        do {
            return try await withAsyncTimeout(timeout, operationName: "Move readback") {
                await task.value
            }
        } catch {
            return nil
        }
    }

    /// Applies one named clearance transition. Automatic observations pass `nil`
    /// and never reach this function.
    private func clearRecoveryDecisions(
        for id: AudioFile.ID,
        clearing: FileRecoveryClearance,
        observation: AudioFile.Observation
    ) {
        guard var decisions = recoveryDecisionsByID[id], !decisions.isEmpty else { return }
        let observedIdentity = EntryIdentityKey(fingerprint: observation.fingerprint)

        switch clearing {
        case .receiptMatchedReadback(let moveID):
            decisions = decisions.filter { decision in
                if case .moveReadbackPending(let pendingMoveID, _, _) = decision {
                    return pendingMoveID != moveID
                }
                return true
            }

        case .explicitAuthorizedReload:
            decisions = decisions.filter { decision in
                switch decision {
                case .moveReadbackPending(_, let destinationURL, let expectedIdentity):
                    let sameLocation = FileSystemPathSemantics.key(for: destinationURL)
                        == FileSystemPathSemantics.key(for: observation.url)
                    return !(sameLocation && expectedIdentity.matches(observedIdentity))
                case .recoveryLocationUnresolved(let expectedIdentity):
                    guard let expectedIdentity else { return true }
                    return !expectedIdentity.matches(observedIdentity)
                case .journalPending:
                    return true
                }
            }

        case .verifiedJournalLocation(let operationID):
            decisions.remove(.journalPending(operationID))

        case .explicitReplacementAcceptance(let target):
            let targetPathKey = FileSystemPathSemantics.key(for: target.url)
            let observedPathKey = FileSystemPathSemantics.key(for: observation.url)
            guard target.id == id,
                  targetPathKey == observedPathKey,
                  target.fingerprint == observation.fingerprint,
                  target.version == observation.version else {
                return
            }
            decisions = decisions.filter { decision in
                switch decision {
                case .moveReadbackPending(_, let destinationURL, _):
                    return FileSystemPathSemantics.key(for: destinationURL) != observedPathKey
                case .recoveryLocationUnresolved:
                    return false
                case .journalPending:
                    return true
                }
            }
        }

        recoveryDecisionsByID[id] = decisions.isEmpty ? nil : decisions
    }
}

private actor MoveReadbackLaneLimiter {
    private var activeLeaseIDs: Set<UUID> = []
    private var overdueLeaseIDs: Set<UUID> = []
    private var waiters: [CheckedContinuation<UUID?, Never>] = []
    private let maximum: Int

    init(maximum: Int) {
        self.maximum = max(1, maximum)
    }

    func acquire() async -> UUID? {
        if activeLeaseIDs.count < maximum {
            let id = UUID()
            activeLeaseIDs.insert(id)
            return id
        }
        if overdueLeaseIDs.count >= maximum {
            return nil
        }
        return await withCheckedContinuation { continuation in
            if activeLeaseIDs.count < maximum {
                let id = UUID()
                activeLeaseIDs.insert(id)
                continuation.resume(returning: id)
            } else if overdueLeaseIDs.count >= maximum {
                continuation.resume(returning: nil)
            } else {
                waiters.append(continuation)
            }
        }
    }

    func markOverdue(_ leaseID: UUID) {
        guard activeLeaseIDs.contains(leaseID) else { return }
        overdueLeaseIDs.insert(leaseID)
        if overdueLeaseIDs.count >= maximum {
            let pending = waiters
            waiters.removeAll()
            for waiter in pending {
                waiter.resume(returning: nil)
            }
        }
    }

    func release(_ leaseID: UUID) {
        guard activeLeaseIDs.remove(leaseID) != nil else { return }
        overdueLeaseIDs.remove(leaseID)
        if !waiters.isEmpty, activeLeaseIDs.count < maximum {
            let next = waiters.removeFirst()
            let newLeaseID = UUID()
            activeLeaseIDs.insert(newLeaseID)
            next.resume(returning: newLeaseID)
        }
    }
}

/// One-shot signal used to start the readback deadline only after the worker
/// enters its destination reservation.
private nonisolated final class MoveReadbackSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var didSignal = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func signal() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            guard !didSignal else { return [] }
            didSignal = true
            let list = continuations
            continuations.removeAll()
            return list
        }
        for continuation in pending {
            continuation.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadySignaled = lock.withLock { () -> Bool in
                if didSignal {
                    return true
                }
                continuations.append(continuation)
                return false
            }
            if alreadySignaled {
                continuation.resume()
            }
        }
    }
}

/// Holds security-scoped access for a single readback worker until the worker
/// unwinds (even after a timeout warning has already returned to the caller).
private nonisolated final class MoveReadbackScopedAccessLease: @unchecked Sendable {
    private let lock = NSLock()
    private var accessedURLs: [URL]

    init(urls: [URL]) {
        var accessed: [URL] = []
        var seen: Set<String> = []
        let candidates = urls + urls.map { $0.deletingLastPathComponent() }
        for url in candidates {
            let key = FileSystemPathSemantics.key(for: url)
            guard seen.insert(key).inserted else { continue }
            if url.startAccessingSecurityScopedResource() {
                accessed.append(url)
            }
        }
        self.accessedURLs = accessed
    }

    func release() {
        let toStop = lock.withLock { () -> [URL] in
            let current = accessedURLs
            accessedURLs = []
            return current
        }
        for url in toStop.reversed() {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        release()
    }
}
