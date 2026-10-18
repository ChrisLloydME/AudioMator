import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

@MainActor
final class RenameRefreshSafetyTests: XCTestCase {
    func testMoveSupersedesPendingOldURLAndLateReadCannotOverwriteNewerObservation() async throws {
        let original = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/pending-original.mp3"))
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameRefreshFailurePipeline(recoveredVersion: nil))
        viewModel.mergeQuickImportFiles([original])
        viewModel.flushPendingMetadataReloads()
        viewModel.replaceLoadedFile(original, refreshGeneration: viewModel.makeFileModelRefreshGeneration(),
                                   deferVisibleRefresh: true)
        let newURL = URL(fileURLWithPath: "/tmp/pending-moved.mp3")
        _ = await viewModel.applyMovedFiles([(id: original.id, newURL: newURL)])
        viewModel.flushPendingMetadataReloads()
        XCTAssertEqual(viewModel.files.first?.url, newURL)
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
    }

    func testLateMoveReadbackCannotReplaceNewerGeneratedObservation() async throws {
        let original = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/rename-late-source.mp3"))
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameRefreshFailurePipeline(recoveredVersion: nil, beforeLoad: {
            await started.open()
            await release.wait()
        })
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let newURL = URL(fileURLWithPath: "/tmp/rename-late-destination.mp3")
        let move = Task { await viewModel.applyMovedFiles([(id: original.id, newURL: newURL)]) }
        let didStart = (try? await withAsyncTimeout(.seconds(3), operationName: "Test rename gate") {
            await started.wait()
            return true
        }) ?? false
        XCTAssertTrue(didStart)
        let newer = AudioFileTestFactory.make(id: original.id, url: newURL, title: "Newer observation")
        viewModel.replaceLoadedFile(newer, refreshGeneration: viewModel.makeFileModelRefreshGeneration())
        await release.open()
        _ = await move.value
        XCTAssertEqual(viewModel.files.first?.url, newURL)
        XCTAssertEqual(viewModel.files.first?.title, "Newer observation")
    }

    func testFailedRenameRefreshDisablesMetadataWritesWhenRevisionCannotBeRecovered() async {
        let id = UUID()
        let original = AudioFileTestFactory.make(
            id: id,
            url: URL(fileURLWithPath: "/tmp/original.mp3")
        )
        let pipeline = RenameRefreshFailurePipeline(recoveredVersion: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let warnings = await viewModel.applyMovedFiles([
            (id: id, newURL: URL(fileURLWithPath: "/tmp/missing-renamed.mp3"))
        ])

        let moved = try! XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertTrue(warnings.first?.contains("editing is disabled") == true)

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Must not write"
        let result = await viewModel.persistMetadataEdit(edit, to: moved)

        guard case .failure(let reason) = result else {
            return XCTFail("Expected a refresh-required failure")
        }
        XCTAssertTrue(reason.contains("Reload the file"))
        XCTAssertEqual(pipeline.writeCount, 0)
    }

    func testRefreshRequiredRecoveryCannotBeUndoneByQueuedOrOlderReload() throws {
        let original = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/recovery.mp3"))
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameRefreshFailurePipeline(recoveredVersion: nil))
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

    func testFailedFullRefreshRetainsWriteSafetyWhenLightweightRevisionRecovers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameRefresh-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent("renamed.mp3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("renamed payload".utf8).write(to: destination)
        defer { try? FileManager.default.removeItem(at: directory) }

        let version = try TagLibMetadataManager.fileVersion(at: destination)
        let id = UUID()
        let original = AudioFileTestFactory.make(
            id: id,
            url: directory.appendingPathComponent("original.mp3")
        )
        let pipeline = RenameRefreshFailurePipeline(recoveredVersion: version)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let warnings = await viewModel.applyMovedFiles([(id: id, newURL: destination)])

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(moved.fileFingerprint)
        XCTAssertEqual(moved.metadataFileVersion, version)
        XCTAssertTrue(warnings.first?.contains("recovered its safety revision") == true)
    }
}

private final class RenameRefreshFailurePipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let recoveredVersion: MetadataFileVersion?
    private let beforeLoad: (@Sendable () async -> Void)?
    private let lock = NSLock()
    private var recordedWriteCount = 0

    init(recoveredVersion: MetadataFileVersion?, beforeLoad: (@Sendable () async -> Void)? = nil) {
        self.recoveredVersion = recoveredVersion
        self.beforeLoad = beforeLoad
    }

    var writeCount: Int {
        lock.withLock { recordedWriteCount }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await beforeLoad?()
        throw CocoaError(.fileReadCorruptFile)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        guard let recoveredVersion else { throw CocoaError(.fileReadUnknown) }
        return recoveredVersion
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock { recordedWriteCount += 1 }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
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
