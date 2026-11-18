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
    func testAllBatchWritersDrainStartedCommitsAndCancelRemainingFiles() async throws {
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
    func testCapturedPlanResultsStayOrderedThroughReversedCompletions() async throws {
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: PausedProviderReloadPipeline())
        let gate = PlanCompletionGate()
        let names = (0..<7).map { "\($0).flac" }
        let task = Task {
            await viewModel.executeBoundedMetadataPlan(fileNames: names) { index in
                await gate.wait(index)
                return (names[index], .failure("failure \(index)"))
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await gate.enteredCount < 4, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let initiallyEntered = await gate.enteredCount
        XCTAssertEqual(initiallyEntered, 4, "Exactly four targets may enter while all completions are blocked")
        for index in [3, 4, 5] {
            await gate.release(index)
            while await gate.enteredCount < index + 2, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        for index in [6, 2, 1, 0] { await gate.release(index) }
        let outcomes = await task.value
        XCTAssertEqual(outcomes.count, names.count)
        for index in names.indices {
            let outcome = try XCTUnwrap(outcomes[index])
            XCTAssertEqual(outcome.fileName, names[index])
            guard case .failure(let reason) = outcome.result else { return XCTFail("Expected captured failure") }
            XCTAssertEqual(reason, "failure \(index)")
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
        let parallel = ["itunes", "musicbrainz", "filename", "csv"].contains(workflow)
        let names = parallel ? ["first.flac", "second.flac", "third.flac", "fourth.flac", "fifth.flac", "sixth.flac", "seventh.flac"] : ["first.flac", "second.flac"]
        let expectedWrites = queued ? 0 : (parallel ? 4 : 1)
        var files: [AudioFile] = []
        for name in names {
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
                try await viewModel.fileMutationCoordinator.withExclusiveAccess(to: files.map(\.url)) {
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
                XCTAssertEqual(result.failed, 0)
                XCTAssertEqual(result.cancelled.count, queued ? 2 : 1)
                XCTAssertTrue(result.failures.isEmpty)
                XCTAssertTrue(result.cancelled.allSatisfy { $0.reason.localizedCaseInsensitiveContains("cancel") })
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
            while await viewModel.fileMutationCoordinator.queuedMutationCount < (parallel ? 4 : 1), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let queuedCount = await viewModel.fileMutationCoordinator.queuedMutationCount
            XCTAssertEqual(queuedCount, parallel ? 4 : 1)
        } else {
            do {
                try await pipeline.waitUntilReload()
                let commitDeadline = ContinuousClock.now.advanced(by: .seconds(5))
                while pipeline.writeCount < expectedWrites, ContinuousClock.now < commitDeadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertEqual(pipeline.writeCount, expectedWrites)
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
        XCTAssertEqual(pipeline.writeCount, expectedWrites)
        for index in files.indices {
            var expected = originalMaps[index]
            if index < expectedWrites {
                expected[workflow == "renumber" ? "TRACKNUMBER" : "TITLE"] = [workflow == "renumber" ? "7" : "Applied"]
            }
            XCTAssertEqual(try base.rawMetadataValueMap(for: files[index].url), expected, files[index].url.lastPathComponent)
        }
        XCTAssertNil(viewModel.metadataSaveProgress)
        guard workflow != "renumber" else { return }
        let entry = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first)
        XCTAssertTrue(entry.summary.contains(queued ? "No changes were saved to any files." : "\(expectedWrites) of \(files.count)"), entry.summary)
        XCTAssertEqual(entry.issues.map(\.fileName), Array(names.dropFirst(expectedWrites)))
        XCTAssertTrue(entry.issues[0].messages.joined().localizedCaseInsensitiveContains("cancel"))
    }
}

private nonisolated final class PausedProviderReloadPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let base = TagLibAudioMetadataPipeline()
    private let lock = NSLock()
    private var writes = 0
    private let reloadStarted = CancellationTestGate()
    private let reloadRelease = CancellationTestGate()
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
}

nonisolated final class ProviderSemanticWriteTests: XCTestCase {
    @MainActor
    func testTotalOnlyProviderAndCSVWritesPersist() async throws {
        for disc in [false, true] {
            for writer in ["itunes", "musicbrainz", "csv"] {
                let file = try await fixture()
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
                XCTAssertEqual(pipeline.writeCount, 1, "\(writer), disc=\(disc)")
                let saved = try TagLibMetadataManager.readMetadataResult(from: file.url)
                XCTAssertEqual(disc ? saved.disc : saved.track, 0)
                XCTAssertEqual(disc ? saved.discTotal : saved.trackTotal, disc ? 3 : 12)

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
        _ = try base.eraseAllMetadata(at: url, expectedVersion: nil)
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


private actor PlanCompletionGate {
    private var entered: Set<Int> = []
    private var released: Set<Int> = []
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    var enteredCount: Int { entered.count }

    func wait(_ index: Int) async {
        entered.insert(index)
        if released.contains(index) { return }
        await withCheckedContinuation { waiting[index] = $0 }
    }

    func release(_ index: Int) {
        released.insert(index)
        waiting.removeValue(forKey: index)?.resume()
    }
}
