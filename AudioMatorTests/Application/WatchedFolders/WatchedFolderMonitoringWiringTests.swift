import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

#if os(macOS)
/// F4 wiring tests: the real `DirectoryMonitorController` identity layer driven
/// through `AudioViewModel`'s watched-folder scan pipeline.
///
/// These tests use disposable temporary directories and the production monitor
/// controller. Every wait is bounded; assertions about identity/status are
/// values, not timing.
@MainActor
final class WatchedFolderMonitoringWiringTests: XCTestCase {
    // MARK: - Attach, follow-up scans and status

    func testFlatWatchedFolderAttachesMonitorBeforeScanWithoutFollowUpScan() async throws {
        let environment = try makeEnvironment(fileNames: ["track.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))

        let loaded = await waitUntil { viewModel.files.count == 1 }
        XCTAssertTrue(loaded)
        let controller = try await waitForAttachedController(viewModel: viewModel, environment: environment)
        let rootKey = FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)
        let binding = try XCTUnwrap(controller.binding(forKey: rootKey))
        XCTAssertEqual(
            binding.identity,
            NativeDirectoryMonitorFileSystem().identity(at: environment.rootURL)
        )

        let status = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            $0.monitoredDirectoryCount == 1 && !$0.isDegraded
        }
        XCTAssertEqual(status.totalDirectoryCount, 1)
        XCTAssertEqual(status.failedToOpenCount, 0)
        XCTAssertEqual(status.identityMismatchCount, 0)
        XCTAssertTrue(status.message.contains("added, removed and renamed entries"))

        // The root descriptor was attached before enumeration, so the first scan
        // sees unchanged attachments and schedules no follow-up scan.
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(pipeline.loadCount, 1, "an unchanged attachment must not schedule a follow-up scan")
        XCTAssertEqual(viewModel.directoryMonitoringStatuses[environment.folder.id]?.isDegraded, false)
    }

    func testNestedDirectoryAttachmentSchedulesExactlyOneFollowUpScan() async throws {
        let environment = try makeEnvironment(fileNames: ["Sub/nested.mp3"], nestedDirectoryNames: ["Sub"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))

        let loaded = await waitUntil { viewModel.files.count == 1 && pipeline.loadCount >= 1 }
        XCTAssertTrue(loaded)

        // The first scan discovers "Sub" after enumeration; installing its
        // descriptor requests one follow-up scan. The follow-up observes
        // unchanged attachments and requests no further scan.
        let followedUp = await waitUntil { pipeline.loadCount == 2 }
        XCTAssertTrue(followedUp, "expected exactly one follow-up scan, loadCount=\(pipeline.loadCount)")
        let status = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            $0.monitoredDirectoryCount == 2 && !$0.isDegraded
        }
        XCTAssertEqual(status.totalDirectoryCount, 2)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(pipeline.loadCount, 2, "a scan with unchanged attachments must schedule no further scan")
    }

    func testCapOmissionPublishesDegradedStatusWithoutDroppingRoot() async throws {
        let nestedNames = (0..<130).map { "nested-\(String(format: "%03d", $0))" }
        let environment = try makeEnvironment(fileNames: [], nestedDirectoryNames: nestedNames)
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))

        let status = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            $0.omittedByLimitCount > 0
        }
        XCTAssertEqual(status.totalDirectoryCount, 131)
        XCTAssertEqual(status.monitoredDirectoryCount, 128)
        XCTAssertEqual(status.omittedByLimitCount, 3)
        XCTAssertTrue(status.isDegraded)
        XCTAssertTrue(status.message.contains("exceed the monitoring limit"))
        let controller = try await waitForAttachedController(viewModel: viewModel, environment: environment)
        let rootKey = FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)
        XCTAssertNotNil(controller.binding(forKey: rootKey), "root directory is always monitored")
        let nestedBinding = controller.binding(
            forKey: FileSystemPathSemantics.key(
                for: environment.rootURL.appendingPathComponent(nestedNames[129], isDirectory: true)
            )
        )
        XCTAssertNil(nestedBinding, "a capped nested directory must not be reported active")
    }

    // MARK: - Same-key replacement and terminal events

    func testSameKeyRootReplacementRebindsMonitorAndKeepsStatusTruthful() async throws {
        let environment = try makeEnvironment(fileNames: ["old.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))

        let controller = try await waitForAttachedController(viewModel: viewModel, environment: environment)
        let rootKey = FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)
        let originalBinding = try XCTUnwrap(controller.binding(forKey: rootKey))
        _ = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) { !$0.isDegraded }

        // Replace the watched root at the same pathname without a full app
        // restart. The retained descriptor follows the old inode; the refresh
        // must compare identities, rebind and report the current identity.
        let movedURL = environment.baseURL.appendingPathComponent("LibraryMoved", isDirectory: true)
        try FileManager.default.moveItem(at: environment.rootURL, to: movedURL)
        try FileManager.default.createDirectory(at: environment.rootURL, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: environment.rootURL.appendingPathComponent("new.mp3"))

        viewModel.refreshWatchedFolder(id: environment.folder.id)

        let rebound = await waitUntil {
            guard let binding = controller.binding(forKey: rootKey) else { return false }
            return binding.instanceToken != originalBinding.instanceToken
        }
        XCTAssertTrue(rebound, "monitor did not rebind to the replacement directory")
        let reboundBinding = try XCTUnwrap(controller.binding(forKey: rootKey))
        XCTAssertEqual(
            reboundBinding.identity,
            NativeDirectoryMonitorFileSystem().identity(at: environment.rootURL)
        )
        XCTAssertNotEqual(reboundBinding.identity, originalBinding.identity)
        XCTAssertFalse(controller.isCurrent(originalBinding.instanceToken, forKey: rootKey))

        let filesUpdated = await waitUntil {
            viewModel.files.map(\.url.lastPathComponent) == ["new.mp3"]
        }
        XCTAssertTrue(filesUpdated)
        let status = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            !$0.isDegraded && $0.monitoredDirectoryCount == 1
        }
        XCTAssertEqual(status.identityMismatchCount, 0)
    }

    func testStaleCallbacksCannotInvalidateReplacementOrScheduleStatusChange() async throws {
        let environment = try makeEnvironment(fileNames: ["track.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))

        let controller = try await waitForAttachedController(viewModel: viewModel, environment: environment)
        let rootKey = FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)
        let binding = try XCTUnwrap(controller.binding(forKey: rootKey))
        _ = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) { !$0.isDegraded }
        try await Task.sleep(for: .milliseconds(300))

        let statusBefore = viewModel.directoryMonitoringStatuses[environment.folder.id]
        let revisionBefore = viewModel.filesRevision
        let staleEvent = DirectoryMonitorControllerEvent(
            key: rootKey,
            url: environment.rootURL,
            identity: binding.identity,
            instanceToken: DirectoryMonitorInstanceToken(),
            flags: [.write]
        )
        viewModel.handleDirectoryMonitorEvent(folderID: environment.folder.id, event: staleEvent)
        viewModel.handleDirectoryMonitorEvent(
            folderID: environment.folder.id,
            event: DirectoryMonitorControllerEvent(
                key: rootKey,
                url: environment.rootURL,
                identity: binding.identity,
                instanceToken: DirectoryMonitorInstanceToken(),
                flags: [.rename]
            )
        )
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(viewModel.directoryMonitoringStatuses[environment.folder.id], statusBefore)
        XCTAssertEqual(viewModel.filesRevision, revisionBefore, "a stale callback must not schedule a scan")
        XCTAssertEqual(controller.binding(forKey: rootKey)?.instanceToken, binding.instanceToken)
    }

    func testRemovedNestedDirectoryTerminalEventRescansWithoutDegradingCurrentSet() async throws {
        let environment = try makeEnvironment(fileNames: ["Sub/nested.mp3"], nestedDirectoryNames: ["Sub"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))

        let subURL = environment.rootURL.appendingPathComponent("Sub", isDirectory: true)
        let subKey = FileSystemPathSemantics.key(for: subURL.standardizedFileURL)
        let controller = try await waitForAttachedController(viewModel: viewModel, environment: environment)
        let subBinding = try await waitUntilReturning { controller.binding(forKey: subKey) }
        XCTAssertNotNil(subBinding)

        let movedSubURL = environment.baseURL.appendingPathComponent("SubMoved", isDirectory: true)
        try FileManager.default.moveItem(at: subURL, to: movedSubURL)

        // The terminal event schedules a rescan; the rescan drops the removed
        // directory from the plan and prunes the file, while the monitoring
        // status remains truthful (nothing planned is missing).
        let filePruned = await waitUntil { viewModel.files.isEmpty }
        XCTAssertTrue(filePruned)
        let status = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            $0.totalDirectoryCount == 1 && $0.monitoredDirectoryCount == 1 && !$0.isDegraded
        }
        XCTAssertNil(controller.binding(forKey: subKey))
        XCTAssertNotNil(controller.binding(forKey: FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)))
        XCTAssertEqual(status.identityMismatchCount, 0)
    }

    // MARK: - Unavailable roots and manual refresh

    func testMissingRootPublishesDegradedStatusAndManualRefreshRecovers() async throws {
        let environment = try makeEnvironment(fileNames: ["track.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))
        _ = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) { !$0.isDegraded }

        try FileManager.default.removeItem(at: environment.rootURL)
        viewModel.refreshWatchedFolder(id: environment.folder.id)

        let degraded = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            $0.isDegraded
        }
        XCTAssertEqual(degraded.monitoredDirectoryCount, 0)
        XCTAssertGreaterThanOrEqual(degraded.failedToOpenCount, 1)
        XCTAssertEqual(degraded.identityMismatchCount, 0)
        XCTAssertTrue(degraded.message.contains("be opened"), degraded.message)

        // The folder path reappears and the user explicitly refreshes.
        try FileManager.default.createDirectory(at: environment.rootURL, withIntermediateDirectories: false)
        try Data("recovered".utf8).write(to: environment.rootURL.appendingPathComponent("track.mp3"))
        viewModel.refreshWatchedFolder(id: environment.folder.id)

        let recovered = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            !$0.isDegraded && $0.monitoredDirectoryCount == 1
        }
        XCTAssertEqual(recovered.totalDirectoryCount, 1)
        XCTAssertEqual(recovered.failedToOpenCount, 0)
        let filesRecovered = await waitUntil { viewModel.files.map(\.url.lastPathComponent) == ["track.mp3"] }
        XCTAssertTrue(filesRecovered)
    }

    func testPermissionLossDegradesMonitoringAndRefreshRecoversAfterAccessRestored() async throws {
        let environment = try makeEnvironment(fileNames: ["track.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))
        _ = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) { !$0.isDegraded }

        let originalPermissions: NSNumber? = try FileManager.default
            .attributesOfItem(atPath: environment.rootURL.path)[.posixPermissions] as? NSNumber
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o000))],
            ofItemAtPath: environment.rootURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: originalPermissions ?? NSNumber(value: Int16(0o755))],
                ofItemAtPath: environment.rootURL.path
            )
        }

        viewModel.refreshWatchedFolder(id: environment.folder.id)
        let degraded = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            $0.isDegraded
        }
        XCTAssertGreaterThanOrEqual(
            degraded.scanFailureCount + degraded.failedToOpenCount + degraded.identityMismatchCount,
            1
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: originalPermissions ?? NSNumber(value: Int16(0o755))],
            ofItemAtPath: environment.rootURL.path
        )
        viewModel.refreshWatchedFolder(id: environment.folder.id)
        _ = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) {
            !$0.isDegraded && $0.monitoredDirectoryCount == 1
        }
    }

    func testRemovalStopsControllersAndReappearanceUsesFreshInstances() async throws {
        let environment = try makeEnvironment(fileNames: ["track.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let firstViewModel = environment.makeViewModel(pipeline: pipeline)
        firstViewModel.setSidebarSelection(.watchedFolder(environment.folder.id))
        let firstController = try await waitForAttachedController(
            viewModel: firstViewModel,
            environment: environment
        )
        let rootKey = FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)
        let firstBinding = try XCTUnwrap(firstController.binding(forKey: rootKey))
        _ = try await waitForStatus(viewModel: firstViewModel, folderID: environment.folder.id) { !$0.isDegraded }

        firstViewModel.removeWatchedFolder(id: environment.folder.id)
        XCTAssertTrue(firstController.snapshot().isStopped)
        XCTAssertNil(firstViewModel.directoryMonitoringStatuses[environment.folder.id])
        XCTAssertNil(firstViewModel.directoryMonitorController(for: environment.folder.id))

        // Reappearance in a new session must use a fresh controller/instance.
        environment.folderStore.saveFolders([environment.folder])
        let secondViewModel = environment.makeViewModel(pipeline: pipeline)
        secondViewModel.setSidebarSelection(.watchedFolder(environment.folder.id))
        defer { secondViewModel.removeWatchedFolders(ids: [environment.folder.id]) }
        let secondController = try await waitForAttachedController(
            viewModel: secondViewModel,
            environment: environment
        )
        XCTAssertTrue(secondController !== firstController)
        let secondBinding = try await waitUntilReturning { secondController.binding(forKey: rootKey) }
        let reboundBinding = try XCTUnwrap(secondBinding)
        XCTAssertNotEqual(reboundBinding.instanceToken, firstBinding.instanceToken)
        XCTAssertEqual(
            reboundBinding.identity,
            NativeDirectoryMonitorFileSystem().identity(at: environment.rootURL)
        )
        _ = try await waitForStatus(viewModel: secondViewModel, folderID: environment.folder.id) {
            !$0.isDegraded && $0.monitoredDirectoryCount == 1
        }
    }

    func testCancelledScanDoesNotPublishAfterFolderRemoval() async throws {
        let environment = try makeEnvironment(fileNames: ["track.mp3"])
        defer { environment.cleanup() }
        let pipeline = BlockingMonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))
        _ = try await waitForAttachedController(viewModel: viewModel, environment: environment)

        pipeline.blockNextLoad()
        viewModel.scheduleWatchedFolderRescan(for: environment.folder.id, debounceMilliseconds: 0)
        let blocked = await pipeline.waitUntilBlocked()
        XCTAssertTrue(blocked)

        viewModel.removeWatchedFolder(id: environment.folder.id)
        await pipeline.release()
        _ = await pipeline.waitUntilReturned()

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(viewModel.directoryMonitoringStatuses[environment.folder.id])
        XCTAssertNil(viewModel.directoryMonitorController(for: environment.folder.id))
        XCTAssertTrue(viewModel.files.isEmpty)
    }

    func testUserRequestedRefreshWatchedFoldersUpdatesMonitorsAndFiles() async throws {
        let environment = try makeEnvironment(fileNames: ["first.mp3"])
        defer { environment.cleanup() }
        let pipeline = MonitoringScanPipeline()
        let viewModel = environment.makeViewModel(pipeline: pipeline)
        viewModel.setSidebarSelection(.watchedFolder(environment.folder.id))
        _ = try await waitForStatus(viewModel: viewModel, folderID: environment.folder.id) { !$0.isDegraded }

        try Data("second".utf8).write(to: environment.rootURL.appendingPathComponent("second.mp3"))
        viewModel.refreshWatchedFolders()

        let refreshed = await waitUntil {
            Set(viewModel.files.map(\.url.lastPathComponent)) == ["first.mp3", "second.mp3"]
        }
        XCTAssertTrue(refreshed)
        let controller = try await waitForAttachedController(viewModel: viewModel, environment: environment)
        XCTAssertEqual(
            controller.binding(
                forKey: FileSystemPathSemantics.key(for: environment.rootURL.standardizedFileURL)
            )?.identity,
            NativeDirectoryMonitorFileSystem().identity(at: environment.rootURL)
        )
    }

    // MARK: - Helpers

    private func waitForAttachedController(
        viewModel: AudioViewModel,
        environment: MonitoringEnvironment
    ) async throws -> DirectoryMonitorController {
        let controller: DirectoryMonitorController? = await waitUntilReturning {
            () -> DirectoryMonitorController? in
            guard let controller = viewModel.directoryMonitorController(for: environment.folder.id),
                  !controller.snapshot().bindings.isEmpty else { return nil }
            return controller
        }
        return try XCTUnwrap(controller, "no attached controller")
    }

    private func waitForStatus(
        viewModel: AudioViewModel,
        folderID: UUID,
        _ predicate: (DirectoryMonitoringStatus) -> Bool
    ) async throws -> DirectoryMonitoringStatus {
        let status: DirectoryMonitoringStatus? = await waitUntilReturning {
            () -> DirectoryMonitoringStatus? in
            guard let status = viewModel.directoryMonitoringStatuses[folderID],
                  predicate(status) else { return nil }
            return status
        }
        return try XCTUnwrap(status)
    }

    private func waitUntil(timeout: Duration = .seconds(8), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func waitUntilReturning<T>(
        timeout: Duration = .seconds(8),
        _ condition: () -> T?
    ) async -> T? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = condition() { return value }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func makeEnvironment(
        fileNames: [String],
        nestedDirectoryNames: [String] = []
    ) throws -> MonitoringEnvironment {
        try MonitoringEnvironment(
            fileNames: fileNames,
            nestedDirectoryNames: nestedDirectoryNames
        )
    }
}

// MARK: - Environment

@MainActor
private struct MonitoringEnvironment {
    let baseURL: URL
    let rootURL: URL
    let folder: WatchedFolder
    let folderStore: WatchedFolderStore
    let defaults: UserDefaults
    let suiteName: String

    init(fileNames: [String], nestedDirectoryNames: [String]) throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF4Wiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let rootURL = baseURL.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for directoryName in nestedDirectoryNames {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(directoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for fileName in fileNames {
            let fileURL = rootURL.appendingPathComponent(fileName)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(fileName.utf8).write(to: fileURL)
        }

        let suiteName = "AudioMatorTestsF4Wiring.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let folderStore = WatchedFolderStore(userDefaults: defaults)
        let folder = try folderStore.makeFolder(from: rootURL)
        folderStore.saveFolders([folder])

        self.baseURL = baseURL
        self.rootURL = rootURL
        self.folder = folder
        self.folderStore = folderStore
        self.defaults = defaults
        self.suiteName = suiteName
    }

    func makeViewModel(pipeline: any AudioMetadataPipeline) -> AudioViewModel {
        let journalStore = LocalRenameJournalStore(
            directoryURL: baseURL.appendingPathComponent("RenameJournal-\(UUID().uuidString)", isDirectory: true)
        )
        return AudioViewModel(
            watchedFolderStore: folderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(
                fileURL: baseURL.appendingPathComponent("issues-\(UUID().uuidString).json")
            ),
            conflictPolicyDefaults: defaults,
            renameFileSystem: LocalRenameFileSystem(),
            renameJournalStore: journalStore,
            renameJournalAutoClassification: false
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: baseURL)
    }
}

// MARK: - Test pipelines

/// Returns a display observation with a deliberately synthetic fingerprint so
/// every rescan re-reads the file; `loadCount` therefore counts scan passes.
private nonisolated final class MonitoringScanPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private var loadCountStorage = 0

    var loadCount: Int { lock.withLock { loadCountStorage } }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        lock.withLock { loadCountStorage += 1 }
        return await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url, title: url.lastPathComponent)
        }
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
}

/// Blocks the next metadata load so a scan can be cancelled while in flight.
private nonisolated final class BlockingMonitoringScanPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let condition = NSCondition()
    private var shouldBlockNextLoad = false
    private var isBlocked = false
    private var isReleased = false
    private var isReturned = false

    func blockNextLoad() {
        condition.withLock {
            shouldBlockNextLoad = true
            isBlocked = false
            isReleased = false
            isReturned = false
        }
    }

    func waitUntilBlocked(timeout: Duration = .seconds(8)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition.withLock({ isBlocked }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition.withLock { isBlocked }
    }

    func release() async {
        condition.withLock {
            isReleased = true
            condition.broadcast()
        }
    }

    func waitUntilReturned(timeout: Duration = .seconds(8)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition.withLock({ isReturned }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition.withLock { isReturned }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        let shouldBlock = condition.withLock { () -> Bool in
            if shouldBlockNextLoad {
                shouldBlockNextLoad = false
                return true
            }
            return false
        }
        if shouldBlock {
            condition.withLock {
                isBlocked = true
                condition.broadcast()
                while !isReleased {
                    condition.wait()
                }
                isReturned = true
                condition.broadcast()
            }
        }
        return await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url, title: url.lastPathComponent)
        }
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
}
#endif
