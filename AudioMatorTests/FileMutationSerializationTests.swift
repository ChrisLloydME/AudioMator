import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class FileMutationSerializationTests: XCTestCase {
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

        async let metadataWrite = viewModel.writeMetadataOffMainActor(payload, to: canonicalURL)
        let didStartMetadataWrite = try await waitUntil { pipeline.totalMutationCount == 1 }
        XCTAssertTrue(didStartMetadataWrite)

        async let rawMapWrite = viewModel.writeRawMetadataPropertyMapOffMainActor([:], to: aliasURL)
        let didQueueAliasMutation = try await waitUntil {
            await viewModel.fileMutationCoordinator.queuedMutationCount == 1
        }
        let mutationCountBeforeRelease = pipeline.totalMutationCount
        pipeline.releaseFirstMutation()
        _ = try await (metadataWrite, rawMapWrite)

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

        async let metadataWrite = viewModel.writeMetadataOffMainActor(payload, to: fileURL)
        let didStartMetadataWrite = try await waitUntil { pipeline.totalMutationCount == 1 }
        XCTAssertTrue(didStartMetadataWrite)

        async let metadataErase = viewModel.eraseAllMetadataOffMainActor(at: fileURL)
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
        _ = try await (metadataWrite, metadataErase)
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
