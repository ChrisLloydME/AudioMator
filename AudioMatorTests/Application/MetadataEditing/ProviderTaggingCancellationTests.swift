import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

@MainActor
final class ProviderTaggingCancellationTests: XCTestCase {
    func testITunesCancellationAfterCommitKeepsActualOutcomeAndAccountsForRemainingFiles() async throws {
        try await checkCancellation(musicBrainz: false)
    }

    func testMusicBrainzCancellationAfterCommitKeepsActualOutcomeAndAccountsForRemainingFiles() async throws {
        try await checkCancellation(musicBrainz: true)
    }

    private func checkCancellation(musicBrainz: Bool) async throws {
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
        let task = Task {
            if musicBrainz {
                await viewModel.applyMusicBrainzTaggingPlan(files.map {
                    MusicBrainzTaggingWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                        values: [.title: "Applied"], expectedFileFingerprint: $0.fileFingerprint)
                })
            } else {
                await viewModel.applyiTunesTaggingPlan(files.map {
                    iTunesTaggingWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                        values: [.title: "Applied"], expectedFileFingerprint: $0.fileFingerprint)
                })
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !pipeline.hasCommitted, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let committed = pipeline.hasCommitted
        task.cancel()
        pipeline.releaseReload()
        await task.value
        XCTAssertTrue(committed, "The test must cancel after a real commit")
        XCTAssertEqual(pipeline.writeCount, 1)
        var expectedFirst = originalMaps[0]
        expectedFirst["TITLE"] = ["Applied"]
        XCTAssertEqual(try base.rawMetadataValueMap(for: files[0].url), expectedFirst)
        XCTAssertEqual(try base.rawMetadataValueMap(for: files[1].url), originalMaps[1])
        XCTAssertNil(viewModel.metadataSaveProgress)
        let entry = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first)
        XCTAssertTrue(entry.summary.contains("1 of 2"), entry.summary)
        XCTAssertEqual(entry.issues.map(\.fileName), ["second.flac"])
        XCTAssertTrue(entry.issues[0].messages.joined().localizedCaseInsensitiveContains("cancel"))
    }
}

private final class PausedProviderReloadPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let base = TagLibAudioMetadataPipeline()
    private let lock = NSLock()
    private var writes = 0
    private var released = false
    nonisolated var hasCommitted: Bool { lock.withLock { writes > 0 } }
    nonisolated var writeCount: Int { lock.withLock { writes } }
    nonisolated func releaseReload() { lock.withLock { released = true } }
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !lock.withLock({ released }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
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
        try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }
    nonisolated func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?, to url: URL, verifyAfterWrite: Bool, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        try base.writeTrackNumberText(trackNumberText, discNumberText: discNumberText, to: url, verifyAfterWrite: verifyAfterWrite, expectedVersion: expectedVersion)
    }
}
