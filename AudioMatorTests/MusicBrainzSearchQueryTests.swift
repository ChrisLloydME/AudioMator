import XCTest
@testable import AudioMator

final class MusicBrainzSearchQueryTests: XCTestCase {
    func testSelectionReleaseQueryUsesNormalizedSelectionSummary() {
        let inputs = [
            MusicBrainzFileSearchInput(
                id: "one",
                displayTitle: "One",
                title: "One",
                artist: "Track Artist",
                albumArtist: "Album Artist",
                album: "Shared Album",
                trackNumber: "01/12",
                trackTotal: 12,
                releaseDate: "2024-03-02",
                barcode: "123456789012",
                musicBrainzAlbumID: "release-id"
            ),
            MusicBrainzFileSearchInput(
                id: "two",
                displayTitle: "Two",
                title: "Two",
                artist: "Track Artist",
                albumArtist: "Album Artist",
                album: "Shared Album",
                trackNumber: "02/12",
                trackTotal: 12,
                releaseDate: "2024",
                barcode: "123456789012",
                musicBrainzAlbumID: "release-id"
            )
        ]
        let filters = MusicBrainzReleaseFilters(statuses: [.official])
        let query = MusicBrainzSearchQuery(
            mode: .file,
            fileInputs: inputs,
            releaseFilters: filters
        )

        let releaseQuery = query.selectionReleaseQuery

        XCTAssertEqual(releaseQuery.mode, .album)
        XCTAssertEqual(releaseQuery.artist, "Album Artist")
        XCTAssertEqual(releaseQuery.album, "Shared Album")
        XCTAssertEqual(releaseQuery.trackTotal, 12)
        XCTAssertEqual(releaseQuery.releaseDate, "2024")
        XCTAssertEqual(releaseQuery.barcode, "123456789012")
        XCTAssertEqual(releaseQuery.musicBrainzAlbumID, "release-id")
        XCTAssertEqual(releaseQuery.fileInputs, inputs)
        XCTAssertEqual(releaseQuery.releaseFilters, filters)
    }

    func testQueryInitializationPreservesNormalizationRules() {
        let query = MusicBrainzSearchQuery(
            mode: .track,
            title: "  Title  ",
            artist: " Artist\n",
            trackNumber: " 007/12 ",
            trackTotal: -1,
            durationMilliseconds: 0,
            releaseDate: " 2024-03-02 "
        )

        XCTAssertEqual(query.title, "Title")
        XCTAssertEqual(query.artist, "Artist")
        XCTAssertEqual(query.normalizedTrackNumber, 7)
        XCTAssertEqual(query.trackTotal, 0)
        XCTAssertNil(query.durationMilliseconds)
        XCTAssertEqual(query.normalizedReleaseYear, "2024")
    }
}
