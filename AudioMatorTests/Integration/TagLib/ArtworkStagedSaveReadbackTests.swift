import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Real-fixture proof for the AM-18 staging boundary: a downloaded artwork image
/// that was staged through the guarded handoff is byte-identical on disk before
/// the separate Inspector Save, and the save then persists exactly those PNG
/// bytes while unrelated fields survive. Covers the supported artwork writers
/// (MP3, M4A, FLAC).
nonisolated final class ArtworkStagedSaveReadbackTests: XCTestCase {
    private static let tinyPNGData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
    )!

    @MainActor
    private var pipeline: TagLibAudioMetadataPipeline { TagLibAudioMetadataPipeline() }

    @MainActor
    func testStagedDownloadedArtworkPersistsThroughInspectorSaveForSupportedFixtures() async throws {
        // Use the bytes exactly as an online download service returns them: the
        // download contract already normalizes to PNG, so no re-encode happens on
        // this path.
        let expectedPNG = Self.tinyPNGData

        for fileExtension in ["mp3", "m4a", "flac"] {
            let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: fileExtension)
            defer { MetadataTestTokens.removeFixtureCopy(at: url) }

            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let originalBytes = try Data(contentsOf: url)
            let originalTitle = file.title
            let originalAlbum = file.album

            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline, writableFixtures: [file])
            viewModel.mergeQuickImportFiles([file])
            viewModel.setSelectedAudioIDs([file.id])
            viewModel.edit?.title = "Artwork Save Title"

            let intent = try XCTUnwrap(
                viewModel.beginArtworkImport(for: file, source: .clipboard),
                "A real Inspector draft must authorize the handoff (\(fileExtension))"
            )
            let outcome = await viewModel.finishArtworkImport(
                imageData: expectedPNG,
                intent: intent,
                normalize: { data in data }
            )
            XCTAssertEqual(outcome, .staged, fileExtension)

            // Staging only: no byte on disk changed yet.
            XCTAssertEqual(
                try Data(contentsOf: url),
                originalBytes,
                "Staging must not write \(fileExtension) bytes"
            )
            XCTAssertTrue(viewModel.hasUnsavedInspectorChanges, fileExtension)

            viewModel.saveInspectorEdits()
            try await saveFinished(viewModel)

            let saved = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(saved.artworkData, expectedPNG, "Artwork PNG bytes must round-trip (\(fileExtension))")
            XCTAssertEqual(saved.title, "Artwork Save Title", "Unrelated edit must persist (\(fileExtension))")
            XCTAssertEqual(saved.album, originalAlbum, "Unrelated fields must survive (\(fileExtension))")
            XCTAssertNotEqual(originalBytes, try Data(contentsOf: url), "Save must have written the file")
            XCTAssertFalse(viewModel.hasUnsavedInspectorChanges, fileExtension)

            // Clear-artwork round trip through the same guarded boundary.
            let clearIntent = try XCTUnwrap(
                viewModel.captureArtworkTransfer(targetIDs: [file.id], source: .clear)
            )
            guard case .staged = viewModel.commitArtworkTransfer(clearIntent, action: .remove) else {
                return XCTFail("Expected the clear command to stage (\(fileExtension))")
            }
            viewModel.saveInspectorEdits()
            try await saveFinished(viewModel)
            let cleared = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertNil(cleared.artworkData, "Clear must round-trip removal (\(fileExtension))")
            XCTAssertEqual(cleared.title, "Artwork Save Title", fileExtension)

            // Keep the original title meaningful in the failure output.
            XCTAssertEqual(originalTitle.isEmpty, true, fileExtension)
        }
    }

    @MainActor
    private func saveFinished(_ viewModel: AudioViewModel) async throws {
        XCTAssertNotNil(viewModel.metadataSaveProgress)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while viewModel.metadataSaveProgress != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(viewModel.metadataSaveProgress, "Save timed out")
    }
}
