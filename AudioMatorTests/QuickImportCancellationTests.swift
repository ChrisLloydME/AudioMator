import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class QuickImportCancellationTests: XCTestCase {
    func testClearCancelsImportAndRejectsLateBatch() async throws {
        let gate = QuickImportLoadGate()
        let pipeline = DelayedQuickImportMetadataPipeline(gate: gate)
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorQuickImport-\(UUID().uuidString).mp3")

        viewModel.importQuickFiles(from: [fileURL])
        await gate.waitUntilStarted()

        viewModel.clearQuickImportFiles()
        await gate.release()
        await gate.waitUntilReturned()
        try await Task.sleep(for: .milliseconds(150))

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
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore()
        )

        await gate.waitUntilStarted()
        viewModel.removeWatchedFolder(id: folder.id)
        await gate.release()
        await gate.waitUntilReturned()
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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)

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
}

private actor QuickImportLoadGate {
    private var didStart = false
    private var didRelease = false
    private var didReturn = false
    private var wasCancelledOnReturn = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var returnWaiters: [CheckedContinuation<Void, Never>] = []

    func suspendLoad() async {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        guard !didRelease else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        didRelease = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    func markReturned(wasCancelled: Bool) {
        didReturn = true
        wasCancelledOnReturn = wasCancelled
        returnWaiters.forEach { $0.resume() }
        returnWaiters.removeAll()
    }

    func waitUntilReturned() async {
        guard !didReturn else { return }
        await withCheckedContinuation { returnWaiters.append($0) }
    }

    func wasCancelledWhenReturned() -> Bool {
        wasCancelledOnReturn
    }
}

private final class DelayedQuickImportMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let gate: QuickImportLoadGate

    init(gate: QuickImportLoadGate) {
        self.gate = gate
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await gate.suspendLoad()
        let file = await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
        await gate.markReturned(wasCancelled: Task.isCancelled)
        return file
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}

private final class PartiallyFailingQuickImportMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let unreadableURL: URL

    init(unreadableURL: URL) {
        self.unreadableURL = unreadableURL
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if url == unreadableURL {
            throw CocoaError(.fileReadNoPermission)
        }
        return await AudioFileTestFactory.make(id: id, url: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
#endif
