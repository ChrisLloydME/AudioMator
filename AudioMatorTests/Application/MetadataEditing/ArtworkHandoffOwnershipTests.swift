import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Destination-draft ownership for the six local artwork handoffs
/// (Finder / photo library / clipboard, single and batch). Each command captures
/// its F3 Inspector draft authority before the first suspension; completion may
/// only stage into that same live draft with the full captured target set.
nonisolated final class ArtworkHandoffOwnershipTests: XCTestCase {
    // MARK: - Positive single handoffs

    @MainActor
    func testFinderSingleHandoffStagesIntoCapturedDraft() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .finder)
        )
        harness.viewModel.edit?.title = "Edited Title"

        let outcome = await harness.viewModel.finishPickedArtworkImport(
            url: harness.artworkFileURL,
            intent: intent
        )

        XCTAssertEqual(outcome, .staged)
        try assertSingleStaged(
            harness,
            expectedPNG: try expectedNormalizedPNG()
        )
        XCTAssertEqual(harness.viewModel.edit?.title, "Edited Title")
        XCTAssertNil(harness.viewModel.multiEdit)
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    @MainActor
    func testPhotoLibrarySingleHandoffStagesIntoCapturedDraft() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        let intent = try XCTUnwrap(
            harness.viewModel.beginPhotoLibraryArtworkImport(for: harness.file)
        )

        await harness.viewModel.finishArtworkImport(
            imageData: Self.tinyPNGData,
            intent: intent
        )

        try assertSingleStaged(harness, expectedPNG: try expectedNormalizedPNG())
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
        XCTAssertEqual(try Data(contentsOf: harness.audioFileURL), harness.audioBytes)
    }

    @MainActor
    func testClipboardSingleHandoffStagesIntoCapturedDraft() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .clipboard)
        )

        await harness.viewModel.finishArtworkImport(
            imageData: Self.tinyPNGData,
            intent: intent
        )

        try assertSingleStaged(harness, expectedPNG: try expectedNormalizedPNG())
        XCTAssertEqual(try Data(contentsOf: harness.audioFileURL), harness.audioBytes)
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    // MARK: - Positive batch handoffs

    @MainActor
    func testFinderBatchHandoffStagesIntoCapturedMultiDraft() async throws {
        let harness = try makeMultiHarness()
        defer { harness.removeTemporaryDirectory() }
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.files, source: .finder)
        )

        let outcome = await harness.viewModel.finishPickedArtworkImport(
            url: harness.artworkFileURL,
            intent: intent
        )

        XCTAssertEqual(outcome, .staged)
        try assertMultiStaged(harness, expectedPNG: try expectedNormalizedPNG())
        for (url, bytes) in harness.audioBytesByURL {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    @MainActor
    func testPhotoLibraryBatchHandoffStagesIntoCapturedMultiDraft() async throws {
        let harness = try makeMultiHarness()
        defer { harness.removeTemporaryDirectory() }
        let intent = try XCTUnwrap(
            harness.viewModel.beginPhotoLibraryArtworkImport(for: harness.files)
        )

        await harness.viewModel.finishArtworkImport(
            imageData: Self.tinyPNGData,
            intent: intent
        )

        try assertMultiStaged(harness, expectedPNG: try expectedNormalizedPNG())
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    @MainActor
    func testClipboardBatchHandoffStagesIntoCapturedMultiDraft() async throws {
        let harness = try makeMultiHarness()
        defer { harness.removeTemporaryDirectory() }
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.files, source: .clipboard)
        )

        await harness.viewModel.finishArtworkImport(
            imageData: Self.tinyPNGData,
            intent: intent
        )

        try assertMultiStaged(harness, expectedPNG: try expectedNormalizedPNG())
        for (url, bytes) in harness.audioBytesByURL {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    // MARK: - Guarded rejection: selection / draft ownership

    @MainActor
    func testSelectionChangeDuringGatedNormalizationRejectsHandoff() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        let other = harness.makeOtherFile()
        harness.viewModel.mergeQuickImportFiles([other])
        harness.viewModel.edit?.title = "Edited Title"

        let gate = ArtworkNormalizationGate()
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .clipboard)
        )
        let task = Task {
            await harness.viewModel.finishArtworkImport(
                imageData: Self.tinyPNGData,
                intent: intent,
                normalize: { data in
                    await gate.wait()
                    return data
                }
            )
        }
        await gate.waitUntilStarted()

        harness.viewModel.setSelectedAudioIDs([other.id])
        await gate.release()
        let outcome = await task.value

        guard case .rejected(let rejection)? = outcome else {
            return XCTFail("Expected a rejected handoff, got \(String(describing: outcome))")
        }
        if case .draftChanged = rejection {
            // expected
        } else {
            XCTFail("Expected draftChanged, got \(rejection)")
        }
        assertStaleHUD(harness.viewModel)
        XCTAssertEqual(harness.viewModel.editSourceFileID, other.id)
        XCTAssertEqual(harness.viewModel.edit?.artworkEditAction, .unchanged)
        XCTAssertNil(harness.viewModel.multiEdit)
        XCTAssertEqual(try Data(contentsOf: harness.audioFileURL), harness.audioBytes)
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    @MainActor
    func testSameIDReopenWhileGatedRejectsOlderHandoff() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        let other = harness.makeOtherFile()
        harness.viewModel.mergeQuickImportFiles([other])

        let gate = ArtworkNormalizationGate()
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .photoLibrary)
        )
        let task = Task {
            await harness.viewModel.finishArtworkImport(
                imageData: Self.tinyPNGData,
                intent: intent,
                normalize: { data in
                    await gate.wait()
                    return data
                }
            )
        }
        await gate.waitUntilStarted()

        // Leave the captured selection entirely, then reopen a new draft for the
        // exact same file ID. The session identity differs, so the old intent is
        // inert in both drafts.
        harness.viewModel.setSelectedAudioIDs([other.id])
        harness.viewModel.setSelectedAudioIDs([harness.file.id])
        await gate.release()
        let outcome = await task.value

        guard case .rejected? = outcome else {
            return XCTFail("Expected the same-ID reopen to reject the older handoff")
        }
        assertStaleHUD(harness.viewModel)
        XCTAssertEqual(harness.viewModel.editSourceFileID, harness.file.id)
        XCTAssertEqual(harness.viewModel.edit?.artworkEditAction, .unchanged)
        XCTAssertNil(harness.viewModel.multiEdit)
        XCTAssertEqual(try Data(contentsOf: harness.audioFileURL), harness.audioBytes)
    }

    @MainActor
    func testRemovedCapturedTargetRejectsBatchHandoffWithoutSubsetStaging() async throws {
        let harness = try makeMultiHarness()
        defer { harness.removeTemporaryDirectory() }

        let gate = ArtworkNormalizationGate()
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.files, source: .clipboard)
        )
        let task = Task {
            await harness.viewModel.finishArtworkImport(
                imageData: Self.tinyPNGData,
                intent: intent,
                normalize: { data in
                    await gate.wait()
                    return data
                }
            )
        }
        await gate.waitUntilStarted()

        let removed = harness.files[1]
        let surviving = harness.files[0]
        harness.viewModel.removeQuickImportFile(id: removed.id)
        await gate.release()
        let outcome = await task.value

        guard case .rejected? = outcome else {
            return XCTFail("Expected the removed captured target to reject the batch handoff")
        }
        assertStaleHUD(harness.viewModel)
        XCTAssertNil(harness.viewModel.multiEdit, "No multi draft may be created for a surviving subset")
        XCTAssertEqual(harness.viewModel.edit?.artworkEditAction, .unchanged)
        XCTAssertEqual(harness.viewModel.editSourceFileID, surviving.id)
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    @MainActor
    func testNewerClearSupersedesPendingLocalHandoff() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        harness.viewModel.edit?.title = "Edited Title"

        let gate = ArtworkNormalizationGate()
        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .finder)
        )
        let task = Task {
            await harness.viewModel.finishArtworkImport(
                imageData: Self.tinyPNGData,
                intent: intent,
                normalize: { data in
                    await gate.wait()
                    return data
                }
            )
        }
        await gate.waitUntilStarted()

        // A newer synchronous Clear owns the draft; the pending older handoff is
        // superseded and must not overwrite it.
        harness.viewModel.clearArtwork(for: harness.file)
        XCTAssertEqual(harness.viewModel.edit?.artworkEditAction, .remove)

        await gate.release()
        let outcome = await task.value

        guard case .rejected(let rejection)? = outcome else {
            return XCTFail("Expected the pending local handoff to be rejected")
        }
        if case .superseded = rejection {
            // expected
        } else {
            XCTFail("Expected superseded, got \(rejection)")
        }
        XCTAssertEqual(
            harness.viewModel.edit?.artworkEditAction,
            .remove,
            "The late handoff must not replace the newer Clear command"
        )
        XCTAssertEqual(harness.viewModel.edit?.title, "Edited Title")
        XCTAssertEqual(harness.recorder.writeInvocationCount, 0)
    }

    @MainActor
    func testDeferredObsoleteCompletionIsInert() async throws {
        let harness = try makeSingleHarness()
        defer { harness.removeTemporaryDirectory() }
        let other = harness.makeOtherFile()
        harness.viewModel.mergeQuickImportFiles([other])

        let intent = try XCTUnwrap(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .finder)
        )

        // The draft is replaced before the deferred callback runs. Capturing a
        // new command after the transition also supersedes the old intent.
        harness.viewModel.setSelectedAudioIDs([other.id])
        harness.viewModel.edit?.title = "Other Draft Edit"
        harness.viewModel.metadataWriteHUD = nil

        let outcome = await harness.viewModel.finishArtworkImport(
            imageData: Self.tinyPNGData,
            intent: intent
        )

        XCTAssertNil(outcome, "An obsolete completion must not stage or report")
        XCTAssertNil(harness.viewModel.metadataWriteHUD, "Obsolete failures stay silent")
        XCTAssertEqual(harness.viewModel.editSourceFileID, other.id)
        XCTAssertEqual(harness.viewModel.edit?.title, "Other Draft Edit")
        XCTAssertEqual(harness.viewModel.edit?.artworkEditAction, .unchanged)
        XCTAssertEqual(try Data(contentsOf: harness.audioFileURL), harness.audioBytes)
    }

    @MainActor
    func testNoInspectorDraftCannotAuthorizeLocalHandoff() throws {
        let harness = try makeSingleHarness(createDraft: false)
        defer { harness.removeTemporaryDirectory() }

        XCTAssertNil(
            harness.viewModel.beginArtworkImport(for: harness.file, source: .clipboard)
        )
        XCTAssertNil(
            harness.viewModel.beginArtworkImport(for: [harness.file], source: .finder)
        )
        XCTAssertNil(harness.viewModel.artworkImportTask)
        XCTAssertNil(harness.viewModel.edit)
    }

    // MARK: - Harness

    private static let tinyPNGData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    )!

    @MainActor
    private func expectedNormalizedPNG() throws -> Data {
        try ArtworkImageNormalizer.normalizedPNGData(from: Self.tinyPNGData)
    }

    private struct SingleHarness {
        let viewModel: AudioViewModel
        let recorder: ArtworkHandoffWriteRecorder
        let file: AudioFile
        let audioFileURL: URL
        let audioBytes: Data
        let artworkFileURL: URL
        let temporaryDirectory: URL

        @MainActor
        func makeOtherFile() -> AudioFile {
            let url = temporaryDirectory.appendingPathComponent("other-track.mp3")
            try? Data([0x49, 0x44, 0x33, 0x03]).write(to: url)
            return AudioFileTestFactory.make(
                url: url,
                title: "Other Track",
                album: "Other Album"
            )
        }

        func removeTemporaryDirectory() {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    private struct MultiHarness {
        let viewModel: AudioViewModel
        let recorder: ArtworkHandoffWriteRecorder
        let files: [AudioFile]
        let audioBytesByURL: [URL: Data]
        let artworkFileURL: URL
        let temporaryDirectory: URL

        func removeTemporaryDirectory() {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    private func makeSingleHarness(createDraft: Bool = true) throws -> SingleHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkHandoffOwnershipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let audioURL = directory.appendingPathComponent("track.mp3")
        let audioBytes = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00])
        try audioBytes.write(to: audioURL)

        let artworkURL = directory.appendingPathComponent("cover.png")
        try Self.tinyPNGData.write(to: artworkURL)

        let recorder = ArtworkHandoffWriteRecorder()
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: ArtworkHandoffMetadataPipeline(
                recorder: recorder,
                fileOverride: nil
            )
        )
        let file = AudioFileTestFactory.make(
            url: audioURL,
            title: "Test Track",
            album: "Test Album"
        )
        viewModel.mergeQuickImportFiles([file])
        if createDraft {
            viewModel.setSelectedAudioIDs([file.id])
        }

        return SingleHarness(
            viewModel: viewModel,
            recorder: recorder,
            file: file,
            audioFileURL: audioURL,
            audioBytes: audioBytes,
            artworkFileURL: artworkURL,
            temporaryDirectory: directory
        )
    }

    @MainActor
    private func makeMultiHarness() throws -> MultiHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkHandoffOwnershipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var files: [AudioFile] = []
        var bytesByURL: [URL: Data] = [:]
        for index in 0..<2 {
            let url = directory.appendingPathComponent("track-\(index).mp3")
            let bytes = Data([0x49, 0x44, 0x33, 0x03, UInt8(index), 0x00, 0x00, 0x00])
            try bytes.write(to: url)
            bytesByURL[url] = bytes
            files.append(
                AudioFileTestFactory.make(
                    url: url,
                    title: "Test Track \(index)",
                    album: "Test Album"
                )
            )
        }

        let artworkURL = directory.appendingPathComponent("cover.png")
        try Self.tinyPNGData.write(to: artworkURL)

        let recorder = ArtworkHandoffWriteRecorder()
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: ArtworkHandoffMetadataPipeline(
                recorder: recorder,
                fileOverride: nil
            )
        )
        viewModel.mergeQuickImportFiles(files)
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))

        return MultiHarness(
            viewModel: viewModel,
            recorder: recorder,
            files: files,
            audioBytesByURL: bytesByURL,
            artworkFileURL: artworkURL,
            temporaryDirectory: directory
        )
    }

    // MARK: - Assertions

    @MainActor
    private func assertSingleStaged(
        _ harness: SingleHarness,
        expectedPNG: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let action = try XCTUnwrap(harness.viewModel.edit?.artworkEditAction, file: file, line: line)
        guard case .replace(let pendingArtwork) = action else {
            return XCTFail("Expected staged artwork replacement, got \(action)", file: file, line: line)
        }
        XCTAssertEqual(pendingArtwork.data, expectedPNG, file: file, line: line)
        XCTAssertEqual(pendingArtwork.mimeType, "image/png", file: file, line: line)
        XCTAssertEqual(
            try Data(contentsOf: harness.audioFileURL),
            harness.audioBytes,
            "Staging must not touch disk",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertMultiStaged(
        _ harness: MultiHarness,
        expectedPNG: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let multiEdit = try XCTUnwrap(harness.viewModel.multiEdit, file: file, line: line)
        guard case .replace(let pendingArtwork) = multiEdit.artworkEditAction else {
            return XCTFail("Expected staged multi artwork replacement", file: file, line: line)
        }
        XCTAssertEqual(pendingArtwork.data, expectedPNG, file: file, line: line)
        XCTAssertEqual(harness.viewModel.selectedAudioIDs, Set(harness.files.map(\.id)), file: file, line: line)
    }

    @MainActor
    private func assertStaleHUD(
        _ viewModel: AudioViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Artwork Wasn’t Applied", file: file, line: line)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure, file: file, line: line)
        XCTAssertFalse(viewModel.metadataWriteHUD?.subtitle.isEmpty == true, file: file, line: line)
    }
}

// MARK: - Gated normalization

private actor ArtworkNormalizationGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

// MARK: - Recording pipeline

private nonisolated final class ArtworkHandoffWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var writeInvocationCount: Int {
        lock.withLock { count }
    }

    func recordWrite() {
        lock.withLock { count += 1 }
    }
}

private nonisolated final class ArtworkHandoffMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let recorder: ArtworkHandoffWriteRecorder
    private let fileOverride: AudioFile?

    init(recorder: ArtworkHandoffWriteRecorder, fileOverride: AudioFile?) {
        self.recorder = recorder
        self.fileOverride = fileOverride
    }

    func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let fileOverride { return fileOverride }
        return await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
    }

    func rawMetadataDumpText(for url: URL) -> String? { nil }
    func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recorder.recordWrite()
        return AudioMetadataWriteResult(warnings: [])
    }

    func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recorder.recordWrite()
        return AudioMetadataWriteResult(warnings: [])
    }

    func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recorder.recordWrite()
        return AudioMetadataWriteResult(warnings: [])
    }
}
