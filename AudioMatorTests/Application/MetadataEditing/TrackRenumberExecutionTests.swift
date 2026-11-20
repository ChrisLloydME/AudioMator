import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

#if os(macOS)
nonisolated final class TrackRenumberExecutionTests: XCTestCase {
    // MARK: - Fixtures

    private struct ReviewedFixture {
        let file: AudioFile
        let url: URL
    }

    @MainActor
    private func makeReviewedFixture(
        _ name: String,
        extension fileExtension: String = "mp3",
        track: Int = 0,
        trackTotal: Int = 0,
        disc: Int = 0,
        discTotal: Int = 0,
        trackNumberText: String = "",
        title: String = "Original"
    ) throws -> ReviewedFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackRenumberExecution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("\(name).\(fileExtension)")
        try Data(repeating: 0x41, count: 64).write(to: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let version = try XCTUnwrap(AudioFileTestFactory.fixtureFileVersion)
        let file = AudioFileTestFactory.make(
            url: url,
            title: title,
            track: track,
            trackTotal: trackTotal,
            disc: disc,
            discTotal: discTotal,
            trackNumberText: trackNumberText,
            fileFingerprint: fingerprint,
            metadataFileVersion: version
        )
        return ReviewedFixture(file: file, url: url)
    }

    /// The reloaded observation the fake pipeline returns after a committed write.
    @MainActor
    private func reloadedFile(_ file: AudioFile, track: Int) -> AudioFile {
        AudioFileTestFactory.make(
            id: file.id,
            url: file.url,
            title: file.title,
            track: track,
            trackTotal: file.trackTotal,
            disc: file.disc,
            discTotal: file.discTotal,
            trackNumberText: String(track),
            fileFingerprint: file.fileFingerprint,
            metadataFileVersion: file.metadataFileVersion
        )
    }

    @MainActor
    private func makePlan(
        _ viewModel: AudioViewModel,
        files: [AudioFile],
        direction: TrackRenumberDirection = .ascending,
        startNumberText: String = "1"
    ) -> TrackRenumberPlan {
        viewModel.makeTrackRenumberPlan(
            orderedFiles: files,
            selectedIDs: [],
            direction: direction,
            startNumberText: startNumberText
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @escaping () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw XCTestError(.failureWhileWaiting)
    }

    // MARK: - Patch-level execution

    @MainActor
    func testExecutionWritesOnlyTrackComponentAndForwardsReviewedRevision() async throws {
        let fixture = try makeReviewedFixture(
            "track-only",
            extension: "flac",
            track: 3,
            trackTotal: 12,
            disc: 2,
            discTotal: 3,
            trackNumberText: "3/12"
        )
        let pipeline = RenumberRecordingMetadataPipeline(
            reloadFiles: [fixture.url: reloadedFile(fixture.file, track: 7)]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let plan = makePlan(viewModel, files: [fixture.file], startNumberText: "7")

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.totalTargets, 1)
        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(pipeline.writes.count, 1)
        guard let record = pipeline.writes.first else { return }
        // Patch-level assertion replaces the old synthetic verification flag.
        XCTAssertEqual(record.payload.requestedFields, Set([MetadataFieldKey.track]))
        XCTAssertEqual(record.payload.trackNumber, 7)
        XCTAssertEqual(record.payload.trackNumberText, "7")
        XCTAssertEqual(record.payload.trackTotal, 12)
        XCTAssertEqual(record.payload.discNumber, 2)
        XCTAssertEqual(record.payload.discTotal, 3)
        XCTAssertEqual(record.expectedVersion, fixture.file.metadataFileVersion)
        XCTAssertEqual(record.url, fixture.url)
        XCTAssertEqual(viewModel.files.first?.track, 7)
    }

    @MainActor
    func testInvalidStartPlanIssuesZeroWritesAndLeavesPositiveTagUnchanged() async throws {
        let fixture = try makeReviewedFixture("invalid-start", track: 7, trackNumberText: "7")
        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let beforeBytes = try Data(contentsOf: fixture.url)

        for startText in ["0", "", "10000", "-1", "1.5"] {
            let plan = makePlan(viewModel, files: [fixture.file], startNumberText: startText)
            XCTAssertFalse(plan.isStartValid, "\(startText) must be invalid")
            let result = await viewModel.renumberTrackNumbers(using: plan)
            XCTAssertNotNil(result.validationMessage, "\(startText) must report explicit invalid state")
            XCTAssertEqual(result.succeeded, 0)
            XCTAssertTrue(result.cancelled.isEmpty)
        }

        XCTAssertTrue(pipeline.writes.isEmpty, "Invalid direct text must issue zero writes.")
        XCTAssertEqual(try Data(contentsOf: fixture.url), beforeBytes)
    }

    @MainActor
    func testUnsupportedLayoutPlanIssuesZeroWrites() async throws {
        let fixture = try makeReviewedFixture("unsupported-layout", extension: "xm")
        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let plan = makePlan(viewModel, files: [fixture.file])

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.skippedUnsupported, 1)
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertTrue(pipeline.writes.isEmpty)
    }

    @MainActor
    func testRefreshRequiredTargetsDoNotConsumeNumbersAtFirstOrMiddlePosition() async throws {
        for blockedIndex in [0, 1] {
            let first = try makeReviewedFixture("refresh-first", track: 0)
            let middle = try makeReviewedFixture("refresh-middle", track: 0)
            let last = try makeReviewedFixture("refresh-last", track: 0)
            let files = [first.file, middle.file, last.file]
            let pipeline = RenumberRecordingMetadataPipeline(
                reloadFiles: [
                    first.url: reloadedFile(first.file, track: 1),
                    last.url: reloadedFile(last.file, track: 2),
                ]
            )
            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
            viewModel.mergeQuickImportFiles(files)
            viewModel.markFileRequiresRefresh(id: files[blockedIndex].id)
            let plan = makePlan(viewModel, files: files, startNumberText: "1")

            XCTAssertEqual(plan.executableCount, 2)
            let result = await viewModel.renumberTrackNumbers(using: plan)

            XCTAssertEqual(result.totalTargets, 3)
            XCTAssertEqual(result.failed, 1)
            XCTAssertEqual(result.succeeded, 2)
            XCTAssertEqual(pipeline.writes.map(\.payload.trackNumber), [1, 2])
            XCTAssertEqual(
                result.failures.map(\.fileName),
                [files[blockedIndex].url.lastPathComponent]
            )
        }
    }

    @MainActor
    func testMixedOrderExecutionSkipsUnsupportedWithoutConsumingNumbers() async throws {
        let first = try makeReviewedFixture("mixed-first", extension: "mp3", track: 0)
        let unsupportedFile = try makeReviewedFixture("mixed-unsupported", extension: "xm", track: 4)
        let last = try makeReviewedFixture("mixed-last", extension: "flac", track: 0)
        let pipeline = RenumberRecordingMetadataPipeline(
            reloadFiles: [
                first.url: reloadedFile(first.file, track: 1),
                last.url: reloadedFile(last.file, track: 2),
            ]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first.file, unsupportedFile.file, last.file])
        let plan = makePlan(
            viewModel,
            files: [first.file, unsupportedFile.file, last.file],
            startNumberText: "1"
        )

        XCTAssertEqual(plan.rows.map(\.id), [first.file.id, unsupportedFile.file.id, last.file.id])
        XCTAssertEqual(plan.rows.map(\.assignedNumber), [1, nil, 2])

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.totalTargets, 3)
        XCTAssertEqual(result.skippedUnsupported, 1)
        XCTAssertEqual(result.succeeded, 2)
        XCTAssertEqual(pipeline.writes.map(\.payload.trackNumber), [1, 2])
        XCTAssertEqual(
            pipeline.writes.map(\.url),
            [first.url, last.url]
        )
    }

    @MainActor
    func testAlreadyDesiredRowIsNotWrittenBesideChangedRow() async throws {
        let unchanged = try makeReviewedFixture(
            "noop",
            track: 7,
            trackTotal: 12,
            trackNumberText: "007/12"
        )
        let changed = try makeReviewedFixture("changed", track: 1, trackNumberText: "1")
        let pipeline = RenumberRecordingMetadataPipeline(
            reloadFiles: [changed.url: reloadedFile(changed.file, track: 8)]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([unchanged.file, changed.file])
        let unchangedBytes = try Data(contentsOf: unchanged.url)
        let plan = makePlan(
            viewModel,
            files: [unchanged.file, changed.file],
            startNumberText: "7"
        )

        XCTAssertTrue(plan.rows[0].isUnchanged)
        XCTAssertEqual(plan.rows[0].assignedNumber, 7)
        XCTAssertEqual(plan.rows[1].assignedNumber, 8)

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(result.unchanged, 1)
        XCTAssertEqual(pipeline.writes.map(\.payload.trackNumber), [8])
        XCTAssertEqual(
            try Data(contentsOf: unchanged.url),
            unchangedBytes,
            "An already desired number must not reach the writer."
        )
    }

    @MainActor
    func testRuntimeFailureKeepsReviewedSlotsForOtherFiles() async throws {
        let first = try makeReviewedFixture("slot-first", track: 0)
        let middle = try makeReviewedFixture("slot-middle", track: 0)
        let last = try makeReviewedFixture("slot-last", track: 0)
        let pipeline = RenumberRecordingMetadataPipeline(
            reloadFiles: [
                first.url: reloadedFile(first.file, track: 1),
                last.url: reloadedFile(last.file, track: 3),
            ]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first.file, middle.file, last.file])
        let plan = makePlan(
            viewModel,
            files: [first.file, middle.file, last.file],
            startNumberText: "1"
        )

        // The middle file changes on disk after review; its row fails at write time
        // and must keep its assigned slot. The later file keeps number 3.
        try Data(repeating: 0x42, count: 128).write(to: middle.url)

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 2)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(pipeline.writes.map(\.payload.trackNumber), [1, 3])
        XCTAssertEqual(
            result.failures.map(\.fileName),
            [middle.url.lastPathComponent]
        )
    }

    @MainActor
    func testDurabilityAndReloadWarningsAreRetainedWithoutReapply() async throws {
        let fixture = try makeReviewedFixture("warnings")
        let reloadError = NSError(
            domain: "TrackRenumberExecutionTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Injected readback failure"]
        )
        let pipeline = RenumberRecordingMetadataPipeline(
            reloadError: reloadError,
            commitStatus: .durabilityUncertain("Injected directory sync failure")
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let plan = makePlan(viewModel, files: [fixture.file], startNumberText: "7")

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(pipeline.writes.count, 1, "A committed write with uncertain durability must not be retried.")
        let messages = result.warnings.flatMap(\.messages).joined(separator: "\n")
        XCTAssertTrue(messages.contains("Injected directory sync failure"), messages)
        XCTAssertTrue(messages.localizedCaseInsensitiveContains("don't repeat this save"), messages)
        XCTAssertTrue(messages.contains("Injected readback failure"), messages)
    }

    @MainActor
    func testStaleFingerprintIsRejectedBeforeWriter() async throws {
        let fixture = try makeReviewedFixture("stale-fingerprint", track: 0)
        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let plan = makePlan(viewModel, files: [fixture.file], startNumberText: "7")

        try Data(repeating: 0x43, count: 256).write(to: fixture.url, options: .atomic)

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertTrue(
            result.failures.first?.reason.localizedCaseInsensitiveContains("changed") == true,
            result.failures.first?.reason ?? ""
        )
        XCTAssertTrue(pipeline.writes.isEmpty)
    }

    @MainActor
    func testStaleReviewedRevisionIsRejectedBeforeWriter() async throws {
        let fixture = try makeReviewedFixture("stale-revision", track: 0)
        let alternativeVersion = try await alternativeFileVersion()
        guard alternativeVersion != fixture.file.metadataFileVersion else {
            throw XCTSkip("The package revision tokens are not distinguishable in this environment.")
        }

        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let plan = makePlan(viewModel, files: [fixture.file], startNumberText: "7")

        let staleObservation = try XCTUnwrap(fixture.file.fileFingerprint)
        viewModel.replaceLoadedFile(
            AudioFileTestFactory.makeObserved(
                id: fixture.file.id,
                url: fixture.url,
                title: fixture.file.title,
                fileFingerprint: staleObservation,
                metadataFileVersion: alternativeVersion
            )
        )

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertTrue(
            result.failures.first?.reason.localizedCaseInsensitiveContains("changed") == true,
            result.failures.first?.reason ?? ""
        )
        XCTAssertTrue(pipeline.writes.isEmpty)
    }

    @MainActor
    func testStaleIdentityIsRejectedBeforeWriter() async throws {
        let fixture = try makeReviewedFixture("stale-identity", track: 0)
        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let plan = makePlan(viewModel, files: [fixture.file], startNumberText: "7")

        // Same UUID, different physical URL: the reviewed target no longer
        // associates and must not be written.
        viewModel.replaceLoadedFile(
            AudioFileTestFactory.make(
                id: fixture.file.id,
                url: fixture.url.deletingLastPathComponent().appendingPathComponent("moved.mp3")
            )
        )

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertTrue(pipeline.writes.isEmpty)
    }

    @MainActor
    func testCancelledQueueStopsBeforeNextFile() async throws {
        let first = try makeReviewedFixture("cancel-first", track: 0)
        let second = try makeReviewedFixture("cancel-second", track: 0)
        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first.file, second.file])
        let plan = makePlan(viewModel, files: [first.file, second.file], startNumberText: "1")

        let entered = RenumberTestGate()
        let release = RenumberTestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(
                to: [first.url, second.url]
            ) {
                await entered.open()
                await release.wait()
            }
        }
        await entered.wait()

        let renumberTask = Task {
            await viewModel.renumberTrackNumbers(using: plan)
        }
        try await waitUntil {
            await viewModel.fileMutationCoordinator.queuedMutationCount >= 1
        }
        renumberTask.cancel()
        await release.open()
        await holder.value

        let result = await renumberTask.value

        XCTAssertEqual(pipeline.writes.count, 0)
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(result.cancelled.count, 2)
        XCTAssertTrue(result.cancelled.allSatisfy {
            $0.reason.localizedCaseInsensitiveContains("cancel")
        })
    }

    @MainActor
    func testCancelAfterFirstCommitPreservesFirstAndCancelsRemainingWithPerFileMessage() async throws {
        let first = try makeReviewedFixture("cancel-after-first", track: 0)
        let second = try makeReviewedFixture("cancel-after-second", track: 0)
        let pipeline = RenumberRecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first.file, second.file])
        let plan = makePlan(viewModel, files: [first.file, second.file], startNumberText: "1")

        // Block only the second file's reservation so file 1 commits while file 2
        // waits on the coordinator, then cancel.
        let entered = RenumberTestGate()
        let release = RenumberTestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [second.url]) {
                await entered.open()
                await release.wait()
            }
        }
        await entered.wait()

        let renumberTask = Task {
            await viewModel.renumberTrackNumbers(using: plan)
        }
        try await waitUntil {
            guard pipeline.writes.count == 1 else { return false }
            let queued = await viewModel.fileMutationCoordinator.queuedMutationCount
            return queued >= 1
        }
        renumberTask.cancel()
        await release.open()
        await holder.value

        let result = await renumberTask.value
        XCTAssertEqual(pipeline.writes.count, 1)
        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(result.cancelled.count, 1)
        XCTAssertEqual(result.cancelled.first?.fileName, second.url.lastPathComponent)
        XCTAssertFalse(
            result.cancelled.first?.reason.contains("No track numbers were changed") == true,
            "After an earlier file committed, trailing cancellation must not claim no track numbers changed"
        )
    }

    @MainActor
    private func alternativeFileVersion() async throws -> MetadataFileVersion {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(
            bundle.url(forResource: "testAudioFile", withExtension: "m4a", subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: "testAudioFile", withExtension: "m4a")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackRenumberVersion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let copyURL = directory.appendingPathComponent("version-source.m4a")
        try FileManager.default.copyItem(at: source, to: copyURL)
        let file = try await TagLibAudioMetadataPipeline().loadAudioFile(at: copyURL, id: UUID())
        return try XCTUnwrap(file.metadataFileVersion)
    }
}

// MARK: - Recording pipeline

private nonisolated final class RenumberRecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    nonisolated struct RecordedWrite: Sendable {
        let url: URL
        let payload: MetadataEditPayload
        let expectedVersion: MetadataFileVersion
    }

    private let lock = NSLock()
    private var recordedWrites: [RecordedWrite] = []
    private let reloadFiles: [URL: AudioFile]
    private let reloadError: (any Error)?
    private let commitStatus: AudioMetadataCommitStatus

    init(
        reloadFiles: [URL: AudioFile] = [:],
        reloadError: (any Error)? = nil,
        commitStatus: AudioMetadataCommitStatus = .durable
    ) {
        self.reloadFiles = reloadFiles
        self.reloadError = reloadError
        self.commitStatus = commitStatus
    }

    var writes: [RecordedWrite] {
        lock.withLock { recordedWrites }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let reloadError { throw reloadError }
        guard let file = reloadFiles[url] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return file
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [], commitStatus: commitStatus)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [], commitStatus: commitStatus)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [], commitStatus: commitStatus)
    }

    /// Plan-time projection must come from the same deterministic encoder as the
    /// commit. Forward to the real adapter so the plan is reviewed against real
    /// capability data rather than the protocol's fail-closed default.
    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try TagLibAudioMetadataPipeline().projectMetadataWrite(intent, fileExtension: fileExtension)
    }

    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            recordedWrites.append(
                RecordedWrite(url: url, payload: edit, expectedVersion: expectedVersion)
            )
        }
        return AudioMetadataWriteResult(warnings: [], commitStatus: commitStatus)
    }
}

private actor RenumberTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
#endif
