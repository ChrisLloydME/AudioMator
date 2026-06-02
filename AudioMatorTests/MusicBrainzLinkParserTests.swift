import XCTest
@testable import AudioMator

final class MusicBrainzLinkParserTests: XCTestCase {
    func testParseSupportsRecordingAndReleaseLinksWithOrWithoutScheme() throws {
        let recordingID = "6f1ed5f8-8bf7-4a4c-a6c9-4bb5a8f6d001"
        let releaseID = "bb30c6f5-0f9d-41f1-8e61-a9a8150419b8"

        XCTAssertEqual(
            try MusicBrainzLinkParser.parse("https://musicbrainz.org/recording/\(recordingID)"),
            .recording(recordingID)
        )
        XCTAssertEqual(
            try MusicBrainzLinkParser.parse("musicbrainz.org/release/\(releaseID)?inc=recordings"),
            .release(releaseID)
        )
    }

    func testParseRejectsUnsupportedHostsInvalidIDsAndUnsupportedEntities() {
        XCTAssertThrowsError(try MusicBrainzLinkParser.parse("https://example.com/release/bb30c6f5-0f9d-41f1-8e61-a9a8150419b8")) { error in
            guard case MusicBrainzClientError.invalidLink = error else {
                return XCTFail("Expected invalidLink, got \(error)")
            }
        }

        XCTAssertThrowsError(try MusicBrainzLinkParser.parse("https://musicbrainz.org/release/not-a-uuid")) { error in
            guard case MusicBrainzClientError.invalidLink = error else {
                return XCTFail("Expected invalidLink, got \(error)")
            }
        }

        XCTAssertThrowsError(try MusicBrainzLinkParser.parse("https://musicbrainz.org/artist/bb30c6f5-0f9d-41f1-8e61-a9a8150419b8")) { error in
            guard case MusicBrainzClientError.unsupportedLink = error else {
                return XCTFail("Expected unsupportedLink, got \(error)")
            }
        }
    }
}
