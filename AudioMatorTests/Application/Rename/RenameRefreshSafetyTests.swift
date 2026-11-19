import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

@MainActor
final class RenameRefreshSafetyTests: XCTestCase {
    // MARK: - Move publication and in-flight invalidation

    func testMoveSupersedesPendingOldURLAndLateReadCannotOverwriteNewerObservation() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameReadbackPipeline(mode: .fail))
        viewModel.mergeQuickImportFiles([original])
        viewModel.flushPendingMetadataReloads()
        viewModel.replaceLoadedFile(
            original,
            refreshGeneration: viewModel.makeFileModelRefreshGeneration(),
            deferVisibleRefresh: true
        )

        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])
        viewModel.flushPendingMetadataReloads()

        XCTAssertEqual(viewModel.files.first?.url, environment.destinationURL)
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertNil(moved.fileFingerprint)
        XCTAssertNil(moved.metadataFileVersion)
        XCTAssertNil(moved.metadataConflictBaseline)
    }

    func testLateMoveReadbackCannotReplaceNewerGeneratedObservation() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameReadbackPipeline(mode: .real, started: started, release: release)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let move = Task { await viewModel.readBackMovedFiles([receipt]) }
        await started.wait()
        let newer = AudioFileTestFactory.makeObserved(
            id: original.id,
            url: environment.destinationURL,
            title: "Newer observation",
            fileFingerprint: try AudioFileFingerprint.capture(at: environment.destinationURL),
            metadataFileVersion: try MetadataTestTokens.mintedVersion(at: environment.destinationURL)
        )
        viewModel.replaceLoadedFile(newer, refreshGeneration: viewModel.makeFileModelRefreshGeneration())
        await release.open()
        _ = await move.value

        XCTAssertEqual(viewModel.files.first?.url, environment.destinationURL)
        XCTAssertEqual(viewModel.files.first?.title, "Newer observation")
        // A newer automatic observation wins the generation race but cannot clear
        // the pending move decision.
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
    }

    // MARK: - Queued writers observe the recovery decision

    func testRecoveryDecisionBlocksStaleDraftsAndAlreadyQueuedWriters() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let reserved = RenameReadGate()
        let release = RenameReadGate()
        let holder = Task {
            try await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [original.url]) {
                await reserved.open()
                await release.wait()
            }
        }
        await reserved.wait()
        var edit = SingleFileEditModel(from: original)
        edit.title = "Stale draft"
        let capturedEdit = edit
        let save = Task { await viewModel.persistMetadataEdit(capturedEdit, to: original) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await viewModel.fileMutationCoordinator.queuedMutationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let queuedCount = await viewModel.fileMutationCoordinator.queuedMutationCount
        XCTAssertEqual(queuedCount, 1)

        viewModel.recordRecoveryDecision(
            .recoveryLocationUnresolved(
                expectedIdentity: EntryIdentityKey(fingerprint: original.fileFingerprint)
            ),
            for: original.id
        )
        await release.open()
        try await holder.value
        guard case .failure(let reason) = await save.value else {
            return XCTFail("Queued stale intent must observe the newer recovery decision")
        }
        XCTAssertTrue(reason.contains("Reload from Disk"))

        let blocked = try XCTUnwrap(viewModel.files.first)
        let rawResult = await viewModel.applyRawMetadataPropertyMaps(
            [original.id: ["TITLE": ["Stale raw edit"]]],
            to: [MetadataEditorTarget(file: blocked)]
        )
        XCTAssertEqual(rawResult.failedTargetIDs, [original.id])
        XCTAssertEqual(pipeline.writeCount, 0)
    }

    // MARK: - Failed readback is fail closed regardless of lightweight probes

    func testFailedFullReadbackKeepsMovedProjectionReadOnlyEvenWhenLightweightProbesSucceed() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let destinationBytes = try Data(contentsOf: environment.destinationURL)
        let warnings = await viewModel.readBackMovedFiles([receipt])

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertNil(moved.fileFingerprint)
        XCTAssertNil(moved.metadataFileVersion)
        XCTAssertNil(moved.metadataConflictBaseline)
        XCTAssertTrue(warnings.first?.contains("Reload from Disk") == true || warnings.first?.contains("couldn’t be reloaded") == true)

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Must not write"
        guard case .failure = await viewModel.persistMetadataEdit(edit, to: moved) else {
            return XCTFail("Inspector save must fail closed after a failed full readback")
        }
        let rawResult = await viewModel.applyRawMetadataPropertyMaps(
            [moved.id: ["TITLE": ["Must not write"]]],
            to: [MetadataEditorTarget(file: moved)]
        )
        XCTAssertEqual(rawResult.failedTargetIDs, [moved.id])
        XCTAssertEqual(pipeline.writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: environment.destinationURL), destinationBytes)
    }

    func testFailedRenameRefreshDisablesMetadataWritesWhenRevisionCannotBeRecovered() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertFalse(warnings.isEmpty)

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Must not write"
        guard case .failure(let reason) = await viewModel.persistMetadataEdit(edit, to: moved) else {
            return XCTFail("Expected a refresh-required failure")
        }
        XCTAssertTrue(reason.contains("Reload from Disk"))
        XCTAssertEqual(pipeline.writeCount, 0)
    }

    func testReceiptMatchedReadbackRestoresAuthorityOnlyForItsMove() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .real)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(warnings.isEmpty)
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(moved.observation)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: moved.id))

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Verified move write"
        guard case .success = await viewModel.persistMetadataEdit(edit, to: moved, comparedTo: moved) else {
            return XCTFail("A receipt-matched readback must restore metadata write authority")
        }
        XCTAssertEqual(pipeline.writeCount, 1)
        XCTAssertNotNil(pipeline.lastExpectedVersion)
    }

    func testReadbackAcrossSamePathReplacementStaysBlocked() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameReadbackPipeline(mode: .real, started: started, release: release)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let readback = Task { await viewModel.readBackMovedFiles([receipt]) }
        await started.wait()
        // Replace the directory entry while the read is in flight.
        try FileManager.default.removeItem(at: environment.destinationURL)
        try Data("different entry".utf8).write(to: environment.destinationURL)
        let replacementBytes = try Data(contentsOf: environment.destinationURL)
        await release.open()
        _ = await readback.value

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertEqual(try Data(contentsOf: environment.destinationURL), replacementBytes)
    }

    func testReadbackTimeoutKeepsBlockedAndLateLoadCannotPublish() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameReadbackPipeline(mode: .real, started: started, release: release)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: pipeline,
            moveReadbackTimeout: .milliseconds(100)
        )
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)

        await release.open()
        try await Task.sleep(for: .milliseconds(300))
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: moved.id))
    }

    // MARK: - Recovery decisions survive automatic observations

    func testRefreshRequiredRecoveryCannotBeUndoneByQueuedOrOlderReload() throws {
        let original = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/recovery.mp3"))
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameReadbackPipeline(mode: .fail))
        viewModel.mergeQuickImportFiles([original])
        viewModel.flushPendingMetadataReloads()
        let generation = viewModel.makeFileModelRefreshGeneration()
        XCTAssertTrue(viewModel.replaceLoadedFile(original, refreshGeneration: generation, deferVisibleRefresh: true))

        let lateGeneration = viewModel.makeFileModelRefreshGeneration()
        viewModel.markFileRequiresRefresh(id: original.id)
        viewModel.flushPendingMetadataReloads()

        XCTAssertTrue(try XCTUnwrap(viewModel.loadedFile(withID: original.id)).requiresMetadataRefreshBeforeWriting)
        XCTAssertFalse(viewModel.replaceLoadedFile(original, refreshGeneration: lateGeneration))
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
    }

    func testMoveReadbackDoesNotClearOlderRecoveryDecision() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameReadbackPipeline(mode: .real))
        viewModel.mergeQuickImportFiles([original])
        viewModel.markFileRequiresRefresh(id: original.id)

        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])
        _ = await viewModel.readBackMovedFiles([receipt])

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: moved.id))
    }

    func testExplicitReloadAfterMoveReadbackFailureRestoresWritableObservation() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])
        _ = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)

        pipeline.setMode(.real)
        await viewModel.reloadSelectedFilesFromDisk()

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertNotNil(moved.observation)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: moved.id))
    }

    // MARK: - Planner and preflight

    func testBlockedSourceIsSourceUnavailableAndCannotBePlanned() throws {
        let displayOnly = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/blocked-source.flac"),
            title: "Blocked",
            includeDefaultFileFingerprint: false
        )
        let plan = makeFileRenamePlan(template: "{{title}}", targetFiles: [displayOnly])
        XCTAssertEqual(plan.rows.first?.status, .sourceUnavailable)
        XCTAssertTrue(plan.operations.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    // MARK: - Helpers

    private struct Environment {
        let sourceURL: URL
        let destinationURL: URL
    }

    private func makeEnvironment() throws -> Environment {
        let source = try MetadataTestTokens.makeFixtureCopy()
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent("renamed-\(UUID().uuidString.prefix(8)).flac")
        return Environment(sourceURL: source, destinationURL: destination)
    }

    private func observedFile(at url: URL, title: String) throws -> AudioFile {
        AudioFileTestFactory.makeObserved(
            url: url,
            title: title,
            fileFingerprint: try AudioFileFingerprint.capture(at: url),
            metadataFileVersion: try MetadataTestTokens.mintedVersion(at: url)
        )
    }

    private func makeReceipt(
        for file: AudioFile,
        from sourceURL: URL,
        to destinationURL: URL
    ) throws -> FileRenameMoveReceipt {
        // The receipt carries the directory-entry identity observed at the end
        // of the move, which is the destination entry. Test fixtures simulate a
        // completed move by copying the source to the destination first.
        FileRenameMoveReceipt(
            moveID: FileMoveID(),
            fileID: file.id,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            entryIdentity: try FileEntryIdentityCapture.capture(at: destinationURL)
        )
    }
}

// MARK: - Recording pipeline

private final class RenameReadbackPipeline: AudioMetadataPipeline, @unchecked Sendable {
    enum LoadMode {
        case fail
        case real
    }

    private let lock = NSLock()
    private var mode: LoadMode
    private var recordedWriteCount = 0
    private var recordedExpectedVersions: [MetadataFileVersion?] = []
    private let started: RenameReadGate?
    private let release: RenameReadGate?

    init(mode: LoadMode, started: RenameReadGate? = nil, release: RenameReadGate? = nil) {
        self.mode = mode
        self.started = started
        self.release = release
    }

    var writeCount: Int { lock.withLock { recordedWriteCount } }
    var lastExpectedVersion: MetadataFileVersion? { lock.withLock { recordedExpectedVersions.last ?? nil } }

    func setMode(_ mode: LoadMode) { lock.withLock { self.mode = mode } }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let started { await started.open() }
        if let release { await release.wait() }
        let mode = lock.withLock { self.mode }
        switch mode {
        case .fail:
            throw CocoaError(.fileReadCorruptFile)
        case .real:
            return try await TagLibAudioMetadataPipeline().loadAudioFile(at: url, id: id)
        }
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try TagLibMetadataManager.readSnapshot(from: url, includingAudioContent: true)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try TagLibMetadataManager.fileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: url)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recordWrite(expectedVersion)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recordWrite(expectedVersion)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recordWrite(expectedVersion)
        return AudioMetadataWriteResult(warnings: [])
    }

    private nonisolated func recordWrite(_ version: MetadataFileVersion?) {
        lock.withLock {
            recordedWriteCount += 1
            recordedExpectedVersions.append(version)
        }
    }
}

private actor RenameReadGate {
    private var opened = false
    private var pending: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { pending.append($0) }
    }

    func open() {
        opened = true
        let waiters = pending
        pending.removeAll()
        waiters.forEach { $0.resume() }
    }
}
