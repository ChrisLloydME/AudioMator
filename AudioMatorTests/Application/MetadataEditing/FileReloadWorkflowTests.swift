import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

@MainActor
final class FileReloadWorkflowTests: XCTestCase {
    func testExplicitReloadUpdatesCleanInspectorAndKeepsSelection() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let refreshed = AudioFileTestFactory.make(id: original.id, url: original.url, title: "Disk")
        let pipeline = FileReloadTestPipeline(files: [refreshed])
        let viewModel = selectedViewModel(original, pipeline: pipeline)

        await viewModel.reloadSelectedFilesFromDisk()

        XCTAssertEqual(viewModel.files.first?.title, "Disk")
        XCTAssertEqual(viewModel.edit?.title, "Disk")
        XCTAssertEqual(viewModel.selectedAudioIDs, [original.id])
        XCTAssertFalse(viewModel.isReloadingSelectedFiles)
        XCTAssertEqual(pipeline.loadCount, 1)
    }

    func testExplicitReloadRequiresDirtyDraftToBeResolved() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let pipeline = FileReloadTestPipeline()
        let viewModel = selectedViewModel(original, pipeline: pipeline)
        viewModel.edit?.title = "Draft"

        await viewModel.reloadSelectedFilesFromDisk()

        XCTAssertEqual(viewModel.edit?.title, "Draft")
        XCTAssertEqual(viewModel.files.first?.title, "Original")
        XCTAssertEqual(pipeline.loadCount, 0)
    }

    func testActivationReloadPreservesDirtyDraftAndItsOriginalRevision() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let refreshed = AudioFileTestFactory.make(id: original.id, url: original.url, title: "External")
        let pipeline = FileReloadTestPipeline(files: [refreshed])
        let viewModel = selectedViewModel(original, pipeline: pipeline)
        viewModel.edit?.title = "Draft"

        await viewModel.refreshSelectedFilesAfterActivation()

        XCTAssertEqual(viewModel.files.first?.title, "External")
        XCTAssertEqual(viewModel.edit?.title, "Draft")
        XCTAssertEqual(viewModel.inspectorEditSourceFilesByID[original.id]?.snapshotID, original.snapshotID)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
    }

    func testActivationSkipsUnchangedRevisionButDetectsPermissionOnlyChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("revision.mp3")
        try Data("revision fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let original = AudioFileTestFactory.make(url: url, title: "Original").withUpdatedURL(
            url,
            fileFingerprint: try AudioFileFingerprint.capture(at: url),
            metadataFileVersion: try TagLibMetadataManager.fileVersion(at: url)
        )
        let refreshed = AudioFileTestFactory.make(id: original.id, url: url, title: "Disk")
        let pipeline = FileReloadTestPipeline(files: [refreshed])
        let viewModel = selectedViewModel(original, pipeline: pipeline)

        await viewModel.refreshSelectedFilesAfterActivation()
        XCTAssertEqual(pipeline.loadCount, 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        await viewModel.refreshSelectedFilesAfterActivation()
        XCTAssertEqual(pipeline.loadCount, 1)
        XCTAssertEqual(viewModel.edit?.title, "Disk")
    }

    func testReloadFailureRetainsLastSnapshotAndReportsManualFailure() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let viewModel = selectedViewModel(original, pipeline: FileReloadTestPipeline())

        await viewModel.reloadSelectedFilesFromDisk()

        XCTAssertEqual(viewModel.files.first?.snapshotID, original.snapshotID)
        XCTAssertEqual(viewModel.edit?.title, "Original")
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Reload Failed")
        XCTAssertFalse(viewModel.isReloadingSelectedFiles)
    }

    func testReloadWaitsForOutstandingMutationReservation() async throws {
        let original = AudioFileTestFactory.make(title: "Original")
        let pipeline = FileReloadTestPipeline(files: [original])
        let viewModel = selectedViewModel(original, pipeline: pipeline)
        let reserved = FileReloadLatch()
        let release = FileReloadLatch()
        let mutation = Task {
            try await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [original.url]) {
                await reserved.signal()
                await release.wait()
            }
        }
        await reserved.wait()
        let reload = Task { await viewModel.reloadSelectedFilesFromDisk() }
        let queued = await waitForQueuedReload(viewModel)
        XCTAssertTrue(queued)
        XCTAssertEqual(pipeline.loadCount, 0)
        await release.signal()
        try await mutation.value
        await reload.value
        XCTAssertEqual(pipeline.loadCount, 1)
    }

    func testLateReloadDoesNotReviveRemovedFile() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let started = FileReloadLatch()
        let release = FileReloadLatch()
        let pipeline = FileReloadTestPipeline(files: [original], beforeLoad: {
            await started.signal()
            await release.wait()
        })
        let viewModel = selectedViewModel(original, pipeline: pipeline)
        let reload = Task { await viewModel.reloadSelectedFilesFromDisk() }
        await started.wait()
        viewModel.removeQuickImportFile(id: original.id)
        await release.signal()
        await reload.value

        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertTrue(viewModel.selectedAudioIDs.isEmpty)
    }

    func testLateReloadCannotReplaceAnIndependentlyRefreshedSnapshot() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let started = FileReloadLatch()
        let release = FileReloadLatch()
        let pipeline = FileReloadTestPipeline(files: [original], beforeLoad: {
            await started.signal()
            await release.wait()
        })
        let viewModel = selectedViewModel(original, pipeline: pipeline)
        let reload = Task { await viewModel.reloadSelectedFilesFromDisk() }
        await started.wait()
        viewModel.mergeQuickImportFiles([
            AudioFileTestFactory.make(id: original.id, url: original.url, title: "Newer")
        ])
        await release.signal()
        await reload.value

        XCTAssertEqual(viewModel.files.first?.title, "Newer")
        XCTAssertEqual(viewModel.edit?.title, "Newer")
    }

    func testEditsMadeDuringReloadArePreservedAndDuplicateReloadIsIgnored() async {
        let original = AudioFileTestFactory.make(title: "Original")
        let refreshed = AudioFileTestFactory.make(id: original.id, url: original.url, title: "Disk")
        let started = FileReloadLatch()
        let release = FileReloadLatch()
        let pipeline = FileReloadTestPipeline(files: [refreshed], beforeLoad: {
            await started.signal()
            await release.wait()
        })
        let viewModel = selectedViewModel(original, pipeline: pipeline)
        let reload = Task { await viewModel.reloadSelectedFilesFromDisk() }
        await started.wait()
        viewModel.edit?.title = "Typed during reload"
        await viewModel.refreshSelectedFilesAfterActivation()
        await release.signal()
        await reload.value

        XCTAssertEqual(pipeline.loadCount, 1)
        XCTAssertEqual(viewModel.files.first?.title, "Disk")
        XCTAssertEqual(viewModel.edit?.title, "Typed during reload")
        XCTAssertEqual(viewModel.inspectorEditSourceFilesByID[original.id]?.snapshotID, original.snapshotID)
    }

    private func selectedViewModel(_ file: AudioFile, pipeline: FileReloadTestPipeline) -> AudioViewModel {
        // Restored watched folders would otherwise use the injected pipeline
        // concurrently and make these selected-file read counts nondeterministic.
        let suiteName = "AudioMatorFileReloadTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suiteName).json")
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: logURL)
        }
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: logURL)
        )
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([file.id])
        return viewModel
    }

    private func waitForQueuedReload(_ viewModel: AudioViewModel) async -> Bool {
        for _ in 0..<200 {
            if await viewModel.fileMutationCoordinator.queuedMutationCount == 1 { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private final class FileReloadTestPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let filesByURL: [URL: AudioFile]
    private let beforeLoad: (@Sendable () async -> Void)?
    private let lock = NSLock()
    nonisolated(unsafe) private var recordedLoadCount = 0

    init(files: [AudioFile] = [], beforeLoad: (@Sendable () async -> Void)? = nil) {
        filesByURL = Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0) })
        self.beforeLoad = beforeLoad
    }

    var loadCount: Int { lock.withLock { recordedLoadCount } }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        lock.withLock { recordedLoadCount += 1 }
        await beforeLoad?()
        guard let file = filesByURL[url] else { throw CocoaError(.fileReadUnknown) }
        return file
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try TagLibMetadataManager.fileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }
    nonisolated func writeRawMetadataPatch(_ patch: RawMetadataPatch, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }
    nonisolated func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?, to url: URL, verifyAfterWrite: Bool, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }
}

private actor FileReloadLatch {
    private var signaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func signal() {
        signaled = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
