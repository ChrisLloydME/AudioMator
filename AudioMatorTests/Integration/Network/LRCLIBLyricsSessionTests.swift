import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

/// AM-08: one explicit owner for the LRCLIB search-to-write lifecycle. Closing the
/// window, returning to Sources, or reseeding cancels outstanding lookups and every
/// write that has not crossed the commit boundary; an admitted commit completes and
/// contributes its real outcome.
nonisolated final class LRCLIBLyricsSessionTests: XCTestCase {
    private struct Queue {
        let directory: URL
        let files: [AudioFile]
        let candidates: [LRCLIBLyricsCandidate]
        let candidatesByTrackName: [String: [LRCLIBLyricsCandidate]]
    }

    // MARK: - Close / back / reseed while the provider is outstanding

    @MainActor
    func testCloseCancelsOutstandingProviderCallWithoutWrites() async throws {
        let queue = try makeQueue(count: 2)
        let gate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: gate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)

        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        try await waitUntil { client.queryCount == 1 }

        store.closeWindowSession()

        XCTAssertFalse(store.isOperationActive)
        XCTAssertNil(store.operationProgress)
        XCTAssertTrue(store.rows.isEmpty)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        gate.open()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(client.queryCount, 1, "A closed session must not start later provider requests")
        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testBackToSourcesRetainsQueueAndBindingsButClearsCandidates() async throws {
        let queue = try makeQueue(count: 2)
        let gate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: gate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        try await waitUntil { client.queryCount == 1 }

        store.leaveBrowser()

        XCTAssertEqual(store.rows.count, 2, "Back retains the queued rows")
        XCTAssertNotNil(store.rows.first?.target, "Back retains the seed bindings")
        XCTAssertEqual(store.searchState, .idle)
        XCTAssertTrue(store.rankedCandidates.isEmpty, "Back clears candidates/results")
        XCTAssertNil(store.operationProgress)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        gate.open()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.queryCount, 1)
        XCTAssertEqual(pipeline.rawWriteCount, 0)

        // A fresh explicit Search after Back is required and works against the
        // retained binding.
        store.searchCurrentFile()
        try await waitUntil { store.searchState == .loaded }
        XCTAssertFalse(store.rankedCandidates.isEmpty)
    }

    @MainActor
    func testReseedDuringProviderCallCannotMutateReplacementSession() async throws {
        let queue = try makeQueue(count: 2)
        let gate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: gate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        try await waitUntil { client.queryCount == 1 }

        let replacement = try LRCLIBLyricsTestSupport.makeObservedFile(
            named: "replacement.mp3",
            directory: queue.directory,
            title: "Replacement Song",
            artist: "Replacement Artist"
        )
        viewModel.mergeQuickImportFiles([replacement])
        store.seed(from: [replacement])

        gate.open()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(client.queryCount, 1, "The old generation must not start another request")
        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertEqual(store.rows.count, 1)
        XCTAssertEqual(store.rows.first?.id, replacement.id)
        XCTAssertEqual(store.searchState, .idle)
        XCTAssertTrue(store.rankedCandidates.isEmpty)
        XCTAssertNil(store.operationProgress)
    }

    @MainActor
    func testNonCooperativeManualSearchAfterReseedCannotPublish() async throws {
        let queue = try makeQueue(count: 1)
        let gate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: gate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        store.searchCurrentFile()
        try await waitUntil { client.queryCount == 1 }
        XCTAssertEqual(store.searchState, .searching)

        let replacement = try LRCLIBLyricsTestSupport.makeObservedFile(
            named: "manual-replacement.mp3",
            directory: queue.directory,
            title: "Manual Replacement",
            artist: "Artist"
        )
        store.seed(from: [replacement])

        gate.open()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(store.searchState, .idle, "A late manual result must not publish into the new session")
        XCTAssertTrue(store.rankedCandidates.isEmpty)
        XCTAssertEqual(client.queryCount, 1)
    }

    @MainActor
    func testDuplicateAutoApplyStartIsRejected() async throws {
        let queue = try makeQueue(count: 2)
        let gate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: gate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)

        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        XCTAssertFalse(store.startAutoApply(writer: viewModel), "A second start during the active operation is rejected")
        XCTAssertFalse(store.startManualApply(writer: viewModel))
        try await waitUntil { client.queryCount == 1 }
        gate.open()
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(client.queryCount, 2, "One operation searches each queued row exactly once")
    }

    @MainActor
    func testCloseBeforeHandoffAfterSearchCompletesNeverCallsWriter() async throws {
        let queue = try makeQueue(count: 2)
        let firstCallGate = LRCLIBTestGate(isOpen: true)
        let lastCallGate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(
            perCallGates: [firstCallGate, lastCallGate],
            candidatesByTrackName: queue.candidatesByTrackName
        )
        let writer = LRCLIBRecordingWriter()
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)

        XCTAssertTrue(store.startAutoApply(writer: writer))
        try await waitUntil { client.queryCount == 2 }

        store.closeWindowSession()
        lastCallGate.open()
        for _ in 0..<30 { await Task.yield() }
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertTrue(writer.autoIntents.isEmpty, "A late provider result must not reach the write handoff")
        XCTAssertEqual(client.queryCount, 2)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    // MARK: - Cancellation at the reservation / admission boundary

    @MainActor
    func testCancellationWhileQueuedAtReservationWritesNothing() async throws {
        let queue = try makeQueue(count: 1)
        let client = LRCLIBGatedClient(
            gate: LRCLIBTestGate(isOpen: true),
            candidatesByTrackName: queue.candidatesByTrackName
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: queue.files[0])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        store.searchCurrentFile()
        try await waitUntil { store.searchState == .loaded }

        let releaseReservation = LRCLIBTestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [queue.files[0].url]) {
                await releaseReservation.wait()
            }
        }
        store.startManualApply(writer: viewModel)
        try await waitForQueuedMutation(in: viewModel)

        store.closeWindowSession()
        releaseReservation.open()
        await holder.value
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testCloseAfterFirstCommitReportsRealOutcomeAndCancelsRemaining() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fixtureURL) }
        let base = TagLibAudioMetadataPipeline()
        let firstURL = directory.appendingPathComponent("first.flac")
        let secondURL = directory.appendingPathComponent("second.flac")
        try FileManager.default.copyItem(at: fixtureURL, to: firstURL)
        try FileManager.default.copyItem(at: fixtureURL, to: secondURL)
        _ = try? base.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["TITLE": ["First Song"], "ARTIST": ["First Artist"]]),
            to: firstURL,
            expectedVersion: nil
        )
        _ = try? base.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["TITLE": ["Second Song"], "ARTIST": ["Second Artist"]]),
            to: secondURL,
            expectedVersion: nil
        )
        let firstFile = try await MetadataTestTokens.makeVerifiedAudioFile(at: firstURL)
        let secondFile = try await MetadataTestTokens.makeVerifiedAudioFile(at: secondURL)
        let firstInput = LRCLIBFileSearchInput(file: firstFile)
        let secondInput = LRCLIBFileSearchInput(file: secondFile)
        let firstCandidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 601,
            track: firstInput.title,
            artist: firstInput.artist,
            duration: firstInput.durationSeconds.map(Double.init),
            syncedLyrics: "[00:01.00]First"
        )
        let secondCandidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 602,
            track: secondInput.title,
            artist: secondInput.artist,
            duration: secondInput.durationSeconds.map(Double.init),
            syncedLyrics: "[00:01.00]Second"
        )
        let client = LRCLIBGatedClient(candidatesByTrackName: [
            firstInput.title: [firstCandidate],
            secondInput.title: [secondCandidate]
        ])
        let pipeline = LRCLIBRealReadbackPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([firstFile, secondFile])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [firstFile, secondFile])
        let secondBytesBefore = try Data(contentsOf: secondURL)

        // Keep the second target queued at the reservation so the close happens
        // after the first commit has crossed admission but before the second one can.
        let releaseSecondReservation = LRCLIBTestGate()
        let reservationAcquired = LRCLIBTestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [secondURL]) {
                reservationAcquired.open()
                await releaseSecondReservation.wait()
            }
        }
        await reservationAcquired.wait()

        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        try await waitUntil { pipeline.rawWriteCount == 1 }
        let queueDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < queueDeadline {
            let queued = await viewModel.fileMutationCoordinator.queuedMutationCount
            if queued > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let queuedSecondWrite = await viewModel.fileMutationCoordinator.queuedMutationCount
        XCTAssertGreaterThan(queuedSecondWrite, 0, "The second file must be waiting at the reservation")

        store.closeWindowSession()
        XCTAssertNil(store.operationProgress)
        releaseSecondReservation.open()
        await holder.value
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 1, "Only the admitted commit may reach the writer")
        let firstMap = try base.rawMetadataValueMap(for: firstURL)
        XCTAssertEqual(firstMap["LYRICS"], ["[00:01.00]First"], "The admitted commit reports and persists its real outcome")
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytesBefore, "An unstarted later file stays untouched")
        XCTAssertNil(try base.rawMetadataValueMap(for: secondURL)["LYRICS"])

        let entry = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first)
        XCTAssertTrue(entry.summary.contains("1 of 2"), entry.summary)
        XCTAssertTrue(entry.summary.localizedCaseInsensitiveContains("cancelled"), entry.summary)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testManualApplyAfterReseedDoesNotMarkNewSession() async throws {
        let queue = try makeQueue(count: 2)
        let client = LRCLIBGatedClient(
            gate: LRCLIBTestGate(isOpen: true),
            candidatesByTrackName: queue.candidatesByTrackName
        )
        let writeGate = LRCLIBSyncGate()
        let pipeline = LRCLIBRecordingPipeline(reloadFile: queue.files[0], writeGate: writeGate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        store.searchCurrentFile()
        try await waitUntil { store.searchState == .loaded }

        store.startManualApply(writer: viewModel)
        try await waitUntil { writeGate.startedCount == 1 }

        let replacement = try LRCLIBLyricsTestSupport.makeObservedFile(
            named: "reseed-during-apply.mp3",
            directory: queue.directory,
            title: "Reseed Replacement",
            artist: "Artist"
        )
        store.seed(from: [replacement])
        writeGate.open()
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 1, "A commit that already crossed admission still completes")
        XCTAssertEqual(store.rows.count, 1)
        XCTAssertNil(store.appliedCandidateID, "A stale completion must not mark the replacement session")
    }

    @MainActor
    func testManualCompletionMarksCapturedRowNotCurrentRow() async throws {
        let queue = try makeQueue(count: 2)
        let client = LRCLIBGatedClient(
            gate: LRCLIBTestGate(isOpen: true),
            candidatesByTrackName: queue.candidatesByTrackName
        )
        let writeGate = LRCLIBSyncGate()
        let pipeline = LRCLIBRecordingPipeline(reloadFile: queue.files[0], writeGate: writeGate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        store.searchCurrentFile()
        try await waitUntil { store.searchState == .loaded }
        let appliedCandidateID = try XCTUnwrap(store.selectedCandidateID)

        store.startManualApply(writer: viewModel)
        try await waitUntil { writeGate.startedCount == 1 }
        store.moveNext()
        XCTAssertEqual(store.currentIndex, 1)
        writeGate.open()
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 1)
        store.movePrevious()
        XCTAssertEqual(store.currentIndex, 0)
        XCTAssertEqual(store.appliedCandidateID, appliedCandidateID, "The captured row/candidate is marked, not the current row")
    }

    @MainActor
    func testEndedOperationProgressCannotReplaceReplacementProgress() async throws {
        let queue = try makeQueue(count: 1)
        let oldGate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: oldGate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        try await waitUntil { client.queryCount == 1 }
        let oldOperation = try XCTUnwrap(store.activeOperation)

        store.closeWindowSession()
        XCTAssertNil(store.operationProgress)

        let replacement = try LRCLIBLyricsTestSupport.makeObservedFile(
            named: "progress-replacement.mp3",
            directory: queue.directory,
            title: "Progress Replacement",
            artist: "Artist"
        )
        store.seed(from: [replacement])
        let newWriter = LRCLIBRecordingWriter()
        newWriter.autoGate = LRCLIBTestGate()
        XCTAssertTrue(store.startAutoApply(writer: newWriter))
        let newOperation = try XCTUnwrap(store.activeOperation)
        XCTAssertNotEqual(newOperation.operationID, oldOperation.operationID)
        XCTAssertEqual(store.operationProgress?.kind, .autoApply)

        oldGate.open()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(store.activeOperation?.operationID, newOperation.operationID)
        XCTAssertNotNil(store.operationProgress, "The ended operation cannot clear the replacement operation's progress")

        newWriter.autoGate?.open()
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)
        XCTAssertNil(store.operationProgress)
    }

    // MARK: - Navigation

    @MainActor
    func testDepartingRowSearchPublishesCancelledState() async throws {
        let queue = try makeQueue(count: 2)
        let gate = LRCLIBTestGate()
        let client = LRCLIBGatedClient(gate: gate, candidatesByTrackName: queue.candidatesByTrackName)
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(queue.files)
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: queue.files)
        store.searchCurrentFile()
        try await waitUntil { client.queryCount == 1 }

        store.moveNext()
        store.movePrevious()

        XCTAssertEqual(store.searchState, .cancelled, "The departing row must not stay stuck searching")
        gate.open()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.queryCount, 1)
        XCTAssertEqual(store.searchState, .cancelled)
    }

    // MARK: - Helpers

    @MainActor
    private func makeQueue(count: Int) throws -> Queue {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory(prefix: "LRCLIBSession")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        var files: [AudioFile] = []
        var candidates: [LRCLIBLyricsCandidate] = []
        var candidatesByTrackName: [String: [LRCLIBLyricsCandidate]] = [:]
        for index in 0..<count {
            let title = "Session Song \(index)"
            let artist = "Session Artist \(index)"
            let file = try LRCLIBLyricsTestSupport.makeObservedFile(
                named: String(format: "session-%02d.mp3", index),
                directory: directory,
                title: title,
                artist: artist
            )
            let input = LRCLIBFileSearchInput(file: file)
            let candidate = LRCLIBLyricsTestSupport.makeCandidate(
                id: 700 + index,
                track: input.title,
                artist: input.artist,
                syncedLyrics: "[00:01.00]Session \(index)"
            )
            files.append(file)
            candidates.append(candidate)
            candidatesByTrackName[input.title] = [candidate]
        }
        return Queue(
            directory: directory,
            files: files,
            candidates: candidates,
            candidatesByTrackName: candidatesByTrackName
        )
    }

    @MainActor
    private func waitUntil(
        deadlineSeconds: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        try await LRCLIBLyricsTestSupport.waitUntil(deadlineSeconds: deadlineSeconds, condition)
    }

    @MainActor
    private func waitForQueuedMutation(in viewModel: AudioViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            let count = await viewModel.fileMutationCoordinator.queuedMutationCount
            if count > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected the strict write to queue behind the reservation")
    }
}
