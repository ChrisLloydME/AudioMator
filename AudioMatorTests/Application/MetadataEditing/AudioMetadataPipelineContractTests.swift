import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

final class AudioMetadataPipelineContractTests: XCTestCase {
    func testTagLibAdapterTreatsPostCommitDurabilityUncertaintyAsCommitted() throws {
        let result = try TagLibAudioMetadataPipeline.interpretingWrite {
            throw TagLibManagerError.committedButDurabilityUncertain("Injected directory sync failure")
        }

        XCTAssertEqual(
            result.commitStatus,
            .durabilityUncertain("Injected directory sync failure")
        )
        XCTAssertTrue(result.warnings.isEmpty)
    }

    @MainActor
    func testMultiFileArtworkComparisonUsesCompletePayload() {
        var firstBytes = Data(repeating: 0x11, count: 256)
        var secondBytes = firstBytes
        firstBytes[128] = 0x22
        secondBytes[128] = 0x33

        let model = MultiFileEditModel(files: [
            AudioFileTestFactory.make(artworkData: firstBytes),
            AudioFileTestFactory.make(artworkData: secondBytes)
        ])

        guard case .mixed = model.initialArtworkState else {
            return XCTFail("Same-length artwork with matching edges but different middle bytes must be mixed")
        }
    }

    @MainActor
    func testRestrictedFormatFieldsAreRejectedBeforeMutation() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/restricted.xm"),
            title: "Allowed title",
            artist: "Original artist"
        )
        var edit = SingleFileEditModel(from: file)
        edit.artist = "Unsupported artist change"
        let payload = MetadataEditPayload(edit, comparedTo: file)

        XCTAssertEqual(
            unsupportedMetadataWriteFields(in: payload, forFileExtension: "xm"),
            [.artist]
        )
    }

    func testWholeValueMapConvenienceBuildsExactDeltaAndForwardsVersion() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tmp")
        try Data("versioned fixture".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let expectedVersion = try TagLibMetadataManager.fileVersion(at: fileURL)
        let pipeline = RecordingPrecisePipeline(initialValueMap: [
            "ARTIST": ["Before", "Second"],
            "REMOVE-ME": ["old"]
        ])
        let desiredValueMap = [
            "ARTIST": ["A; B", "duplicate", "duplicate", "  spaced  "],
            "TITLE": ["New Title"]
        ]

        _ = try pipeline.writeRawMetadataValueMap(
            desiredValueMap,
            to: fileURL,
            expectedVersion: expectedVersion
        )

        let invocation = try XCTUnwrap(pipeline.recordedInvocation)
        XCTAssertEqual(invocation.patch.valuesToSet, desiredValueMap)
        XCTAssertEqual(invocation.patch.removingKeys, ["REMOVE-ME"])
        XCTAssertEqual(invocation.expectedVersion, expectedVersion)
    }
}

private final class RecordingPrecisePipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct Invocation {
        let patch: RawMetadataPatch
        let expectedVersion: MetadataFileVersion?
    }

    private let initialValueMap: RawMetadataValueMap
    private let lock = NSLock()
    nonisolated(unsafe) private var invocation: Invocation?

    init(initialValueMap: RawMetadataValueMap) {
        self.initialValueMap = initialValueMap
    }

    var recordedInvocation: Invocation? {
        lock.withLock { invocation }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        throw CocoaError(.featureUnsupported)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        initialValueMap
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            invocation = Invocation(patch: patch, expectedVersion: expectedVersion)
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        throw CocoaError(.featureUnsupported)
    }
}
