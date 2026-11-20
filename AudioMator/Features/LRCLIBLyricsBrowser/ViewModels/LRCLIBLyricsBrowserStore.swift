import Foundation
import Combine

enum LRCLIBLyricsSearchState: Equatable {
    case idle
    case searching
    case loaded
    case cancelled
    case failed(String)
}

/// Main-actor owner of one LRCLIB browser session and its search-to-write operation.
///
/// The store owns:
/// - one `sessionID` plus a monotonic generation, bumped by every reseed, close and
///   Sources navigation;
/// - the queued rows, each carrying the metadata-only query input beside the
///   `ReviewedMetadataTarget` captured from the exact seed observation;
/// - at most one active operation token, its task and its published progress.
///
/// All published state is gated by the session generation and the operation
/// identity, so a late provider response or an already-started commit can never
/// mutate a replacement session. Disk work always goes through the injected
/// `LRCLIBLyricsWriting` (the `AudioViewModel` strict reviewed-write route); the
/// store itself never writes a file.
@MainActor
final class LRCLIBLyricsBrowserStore: ObservableObject {
    private struct FileState {
        var searchState: LRCLIBLyricsSearchState = .idle
        var rankedCandidates: [LRCLIBRankedCandidate] = []
        var selectedCandidateID: LRCLIBLyricsCandidate.ID?
        var appliedCandidateID: LRCLIBLyricsCandidate.ID?
    }

    private enum SessionEndReason {
        case reseed
        case windowClosed
        case navigatedBack
    }

    @Published private(set) var rows: [LRCLIBLyricsSessionRow] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var sourceDescription: String = "Select files in AudioMator, then choose LRCLIB."
    @Published private(set) var navigationResetToken = UUID()
    @Published private(set) var operationProgress: LRCLIBLyricsOperationProgress?
    @Published private var statesByFileID: [AudioFile.ID: FileState] = [:]

    private(set) var sessionID = LRCLIBLyricsSessionID()
    private(set) var sessionGeneration: UInt64 = 0
    private(set) var activeOperation: LRCLIBLyricsOperationToken?
    /// Operations cancelled by a session end that are still draining. Tests and the
    /// next session can observe that a cancelled task has not yet exited.
    private(set) var drainingOperationIDs: Set<LRCLIBLyricsOperationID> = []

    private let client: any LRCLIBLyricsSearching
    private let providerCallTimeout: Duration
    private var operationTask: Task<Void, Never>?
    private var manualSearchTask: Task<Void, Never>?

    init(
        client: any LRCLIBLyricsSearching = LRCLIBClient(),
        providerCallTimeout: Duration = .seconds(30)
    ) {
        self.client = client
        self.providerCallTimeout = providerCallTimeout
    }

    deinit {
        operationTask?.cancel()
        manualSearchTask?.cancel()
    }

    // MARK: - Queue projection

    var fileInputs: [LRCLIBFileSearchInput] { rows.map(\.input) }

    var hasFiles: Bool { !rows.isEmpty }

    var currentRow: LRCLIBLyricsSessionRow? {
        guard rows.indices.contains(currentIndex) else { return nil }
        return rows[currentIndex]
    }

    var currentFile: LRCLIBFileSearchInput? { currentRow?.input }

    var searchState: LRCLIBLyricsSearchState {
        guard let currentFile else { return .idle }
        return statesByFileID[currentFile.id]?.searchState ?? .idle
    }

    var rankedCandidates: [LRCLIBRankedCandidate] {
        guard let currentFile else { return [] }
        return statesByFileID[currentFile.id]?.rankedCandidates ?? []
    }

    var selectedCandidateID: LRCLIBLyricsCandidate.ID? {
        guard let currentFile else { return nil }
        return statesByFileID[currentFile.id]?.selectedCandidateID
    }

    var selectedCandidate: LRCLIBLyricsCandidate? {
        guard let selectedCandidateID else { return nil }
        return rankedCandidates.first { $0.id == selectedCandidateID }?.candidate
    }

    var appliedCandidateID: LRCLIBLyricsCandidate.ID? {
        guard let currentFile else { return nil }
        return statesByFileID[currentFile.id]?.appliedCandidateID
    }

    var canMovePrevious: Bool { currentIndex > 0 }
    var canMoveNext: Bool { currentIndex + 1 < rows.count }
    var hasMultipleFiles: Bool { rows.count > 1 }

    var queuePositionText: String {
        guard hasFiles else { return "No files selected" }
        return "\(currentIndex + 1) of \(rows.count)"
    }

    var hasSyncedCandidate: Bool {
        rankedCandidates.contains { $0.candidate.hasSyncedLyrics }
    }

    var canApplySelectedCandidate: Bool {
        selectedCandidate?.hasSyncedLyrics == true
    }

    var isOperationActive: Bool { activeOperation != nil }

    var hasDrainingOperations: Bool { !drainingOperationIDs.isEmpty }

    // MARK: - Session lifecycle (the only owner of generation invalidation)

    /// Starts a new session for the supplied selection snapshots.
    ///
    /// Captures the reviewed target from the exact `AudioFile` that supplies the
    /// HTTP query, in the same pass. A file without write authority is still
    /// queued for search/preview with `target == nil`.
    func seed(from files: [AudioFile]) {
        endSession(clearingRows: true, reason: .reseed)
        let newRows = files.map { file in
            LRCLIBLyricsSessionRow(
                input: LRCLIBFileSearchInput(file: file),
                target: ReviewedMetadataTarget(verified: file)
            )
        }
        rows = newRows
        currentIndex = 0
        statesByFileID = Dictionary(uniqueKeysWithValues: newRows.map { ($0.id, FileState()) })
        sourceDescription = newRows.count == 1
            ? "From the selected file metadata, filename, and path."
            : "Reviewing \(newRows.count) selected files one by one."
        navigationResetToken = UUID()
    }

    /// Full teardown when the Online Metadata window closes (or is replaced).
    func closeWindowSession() {
        endSession(clearingRows: true, reason: .windowClosed)
        sourceDescription = "Select files in AudioMator, then choose LRCLIB."
    }

    /// Returning to Sources: cancels outstanding lookups and unstarted writes,
    /// invalidates the generation, clears candidates/applied marks, and retains the
    /// queued rows with their seed bindings so the user can resume with a fresh
    /// Search (or reseed for a changed file).
    func leaveBrowser() {
        endSession(clearingRows: false, reason: .navigatedBack)
        if rows.isEmpty {
            sourceDescription = "Select files in AudioMator, then choose LRCLIB."
        } else if rows.count == 1 {
            sourceDescription = "From the selected file metadata, filename, and path."
        } else {
            sourceDescription = "Reviewing \(rows.count) selected files one by one."
        }
    }

    private func endSession(clearingRows: Bool, reason: SessionEndReason) {
        _ = reason
        // Invalidate first: a completion that slips in afterwards can never pass
        // the generation/operation gate, even if its Swift task ignores cancelling.
        sessionGeneration &+= 1

        manualSearchTask?.cancel()
        manualSearchTask = nil

        if let token = activeOperation {
            operationTask?.cancel()
            drainingOperationIDs.insert(token.operationID)
            activeOperation = nil
            operationTask = nil
            operationProgress = nil
        }

        statesByFileID = statesByFileID.mapValues { state in
            FileState() // clear search results, selection and applied marks
        }
        if clearingRows {
            rows = []
            currentIndex = 0
            statesByFileID = [:]
        }
    }

    // MARK: - Manual search

    func searchCurrentFile() {
        guard activeOperation == nil else { return }
        guard let row = currentRow else { return }
        let query = row.input.query
        let rowID = row.id
        let generation = sessionGeneration

        guard !query.isEmpty else {
            updateState(for: rowID, generation: generation) { state in
                state.searchState = .failed(LRCLIBClientError.emptyQuery.localizedDescription)
                state.rankedCandidates = []
                state.selectedCandidateID = nil
            }
            return
        }

        manualSearchTask?.cancel()
        updateState(for: rowID, generation: generation) { state in
            state.searchState = .searching
            state.rankedCandidates = []
            state.selectedCandidateID = nil
        }

        manualSearchTask = Task { [client, providerCallTimeout, weak self] in
            do {
                let candidates = try await withAsyncTimeout(
                    providerCallTimeout,
                    operationName: String(localized: "Searching LRCLIB")
                ) {
                    try await client.search(matching: query, limit: 20)
                }
                guard !Task.isCancelled, let self, generation == self.sessionGeneration else { return }
                self.manualSearchTask = nil
                let rankedCandidates = LRCLIBCandidateRanker.rankedCandidates(candidates, for: query)
                self.updateState(for: rowID, generation: generation) { state in
                    state.searchState = .loaded
                    state.rankedCandidates = rankedCandidates
                    state.selectedCandidateID = rankedCandidates.first?.id
                }
            } catch is CancellationError {
                guard !Task.isCancelled, let self, generation == self.sessionGeneration else { return }
                self.manualSearchTask = nil
                self.updateState(for: rowID, generation: generation) { state in
                    state.searchState = .cancelled
                }
            } catch {
                guard !Task.isCancelled, let self, generation == self.sessionGeneration else { return }
                self.manualSearchTask = nil
                self.updateState(for: rowID, generation: generation) { state in
                    state.searchState = .failed(
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                    state.rankedCandidates = []
                    state.selectedCandidateID = nil
                }
            }
        }
    }

    func cancelSearch() {
        guard let row = currentRow, searchState == .searching else { return }
        manualSearchTask?.cancel()
        manualSearchTask = nil
        updateState(for: row.id, generation: sessionGeneration) { state in
            state.searchState = .cancelled
        }
    }

    /// Deliberately cancels any in-flight manual search before a bulk operation or
    /// a row change, publishing the departing row's terminal state first.
    private func supersedeManualSearch() {
        guard let row = currentRow else { return }
        let wasSearching = searchState == .searching
        manualSearchTask?.cancel()
        manualSearchTask = nil
        if wasSearching {
            updateState(for: row.id, generation: sessionGeneration) { state in
                state.searchState = .cancelled
            }
        }
    }

    // MARK: - Candidate selection and navigation

    func selectCandidate(_ candidateID: LRCLIBLyricsCandidate.ID?) {
        guard let row = currentRow else { return }
        updateState(for: row.id, generation: sessionGeneration) { state in
            state.selectedCandidateID = candidateID
        }
    }

    func movePrevious() {
        guard canMovePrevious else { return }
        supersedeManualSearch()
        currentIndex -= 1
        navigationResetToken = UUID()
    }

    func moveNext() {
        guard canMoveNext else { return }
        supersedeManualSearch()
        currentIndex += 1
        navigationResetToken = UUID()
    }

    // MARK: - Operations (the only owner of search-to-write lifecycle)

    /// Starts one manual apply for the current row's selected candidate.
    ///
    /// Returns false when another operation is active or no synced candidate is
    /// selected. Duplicate clicks for the same session therefore cannot create a
    /// second job.
    @discardableResult
    func startManualApply(writer: any LRCLIBLyricsWriting) -> Bool {
        guard activeOperation == nil,
              let row = currentRow,
              let candidate = selectedCandidate,
              candidate.hasSyncedLyrics,
              let token = beginOperation(kind: .manualApply) else {
            return false
        }
        let intent = LRCLIBLyricsWriteIntentBuilder.manualIntent(
            row: row,
            candidate: candidate,
            operation: token
        )
        operationProgress = LRCLIBLyricsOperationProgress(
            kind: .manualApply,
            phase: .writing,
            completedCount: 0,
            totalCount: 1,
            currentFileName: row.input.fileName
        )
        operationTask = Task { [weak self, writer] in
            guard let self else { return }
            await self.runManualApply(token: token, intent: intent, writer: writer)
        }
        return true
    }

    /// Starts one bulk apply over a snapshot of the queued rows.
    ///
    /// Deliberately supersedes any tracked manual search first. Returns false when
    /// another operation is already active (`duplicate start during cancellation or
    /// drain` is rejected) or the queue is empty.
    @discardableResult
    func startAutoApply(writer: any LRCLIBLyricsWriting) -> Bool {
        guard activeOperation == nil, !rows.isEmpty else { return false }
        supersedeManualSearch()
        guard let token = beginOperation(kind: .autoApply) else { return false }
        let queueSnapshot = rows
        operationProgress = LRCLIBLyricsOperationProgress(
            kind: .autoApply,
            phase: .searching,
            completedCount: 0,
            totalCount: queueSnapshot.count,
            currentFileName: queueSnapshot.first?.input.fileName ?? ""
        )
        operationTask = Task { [weak self, writer] in
            guard let self else { return }
            await self.runAutoApply(token: token, queue: queueSnapshot, writer: writer)
        }
        return true
    }

    /// Marks applied candidates only for the rows/candidates the writer committed
    /// and only while the exact session generation and operation are still current.
    /// Never consults `currentIndex`/`currentRow`.
    func markApplied(_ entries: [LRCLIBLyricsAppliedEntry], for token: LRCLIBLyricsOperationToken) {
        guard isCurrent(token) else { return }
        for entry in entries where statesByFileID[entry.fileID] != nil {
            statesByFileID[entry.fileID]?.appliedCandidateID = entry.candidateID
        }
    }

    // MARK: - Operation loop

    private func beginOperation(kind: LRCLIBLyricsOperationKind) -> LRCLIBLyricsOperationToken? {
        guard activeOperation == nil else { return nil }
        let token = LRCLIBLyricsOperationToken(
            sessionID: sessionID,
            generation: sessionGeneration,
            operationID: LRCLIBLyricsOperationID(),
            kind: kind
        )
        activeOperation = token
        return token
    }

    private func runManualApply(
        token: LRCLIBLyricsOperationToken,
        intent: LRCLIBLyricsManualWriteIntent,
        writer: any LRCLIBLyricsWriting
    ) async {
        guard checkpoint(token) else {
            finishOperation(token)
            return
        }
        let outcome = await writer.applyLRCLIBLyrics(intent)
        if case .applied = outcome {
            markApplied(
                [LRCLIBLyricsAppliedEntry(fileID: intent.fileID, candidateID: intent.candidateID)],
                for: token
            )
        }
        finishOperation(token)
    }

    private func runAutoApply(
        token: LRCLIBLyricsOperationToken,
        queue: [LRCLIBLyricsSessionRow],
        writer: any LRCLIBLyricsWriting
    ) async {
        var entries: [LRCLIBLyricsAutoWriteEntry] = []
        let totalCount = queue.count
        let client = self.client
        let providerCallTimeout = self.providerCallTimeout

        for (index, row) in queue.enumerated() {
            guard checkpoint(token) else {
                finishOperation(token)
                return
            }
            publishProgress(
                token,
                phase: .searching,
                completedCount: index,
                totalCount: totalCount,
                fileName: row.input.fileName
            )

            let query = row.input.query
            guard !query.isEmpty else {
                updateState(for: token, fileID: row.id) { state in
                    state.searchState = .failed(LRCLIBClientError.emptyQuery.localizedDescription)
                    state.rankedCandidates = []
                    state.selectedCandidateID = nil
                }
                continue
            }

            updateState(for: token, fileID: row.id) { state in
                state.searchState = .searching
                state.rankedCandidates = []
                state.selectedCandidateID = nil
            }

            do {
                let candidates = try await withAsyncTimeout(
                    providerCallTimeout,
                    operationName: String(localized: "Searching LRCLIB")
                ) {
                    try await client.search(matching: query, limit: 20)
                }
                guard checkpoint(token) else {
                    finishOperation(token)
                    return
                }

                let rankedCandidates = LRCLIBCandidateRanker.rankedCandidates(candidates, for: query)
                let bestSyncedCandidate = rankedCandidates.first {
                    LRCLIBCandidateRanker.isHighConfidenceAutoMatch($0.candidate, for: query)
                        && $0.candidate.hasSyncedLyrics
                }?.candidate

                updateState(for: token, fileID: row.id) { state in
                    state.searchState = .loaded
                    state.rankedCandidates = rankedCandidates
                    state.selectedCandidateID = bestSyncedCandidate?.id ?? rankedCandidates.first?.id
                }

                if let bestSyncedCandidate {
                    entries.append(
                        LRCLIBLyricsWriteIntentBuilder.autoEntry(
                            row: row,
                            candidate: bestSyncedCandidate,
                            operation: token
                        )
                    )
                }
            } catch is CancellationError {
                finishOperation(token)
                return
            } catch {
                guard checkpoint(token) else {
                    finishOperation(token)
                    return
                }
                updateState(for: token, fileID: row.id) { state in
                    state.searchState = .failed(
                        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                    state.rankedCandidates = []
                    state.selectedCandidateID = nil
                }
            }
        }

        // Handoff checkpoint: a late provider result or a session end must never
        // start a write.
        guard checkpoint(token) else {
            finishOperation(token)
            return
        }
        publishProgress(
            token,
            phase: .writing,
            completedCount: 0,
            totalCount: max(entries.count, 1),
            fileName: ""
        )

        let intent = LRCLIBLyricsAutoWriteIntent(operation: token, entries: entries)
        let outcome = await writer.applyLRCLIBLyricsAutoMatches(intent)
        if isCurrent(token) {
            markApplied(outcome.appliedEntries, for: token)
        }
        finishOperation(token)
    }

    private func publishProgress(
        _ token: LRCLIBLyricsOperationToken,
        phase: LRCLIBLyricsOperationPhase,
        completedCount: Int,
        totalCount: Int,
        fileName: String
    ) {
        guard isCurrent(token) else { return }
        operationProgress = LRCLIBLyricsOperationProgress(
            kind: token.kind,
            phase: phase,
            completedCount: completedCount,
            totalCount: max(totalCount, 1),
            currentFileName: fileName
        )
    }

    private func isCurrent(_ token: LRCLIBLyricsOperationToken) -> Bool {
        token.sessionID == sessionID
            && token.generation == sessionGeneration
            && activeOperation?.operationID == token.operationID
    }

    private func checkpoint(_ token: LRCLIBLyricsOperationToken) -> Bool {
        !Task.isCancelled && isCurrent(token)
    }

    private func finishOperation(_ token: LRCLIBLyricsOperationToken) {
        drainingOperationIDs.remove(token.operationID)
        guard isCurrent(token) else { return }
        activeOperation = nil
        operationTask = nil
        operationProgress = nil
    }

    // MARK: - Gated state mutation

    private func updateState(
        for fileID: AudioFile.ID,
        generation: UInt64,
        mutate: (inout FileState) -> Void
    ) {
        guard generation == sessionGeneration, statesByFileID[fileID] != nil else { return }
        var state = statesByFileID[fileID] ?? FileState()
        mutate(&state)
        statesByFileID[fileID] = state
    }

    private func updateState(
        for token: LRCLIBLyricsOperationToken,
        fileID: AudioFile.ID,
        mutate: (inout FileState) -> Void
    ) {
        guard isCurrent(token) else { return }
        var state = statesByFileID[fileID] ?? FileState()
        mutate(&state)
        statesByFileID[fileID] = state
    }
}
