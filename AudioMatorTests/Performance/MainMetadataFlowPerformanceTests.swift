import AppKit
import Combine
import Foundation
import SwiftUI
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class MainMetadataFlowPerformanceTests: XCTestCase {
    @MainActor
    func testInspectorBatchOverlapsFourTransactionsAndBoundsQueuedWork() async throws {
        let (version, versionFixture) = try makeSyntheticVersion()
        defer { MetadataTestTokens.removeFixtureCopy(at: versionFixture) }
        let (files, directory) = try makeObservedSyntheticFiles(
            count: 13, prefix: "AudioMatorConcurrent", version: version
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = SyntheticReloadGate()
        let pipeline = SyntheticMetadataFlowPipeline(files: files, version: version, reloadGate: gate)
        let name = "AudioMatorConcurrentFlow-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")),
            conflictPolicyDefaults: defaults
        )
        viewModel.mergeQuickImportFiles(files)
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
        viewModel.multiEdit?.setText("Concurrent title", for: .title)
        viewModel.saveInspectorEdits()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while pipeline.writeCount < 4, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        // All four reservations remain occupied through their blocked readbacks.
        // A serial implementation stalls at one; unbounded work writes all 13.
        XCTAssertEqual(pipeline.writeCount, 4)
        XCTAssertEqual(pipeline.maximumActiveTransactions, 4)
        await gate.release()
        while viewModel.metadataSaveProgress != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertEqual(pipeline.writeCount, files.count)
        XCTAssertEqual(pipeline.loadCount, files.count)
        XCTAssertEqual(pipeline.maximumActiveTransactions, 4)
        XCTAssertTrue(viewModel.files.allSatisfy { $0.title == "Concurrent title" })
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testLargeArtworkRangeReselectionTimings() throws {
        let count = 64
        let bytesPerCover = 2 * 1_024 * 1_024
        let files = (0..<count).map { index in
            AudioFileTestFactory.make(
                url: URL(fileURLWithPath: "/synthetic/covers/\(index).mp3"), title: "Track \(index)",
                artworkData: Data(repeating: 0x42, count: bytesPerCover), includeDefaultFileFingerprint: false
            )
        }
        let (version, versionFixture) = try makeSyntheticVersion()
        defer { MetadataTestTokens.removeFixtureCopy(at: versionFixture) }
        let name = "AudioMatorArtworkFlow-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: SyntheticMetadataFlowPipeline(files: files, version: version),
            saveIssueLogStore: SaveIssueLogStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")),
            conflictPolicyDefaults: defaults
        )
        viewModel.mergeQuickImportFiles(files)
        let clock = ContinuousClock()
        var start = clock.now
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
        let cold = start.duration(to: clock.now)
        start = clock.now
        viewModel.setSelectedAudioIDs(Set(files.dropFirst().map(\.id)))
        let changedAnchor = start.duration(to: clock.now)
        start = clock.now
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
        let restored = start.duration(to: clock.now)
        guard case .shared = viewModel.multiEdit?.initialArtworkState else { return XCTFail("Expected identical full covers") }
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
        print("Main artwork flow \(count) independent \(bytesPerCover)-byte covers: cold=\(milliseconds(cold)) ms, changed anchor=\(milliseconds(changedAnchor)) ms, restored=\(milliseconds(restored)) ms")
    }

    @MainActor
    func testSyntheticLibrarySelectionAndBatchSaveFlow() async throws {
        let (version, versionFixture) = try makeSyntheticVersion()
        defer { MetadataTestTokens.removeFixtureCopy(at: versionFixture) }
        for count in [1_000, 4_000] {
            let (files, directory) = try makeObservedSyntheticFiles(
                count: count, prefix: "AudioMatorFlow-\(count)",
                version: version, artist: "Artist", album: "Album"
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let pipeline = SyntheticMetadataFlowPipeline(files: files, version: version)
            let defaultsName = "AudioMatorFlow-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
            defer { defaults.removePersistentDomain(forName: defaultsName) }
            let viewModel = AudioViewModel(
                watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
                fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
                metadataPipeline: pipeline,
                saveIssueLogStore: SaveIssueLogStore(fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("AudioMatorFlow-\(UUID().uuidString).json")),
                conflictPolicyDefaults: defaults
            )
            viewModel.mergeQuickImportFiles(files)
            let parent = makeTable(viewModel: viewModel, files: files)
            let coordinator = parent.makeCoordinator()
            let scrollView = coordinator.makeScrollView()
            coordinator.update(parent: parent, scrollView: scrollView)
            let table = try XCTUnwrap(scrollView.documentView as? NSTableView)
            var selectionMilliseconds: [Double] = []
            let clock = ContinuousClock()
            for index in 0..<100 {
                let start = clock.now
                XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
                XCTAssertEqual(viewModel.selectedFiles.first?.id, files[index].id)
                selectionMilliseconds.append(milliseconds(start.duration(to: clock.now)))
            }
            viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
            viewModel.multiEdit?.setText("Saved batch title", for: .title)
            var collectionPublications = 0
            var progressPublications = 0
            let subscription = viewModel.$files.dropFirst().sink { files in
                collectionPublications += 1
                coordinator.update(parent: self.makeTable(viewModel: viewModel, files: files), scrollView: scrollView)
            }
            let progressSubscription = viewModel.$metadataSaveProgress.dropFirst().sink { progress in
                progressPublications += 1
                // Model a real window update: progress also reevaluates the
                // table and Inspector even when the file collection is unchanged.
                if progress != nil {
                    let parent = self.makeTable(viewModel: viewModel, files: viewModel.files, revision: viewModel.filesRevision)
                    coordinator.update(parent: parent, scrollView: scrollView)
                    _ = MergedAudioFile(files: viewModel.selectedFiles)
                }
            }
            let saveStart = clock.now
            viewModel.saveInspectorEdits()
            let stallTimeout: Duration = .seconds(120)
            var lastProgressTime = clock.now
            var lastCompletedCount = 0
            while let progress = viewModel.metadataSaveProgress {
                if progress.completedUnitCount > lastCompletedCount {
                    lastCompletedCount = progress.completedUnitCount
                    lastProgressTime = clock.now
                }
                guard lastProgressTime.duration(to: clock.now) < stallTimeout else {
                    XCTFail("Batch save stalled at \(lastCompletedCount) of \(count) files for \(stallTimeout).")
                    return
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            let saveTime = saveStart.duration(to: clock.now)
            withExtendedLifetime(subscription) {}
            withExtendedLifetime(progressSubscription) {}
            XCTAssertNil(viewModel.metadataSaveProgress)
            XCTAssertEqual(pipeline.writeCount, count)
            XCTAssertEqual(pipeline.loadCount, count)
            XCTAssertTrue(viewModel.files.allSatisfy { $0.title == "Saved batch title" })
            XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
            XCTAssertEqual(viewModel.selectedAudioIDs, Set(files.map(\.id)))
            XCTAssertLessThan(collectionPublications, count / 4)
            // Intermediate progress is throttled to one update per 100 ms.
            // Start, last completion, finishing and clear can publish immediately.
            let progressPublicationLimit = Int(milliseconds(saveTime) / 100) + 4
            XCTAssertLessThanOrEqual(progressPublications, progressPublicationLimit)
            let median = selectionMilliseconds.sorted()[selectionMilliseconds.count / 2]
            print("Main metadata flow \(count) files: selection median=\(median) ms, save=\(milliseconds(saveTime)) ms, collection publications=\(collectionPublications), progress publications=\(progressPublications)")
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    @MainActor
    private func makeTable(viewModel: AudioViewModel, files: [AudioFile], revision: UUID = UUID()) -> MiddleListTable {
        MiddleListTable(
            files: files, filesRevision: revision,
            selection: Binding(get: { viewModel.selectedAudioIDs }, set: { viewModel.setSelectedAudioIDs($0) }),
            visibleColumns: .constant([.title, .artist, .album]),
            customOrder: .constant([]), middleListSort: .constant(nil),
            onOpenSelectedFiles: {}, onRevealSelectedFilesInFinder: {},
            onCopySelectedFilePaths: {}, onCopySelectedFileNames: {},
            onFindSelectedFileInMusicBrainz: {}, onRequestCreateMuseAmpIDs: {}, onRequestEraseAllTags: {},
            onReloadSelectedFiles: {}, isFileReloadEnabled: true,
            isMuseAmpSupportEnabled: false, isMuseAmpIDCreationEnabled: true
        )
    }
}

/// Exercises the real reservation, write/reload executor and inspector orchestration
/// while removing disk latency. It cannot contact the network or change user files.
private func makeSyntheticVersion() throws -> (MetadataFileVersion, URL) {
    let fixture = try MetadataTestTokens.makeFixtureCopy()
    return (try MetadataTestTokens.mintedVersion(at: fixture), fixture)
}

private func makeObservedSyntheticFiles(
    count: Int,
    prefix: String,
    version: MetadataFileVersion,
    titlePrefix: String = "Track",
    artist: String = "",
    album: String = ""
) throws -> ([AudioFile], URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var files: [AudioFile] = []
    files.reserveCapacity(count)
    for index in 0..<count {
        let url = directory.appendingPathComponent("\(index).mp3")
        try Data().write(to: url)
        files.append(
            AudioFileTestFactory.makeObserved(
                url: url,
                title: "\(titlePrefix) \(index)",
                artist: artist,
                album: album,
                fileFingerprint: try AudioFileFingerprint.capture(at: url),
                metadataFileVersion: version
            )
        )
    }
    return (files, directory)
}

private final class SyntheticMetadataFlowPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private let version: MetadataFileVersion
    nonisolated(unsafe) private var filesByURL: [URL: AudioFile]
    nonisolated(unsafe) private var titlesByURL: [URL: String] = [:]
    nonisolated(unsafe) private var writes = 0
    nonisolated(unsafe) private var loads = 0
    nonisolated(unsafe) private var activeTransactions = 0
    nonisolated(unsafe) private var maximumActive = 0
    private let reloadGate: SyntheticReloadGate?

    init(files: [AudioFile], version: MetadataFileVersion, reloadGate: SyntheticReloadGate? = nil) {
        filesByURL = Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0) })
        self.version = version
        self.reloadGate = reloadGate
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion { version }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try TagLibAudioMetadataPipeline().projectMetadataWrite(intent, fileExtension: fileExtension)
    }
    nonisolated var maximumActiveTransactions: Int { lock.withLock { maximumActive } }
    nonisolated var writeCount: Int { lock.withLock { writes } }
    nonisolated var loadCount: Int { lock.withLock { loads } }
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        let (previous, title) = try lock.withLock {
            loads += 1
            guard let file = filesByURL[url] else { throw CocoaError(.fileNoSuchFile) }
            return (file, titlesByURL[url])
        }
        if let reloadGate { await reloadGate.wait() }
        defer { lock.withLock { activeTransactions -= 1 } }
        let fileVersion = version
        return await MainActor.run {
            AudioFileTestFactory.makeObserved(
                id: previous.id,
                url: url,
                title: title ?? previous.title,
                artist: previous.artist,
                album: previous.album,
                fileFingerprint: previous.fileFingerprint ?? AudioFileTestFactory.fingerprint(for: url),
                metadataFileVersion: fileVersion
            )
        }
    }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        let patch = try TagLibAudioMetadataPipeline.metadataPatchForWrite(from: edit)
        return try lock.withLock {
            guard filesByURL[url] != nil else { throw CocoaError(.fileNoSuchFile) }
            writes += 1
            activeTransactions += 1
            maximumActive = max(maximumActive, activeTransactions)
            if case .text(let title) = patch.fields[.title] { titlesByURL[url] = title }
            return AudioMetadataWriteResult(warnings: [])
        }
    }
    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { throw CocoaError(.featureUnsupported) }
    nonisolated func writeRawMetadataPatch(_ patch: RawMetadataPatch, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult { throw CocoaError(.featureUnsupported) }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult { throw CocoaError(.featureUnsupported) }
}

private actor SyntheticReloadGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
