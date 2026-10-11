import AVFoundation
import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Non-gating timings: correctness gates live in the integration and conflict tests.
/// Run this class explicitly to compare the same fixtures/toolchain before and after changes.
nonisolated final class MetadataIOPerformanceTests: XCTestCase {
    @MainActor
    func testLongMP3MetadataIOStageTimings() async throws {
        let bundle = Bundle(for: Self.self)
        let name = "testAudioFile.mp3"
        let source = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: name, withExtension: nil))
        let bytes = try Data(contentsOf: source)
        // Keep the leading ID3 tag once and repeat the fixture's MPEG audio.
        // Remove a trailing ID3v1 tag so it does not appear between audio segments.
        XCTAssertEqual(String(decoding: bytes.prefix(3), as: UTF8.self), "ID3")
        let tagLength = bytes[6..<10].reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
        let audioEnd = bytes.count >= 128 && String(decoding: bytes.suffix(128).prefix(3), as: UTF8.self) == "TAG"
            ? bytes.count - 128 : bytes.count
        let audio = bytes[(10 + tagLength)..<audioEnd]
        XCTAssertFalse(audio.isEmpty)
        var largeFile = Data(bytes.prefix(10 + tagLength))
        while largeFile.count < 32 * 1_024 * 1_024 { largeFile.append(audio) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorLongMP3IO-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("long.mp3")
        try largeFile.write(to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let clock = ContinuousClock()
        let start = clock.now
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let loadTime = start.duration(to: clock.now)
        XCTAssertGreaterThan(file.duration, 0)
        var draft = SingleFileEditModel(from: file)
        draft.title = "Long recording benchmark"
        let saveStart = clock.now
        _ = try MetadataConflictResolver.writeMetadata(
            MetadataEditPayload(draft, comparedTo: file),
            original: try XCTUnwrap(file.metadataConflictBaseline),
            originalFingerprint: try XCTUnwrap(file.fileFingerprint),
            originalVersion: try XCTUnwrap(file.metadataFileVersion),
            policy: .mergeNonConflicting, pipeline: pipeline, url: url
        )
        let saveTime = saveStart.duration(to: clock.now)
        let reloadStart = clock.now
        let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
        let reloadTime = reloadStart.duration(to: clock.now)
        XCTAssertEqual(reloaded.title, draft.title)
        print("Metadata IO long MP3 \(largeFile.count) bytes ms: load=\(milliseconds(loadTime)), resolvedSave=\(milliseconds(saveTime)), reload=\(milliseconds(reloadTime))")
    }

    @MainActor
    func testMetadataIOStageTimings() async throws {
        let bundle = Bundle(for: Self.self)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMetadataIO-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = TagLibAudioMetadataPipeline()
        let clock = ContinuousClock()
        for ext in ["mp3", "m4a", "flac", "aac", "ogg", "wav"] {
            let name = "testAudioFile.\(ext)"
            let source = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: name, withExtension: nil))
            let url = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: url)
            var snapshotTime = Duration.zero
            var avTime = Duration.zero
            var loadTime = Duration.zero
            var saveTime = Duration.zero
            var directSaveTime = Duration.zero
            for index in 0..<8 {
                var start = clock.now
                _ = try pipeline.conflictSnapshot(for: url)
                snapshotTime += start.duration(to: clock.now)
                start = clock.now
                _ = try? await AVURLAsset(url: url).load(.metadata)
                avTime += start.duration(to: clock.now)
                start = clock.now
                let file = try await pipeline.loadAudioFile(at: url, id: UUID())
                loadTime += start.duration(to: clock.now)
                var draft = SingleFileEditModel(from: file)
                draft.title = "Benchmark resolved \(index)"
                start = clock.now
                _ = try MetadataConflictResolver.writeMetadata(
                    MetadataEditPayload(draft, comparedTo: file),
                    original: try XCTUnwrap(file.metadataConflictBaseline),
                    originalFingerprint: try XCTUnwrap(file.fileFingerprint),
                    originalVersion: try XCTUnwrap(file.metadataFileVersion),
                    policy: .mergeNonConflicting, pipeline: pipeline, url: url
                )
                saveTime += start.duration(to: clock.now)
                let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
                XCTAssertEqual(reloaded.title, draft.title)
                draft.title = "Benchmark direct \(index)"
                start = clock.now
                _ = try pipeline.writeMetadata(
                    MetadataEditPayload(draft, comparedTo: reloaded), to: url,
                    expectedVersion: reloaded.metadataFileVersion
                )
                directSaveTime += start.duration(to: clock.now)
            }
            print("Metadata IO \(ext) mean ms: snapshot=\(milliseconds(snapshotTime) / 8), AVMetadata=\(milliseconds(avTime) / 8), load=\(milliseconds(loadTime) / 8), resolvedSave=\(milliseconds(saveTime) / 8), directSave=\(milliseconds(directSaveTime) / 8)")
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
