import AVFoundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

@MainActor
final class StoreIdentifierWriteTests: XCTestCase {
    private func aiff() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("aiff")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true
            ])
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4410))
            buffer.frameLength = 4410
            if let samples = buffer.floatChannelData { samples[0].update(repeating: 0, count: 4410) }
            try file.write(from: buffer)
        }
        return url
    }

    func testDedicatedIDsUseRegistryIntegerShapeAndPreserveUntouchedTextIdentifiers() {
        let original = AudioFileTestFactory.make()
        var edit = SingleFileEditModel(from: original)
        edit.itunesAlbumID = "1234567890"
        edit.itunesArtistID = "123456"
        edit.itunesCatalogID = "987654"
        edit.musicBrainzAlbumID = "00000000-0000-0000-0000-000000000001"
        let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: MetadataEditPayload(edit, comparedTo: original))
        XCTAssertEqual(patch.fields[.itunesAlbumID], .integer(1234567890))
        XCTAssertEqual(patch.fields[.itunesArtistID], .integer(123456))
        XCTAssertEqual(patch.fields[.itunesCatalogID], .integer(987654))
        XCTAssertEqual(patch.fields[.musicBrainzAlbumID], .text(edit.musicBrainzAlbumID))
    }

    func testAIFFStoreIDsSetReplaceClearAndReloadThroughRealAppPipeline() async throws {
        let url = try aiff()
        let pipeline = TagLibAudioMetadataPipeline()
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())
        for values in [["1234567890", "123456", "987654"], ["42", "43", "44"], ["", "", ""]] {
            var edit = SingleFileEditModel(from: file)
            edit.itunesAlbumID = values[0]
            edit.itunesArtistID = values[1]
            edit.itunesCatalogID = values[2]
            let payload = MetadataEditPayload(edit, comparedTo: file)
            _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion)
            file = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(file.itunesAlbumID, values[0])
            XCTAssertEqual(file.itunesArtistID, values[1])
            XCTAssertEqual(file.itunesCatalogID, values[2])
        }
    }

    func testInvalidAndOutOfRangeIDsRejectWithoutPartialTitleSave() async throws {
        let url = try aiff()
        let pipeline = TagLibAudioMetadataPipeline()
        for invalid in ["not-a-number", "-1", "4294967296", "99999999999999999999999999"] {
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let before = try Data(contentsOf: url)
            var edit = SingleFileEditModel(from: file)
            edit.title = "Must not be committed"
            edit.itunesArtistID = invalid
            XCTAssertThrowsError(try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion))
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }
}
