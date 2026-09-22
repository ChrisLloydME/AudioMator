import XCTest
@testable import AudioMator

final class MusicBrainzResultModelsTests: XCTestCase {
    func testRecordingReleaseConversionPreservesSearchResultIdentity() throws {
        let release = MusicBrainzRecordingResult.Release(
            id: "release-id",
            title: "Release Title",
            date: "2026-06-20",
            country: "GB",
            status: "Official"
        )

        let result = MusicBrainzReleaseSearchResult(recordingRelease: release)

        XCTAssertEqual(result.id, release.id)
        XCTAssertEqual(result.title, release.title)
        XCTAssertEqual(result.date, release.date)
        XCTAssertEqual(result.country, release.country)
        XCTAssertEqual(result.status, release.status)
        XCTAssertEqual(result.score, 0)
        XCTAssertTrue(result.mediaFormats.isEmpty)
        XCTAssertTrue(try XCTUnwrap(result.musicBrainzURL).absoluteString.hasSuffix("/release/release-id"))
    }

    func testSearchResultsCountsBothResultKinds() {
        let recording = MusicBrainzRecordingResult(
            id: "recording-id",
            title: "Track",
            artistCredit: "Artist",
            score: 100,
            disambiguation: "",
            firstReleaseDate: "2026",
            durationMilliseconds: 180_000,
            releases: []
        )

        XCTAssertEqual(MusicBrainzSearchResults.recordings([recording]).count, 1)
        XCTAssertFalse(MusicBrainzSearchResults.recordings([recording]).isEmpty)
        XCTAssertEqual(MusicBrainzSearchResults.releases([]).count, 0)
        XCTAssertTrue(MusicBrainzSearchResults.releases([]).isEmpty)
    }

    func testClientErrorsPreserveUserVisibleDescriptions() {
        XCTAssertEqual(
            MusicBrainzClientError.requestFailed(statusCode: 503).errorDescription,
            "MusicBrainz returned HTTP 503."
        )
        XCTAssertEqual(
            MusicBrainzClientError.decodingFailed("Missing key.").errorDescription,
            "MusicBrainz returned data AudioMator couldn't read. Missing key."
        )
    }
}
