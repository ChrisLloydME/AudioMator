import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class FileMutationSerializationTests: XCTestCase {
    func testMetadataMutationHelpersSerializeNormalizedURLAliases() async throws {
        let pipeline = OverlapDetectingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMutationSerialization", isDirectory: true)
        let canonicalURL = directoryURL.appendingPathComponent("track.mp3")
        let aliasURL = directoryURL
            .appendingPathComponent("unused", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("track.mp3")
        let file = AudioFileTestFactory.make(url: canonicalURL)
        let payload = MetadataEditPayload(SingleFileEditModel(from: file))

        async let metadataWrite = viewModel.writeMetadataOffMainActor(payload, to: canonicalURL)
        async let rawMapWrite = viewModel.writeRawMetadataPropertyMapOffMainActor([:], to: aliasURL)
        _ = try await (metadataWrite, rawMapWrite)

        XCTAssertEqual(
            pipeline.maximumConcurrentMutations,
            1,
            "Mutations for aliases of the same normalized file URL must not overlap."
        )
    }

    func testMetadataWriteEraseAndTrackRenumberShareOneFileReservation() async throws {
        let pipeline = OverlapDetectingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        let fileID = UUID()
        let fileURL = URL(fileURLWithPath: "/tmp/AudioMatorSharedMutation.mp3")
        let file = AudioFileTestFactory.make(
            id: fileID,
            url: fileURL,
            includeDefaultFileFingerprint: false
        )
        let payload = MetadataEditPayload(SingleFileEditModel(from: file))
        viewModel.mergeQuickImportFiles([file])

        async let metadataWrite = viewModel.writeMetadataOffMainActor(payload, to: fileURL)
        async let metadataErase = viewModel.eraseAllMetadataOffMainActor(at: fileURL)
        async let renumberResult = viewModel.renumberTrackNumbers(
            orderedIDs: [fileID],
            selectedIDs: [],
            options: TrackRenumberOptions(
                direction: .ascending,
                startNumber: 1,
                padWithZeros: false
            )
        )

        _ = try await (metadataWrite, metadataErase)
        _ = await renumberResult

        XCTAssertEqual(
            pipeline.maximumConcurrentMutations,
            1,
            "Write, erase, and renumber must serialize mutations for the same file URL."
        )
    }
}

private final class OverlapDetectingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let condition = NSCondition()
    private var activeMutations = 0
    private var recordedMaximumConcurrentMutations = 0

    var maximumConcurrentMutations: Int {
        condition.withLock { recordedMaximumConcurrentMutations }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        throw TestError.unexpectedRead
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        [:]
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        recordMutationOverlap()
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        recordMutationOverlap()
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        recordMutationOverlap()
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        recordMutationOverlap()
        return AudioMetadataWriteResult(warnings: [])
    }

    private func recordMutationOverlap() {
        condition.lock()
        activeMutations += 1
        recordedMaximumConcurrentMutations = max(
            recordedMaximumConcurrentMutations,
            activeMutations
        )
        condition.broadcast()

        let deadline = Date().addingTimeInterval(0.2)
        while activeMutations < 2, Date() < deadline {
            condition.wait(until: deadline)
        }

        activeMutations -= 1
        condition.broadcast()
        condition.unlock()
    }

    private enum TestError: Error {
        case unexpectedRead
    }
}
#endif
