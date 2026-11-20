import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Table-driven acceptance for the reviewed Inspector and Raw Editor write routes.
///
/// Every case uses a real disposable fixture copy so the authoritative
/// fingerprint/package-token checks run against disk. The recording pipeline plays
/// the package writer/reloader and records the exact forwarded revision.
nonisolated final class InspectorReviewedWriteAcceptanceTests: XCTestCase {
    // MARK: - Fixtures

    @MainActor
    private func makeObservedFixture(
        title: String = "Original"
    ) throws -> (url: URL, file: AudioFile, version: MetadataFileVersion) {
        let url = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: url,
            title: title,
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        return (url, file, tokens.version)
    }

    @MainActor
    private func makeInspectorViewModel(
        file: AudioFile,
        pipeline: AcceptanceReviewedPipeline,
        draftTitle: String? = "Inspector Draft"
    ) -> AudioViewModel {
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([file.id])
        viewModel.updateEditForSelection()
        if let draftTitle {
            viewModel.edit?.title = draftTitle
        }
        return viewModel
    }

    @MainActor
    private func waitForSave(_ viewModel: AudioViewModel) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while viewModel.metadataSaveProgress != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        // Allow the main-actor completion (HUD/status) to run.
        try? await Task.sleep(for: .milliseconds(20))
    }

    // MARK: - Inspector cases

    @MainActor
    func testEqualObservationRefreshStillWritesAndForwardsCapturedRevision() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = makeInspectorViewModel(file: fixture.file, pipeline: pipeline)

        // A passive refresh republishes an equal observation (new snapshotID,
        // same path/fingerprint/version). The dirty draft keeps its captured source.
        let refreshed = AudioFileTestFactory.make(
            id: fixture.file.id,
            url: fixture.url,
            title: "Original",
            fileFingerprint: fixture.file.fileFingerprint!,
            metadataFileVersion: fixture.version
        )
        viewModel.mergeQuickImportFiles([refreshed])

        viewModel.saveInspectorEdits()
        await waitForSave(viewModel)

        XCTAssertEqual(pipeline.metadataWriteRecords.count, 1)
        XCTAssertEqual(pipeline.metadataWriteRecords.first?.expectedVersion, fixture.version)
        XCTAssertEqual(pipeline.metadataWriteRecords.first?.payload.title, "Inspector Draft")
        XCTAssertTrue(viewModel.metadataWriteHUD?.style == .success)
    }

    @MainActor
    func testSameUUIDReplacementAfterReviewRejectsWithoutWritingOrChangingBytes() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = makeInspectorViewModel(file: fixture.file, pipeline: pipeline)

        // Same path and same session UUID, different bytes on disk after review.
        try Data(repeating: 0x5A, count: 96).write(to: fixture.url, options: .atomic)
        let bytesAfterReplacement = try Data(contentsOf: fixture.url)

        viewModel.saveInspectorEdits()
        await waitForSave(viewModel)

        XCTAssertTrue(pipeline.metadataWriteRecords.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytesAfterReplacement)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
    }

    @MainActor
    func testMissingDiskTokensRejectBeforeAnyWriterCall() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = makeInspectorViewModel(file: fixture.file, pipeline: pipeline)

        // Replace the captured source with a display projection that carries no
        // observation (missing fingerprint/version). No `?? file` fallback is
        // allowed to synthesize authority from the model loaded at Apply.
        viewModel.inspectorEditSourceFilesByID[fixture.file.id] = AudioFileTestFactory.make(
            id: fixture.file.id,
            url: fixture.url,
            title: "Original",
            includeDefaultFileFingerprint: false
        )
        viewModel.saveInspectorEdits()
        await waitForSave(viewModel)

        XCTAssertTrue(pipeline.metadataWriteRecords.isEmpty)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
    }

    @MainActor
    func testPreExistingProtectionRejectsBeforeAnyWriterCall() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = makeInspectorViewModel(file: fixture.file, pipeline: pipeline)
        viewModel.markFileRequiresRefresh(id: fixture.file.id)

        viewModel.saveInspectorEdits()
        await waitForSave(viewModel)

        XCTAssertTrue(pipeline.metadataWriteRecords.isEmpty)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
    }

    @MainActor
    func testPostQueueInvalidationRevokesPermitBeforeAdmission() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = makeInspectorViewModel(file: fixture.file, pipeline: pipeline)

        let hold = AsyncGate()
        let release = AsyncGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [fixture.url]) {
                await hold.open()
                await release.wait()
            }
        }
        await hold.wait()
        viewModel.saveInspectorEdits()

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await viewModel.fileMutationCoordinator.queuedMutationCount == 0,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.markFileRequiresRefresh(id: fixture.file.id)
        await release.open()
        await holder.value
        await waitForSave(viewModel)

        XCTAssertTrue(pipeline.metadataWriteRecords.isEmpty)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertEqual(viewModel.metadataCommitPermits.activePermitCount, 0)
    }

    @MainActor
    func testEqualFingerprintChangedVersionRejectsWithUnchangedBytes() async throws {
        let fixture = try makeObservedFixture()
        let otherFixture = try makeObservedFixture(title: "Other")
        // The fake package reports a different opaque revision while the file
        // fingerprint still matches: the resolver must fail closed before writing.
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: otherFixture.version]
        )
        let viewModel = makeInspectorViewModel(file: fixture.file, pipeline: pipeline)
        let bytesBefore = try Data(contentsOf: fixture.url)

        viewModel.saveInspectorEdits()
        await waitForSave(viewModel)

        XCTAssertTrue(pipeline.metadataWriteRecords.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytesBefore)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
    }

    // MARK: - Raw editor cases

    @MainActor
    func testRawApplyForwardsCapturedRevisionAndExactDelta() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let target = MetadataEditorTarget(file: fixture.file)
        var draft = try XCTUnwrap(fixture.file.metadataConflictBaseline).values
        draft["TITLE"] = ["Raw reviewed title"]

        let result = await viewModel.applyRawMetadataPropertyMaps([fixture.file.id: draft], to: [target])

        XCTAssertEqual(result.succeededTargetIDs, [fixture.file.id])
        XCTAssertEqual(pipeline.rawWriteRecords.count, 1)
        XCTAssertEqual(pipeline.rawWriteRecords.first?.expectedVersion, fixture.version)
        XCTAssertEqual(
            pipeline.rawWriteRecords.first?.patch.valuesToSet["TITLE"],
            ["Raw reviewed title"]
        )
    }

    @MainActor
    func testRawApplyNoOpDoesNotReachWriter() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let target = MetadataEditorTarget(file: fixture.file)
        let unchangedDraft = try XCTUnwrap(fixture.file.metadataConflictBaseline).values

        let result = await viewModel.applyRawMetadataPropertyMaps(
            [fixture.file.id: unchangedDraft],
            to: [target]
        )

        XCTAssertEqual(result.succeededTargetIDs, [fixture.file.id])
        XCTAssertTrue(pipeline.rawWriteRecords.isEmpty)
    }

    @MainActor
    func testRawApplyRejectsTargetWithoutReviewedAuthority() async throws {
        let fixture = try makeObservedFixture()
        let pipeline = AcceptanceReviewedPipeline(
            filesByURL: [fixture.url: fixture.file],
            versionsByURL: [fixture.url: fixture.version]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        var draft = try XCTUnwrap(fixture.file.metadataConflictBaseline).values
        draft["TITLE"] = ["Should not be written"]
        let displayTarget = MetadataEditorTarget(
            file: AudioFileTestFactory.make(
                id: fixture.file.id,
                url: fixture.url,
                title: "Original",
                includeDefaultFileFingerprint: false
            )
        )

        let result = await viewModel.applyRawMetadataPropertyMaps(
            [fixture.file.id: draft],
            to: [displayTarget]
        )

        XCTAssertEqual(result.failedTargetIDs, [fixture.file.id])
        XCTAssertTrue(pipeline.rawWriteRecords.isEmpty)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

/// Recording test double for the reviewed Inspector/raw routes. It never touches
/// disk itself; the route's own resolver performs the authoritative checks.
private nonisolated final class AcceptanceReviewedPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct MetadataRecord: Sendable {
        let url: URL
        let expectedVersion: MetadataFileVersion
        let payload: MetadataEditPayload
    }

    struct RawRecord: Sendable {
        let url: URL
        let expectedVersion: MetadataFileVersion
        let patch: RawMetadataPatch
    }

    private let lock = NSLock()
    private let filesByURL: [URL: AudioFile]
    private let versionsByURL: [URL: MetadataFileVersion]
    private var metadataRecords: [MetadataRecord] = []
    private var rawRecords: [RawRecord] = []

    init(
        filesByURL: [URL: AudioFile],
        versionsByURL: [URL: MetadataFileVersion]
    ) {
        self.filesByURL = filesByURL
        self.versionsByURL = versionsByURL
    }

    var metadataWriteRecords: [MetadataRecord] { lock.withLock { metadataRecords } }
    var rawWriteRecords: [RawRecord] { lock.withLock { rawRecords } }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        guard let file = filesByURL[url] else { throw CocoaError(.fileNoSuchFile) }
        return file
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        guard let version = versionsByURL[url] else { throw CocoaError(.featureUnsupported) }
        return version
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        // The acceptance cases either take the unchanged-revision fast path or
        // must fail before a rebase; a rebase attempt is always rejected here.
        throw CocoaError(.featureUnsupported)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        guard let expectedVersion else { throw CocoaError(.fileWriteUnknown) }
        lock.withLock {
            metadataRecords.append(
                MetadataRecord(url: url, expectedVersion: expectedVersion, payload: edit)
            )
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        guard let expectedVersion else { throw CocoaError(.fileWriteUnknown) }
        lock.withLock {
            rawRecords.append(
                RawRecord(url: url, expectedVersion: expectedVersion, patch: patch)
            )
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
