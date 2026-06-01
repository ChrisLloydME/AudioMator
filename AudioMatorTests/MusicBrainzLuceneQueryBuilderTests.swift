import XCTest
@testable import AudioMator

final class MusicBrainzLuceneQueryBuilderTests: XCTestCase {
    func testRecordingSearchQueriesEscapeReservedLuceneCharacters() {
        let query = MusicBrainzSearchQuery(
            mode: .track,
            title: "A+B",
            artist: "C:D",
            album: "The (Album)",
            trackNumber: "03/10",
            trackTotal: 10
        )

        let queries = MusicBrainzLuceneQueryBuilder.recordingSearchQueries(from: query)
        let joinedQueries = queries.joined(separator: "\n")

        XCTAssertTrue(joinedQueries.contains("recording:\"A\\+B\""))
        XCTAssertTrue(joinedQueries.contains("artist:\"C\\:D\""))
        XCTAssertTrue(joinedQueries.contains("release:\"The \\(Album\\)\""))
        XCTAssertTrue(joinedQueries.contains("tnum:3"))
        XCTAssertLessThanOrEqual(queries.count, 6)
    }

    func testReleaseSearchQueriesApplyReleaseFiltersToEveryPreferredClause() {
        let query = MusicBrainzSearchQuery(
            mode: .album,
            artist: "Artist",
            album: "Album",
            releaseFilters: MusicBrainzReleaseFilters(
                mediaFormats: [.digitalMedia, .cd],
                releaseYear: "2024-01-01",
                countries: ["us", "GB", "ignored"],
                statuses: [.official]
            )
        )

        let queries = MusicBrainzLuceneQueryBuilder.releaseSearchQueries(from: query)

        XCTAssertFalse(queries.isEmpty)
        for query in queries {
            XCTAssertTrue(query.contains("date:\"2024\""))
            XCTAssertTrue(query.contains("(country:\"gb\" OR country:\"us\")"))
            XCTAssertTrue(query.contains("status:\"official\""))
            XCTAssertTrue(query.contains("format:\"CD\""))
            XCTAssertTrue(query.contains("format:\"Digital Media\""))
        }
    }

    func testReleaseSearchQueriesDeduplicateAndLimitPreferredClauses() {
        let query = MusicBrainzSearchQuery(
            mode: .album,
            title: "Shared",
            artist: "Shared",
            album: "Shared"
        )

        let queries = MusicBrainzLuceneQueryBuilder.releaseSearchQueries(from: query)

        XCTAssertEqual(queries, Array(NSOrderedSet(array: queries)) as? [String])
        XCTAssertLessThanOrEqual(queries.count, 6)
    }
}
