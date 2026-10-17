import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class WatchedFolderRefreshOrderingTests: XCTestCase {
    func testRescanCannotReplaceNewerMutationSnapshot() async throws {
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let rootURL = applicationSupport
            .appendingPathComponent("AudioMatorWatchedOrdering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("track.mp3")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))

        let suiteName = "AudioMatorWatchedOrdering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = WatchedFolderStore(userDefaults: defaults)
        let folder = try folderStore.makeFolder(from: rootURL)
        folderStore.saveFolders([folder])

        let pipeline = GatedWatchedFolderPipeline()
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorWatchedOrdering-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let viewModel = AudioViewModel(
            watchedFolderStore: folderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: logURL),
            conflictPolicyDefaults: defaults
        )
        viewModel.setSidebarSelection(.watchedFolder(folder.id))
        viewModel.scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)

        let didLoadInitial = try await waitUntil {
            viewModel.files.count == 1 && viewModel.files.first?.title == "Old"
        }
        let directoryContents = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
        XCTAssertTrue(
            didLoadInitial,
            "watchedFolders=\(viewModel.watchedFolders.count) files=\(viewModel.files.count) mode=\(viewModel.currentFileSourceMode) root=\(rootURL.path) resolved=\(viewModel.watchedFolders.first?.url.path ?? "nil") contents=\(directoryContents) readable=\(AudioFormatSupport.readableExtensions.contains("mp3")) status=\(String(describing: viewModel.directoryMonitoringStatuses))"
        )
        let old = try XCTUnwrap(viewModel.files.first)

        pipeline.prepareToBlockNextLoad()
        viewModel.scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)
        let didBlock = await pipeline.waitUntilBlocked()
        XCTAssertTrue(didBlock)

        let refreshed = AudioFileTestFactory.make(
            id: old.id,
            url: old.url,
            title: "New",
            fileFingerprint: old.fileFingerprint
        )
        XCTAssertTrue(viewModel.replaceLoadedFile(
            refreshed,
            refreshGeneration: viewModel.makeFileModelRefreshGeneration()
        ))
        pipeline.setCurrentTitle("New")
        await pipeline.release()
        let didReturn = await pipeline.waitUntilReturned()
        XCTAssertTrue(didReturn)

        // The aborted rescan may schedule a short retry; allow it to run and
        // confirm the newer mutation snapshot is still authoritative.
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(viewModel.files.first?.title, "New")
        XCTAssertEqual(viewModel.files.first?.id, old.id)
    }

    func testRescanReusesUnchangedFilesAndReloadsOnlyChangedOnes() async throws {
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let rootURL = applicationSupport
            .appendingPathComponent("AudioMatorWatchedReuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstURL = rootURL.appendingPathComponent("a.mp3")
        let secondURL = rootURL.appendingPathComponent("b.mp3")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)

        let suiteName = "AudioMatorWatchedReuse.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = WatchedFolderStore(userDefaults: defaults)
        let folder = try folderStore.makeFolder(from: rootURL)
        folderStore.saveFolders([folder])

        let pipeline = CountingWatchedFolderPipeline()
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorWatchedReuse-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let viewModel = AudioViewModel(
            watchedFolderStore: folderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: logURL),
            conflictPolicyDefaults: defaults
        )
        viewModel.setSidebarSelection(.watchedFolder(folder.id))

        let didLoadInitial = try await waitUntil { viewModel.files.count == 2 }
        XCTAssertTrue(didLoadInitial)
        XCTAssertEqual(pipeline.loadCount, 2)

        try Data("second changed".utf8).write(to: secondURL, options: .atomic)
        viewModel.scheduleWatchedFolderRescan(for: folder.id, debounceMilliseconds: 0)

        let didReload = try await waitUntil { pipeline.loadCount == 3 }
        XCTAssertTrue(didReload)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(pipeline.loadCount, 3, "Only the changed file should be fully reloaded")
        XCTAssertEqual(viewModel.files.map(\.url.lastPathComponent).sorted(), ["a.mp3", "b.mp3"])
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private final class CountingWatchedFolderPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedLoadCount = 0

    var loadCount: Int { lock.withLock { recordedLoadCount } }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        lock.withLock { recordedLoadCount += 1 }
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let version = try TagLibMetadataManager.fileVersion(at: url)
        return await MainActor.run {
            AudioFileTestFactory.make(
                id: id,
                url: url,
                title: url.lastPathComponent,
                fileFingerprint: fingerprint,
                metadataFileVersion: version
            )
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
    nonisolated func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?, to url: URL, verifyAfterWrite: Bool, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }
}

private final class GatedWatchedFolderPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let condition = NSCondition()
    private var loadCount = 0
    private var shouldBlockNextLoad = false
    private var isBlocked = false
    private var isReleased = false
    private var returned = false
    private var currentTitle = "Old"

    func prepareToBlockNextLoad() {
        condition.withLock {
            shouldBlockNextLoad = true
            isBlocked = false
            isReleased = false
            returned = false
        }
    }

    func setCurrentTitle(_ title: String) {
        condition.withLock { currentTitle = title }
    }

    func waitUntilBlocked(timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
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

    func waitUntilReturned(timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition.withLock({ returned }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition.withLock { returned }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        let shouldBlock = condition.withLock { () -> Bool in
            loadCount += 1
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
                returned = true
                condition.broadcast()
            }
            return await MainActor.run {
                AudioFileTestFactory.make(id: id, url: url, title: "Old")
            }
        }
        let title = condition.withLock { currentTitle }
        return await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url, title: title)
        }
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
#endif
