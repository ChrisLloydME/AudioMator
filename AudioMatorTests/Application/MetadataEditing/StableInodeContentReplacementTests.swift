import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class StableInodeContentReplacementTests: XCTestCase {
    @MainActor
    func testAutomaticPoliciesMustNotWriteAfterDifferentPCMPayloadReplacesAudioInPlace() async throws {
        for policy in [MetadataConflictPolicy.mergeNonConflicting, .preferUserChanges, .preferDiskChanges] {
            try await checkPayloadReplacement(policy: policy)
        }
    }

    @MainActor
    func testManualReloadPolicyRefusesDifferentPCMPayloadReplacement() async throws {
        try await checkPayloadReplacement(policy: .requireReload)
    }

    @MainActor
    private func checkPayloadReplacement(policy: MetadataConflictPolicy) async throws {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile.wav", withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.wav", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("replacement.wav")
        try FileManager.default.copyItem(at: source, to: url)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        let pipeline = TagLibAudioMetadataPipeline()
        let baseline = try await pipeline.loadAudioFile(at: url, id: UUID())
        let originalFingerprint = try XCTUnwrap(baseline.fileFingerprint)
        let originalMetadata = try XCTUnwrap(baseline.metadataConflictBaseline)
        let originalVersion = try XCTUnwrap(baseline.metadataFileVersion)
        let originalBytes = try Data(contentsOf: url)
        var replacement = originalBytes
        XCTAssertEqual(String(decoding: replacement.prefix(4), as: UTF8.self), "RIFF")
        var cursor = 12
        var audioRange: Range<Int>?
        while cursor + 8 <= replacement.count {
            let size = (0..<4).reduce(0) { $0 | (Int(replacement[cursor + 4 + $1]) << (8 * $1)) }
            guard size <= replacement.count - cursor - 8 else { break }
            if String(decoding: replacement[cursor..<(cursor + 4)], as: UTF8.self) == "data" {
                audioRange = (cursor + 8)..<(cursor + 8 + size)
                break
            }
            cursor += 8 + size + size % 2
        }
        let range = try XCTUnwrap(audioRange)
        XCTAssertGreaterThan(range.count, 0)
        replacement.replaceSubrange(range, with: repeatElement(UInt8(0x66), count: range.count))
        XCTAssertNotEqual(replacement, originalBytes, "This must replace audio samples, not tags or identical bytes")
        let handle = try FileHandle(forUpdating: url)
        try handle.write(contentsOf: replacement)
        try handle.synchronize()
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        XCTAssertEqual(try AudioFileFingerprint.capture(at: url), originalFingerprint,
                       "Same path, device, inode, size and mtime are required for this reproduction")
        var draft = SingleFileEditModel(from: baseline)
        draft.title = "Stale draft applied to different PCM audio"
        XCTAssertNotEqual(draft.title, baseline.title)
        XCTAssertThrowsError(try MetadataConflictResolver.writeMetadata(
            MetadataEditPayload(draft, comparedTo: baseline),
            original: originalMetadata,
            originalFingerprint: originalFingerprint,
            originalVersion: originalVersion,
            policy: policy, pipeline: pipeline, url: url))
        XCTAssertEqual(try Data(contentsOf: url), replacement, "Rejected writes must leave replacement bytes intact")
    }
}
