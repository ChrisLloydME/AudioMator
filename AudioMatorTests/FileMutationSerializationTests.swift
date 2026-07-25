import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class FileMutationSerializationTests: XCTestCase {
    func testMetadataMutationKeepsReservationUntilPersistedSnapshotReloads() async throws {
        let pipeline = ReloadGatedMutationPipeline()
        let coordinator = FileMutationCoordinator()
        let executor = MetadataFileMutationExecutor(
            metadataPipeline: pipeline,
            fileMutationCoordinator: coordinator
        )
        let fileID = UUID()
        let fileURL = URL(fileURLWithPath: "/tmp/AudioMatorAtomicWriteReload.mp3")

        let firstTask = Task {
            await executor.execute(
                at: fileURL,
                id: fileID,
                expectedFileFingerprint: nil
            ) { pipeline, url in
                try pipeline.writeRawMetadataPropertyMap(["TITLE": "First"], to: url)
            }
        }
        await pipeline.reloadStarted.wait()

        let secondMutationEntered = AsyncTestLatch()
        let secondTask = Task {
            try await coordinator.withExclusiveAccess(to: [fileURL]) {
                await secondMutationEntered.signal()
            }
        }
        let didQueueSecondMutation = try await waitUntil {
            await coordinator.queuedMutationCount == 1
        }

        XCTAssertTrue(didQueueSecondMutation)
        let didEnterBeforeReloadFinished = await secondMutationEntered.isSignaled
        XCTAssertFalse(didEnterBeforeReloadFinished)

        await pipeline.allowReload.signal()
        let firstResult = await firstTask.value
        try await secondTask.value

        guard case .success(let success) = firstResult else {
            return XCTFail("Expected the write and reload transaction to succeed.")
        }
        XCTAssertTrue(success.didReloadFile)
        XCTAssertEqual(success.reloadedFile?.id, fileID)
        let didEnterAfterReloadFinished = await secondMutationEntered.isSignaled
        XCTAssertTrue(didEnterAfterReloadFinished)
    }

    func testMetadataMutationDistinguishesPersistedWriteFromReloadFailure() async {
        let pipeline = ReloadFailingMutationPipeline()
        let executor = MetadataFileMutationExecutor(
            metadataPipeline: pipeline,
            fileMutationCoordinator: FileMutationCoordinator()
        )
        let fileURL = URL(fileURLWithPath: "/tmp/AudioMatorReloadFailure.mp3")

        let result = await executor.execute(
            at: fileURL,
            id: UUID(),
            expectedFileFingerprint: nil
        ) { pipeline, url in
            try pipeline.eraseAllMetadata(at: url)
        }

        guard case .success(let success) = result else {
            return XCTFail("A reload failure must not erase the successful write result.")
        }
        XCTAssertEqual(success.writeResult.warnings, ["Injected write warning"])
        XCTAssertFalse(success.didReloadFile)
        XCTAssertEqual(success.reloadErrorDescription, "Injected reload failure")
    }

    func testMetadataMutationHelpersSerializeNormalizedURLAliases() async throws {
        let pipeline = BlockingMutationPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMutationSerialization", isDirectory: true)
        let canonicalURL = directoryURL.appendingPathComponent("track.mp3")
        let aliasURL = directoryURL
            .appendingPathComponent("unused", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("track.mp3")
        let file = AudioFileTestFactory.make(url: canonicalURL)
        let payload = MetadataEditPayload(SingleFileEditModel(from: file))
        let executor = MetadataFileMutationExecutor(
            metadataPipeline: pipeline,
            fileMutationCoordinator: viewModel.fileMutationCoordinator
        )

        async let metadataWrite = executor.execute(
            at: canonicalURL,
            id: file.id,
            expectedFileFingerprint: nil
        ) { pipeline, url in
            try pipeline.writeMetadata(payload, to: url)
        }
        let didStartMetadataWrite = try await waitUntil { pipeline.totalMutationCount == 1 }
        XCTAssertTrue(didStartMetadataWrite)

        async let rawMapWrite = executor.execute(
            at: aliasURL,
            id: file.id,
            expectedFileFingerprint: nil
        ) { pipeline, url in
            try pipeline.writeRawMetadataPropertyMap([:], to: url)
        }
        let didQueueAliasMutation = try await waitUntil {
            await viewModel.fileMutationCoordinator.queuedMutationCount == 1
        }
        let mutationCountBeforeRelease = pipeline.totalMutationCount
        pipeline.releaseFirstMutation()
        _ = await (metadataWrite, rawMapWrite)

        XCTAssertTrue(didQueueAliasMutation)
        XCTAssertEqual(mutationCountBeforeRelease, 1)
        XCTAssertEqual(pipeline.mutationCount(for: .metadataWrite), 1)
        XCTAssertEqual(pipeline.mutationCount(for: .rawMapWrite), 1)
    }

    func testMetadataWriteEraseAndTrackRenumberShareOneFileReservation() async throws {
        let pipeline = BlockingMutationPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        let fileID = UUID()
        let fileURL = URL(fileURLWithPath: "/tmp/AudioMatorSharedMutation.mp3")
        let file = AudioFileTestFactory.make(
            id: fileID,
            url: fileURL,
            includeDefaultFileFingerprint: false
        )
        let payload = MetadataEditPayload(SingleFileEditModel(from: file))
        viewModel.mergeQuickImportFiles([file])
        let executor = MetadataFileMutationExecutor(
            metadataPipeline: pipeline,
            fileMutationCoordinator: viewModel.fileMutationCoordinator
        )

        async let metadataWrite = executor.execute(
            at: fileURL,
            id: fileID,
            expectedFileFingerprint: nil
        ) { pipeline, url in
            try pipeline.writeMetadata(payload, to: url)
        }
        let didStartMetadataWrite = try await waitUntil { pipeline.totalMutationCount == 1 }
        XCTAssertTrue(didStartMetadataWrite)

        async let metadataErase = executor.execute(
            at: fileURL,
            id: fileID,
            expectedFileFingerprint: nil
        ) { pipeline, url in
            try pipeline.eraseAllMetadata(at: url)
        }
        async let renumberResult = viewModel.renumberTrackNumbers(
            orderedIDs: [fileID],
            selectedIDs: [],
            options: TrackRenumberOptions(
                direction: .ascending,
                startNumber: 1,
                padWithZeros: false
            )
        )

        let didQueueBothMutations = try await waitUntil {
            await viewModel.fileMutationCoordinator.queuedMutationCount == 2
        }
        let mutationCountBeforeRelease = pipeline.totalMutationCount
        pipeline.releaseFirstMutation()
        _ = await (metadataWrite, metadataErase)
        let result = await renumberResult

        XCTAssertTrue(didQueueBothMutations)
        XCTAssertEqual(mutationCountBeforeRelease, 1)
        XCTAssertEqual(pipeline.mutationCount(for: .metadataWrite), 1)
        XCTAssertEqual(pipeline.mutationCount(for: .erase), 1)
        XCTAssertEqual(pipeline.mutationCount(for: .trackRenumber), 1)
        XCTAssertEqual(result.succeeded, 1)
    }

    func testCancelledWaiterDoesNotExecuteQueuedMutation() async throws {
        let coordinator = FileMutationCoordinator()
        let fileURL = URL(fileURLWithPath: "/tmp/AudioMatorCancelledMutation.mp3")
        let firstMutationEntered = AsyncTestLatch()
        let releaseFirstMutation = AsyncTestLatch()
        let secondMutationExecuted = AsyncTestLatch()

        let firstTask = Task {
            try await coordinator.withExclusiveAccess(to: [fileURL]) {
                await firstMutationEntered.signal()
                await releaseFirstMutation.wait()
            }
        }
        await firstMutationEntered.wait()

        let secondTask = Task {
            do {
                try await coordinator.withExclusiveAccess(to: [fileURL]) {
                    await secondMutationExecuted.signal()
                }
                return WaiterOutcome.executed
            } catch is CancellationError {
                return WaiterOutcome.cancelled
            } catch {
                return WaiterOutcome.failed
            }
        }
        let didQueueSecondMutation = try await waitUntil {
            await coordinator.queuedMutationCount == 1
        }
        secondTask.cancel()
        await releaseFirstMutation.signal()

        _ = try await firstTask.value
        let secondOutcome = await secondTask.value

        XCTAssertTrue(didQueueSecondMutation)
        XCTAssertEqual(secondOutcome, .cancelled)
        let didExecuteCancelledMutation = await secondMutationExecuted.isSignaled
        XCTAssertFalse(
            didExecuteCancelledMutation,
            "A mutation cancelled while waiting for a file reservation must never execute later."
        )

        let followUpMutationExecuted = AsyncTestLatch()
        try await coordinator.withExclusiveAccess(to: [fileURL]) {
            await followUpMutationExecuted.signal()
        }
        let didExecuteFollowUpMutation = await followUpMutationExecuted.isSignaled
        XCTAssertTrue(
            didExecuteFollowUpMutation,
            "Cancelling a waiter must leave the file reservation usable by later mutations."
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () async -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private enum WaiterOutcome: Equatable {
    case executed
    case cancelled
    case failed
}

private actor AsyncTestLatch {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isSignaled: Bool { signaled }

    func signal() {
        guard !signaled else { return }
        signaled = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class ReloadGatedMutationPipeline: AudioMetadataPipeline, @unchecked Sendable {
    let reloadStarted = AsyncTestLatch()
    let allowReload = AsyncTestLatch()

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await reloadStarted.signal()
        await allowReload.wait()
        return await AudioFileTestFactory.make(
            id: id,
            url: url,
            includeDefaultFileFingerprint: false
        )
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}

private final class ReloadFailingMutationPipeline: AudioMetadataPipeline, @unchecked Sendable {
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        throw ReloadFailure.injected
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: ["Injected write warning"])
    }

    nonisolated func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: ["Injected write warning"])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: ["Injected write warning"])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: ["Injected write warning"])
    }

    private enum ReloadFailure: LocalizedError {
        case injected

        var errorDescription: String? { "Injected reload failure" }
    }
}

nonisolated private enum RecordedMutationKind: Hashable {
    case metadataWrite
    case rawMapWrite
    case erase
    case trackRenumber
}

private final class BlockingMutationPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let condition = NSCondition()
    private var recordedMutationCounts: [RecordedMutationKind: Int] = [:]
    private var recordedTotalMutationCount = 0
    private var isFirstMutationReleased = false

    var totalMutationCount: Int {
        condition.withLock { recordedTotalMutationCount }
    }

    func mutationCount(for kind: RecordedMutationKind) -> Int {
        condition.withLock { recordedMutationCounts[kind, default: 0] }
    }

    func releaseFirstMutation() {
        condition.withLock {
            isFirstMutationReleased = true
            condition.broadcast()
        }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        [:]
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        recordMutation(.metadataWrite)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        recordMutation(.rawMapWrite)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        recordMutation(.erase)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        recordMutation(.trackRenumber)
        return AudioMetadataWriteResult(warnings: [])
    }

    private func recordMutation(_ kind: RecordedMutationKind) {
        condition.lock()
        recordedMutationCounts[kind, default: 0] += 1
        recordedTotalMutationCount += 1
        condition.broadcast()

        if recordedTotalMutationCount == 1 {
            while !isFirstMutationReleased {
                condition.wait()
            }
        }

        condition.unlock()
    }
}
#endif
