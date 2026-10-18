import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
@MainActor
final class QuickImportCancellationTests: XCTestCase {
    func testRemovingFileRejectsLateReimportOfSameURL() async throws {
        let gate = QuickImportLoadGate()
        let pipeline = DelayedQuickImportMetadataPipeline(gate: gate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorQuickImportRemove-\(UUID().uuidString).mp3")
        let visibleFile = AudioFileTestFactory.make(url: fileURL)

        viewModel.mergeQuickImportFiles([visibleFile])
        viewModel.importQuickFiles(from: [fileURL])
        try await gate.waitUntilStarted()

        viewModel.removeQuickImportFile(id: visibleFile.id)
        await gate.release()
        try await gate.waitUntilReturned()
        try await waitUntil(viewModel.activeQuickImportTaskCount == 0)

        XCTAssertTrue(
            viewModel.files.isEmpty,
            "A late import completion must not undo the user's newer remove action."
        )

        viewModel.importQuickFiles(from: [fileURL])
        try await waitUntil(viewModel.files.count == 1)
        XCTAssertEqual(viewModel.files.first?.url, fileURL)
    }

    func testRemovingFileSuppressesLateFailureFromSameURL() async throws {
        let gate = QuickImportLoadGate()
        let pipeline = DelayedQuickImportMetadataPipeline(gate: gate, shouldFail: true)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorQuickImportRemoveFailure-\(UUID().uuidString).mp3")
        let visibleFile = AudioFileTestFactory.make(url: fileURL)

        viewModel.mergeQuickImportFiles([visibleFile])
        viewModel.importQuickFiles(from: [fileURL])
        try await gate.waitUntilStarted()

        viewModel.removeQuickImportFile(id: visibleFile.id)
        await gate.release()
        try await gate.waitUntilReturned()
        try await waitUntil(viewModel.activeQuickImportTaskCount == 0)

        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertNil(
            viewModel.metadataWriteHUD,
            "An obsolete import failure must not surface after the user removes that URL."
        )
    }

    func testClearCancelsImportAndRejectsLateBatch() async throws {
        let gate = QuickImportLoadGate()
        let pipeline = DelayedQuickImportMetadataPipeline(gate: gate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorQuickImport-\(UUID().uuidString).mp3")

        viewModel.importQuickFiles(from: [fileURL])
        try await gate.waitUntilStarted()

        viewModel.clearQuickImportFiles()
        await gate.release()
        try await gate.waitUntilReturned()
        try await waitUntil(viewModel.activeQuickImportTaskCount == 0)

        XCTAssertTrue(
            viewModel.files.isEmpty,
            "A batch from an import session cleared by the user must not merge later."
        )
    }

    func testRemovingWatchedFolderCancelsInFlightMetadataLoads() async throws {
        let suiteName = "AudioMator.WatchedFolderCancellationTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolderCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("track.mp3")
        XCTAssertTrue(FileManager.default.createFile(atPath: audioURL.path, contents: Data()))
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let folder = try store.makeFolder(from: rootURL)
        store.saveFolders([folder])

        let gate = QuickImportLoadGate()
        let pipeline = DelayedQuickImportMetadataPipeline(gate: gate)
        let viewModel = AudioViewModel(
            watchedFolderStore: store,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: userDefaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: userDefaults
        )

        try await gate.waitUntilStarted()
        viewModel.removeWatchedFolder(id: folder.id)
        await gate.release()
        try await gate.waitUntilReturned()
        let wasCancelled = await gate.wasCancelledWhenReturned()

        XCTAssertTrue(
            wasCancelled,
            "Removing a watched folder must cancel metadata reads owned by its rescan."
        )
    }

    func testQuickImportReportsUnreadableFilesAndKeepsSuccessfulSiblings() async throws {
        let unreadableURL = URL(fileURLWithPath: "/tmp/00-unreadable-import.mp3")
        let readableURL = URL(fileURLWithPath: "/tmp/01-readable-import.mp3")
        let pipeline = PartiallyFailingQuickImportMetadataPipeline(unreadableURL: unreadableURL)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)

        viewModel.importQuickFiles(from: [unreadableURL, readableURL])

        let deadline = Date().addingTimeInterval(2)
        while (viewModel.files.count != 1 || viewModel.metadataWriteHUD == nil), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(viewModel.files.map(\.url), [readableURL])
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .warning)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "File Not Imported")
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("00-unreadable-import.mp3") == true)
        XCTAssertFalse(
            viewModel.metadataWriteHUD?.subtitle.contains("/tmp/") == true,
            "Import feedback should identify the filename without disclosing its full path."
        )
    }

    func testQuickImportRetriesTransientInitialReadFailure() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/transient-first-read-failure.mp3")
        let control = TransientQuickImportReadControl()
        let pipeline = TransientlyFailingQuickImportMetadataPipeline(control: control)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)

        viewModel.importQuickFiles(from: [fileURL])
        try await waitUntil(viewModel.activeQuickImportTaskCount == 0)
        let attemptCount = await control.attemptCount(for: fileURL)

        XCTAssertEqual(viewModel.files.map(\.url), [fileURL])
        XCTAssertEqual(attemptCount, 2)
        XCTAssertNil(viewModel.metadataWriteHUD)
    }

    func testWatchedFolderRefreshRetainsLastKnownFileWhenMetadataReadFails() async throws {
        let suiteName = "AudioMator.WatchedFolderReadFailureTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolderReadFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let firstURL = rootURL.appendingPathComponent("01-first.mp3")
        let secondURL = rootURL.appendingPathComponent("02-second.mp3")
        XCTAssertTrue(FileManager.default.createFile(atPath: firstURL.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondURL.path, contents: Data()))
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let folder = try store.makeFolder(from: rootURL)
        store.saveFolders([folder])
        let pipeline = ControllableWatchedFolderMetadataPipeline()
        let viewModel = AudioViewModel(
            watchedFolderStore: store,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: userDefaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: userDefaults
        )
        viewModel.setSidebarSelection(.watchedFolder(folder.id))

        try await waitUntil(viewModel.files.count == 2)
        await pipeline.setUnreadableURLs([firstURL])
        viewModel.scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        try await waitUntil(
            viewModel.directoryMonitoringStatuses[folder.id]?.metadataReadFailureCount == 1
        )

        XCTAssertEqual(Set(viewModel.files.map(\.url)), Set([firstURL, secondURL]))
        XCTAssertTrue(
            viewModel.directoryMonitoringStatuses[folder.id]?.message.contains("Last known metadata is retained") == true
        )
    }

    func testWatchedFolderRefreshRetainsLastKnownFilesWhenRootScanFails() async throws {
        let suiteName = "AudioMator.WatchedFolderScanFailureTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolderScanFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("track.mp3")
        XCTAssertTrue(FileManager.default.createFile(atPath: audioURL.path, contents: Data()))
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let folder = try store.makeFolder(from: rootURL)
        store.saveFolders([folder])
        let viewModel = AudioViewModel(
            watchedFolderStore: store,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: userDefaults),
            metadataPipeline: ControllableWatchedFolderMetadataPipeline(),
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: userDefaults
        )
        viewModel.setSidebarSelection(.watchedFolder(folder.id))

        try await waitUntil(viewModel.files.count == 1)
        try FileManager.default.removeItem(at: rootURL)
        viewModel.scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        try await waitUntil(
            viewModel.directoryMonitoringStatuses[folder.id]?.scanFailureCount == 1
        )

        XCTAssertEqual(viewModel.files.map(\.url), [audioURL])
        XCTAssertTrue(
            viewModel.directoryMonitoringStatuses[folder.id]?.message.contains("last known file list is retained") == true
        )
    }

    func testWatchedFolderRefreshUsesScannedURLsWhenPipelineReturnsDuplicateURLs() async throws {
        let suiteName = "AudioMator.WatchedFolderDuplicateURLTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolderDuplicateURL-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let firstURL = rootURL.appendingPathComponent("01-first.mp3")
        let secondURL = rootURL.appendingPathComponent("02-second.mp3")
        XCTAssertTrue(FileManager.default.createFile(atPath: firstURL.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondURL.path, contents: Data()))
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let folder = try store.makeFolder(from: rootURL)
        store.saveFolders([folder])
        let viewModel = AudioViewModel(
            watchedFolderStore: store,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: userDefaults),
            metadataPipeline: DuplicateURLWatchedFolderMetadataPipeline(returnedURL: firstURL),
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: userDefaults
        )
        viewModel.setSidebarSelection(.watchedFolder(folder.id))

        try await waitUntil(viewModel.files.count == 2)

        XCTAssertEqual(Set(viewModel.files.map(\.url)), Set([firstURL, secondURL]))
    }

    func testFailedFirstImportDoesNotBlockProgressivePublication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProgressiveImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = (0..<50).map { root.appendingPathComponent(String(format: "%02d.mp3", $0)) }
        for url in urls { try Data().write(to: url) }
        let gate = QuickImportLoadGate()
        let pipeline = PartiallyFailingQuickImportMetadataPipeline(unreadableURL: urls[0], heldURL: urls[49], gate: gate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.importQuickFiles(from: urls)
        try await gate.waitUntilStarted()
        try await waitUntil(viewModel.files.count >= 24)
        XCTAssertEqual(viewModel.activeQuickImportTaskCount, 1, "The final load is still gated")
        XCTAssertLessThan(viewModel.files.count, 49)
        await gate.release()
        try await waitUntil(viewModel.activeQuickImportTaskCount == 0)
        XCTAssertEqual(viewModel.files.count, 49)
        XCTAssertFalse(viewModel.files.contains { $0.url == urls[0] })
    }

    private func waitUntil(
        _ condition: @autoclosure @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }
}

private enum QuickImportGateTimeout: Error {
    case didNotStart
    case didNotReturn
}

private actor QuickImportLoadGate {
    private var didStart = false
    private var didRelease = false
    private var didReturn = false
    private var wasCancelledOnReturn = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendLoad() async {
        didStart = true

        guard !didRelease else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !didStart, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard didStart else { throw QuickImportGateTimeout.didNotStart }
    }

    func release() {
        didRelease = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    func markReturned(wasCancelled: Bool) {
        didReturn = true
        wasCancelledOnReturn = wasCancelled
    }

    func waitUntilReturned() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !didReturn, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard didReturn else { throw QuickImportGateTimeout.didNotReturn }
    }

    func wasCancelledWhenReturned() -> Bool {
        wasCancelledOnReturn
    }
}

private final class DelayedQuickImportMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let gate: QuickImportLoadGate
    private let shouldFail: Bool

    init(gate: QuickImportLoadGate, shouldFail: Bool = false) {
        self.gate = gate
        self.shouldFail = shouldFail
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await gate.suspendLoad()
        if shouldFail {
            await gate.markReturned(wasCancelled: Task.isCancelled)
            throw CocoaError(.fileReadNoPermission)
        }
        let file = await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
        await gate.markReturned(wasCancelled: Task.isCancelled)
        return file
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
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

private final class PartiallyFailingQuickImportMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let unreadableURL: URL
    private let heldURL: URL?
    private let gate: QuickImportLoadGate?

    init(unreadableURL: URL, heldURL: URL? = nil, gate: QuickImportLoadGate? = nil) {
        self.unreadableURL = unreadableURL
        self.heldURL = heldURL
        self.gate = gate
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if url == heldURL, let gate { await gate.suspendLoad() }
        if url == unreadableURL {
            throw CocoaError(.fileReadNoPermission)
        }
        return await AudioFileTestFactory.make(id: id, url: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
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

private actor TransientQuickImportReadControl {
    private var attemptCountsByURL: [URL: Int] = [:]

    func recordAttempt(for url: URL) -> Int {
        attemptCountsByURL[url, default: 0] += 1
        return attemptCountsByURL[url, default: 0]
    }

    func attemptCount(for url: URL) -> Int {
        attemptCountsByURL[url, default: 0]
    }
}

private final class TransientlyFailingQuickImportMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let control: TransientQuickImportReadControl

    init(control: TransientQuickImportReadControl) {
        self.control = control
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        let attempt = await control.recordAttempt(for: url)
        guard attempt > 1 else {
            throw CocoaError(.fileReadUnknown)
        }
        return await AudioFileTestFactory.make(id: id, url: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
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

private actor WatchedFolderReadControl {
    private var unreadableURLs: Set<URL> = []

    func setUnreadableURLs(_ urls: Set<URL>) {
        unreadableURLs = urls
    }

    func shouldFail(_ url: URL) -> Bool {
        unreadableURLs.contains(url)
    }
}

private final class ControllableWatchedFolderMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let control = WatchedFolderReadControl()

    func setUnreadableURLs(_ urls: Set<URL>) async {
        await control.setUnreadableURLs(urls)
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if await control.shouldFail(url) {
            throw CocoaError(.fileReadNoPermission)
        }
        return await AudioFileTestFactory.make(id: id, url: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
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

private final class DuplicateURLWatchedFolderMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let returnedURL: URL

    init(returnedURL: URL) {
        self.returnedURL = returnedURL
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: returnedURL)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
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
#endif
