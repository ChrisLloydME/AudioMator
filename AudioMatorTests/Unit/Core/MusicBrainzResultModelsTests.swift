import XCTest
@testable import AudioMator

nonisolated final class MusicBrainzResultModelsTests: XCTestCase {
    @MainActor
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
    }

    @MainActor
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

    @MainActor
    func testClientErrorsPreserveUserVisibleDescriptions() {
        XCTAssertEqual(
            MusicBrainzClientError.requestFailed(statusCode: 503).errorDescription,
            "This MusicBrainz lookup couldn’t be completed. Try again later.\nDetails: HTTP 503."
        )
        XCTAssertEqual(
            MusicBrainzClientError.decodingFailed("Missing key.").errorDescription,
            "The metadata from MusicBrainz couldn’t be read. Try again later.\nDetails: Missing key."
        )
    }
}
