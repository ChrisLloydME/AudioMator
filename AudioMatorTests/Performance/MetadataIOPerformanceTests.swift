import AVFoundation
import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Non-gating timings: correctness gates live in the integration and conflict tests.
/// Run this class explicitly to compare the same fixtures/toolchain before and after changes.
final class MetadataIOPerformanceTests: XCTestCase {
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
