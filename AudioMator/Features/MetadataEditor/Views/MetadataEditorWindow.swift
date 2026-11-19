import SwiftUI
import AppKit
import Combine
import TagLibAudioMetadata


struct MetadataEditorTarget: Identifiable, Hashable {
    let id: AudioFile.ID
    let url: URL
    let expectedFileFingerprint: AudioFileFingerprint?
    let expectedMetadataVersion: MetadataFileVersion?
    let metadataConflictBaseline: MetadataConflictBaseline?
    let requiresMetadataRefresh: Bool

    init(file: AudioFile) {
        self.id = file.id
        self.url = file.url
        self.expectedFileFingerprint = file.fileFingerprint
        self.expectedMetadataVersion = file.metadataFileVersion
        self.requiresMetadataRefresh = file.requiresMetadataRefreshBeforeWriting
        self.metadataConflictBaseline = file.metadataConflictBaseline
    }

    nonisolated init(target: MetadataEditorTarget, fingerprint: AudioFileFingerprint, snapshot: MetadataSnapshot) {
        id = target.id
        url = target.url
        expectedFileFingerprint = fingerprint
        expectedMetadataVersion = snapshot.fileVersion
        metadataConflictBaseline = MetadataConflictBaseline(snapshot)
        requiresMetadataRefresh = false
    }

    nonisolated var fileName: String {
        url.lastPathComponent
    }
}

private struct MetadataTextUtilitiesContext: Identifiable {
    let fieldKeys: Set<String>

    var id: String {
        fieldKeys.sorted().joined(separator: "\u{1F}")
    }
}

@MainActor
final class MetadataEditorStore: ObservableObject {
    private struct LoadedState {
        let targets: [MetadataEditorTarget]
        let propertyMaps: [AudioFile.ID: RawMetadataValueMap]
        let errorMessage: String?
    }

    @Published private(set) var targets: [MetadataEditorTarget] = []
    @Published private(set) var originalPropertyMaps: [AudioFile.ID: RawMetadataValueMap] = [:]
    @Published private(set) var draftPropertyMaps: [AudioFile.ID: RawMetadataValueMap] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadErrorMessage: String?
    @Published var selectedFieldKeys: Set<String> = []

    /// Store-owned session identity. A new value is created for every explicit
    /// presentation; completions, closes and load results are accepted only
    /// while their captured identity is still current.
    @Published private(set) var sessionState: MetadataEditorSessionState = .idle
    /// True while a closed applying session is still draining its admitted apply.
    @Published private(set) var isDrainingApply = false
    /// App-owned outcome of the most recent apply, retained even after the window
    /// closed so the operation's real result is never lost with the presentation.
    @Published private(set) var lastApplyOutcome: MetadataEditorApplyOutcome?

    private let metadataPipeline: any AudioMetadataPipeline
    private var loadGeneration: UInt64 = 0
    /// Monotonic counter advanced for every draft mutation and explicit discard.
    private(set) var draftGeneration: UInt64 = 0
    private var currentApplyID: MetadataEditorApplyID?
    private var currentApplyRequest: MetadataEditorApplyRequest?
    private var currentApplyTask: Task<Void, Never>?
    private var drainingApply: DrainingApply?
    private var isWindowPresented = false
    /// Stale completions from a superseded presentation are counted rather than
    /// applied, so tests can prove suppression without inspecting private state.
    private(set) var suppressedStaleCompletionCount = 0

    private struct DrainingApply {
        let presentationID: MetadataEditorPresentationID
        let applyID: MetadataEditorApplyID
        let request: MetadataEditorApplyRequest
    }

    init(metadataPipeline: any AudioMetadataPipeline) {
        self.metadataPipeline = metadataPipeline
    }

    var currentPresentationID: MetadataEditorPresentationID? {
        sessionState.presentationID
    }

    var isApplying: Bool {
        sessionState.isApplying
    }

    /// A closed apply session cannot admit a second raw write until it drains.
    var applyBlockedByDraining: Bool {
        isDrainingApply
    }

    var canStartApply: Bool {
        guard case .ready = sessionState else { return false }
        return isEditable && !isDrainingApply
    }

    var currentTargetIDs: [AudioFile.ID] {
        targets.map(\.id)
    }

    var hasUnsavedChanges: Bool {
        draftPropertyMaps != originalPropertyMaps
    }

    var pendingTargets: [MetadataEditorTarget] {
        targets.filter { target in
            draftPropertyMaps[target.id] != originalPropertyMaps[target.id]
        }
    }

    var isEditable: Bool {
        !isLoading &&
        loadErrorMessage == nil &&
        !targets.isEmpty &&
        originalPropertyMaps.count == targets.count
    }

    fileprivate var rows: [MetadataEditorRow] {
        MetadataEditorDraftRows.makeRows(targets: targets, draftPropertyMaps: draftPropertyMaps)
    }

    var selectionSummaryText: String {
        if targets.count == 1, let target = targets.first {
            return target.fileName
        }

        return "\(targets.count) selected files"
    }

    var selectedFieldKey: String? {
        get {
            selectedFieldKeys.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }.first
        }
        set {
            if let newValue {
                selectedFieldKeys = [newValue]
            } else {
                selectedFieldKeys = []
            }
        }
    }

    var selectionDetailText: String {
        if targets.count == 1, let target = targets.first {
            return target.url.path
        }

        return L10n.string("Only non-empty metadata fields are shown. Mixed values appear as Multiple Values, and changes apply to every selected file.")
    }

    /// Compatibility entry point used by the window before the main-window
    /// integration adopts `openDecision(for:)`. It always starts a fresh
    /// presentation; callers that must preserve a live draft go through
    /// `openDecision(for:)`/`discardAndOpen` first.
    func present(targetFiles: [AudioFile]) {
        presentNew(targetFiles: targetFiles)
    }

    /// Starts a fresh presentation for `targetFiles` without consulting the
    /// current session. The caller owns any required discard confirmation.
    @discardableResult
    func presentNew(targetFiles: [AudioFile]) -> MetadataEditorPresentationID {
        let presentationID = MetadataEditorPresentationID()
        startPresentation(targetFiles: targetFiles, presentationID: presentationID)
        return presentationID
    }

    private func startPresentation(
        targetFiles: [AudioFile],
        presentationID: MetadataEditorPresentationID
    ) {
        let capturedTargets = targetFiles.map(MetadataEditorTarget.init(file:))
        loadGeneration &+= 1
        draftGeneration &+= 1
        let loadContext = MetadataEditorLoadContext(
            presentationID: presentationID,
            loadGeneration: loadGeneration
        )

        targets = capturedTargets
        originalPropertyMaps = [:]
        draftPropertyMaps = [:]
        loadErrorMessage = nil
        selectedFieldKeys = []
        isLoading = true
        sessionState = .loading(presentationID: presentationID, loadGeneration: loadGeneration)
        let metadataPipeline = self.metadataPipeline

        Task.detached(priority: .userInitiated) { [capturedTargets, loadContext, metadataPipeline] in
            let loadedState = Self.loadState(for: capturedTargets, metadataPipeline: metadataPipeline)

            await MainActor.run {
                guard self.currentPresentationID == loadContext.presentationID,
                      case .loading(_, let activeGeneration) = self.sessionState,
                      activeGeneration == loadContext.loadGeneration else { return }
                self.targets = loadedState.targets
                self.originalPropertyMaps = loadedState.propertyMaps
                self.draftPropertyMaps = loadedState.propertyMaps
                self.loadErrorMessage = loadedState.errorMessage
                self.isLoading = false
                self.sessionState = .ready(presentationID: loadContext.presentationID)
                if loadedState.errorMessage == nil {
                    self.realignSelection(preferred: self.selectedFieldKey)
                } else {
                    self.selectedFieldKeys = []
                }
            }
        }
    }

    /// The document controller observes the window being on screen. Repeated
    /// opens are driven by `openDecision(for:)`.
    func windowDidAppear() {
        isWindowPresented = true
    }

    /// Explicit close ownership. The Metadata Editor window calls this (via its
    /// close observer) instead of resetting draft state from a generic
    /// `onDisappear`.
    ///
    /// - Idle/ready/loading close is the documented deliberate discard.
    /// - Close during an apply cancels precommit work, retains an app-owned
    ///   outcome for any admitted write, and leaves the apply draining. The
    ///   presented session ends; a reopened window may load new data but cannot
    ///   start another apply until the drain finishes.
    /// - A close notification carrying a superseded presentation identity is
    ///   ignored so it cannot clear a newer session.
    func windowWillClose(presentationID: MetadataEditorPresentationID?) {
        guard let presentationID,
              currentPresentationID == presentationID else { return }
        isWindowPresented = false

        if case .applying(let applyingPresentationID, let applyID) = sessionState,
           let request = currentApplyRequest {
            currentApplyTask?.cancel()
            currentApplyTask = nil
            currentApplyRequest = nil
            currentApplyID = nil
            drainingApply = DrainingApply(
                presentationID: applyingPresentationID,
                applyID: applyID,
                request: request
            )
            isDrainingApply = true
        }
        endPresentedSession()
    }

    /// Explicit Cancel/close when no apply is in flight. Discards the live draft.
    func cancelAndClose() {
        guard !sessionState.isApplying else { return }
        isWindowPresented = false
        endPresentedSession()
    }

    private func endPresentedSession() {
        // Invalidate any detached load or late completion for this presentation.
        loadGeneration &+= 1
        draftGeneration &+= 1
        sessionState = .idle
        targets = []
        originalPropertyMaps = [:]
        draftPropertyMaps = [:]
        loadErrorMessage = nil
        isLoading = false
        selectedFieldKeys = []
        currentApplyID = nil
        currentApplyRequest = nil
        currentApplyTask = nil
    }

    /// What the main window should do for a requested Metadata Editor open.
    ///
    /// A watch-prune or other passive publication never calls this; it only
    /// decides an explicit user open. The store never resets itself here.
    func openDecision(for targetIDs: [AudioFile.ID]) -> MetadataEditorOpenDecision {
        guard let presentationID = currentPresentationID else {
            if let drainingApply {
                return .presentWhileDraining(presentationID: drainingApply.presentationID)
            }
            return .presentNew
        }

        let requestedIDs = Set(targetIDs)
        switch sessionState {
        case .idle:
            if let drainingApply {
                return .presentWhileDraining(presentationID: drainingApply.presentationID)
            }
            return .presentNew
        case .loading:
            return requestedIDs == Set(currentTargetIDs)
                ? .focusExisting(presentationID: presentationID)
                : (isDrainingApply
                    ? .presentWhileDraining(presentationID: presentationID)
                    : .presentNew)
        case .applying:
            // The window is presented whenever a session is loading/ready/applying;
            // a closed window ends the presented session. Focus rather than reset.
            return .focusExisting(presentationID: presentationID)
        case .ready:
            if requestedIDs == Set(currentTargetIDs) {
                return .focusExisting(presentationID: presentationID)
            }
            if isWindowPresented, hasUnsavedChanges {
                return .confirmDiscardAndOpen(presentationID: presentationID)
            }
            return .presentNew
        }
    }

    /// Deliberate discard-and-open for a confirmed different-target request.
    /// Revalidation against `sessionID` means a stale confirmation cannot discard
    /// a newer draft.
    @discardableResult
    func discardAndOpen(
        targetFiles: [AudioFile],
        sessionID: MetadataEditorPresentationID
    ) -> Bool {
        guard currentPresentationID == sessionID,
              case .ready = sessionState else { return false }
        endPresentedSession()
        presentNew(targetFiles: targetFiles)
        return true
    }

    func discardChanges() {
        draftPropertyMaps = originalPropertyMaps
        draftGeneration &+= 1
        realignSelection(preferred: selectedFieldKey)
    }

    /// Compatibility seam for direct apply callers and existing integration tests.
    /// The editor window itself completes applies through `startApply()` /
    /// `completeApply(_:)`, which is scoped to the captured session and targets.
    func recordAppliedTargets(_ targetIDs: Set<AudioFile.ID>) {
        guard !targetIDs.isEmpty else { return }

        targets.removeAll { targetIDs.contains($0.id) }
        for targetID in targetIDs {
            originalPropertyMaps.removeValue(forKey: targetID)
            draftPropertyMaps.removeValue(forKey: targetID)
        }
        realignSelection(preferred: selectedFieldKey)
    }

    // MARK: - Apply session lifecycle

    /// Captures the exact targets, baselines and raw maps that Done may write.
    /// Returns nil unless the store is ready, loaded, dirty and not draining.
    func startApply() -> MetadataEditorApplyRequest? {
        guard case .ready(let presentationID) = sessionState,
              !isDrainingApply,
              isEditable,
              hasUnsavedChanges else { return nil }

        let applyID = MetadataEditorApplyID()
        let request = MetadataEditorApplyRequest(
            presentationID: presentationID,
            applyID: applyID,
            targets: targets,
            pendingTargets: pendingTargets,
            submittedPropertyMaps: draftPropertyMaps,
            draftGeneration: draftGeneration
        )
        currentApplyID = applyID
        currentApplyRequest = request
        sessionState = .applying(presentationID: presentationID, applyID: applyID)
        return request
    }

    /// The window stores the task so an explicit close can cancel unstarted work.
    func attachApplyTask(_ task: Task<Void, Never>) {
        guard sessionState.isApplying else {
            task.cancel()
            return
        }
        currentApplyTask = task
    }

    /// Maps the raw apply result onto the request it belongs to. This is the
    /// store-side adapter until AudioViewModel exposes a session-scoped outcome.
    func makeApplyOutcome(
        from result: RawMetadataApplyResult,
        for request: MetadataEditorApplyRequest,
        wasCancelled: Bool = false
    ) -> MetadataEditorApplyOutcome {
        MetadataEditorApplyOutcome(
            presentationID: request.presentationID,
            applyID: request.applyID,
            succeededTargetIDs: result.succeededTargetIDs,
            failedTargetIDs: result.failedTargetIDs,
            didApplyAllChanges: result.didApplyAllChanges,
            wasCancelled: wasCancelled
        )
    }

    /// Accepts an apply outcome only for the session/apply that started it.
    ///
    /// Successful targets are removed only when the current customer-facing
    /// target still equals the captured target (ID, URL, expected revision and
    /// baseline). Failures keep their original property maps and live intent. A
    /// completion that belongs to a closed/draining session is recorded as the
    /// app-owned outcome but can never mutate a newer presentation.
    @discardableResult
    func completeApply(_ outcome: MetadataEditorApplyOutcome) -> MetadataEditorApplyCompletion {
        if let drainingApply,
           outcome.presentationID == drainingApply.presentationID,
           outcome.applyID == drainingApply.applyID {
            lastApplyOutcome = outcome
            self.drainingApply = nil
            isDrainingApply = false
            return .sessionClosed
        }

        guard case .applying(let presentationID, let applyID) = sessionState,
              outcome.presentationID == presentationID,
              outcome.applyID == applyID,
              let request = currentApplyRequest else {
            suppressedStaleCompletionCount &+= 1
            return .sessionClosed
        }

        lastApplyOutcome = outcome
        removeCapturedSuccessfulTargets(
            outcome.succeededTargetIDs,
            capturedTargets: request.pendingTargets
        )
        let hasNewerDraftEdits = draftGeneration != request.draftGeneration
        currentApplyID = nil
        currentApplyRequest = nil
        currentApplyTask = nil
        sessionState = .ready(presentationID: presentationID)

        if outcome.didApplyAllChanges && !hasNewerDraftEdits {
            return .dismiss
        }
        return .remainReady
    }

    private func removeCapturedSuccessfulTargets(
        _ succeededTargetIDs: Set<AudioFile.ID>,
        capturedTargets: [MetadataEditorTarget]
    ) {
        var capturedByID: [AudioFile.ID: MetadataEditorTarget] = [:]
        for target in capturedTargets where capturedByID[target.id] == nil {
            capturedByID[target.id] = target
        }

        var removedAny = false
        for targetID in succeededTargetIDs {
            guard let capturedTarget = capturedByID[targetID],
                  let index = targets.firstIndex(where: { $0.id == targetID }),
                  targets[index] == capturedTarget else { continue }
            targets.remove(at: index)
            originalPropertyMaps.removeValue(forKey: targetID)
            draftPropertyMaps.removeValue(forKey: targetID)
            removedAny = true
        }
        if removedAny {
            realignSelection(preferred: selectedFieldKey)
        }
    }

    fileprivate func makeAddFieldContext() -> MetadataFieldEditorContext {
        MetadataFieldEditorContext(
            mode: .add,
            key: nil,
            initialValue: "",
            isMixed: false
        )
    }

    fileprivate func makeEditFieldContext() -> MetadataFieldEditorContext? {
        guard isEditable, let key = selectedFieldKey else { return nil }

        let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
        let firstValues = values.first ?? []
        let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValues }

        return MetadataFieldEditorContext(
            mode: .edit,
            key: key,
            initialValue: isUniform ? firstValues.joined(separator: "\n") : "",
            isMixed: !isUniform,
            displayName: MetadataFieldGuide.displayName(forRawKey: key, fileExtensions: targets.map { $0.url.pathExtension })
        )
    }

    func upsertField(key: String, value: String) {
        guard isEditable else { return }
        let normalizedKey = Self.normalizedFieldKey(key)
        guard !normalizedKey.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap[normalizedKey] = Self.exactFieldValues(value)
            draftPropertyMaps[target.id] = propertyMap
        }

        draftGeneration &+= 1
        selectedFieldKey = normalizedKey
    }

    fileprivate func commitFieldEntry(
        context: MetadataFieldEditorContext,
        key: String,
        value: String
    ) {
        guard isEditable else { return }
        switch context.mode {
        case .add:
            upsertField(key: key, value: value)
        case .edit:
            guard let originalKey = context.key else { return }
            upsertField(key: originalKey, value: value)
        }
    }

    func previewTextUtility(
        pipeline: TextEditPipeline,
        fieldKeys: Set<String>
    ) -> [MetadataTextUtilityPreviewRow] {
        guard !fieldKeys.isEmpty else { return [] }

        let sortedKeys = fieldKeys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        return targets.flatMap { target in
            sortedKeys.compactMap { key in
                guard let currentValues = draftPropertyMaps[target.id]?[key] else { return nil }
                let currentValue = currentValues.joined(separator: "\n")
                return MetadataTextUtilityPreviewRow(
                    targetID: target.id,
                    fileName: target.fileName,
                    fieldKey: key,
                    currentValue: currentValue,
                    previewValue: pipeline.applying(to: currentValue)
                )
            }
        }
    }

    func applyTextUtility(
        pipeline: TextEditPipeline,
        fieldKeys: Set<String>
    ) {
        guard isEditable, !fieldKeys.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]

            for key in fieldKeys {
                guard let currentValues = propertyMap[key] else { continue }
                propertyMap[key] = currentValues.map { pipeline.applying(to: $0) }
            }

            draftPropertyMaps[target.id] = propertyMap
        }

        draftGeneration &+= 1
        realignSelection(preferred: selectedFieldKey)
    }

    func deleteSelectedField() {
        guard isEditable, !selectedFieldKeys.isEmpty else { return }

        for key in selectedFieldKeys {
            deleteField(named: key, realignAfterDelete: false)
        }

        realignSelection(preferred: nil)
    }

    func deleteField(named key: String, realignAfterDelete: Bool = true) {
        guard isEditable, !key.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap.removeValue(forKey: key)
            draftPropertyMaps[target.id] = propertyMap
        }

        draftGeneration &+= 1
        if realignAfterDelete {
            realignSelection(preferred: nil)
        }
    }

    private func realignSelection(preferred: String?) {
        selectedFieldKeys = MetadataEditorDraftRows.realignedSelection(
            currentSelection: selectedFieldKeys,
            preferred: preferred,
            rows: rows
        )
    }

    nonisolated private static func loadState(
        for targets: [MetadataEditorTarget],
        metadataPipeline: any AudioMetadataPipeline
    ) -> LoadedState {
        var propertyMaps: [AudioFile.ID: RawMetadataValueMap] = [:]
        var failures: [String] = []
        var loadedTargets: [MetadataEditorTarget] = []

        for target in targets {
            do {
                if let original = target.metadataConflictBaseline, let fingerprint = target.expectedFileFingerprint {
                    guard !target.requiresMetadataRefresh else { throw TagLibManagerError.fileChanged }
                    let snapshot = try MetadataConflictResolver.currentSnapshot(
                        pipeline: metadataPipeline, url: target.url, originalFingerprint: fingerprint,
                        originalVersion: target.expectedMetadataVersion, original: original
                    )
                    let currentFingerprint = try AudioFileFingerprint.capture(at: target.url)
                    guard snapshot.fileVersion == (try metadataPipeline.metadataFileVersion(at: target.url)) else {
                        throw TagLibManagerError.fileChanged
                    }
                    let refreshed = MetadataEditorTarget(target: target, fingerprint: currentFingerprint, snapshot: snapshot)
                    loadedTargets.append(refreshed)
                    propertyMaps[target.id] = refreshed.metadataConflictBaseline?.values
                } else {
                    propertyMaps[target.id] = try metadataPipeline.rawMetadataValueMap(for: target.url)
                    loadedTargets.append(target)
                }
            } catch {
                loadedTargets.append(target)
                failures.append(String(localized: "Metadata couldn’t be read from “\(target.fileName)”.\nDetails: \((error as NSError).localizedDescription)"))
            }
        }

        let errorMessage: String?
        if failures.isEmpty {
            errorMessage = nil
        } else if failures.count == 1 {
            errorMessage = failures[0]
        } else {
            errorMessage = ([ String(localized: "Metadata couldn’t be read from \(failures.count) files.") ] + failures.prefix(3) + (failures.count > 3 ? [String(localized: "Additional files that couldn’t be read: \(failures.count - 3).")] : [])).joined(separator: "\n")
        }

        return LoadedState(targets: loadedTargets, propertyMaps: propertyMaps, errorMessage: errorMessage)
    }

    nonisolated private static func normalizedFieldKey(_ key: String) -> String {
        MetadataFieldSuggestion.resolvedKey(for: key)
    }

    nonisolated private static func exactFieldValues(_ value: String) -> [String] {
        value.components(separatedBy: "\n")
    }
}

struct MetadataEditorWindowView: View {
    static let windowID = "metadata-editor"

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var store: MetadataEditorStore

    @Environment(\.dismiss) private var dismiss

    @State private var editorContext: MetadataFieldEditorContext?
    @State private var utilityContext: MetadataTextUtilitiesContext?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
                footer
            }
            .padding(20)
            .frame(minWidth: 820, idealWidth: 920, maxWidth: 1040, minHeight: 540, idealHeight: 640)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(AppWindowTitle.metadataEditor)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(
            MetadataEditorWindowCloseObserver {
                store.windowWillClose(presentationID: store.currentPresentationID)
            }
        )
        .sheet(item: $editorContext) { context in
            MetadataFieldEntrySheet(context: context) { key, value in
                store.commitFieldEntry(context: context, key: key, value: value)
            }
        }
        .sheet(item: $utilityContext) { context in
            MetadataTextUtilitiesSheet(store: store, fieldKeys: context.fieldKeys) {
                utilityContext = nil
            }
        }
        .onAppear {
            store.windowDidAppear()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if store.hasUnsavedChanges {
                    Text("Unsaved Changes")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                }
            }

            Text(store.selectionSummaryText)
                .font(.headline)

            Text(store.selectionDetailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            VStack(spacing: 10) {
                Spacer()
                ProgressView("Loading metadata…".localizedUI)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.loadErrorMessage {
            ContentUnavailableView(
                String(localized: "Metadata Couldn’t Be Read"),
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.rows.isEmpty {
            ContentUnavailableView(
                "No Metadata Fields",
                systemImage: "tag",
                description: Text(
                    String(localized: "The selected files have no non-empty metadata fields to show in this editor.")
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MetadataEditorTable(
                rows: store.rows,
                selectedFieldKeys: $store.selectedFieldKeys,
                onEditField: {
                    editorContext = store.makeEditFieldContext()
                },
                onDeleteField: { key in
                    store.deleteField(named: key)
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Edit Selected…") {
                editorContext = store.makeEditFieldContext()
            }
            .disabled(store.selectedFieldKeys.count != 1 || !store.isEditable || store.isApplying)

            Button("Add Field…") {
                editorContext = store.makeAddFieldContext()
            }
            .disabled(!store.isEditable || store.isApplying)

            Button("Delete Field", role: .destructive) {
                store.deleteSelectedField()
            }
            .disabled(store.selectedFieldKeys.isEmpty || !store.isEditable || store.isApplying)

            Button("Utilities…") {
                utilityContext = MetadataTextUtilitiesContext(fieldKeys: store.selectedFieldKeys)
            }
            .disabled(store.selectedFieldKeys.isEmpty || !store.isEditable || store.isApplying)

            Spacer()

            if store.isApplying {
                ProgressView()
                    .controlSize(.small)
            } else if store.applyBlockedByDraining {
                ProgressView()
                    .controlSize(.small)
                    .help(String(localized: "A previous save is still finishing. Wait before saving again."))
            }

            Button("Cancel") {
                store.cancelAndClose()
                dismiss()
            }
            .disabled(store.isApplying)

            Button("Done") {
                Task {
                    await commitAndDismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.isLoading || !store.canStartApply)
        }
    }

    private func commitAndDismiss() async {
        if !store.hasUnsavedChanges {
            dismiss()
            return
        }

        guard let request = store.startApply() else { return }
        let applyTask = Task { @MainActor in
            let applyResult = await viewModel.applyRawMetadataPropertyMaps(
                request.submittedPropertyMaps,
                to: request.pendingTargets
            )
            let outcome = store.makeApplyOutcome(
                from: applyResult,
                for: request,
                wasCancelled: Task.isCancelled
            )
            switch store.completeApply(outcome) {
            case .dismiss:
                dismiss()
            case .remainReady, .sessionClosed:
                break
            }
        }
        store.attachApplyTask(applyTask)
        await applyTask.value
    }
}

/// Window-close ownership for the Metadata Editor.
///
/// The close is reported to `MetadataEditorStore` with the presentation identity
/// captured at notification time; the store ignores a superseded identity and
/// never relies on a generic `onDisappear` reset.
private struct MetadataEditorWindowCloseObserver: NSViewRepresentable {
    let onWindowWillClose: () -> Void

    func makeNSView(context: Context) -> MetadataEditorWindowCloseObserverView {
        let view = MetadataEditorWindowCloseObserverView()
        view.onWindowWillClose = onWindowWillClose
        return view
    }

    func updateNSView(_ nsView: MetadataEditorWindowCloseObserverView, context: Context) {
        nsView.onWindowWillClose = onWindowWillClose
    }
}

private final class MetadataEditorWindowCloseObserverView: NSView {
    var onWindowWillClose: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        onWindowWillClose?()
    }

    private func detach() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
}
