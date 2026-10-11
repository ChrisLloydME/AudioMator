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
        let files = (0..<13).map { index in
            AudioFileTestFactory.make(
                url: URL(fileURLWithPath: "/synthetic/concurrent/\(index).mp3"),
                title: "Track \(index)", includeDefaultFileFingerprint: false
            )
        }
        let gate = SyntheticReloadGate()
        let pipeline = SyntheticMetadataFlowPipeline(files: files, reloadGate: gate)
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
        let name = "AudioMatorArtworkFlow-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: SyntheticMetadataFlowPipeline(files: files),
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
        for count in [1_000, 4_000] {
            let files = (0..<count).map { index in
                AudioFileTestFactory.make(
                    url: URL(fileURLWithPath: "/synthetic/\(index).mp3"),
                    title: "Track \(index)", artist: "Artist", album: "Album",
                    includeDefaultFileFingerprint: false
                )
            }
            let pipeline = SyntheticMetadataFlowPipeline(files: files)
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
            let deadline = clock.now.advanced(by: .seconds(120))
            while viewModel.metadataSaveProgress != nil, clock.now < deadline {
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
            // Gate work, not wall-clock time on a potentially loaded test runner.
            XCTAssertLessThan(collectionPublications, count / 4)
            XCTAssertLessThan(progressPublications, count / 4)
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
private final class SyntheticMetadataFlowPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var filesByURL: [URL: AudioFile]
    nonisolated(unsafe) private var titlesByURL: [URL: String] = [:]
    nonisolated(unsafe) private var writes = 0
    nonisolated(unsafe) private var loads = 0
    nonisolated(unsafe) private var activeTransactions = 0
    nonisolated(unsafe) private var maximumActive = 0
    private let reloadGate: SyntheticReloadGate?

    init(files: [AudioFile], reloadGate: SyntheticReloadGate? = nil) {
        filesByURL = Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0) })
        self.reloadGate = reloadGate
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
        return await MainActor.run {
            AudioFileTestFactory.make(
                id: previous.id, url: url, title: title ?? previous.title,
                artist: previous.artist, album: previous.album, includeDefaultFileFingerprint: false
            )
        }
    }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: edit)
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
    nonisolated func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?, to url: URL, verifyAfterWrite: Bool, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult { throw CocoaError(.featureUnsupported) }
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
