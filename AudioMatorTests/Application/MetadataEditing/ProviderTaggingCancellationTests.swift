import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class ProviderTaggingCancellationTests: XCTestCase {
    @MainActor
    func testITunesCancellationAfterCommitKeepsActualOutcomeAndAccountsForRemainingFiles() async throws {
        try await checkCancellation(workflow: "itunes")
    }

    @MainActor
    func testMusicBrainzCancellationAfterCommitKeepsActualOutcomeAndAccountsForRemainingFiles() async throws {
        try await checkCancellation(workflow: "musicbrainz")
    }

    @MainActor
    func testAllBatchWritersStopAfterCommittedFile() async throws {
        for workflow in ["filename", "csv", "raw", "renumber"] {
            try await checkCancellation(workflow: workflow)
        }
    }

    @MainActor
    func testEveryBatchWriterCancelsWhileQueuedWithoutWriting() async throws {
        for workflow in ["itunes", "musicbrainz", "filename", "csv", "raw", "renumber"] {
            try await checkCancellation(workflow: workflow, queued: true)
        }
    }

    @MainActor
    private func checkCancellation(workflow: String, queued: Bool = false) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProviderCancellation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile.flac", withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil))
        let base = TagLibAudioMetadataPipeline()
        var files: [AudioFile] = []
        for name in ["first.flac", "second.flac"] {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: url)
            _ = try base.writeRawMetadataPatch(RawMetadataPatch(valuesToSet: [
                "TITLE": ["Original"], "ARTIST": ["Keep A", "Keep B"], "CUSTOM-KEEP": ["untouched"]
            ]), to: url, expectedVersion: nil)
            files.append(try await base.loadAudioFile(at: url, id: UUID()))
        }
        let originalMaps = try files.map { try base.rawMetadataValueMap(for: $0.url) }
        let pipeline = PausedProviderReloadPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(files)
        let reserved = CancellationTestGate()
        let releaseReservation = CancellationTestGate()
        let reservation = Task {
            if queued {
                try await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [files[0].url]) {
                    await reserved.open()
                    await releaseReservation.wait()
                }
            }
        }
        if queued { await reserved.wait() }
        let task = Task {
            switch workflow {
            case "filename":
                _ = await viewModel.applyFilenameMetadataPlan(files.map {
                    FilenameMetadataWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                        values: [.title: "Applied"], expectedFileFingerprint: $0.fileFingerprint)
                })
            case "csv":
                _ = await viewModel.applyMetadataExchangeWriteEntries(files.map {
                    MetadataExchangeWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                        values: [.title: "Applied"], expectedFileFingerprint: $0.fileFingerprint)
                })
            case "raw":
                let maps = Dictionary(uniqueKeysWithValues: files.enumerated().map { index, file in
                    var map = originalMaps[index]
                    map["TITLE"] = ["Applied"]
                    return (file.id, map)
                })
                _ = await viewModel.applyRawMetadataPropertyMaps(maps, to: files.map(MetadataEditorTarget.init(file:)))
            case "renumber":
                let result = await viewModel.renumberTrackNumbers(orderedIDs: files.map(\.id), selectedIDs: [],
                    options: TrackRenumberOptions(startNumber: 7, padWithZeros: false))
                XCTAssertEqual(result.succeeded, queued ? 0 : 1)
                XCTAssertEqual(result.failed, queued ? 2 : 1)
                XCTAssertTrue(result.failures.allSatisfy { $0.reason.localizedCaseInsensitiveContains("cancel") })
            case "musicbrainz":
                await viewModel.applyMusicBrainzTaggingPlan(files.map {
                    MusicBrainzTaggingWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                        values: [.title: "Applied"], expectedFileFingerprint: $0.fileFingerprint)
                })
            default:
                await viewModel.applyiTunesTaggingPlan(files.map {
                    iTunesTaggingWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                        values: [.title: "Applied"], expectedFileFingerprint: $0.fileFingerprint)
                })
            }
        }
        if queued {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while await viewModel.fileMutationCoordinator.queuedMutationCount == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let queuedCount = await viewModel.fileMutationCoordinator.queuedMutationCount
            XCTAssertEqual(queuedCount, 1)
        } else {
            do {
                try await pipeline.waitUntilReload()
            } catch {
                task.cancel()
                await pipeline.releaseReload()
                await releaseReservation.open()
                try await reservation.value
                await task.value
                throw error
            }
        }
        task.cancel()
        await pipeline.releaseReload()
        await releaseReservation.open()
        try await reservation.value
        await task.value
        XCTAssertEqual(pipeline.writeCount, queued ? 0 : 1)
        var expectedFirst = originalMaps[0]
        if !queued {
            expectedFirst[workflow == "renumber" ? "TRACKNUMBER" : "TITLE"] = [workflow == "renumber" ? "7" : "Applied"]
        }
        XCTAssertEqual(try base.rawMetadataValueMap(for: files[0].url), expectedFirst)
        XCTAssertEqual(try base.rawMetadataValueMap(for: files[1].url), originalMaps[1])
        XCTAssertNil(viewModel.metadataSaveProgress)
        guard workflow != "renumber" else { return }
        let entry = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first)
        XCTAssertTrue(entry.summary.contains(queued ? "No files were saved" : "1 of 2"), entry.summary)
        XCTAssertEqual(entry.issues.map(\.fileName), queued ? ["first.flac", "second.flac"] : ["second.flac"])
        XCTAssertTrue(entry.issues[0].messages.joined().localizedCaseInsensitiveContains("cancel"))
    }
}

private nonisolated final class PausedProviderReloadPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let base = TagLibAudioMetadataPipeline()
    private let lock = NSLock()
    private var writes = 0
    private let reloadStarted = CancellationTestGate()
    private let reloadRelease = CancellationTestGate()
    nonisolated var hasCommitted: Bool { lock.withLock { writes > 0 } }
    nonisolated var writeCount: Int { lock.withLock { writes } }
    nonisolated func releaseReload() async { await reloadRelease.open() }
    nonisolated func waitUntilReload() async throws {
        try await withAsyncTimeout(.seconds(3), operationName: "Test commit gate") {
            await self.reloadStarted.wait()
        }
    }
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await reloadStarted.open()
        await reloadRelease.wait()
        return try await base.loadAudioFile(at: url, id: id)
    }
    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion { try base.metadataFileVersion(at: url) }
    nonisolated func rawMetadataDumpText(for url: URL) -> String? { base.rawMetadataDumpText(for: url) }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { try base.rawMetadataValueMap(for: url) }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        let result = try base.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
        lock.withLock { writes += 1 }
        return result
    }
    nonisolated func writeRawMetadataPatch(_ patch: RawMetadataPatch, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        let result = try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
        lock.withLock { writes += 1 }
        return result
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }
    nonisolated func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?, to url: URL, verifyAfterWrite: Bool, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        let result = try base.writeTrackNumberText(trackNumberText, discNumberText: discNumberText, to: url, verifyAfterWrite: verifyAfterWrite, expectedVersion: expectedVersion)
        lock.withLock { writes += 1 }
        return result
    }
}

nonisolated final class ProviderSemanticWriteTests: XCTestCase {
    @MainActor
    func testTotalOnlyProviderAndCSVWritesAreRejectedWithoutChangingFile() async throws {
        let file = try await fixture()
        let originalBytes = try Data(contentsOf: file.url)
        for disc in [false, true] {
            for writer in ["itunes", "musicbrainz", "csv"] {
                let pipeline = PausedProviderReloadPipeline()
                await pipeline.releaseReload()
                let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
                viewModel.mergeQuickImportFiles([file])
                switch writer {
                case "itunes":
                    await viewModel.applyiTunesTaggingPlan([
                        iTunesTaggingWriteEntry(fileID: file.id, fileName: file.url.lastPathComponent,
                            values: disc ? [.discTotal: "3"] : [.trackTotal: "12"], expectedFileFingerprint: file.fileFingerprint)
                    ])
                case "musicbrainz":
                    await viewModel.applyMusicBrainzTaggingPlan([
                        MusicBrainzTaggingWriteEntry(fileID: file.id, fileName: file.url.lastPathComponent,
                            values: disc ? [.discTotal: "3"] : [.trackTotal: "12"], expectedFileFingerprint: file.fileFingerprint)
                    ])
                default:
                    let plan = MetadataExchangePlanner.makeCSVImportPlan(
                        template: disc ? "{{discTotal}}" : "{{trackTotal}}",
                        sourceText: disc ? "3" : "12", firstRowIsHeader: false,
                        targetFiles: [file], clearBlankImportedValues: false)
                    XCTAssertEqual(plan.writeEntries.count, 1)
                    _ = await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)
                }
                XCTAssertEqual(pipeline.writeCount, 0, "\(writer), disc=\(disc)")
                XCTAssertEqual(try Data(contentsOf: file.url), originalBytes)
                XCTAssertEqual(viewModel.saveIssueLogStore.entries.first?.issues.count, 1)
                XCTAssertTrue(viewModel.saveIssueLogStore.entries.first?.issues.first?.messages.joined()
                    .contains(disc ? "total disc count" : "total track count") == true)
            }
        }
    }

    @MainActor
    func testUneditedTotalOnlyRawFieldDoesNotBlockUnrelatedInspectorWrite() async throws {
        let file = try await fixture(extra: ["TRACKTOTAL": ["12"]])
        XCTAssertEqual(file.track, 0)
        XCTAssertEqual(file.trackTotal, 12)
        let pipeline = PausedProviderReloadPipeline()
        await pipeline.releaseReload()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        let base = TagLibAudioMetadataPipeline()
        var expectedMap = try base.rawMetadataValueMap(for: file.url)
        expectedMap["TITLE"] = ["Changed title"]
        var edit = SingleFileEditModel(from: file)
        edit.title = "Changed title"
        let result = await viewModel.persistMetadataEdit(edit, to: file, comparedTo: file)
        guard case .success = result else { return XCTFail("An unchanged total-only pair must not reject a title edit: \(result)") }
        XCTAssertEqual(pipeline.writeCount, 1)
        XCTAssertEqual(try base.rawMetadataValueMap(for: file.url), expectedMap)
    }

    @MainActor
    private func fixture(extra: RawMetadataValueMap = [:]) async throws -> AudioFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ProviderSemantic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile.flac", withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil))
        let url = directory.appendingPathComponent("semantic.flac")
        try FileManager.default.copyItem(at: source, to: url)
        let base = TagLibAudioMetadataPipeline()
        _ = try base.eraseAllMetadata(at: url)
        _ = try base.writeRawMetadataPatch(RawMetadataPatch(valuesToSet: [
            "TITLE": ["Original"], "ARTIST": ["Keep A", "Keep B"], "CUSTOM-KEEP": ["untouched"]
        ].merging(extra) { _, value in value }), to: url, expectedVersion: nil)
        return try await base.loadAudioFile(at: url, id: UUID())
    }
}

private actor CancellationTestGate {
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
