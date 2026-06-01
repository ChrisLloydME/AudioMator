import Foundation
import Combine

enum LRCLIBLyricsSearchState: Equatable {
    case idle
    case searching
    case loaded
    case cancelled
    case failed(String)
}

struct LRCLIBSyncedLyricsAutoMatch: Identifiable, Equatable, Sendable {
    var id: AudioFile.ID { fileID }

    let fileID: AudioFile.ID
    let fileName: String
    let candidateID: LRCLIBLyricsCandidate.ID
    let syncedLyrics: String
}

@MainActor
final class LRCLIBLyricsBrowserStore: ObservableObject {
    private struct FileState {
        var searchState: LRCLIBLyricsSearchState = .idle
        var rankedCandidates: [LRCLIBRankedCandidate] = []
        var selectedCandidateID: LRCLIBLyricsCandidate.ID?
        var appliedCandidateID: LRCLIBLyricsCandidate.ID?
    }

    @Published private(set) var fileInputs: [LRCLIBFileSearchInput] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var sourceDescription: String = "Select files in AudioMator, then choose LRCLIB."
    @Published private(set) var navigationResetToken = UUID()

    private let client: any LRCLIBLyricsSearching
    private var searchTask: Task<Void, Never>?
    @Published private var statesByFileID: [AudioFile.ID: FileState] = [:]

    init(client: any LRCLIBLyricsSearching = LRCLIBClient()) {
        self.client = client
    }

    deinit {
        searchTask?.cancel()
    }

    var hasFiles: Bool {
        !fileInputs.isEmpty
    }

    var currentFile: LRCLIBFileSearchInput? {
        guard fileInputs.indices.contains(currentIndex) else { return nil }
        return fileInputs[currentIndex]
    }

    var currentQuery: LRCLIBSearchQuery? {
        currentFile?.query
    }

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

    var canMovePrevious: Bool {
        currentIndex > 0
    }

    var canMoveNext: Bool {
        currentIndex + 1 < fileInputs.count
    }

    var hasMultipleFiles: Bool {
        fileInputs.count > 1
    }

    var queuePositionText: String {
        guard hasFiles else { return "No files selected" }
        return "\(currentIndex + 1) of \(fileInputs.count)"
    }

    var hasSyncedCandidate: Bool {
        rankedCandidates.contains { $0.candidate.hasSyncedLyrics }
    }

    var canApplySelectedCandidate: Bool {
        selectedCandidate?.hasSyncedLyrics == true
    }

    func seed(from files: [AudioFile]) {
        searchTask?.cancel()
        let inputs = files.map(LRCLIBFileSearchInput.init(file:))
        fileInputs = inputs
        currentIndex = 0
        statesByFileID = Dictionary(
            uniqueKeysWithValues: inputs.map { ($0.id, FileState()) }
        )
        sourceDescription = inputs.count == 1
            ? "From the selected file metadata, filename, and path."
            : "Reviewing \(inputs.count) selected files one by one."
        navigationResetToken = UUID()
    }

    func closeWindowSession() {
        searchTask?.cancel()
        fileInputs = []
        currentIndex = 0
        statesByFileID = [:]
        sourceDescription = "Select files in AudioMator, then choose LRCLIB."
        navigationResetToken = UUID()
    }

    func searchCurrentFile() {
        guard let file = currentFile else { return }
        let query = file.query
        guard !query.isEmpty else {
            updateState(for: file.id) { state in
                state.searchState = .failed(LRCLIBClientError.emptyQuery.localizedDescription)
                state.rankedCandidates = []
                state.selectedCandidateID = nil
            }
            return
        }

        searchTask?.cancel()
        updateState(for: file.id) { state in
            state.searchState = .searching
            state.rankedCandidates = []
            state.selectedCandidateID = nil
        }

        searchTask = Task { [client] in
            do {
                let candidates = try await client.search(matching: query, limit: 20)
                guard !Task.isCancelled else { return }
                let rankedCandidates = LRCLIBCandidateRanker.rankedCandidates(candidates, for: query)
                await MainActor.run {
                    self.updateState(for: file.id) { state in
                        state.searchState = .loaded
                        state.rankedCandidates = rankedCandidates
                        state.selectedCandidateID = rankedCandidates.first?.id
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.updateState(for: file.id) { state in
                        state.searchState = .cancelled
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.updateState(for: file.id) { state in
                        state.searchState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                        state.rankedCandidates = []
                        state.selectedCandidateID = nil
                    }
                }
            }
        }
    }

    func autoSyncedLyricsMatchesForAllFiles(
        progress: @MainActor (_ completedCount: Int, _ totalCount: Int, _ currentFileName: String) -> Void
    ) async -> [LRCLIBSyncedLyricsAutoMatch] {
        guard hasFiles else { return [] }

        searchTask?.cancel()
        var matches: [LRCLIBSyncedLyricsAutoMatch] = []
        let totalCount = fileInputs.count

        progress(0, totalCount, fileInputs.first?.fileName ?? "")

        for (index, file) in fileInputs.enumerated() {
            guard !Task.isCancelled else { break }

            progress(index, totalCount, file.fileName)

            let query = file.query
            guard !query.isEmpty else {
                updateState(for: file.id) { state in
                    state.searchState = .failed(LRCLIBClientError.emptyQuery.localizedDescription)
                    state.rankedCandidates = []
                    state.selectedCandidateID = nil
                }
                progress(index + 1, totalCount, file.fileName)
                continue
            }

            updateState(for: file.id) { state in
                state.searchState = .searching
                state.rankedCandidates = []
                state.selectedCandidateID = nil
            }

            do {
                let candidates = try await client.search(matching: query, limit: 20)
                guard !Task.isCancelled else { break }

                let rankedCandidates = LRCLIBCandidateRanker.rankedCandidates(candidates, for: query)
                let bestSyncedCandidate = rankedCandidates.first { $0.candidate.hasSyncedLyrics }?.candidate

                updateState(for: file.id) { state in
                    state.searchState = .loaded
                    state.rankedCandidates = rankedCandidates
                    state.selectedCandidateID = bestSyncedCandidate?.id ?? rankedCandidates.first?.id
                }
                progress(index + 1, totalCount, file.fileName)

                guard
                    let bestSyncedCandidate,
                    let syncedLyrics = bestSyncedCandidate.syncedLyrics,
                    bestSyncedCandidate.hasSyncedLyrics
                else {
                    continue
                }

                matches.append(
                    LRCLIBSyncedLyricsAutoMatch(
                        fileID: file.id,
                        fileName: file.fileName,
                        candidateID: bestSyncedCandidate.id,
                        syncedLyrics: syncedLyrics
                    )
                )
            } catch is CancellationError {
                updateState(for: file.id) { state in
                    state.searchState = .cancelled
                }
                break
            } catch {
                guard !Task.isCancelled else { break }
                updateState(for: file.id) { state in
                    state.searchState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    state.rankedCandidates = []
                    state.selectedCandidateID = nil
                }
                progress(index + 1, totalCount, file.fileName)
            }
        }

        return matches
    }

    func cancelSearch() {
        guard searchState == .searching else { return }
        searchTask?.cancel()
        if let currentFile {
            updateState(for: currentFile.id) { state in
                state.searchState = .cancelled
            }
        }
    }

    func selectCandidate(_ candidateID: LRCLIBLyricsCandidate.ID?) {
        guard let currentFile else { return }
        updateState(for: currentFile.id) { state in
            state.selectedCandidateID = candidateID
        }
    }

    func movePrevious() {
        guard canMovePrevious else { return }
        searchTask?.cancel()
        currentIndex -= 1
        navigationResetToken = UUID()
    }

    func moveNext() {
        guard canMoveNext else { return }
        searchTask?.cancel()
        currentIndex += 1
        navigationResetToken = UUID()
    }

    func markCurrentFileApplied(candidateID: LRCLIBLyricsCandidate.ID) {
        guard let currentFile else { return }
        updateState(for: currentFile.id) { state in
            state.appliedCandidateID = candidateID
        }
    }

    func markFilesApplied(_ matches: [LRCLIBSyncedLyricsAutoMatch], appliedFileIDs: Set<AudioFile.ID>) {
        for match in matches where appliedFileIDs.contains(match.fileID) {
            updateState(for: match.fileID) { state in
                state.appliedCandidateID = match.candidateID
            }
        }
    }

    private func updateState(
        for fileID: AudioFile.ID,
        mutate: (inout FileState) -> Void
    ) {
        var state = statesByFileID[fileID] ?? FileState()
        mutate(&state)
        statesByFileID[fileID] = state
    }
}
