import XCTest
@testable import AudioMator

final class MusicBrainzLuceneQueryBuilderTests: XCTestCase {
    func testCombinedSearchQueryPreservesPriorityDeduplicatesAndCapsClauses() throws {
        let combined = try XCTUnwrap(
            MusicBrainzProviderLuceneQueryBuilder.combinedSearchQuery(
                from: ["strict", "fallback", "strict", "broad", "unused"],
                maximumClauseCount: 3
            )
        )

        XCTAssertEqual(combined, "(strict OR fallback OR broad)")
        XCTAssertFalse(combined.contains("unused"))
    }

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

    func testFileClusterQueriesIncludeAlbumVariantWithoutTrailingReleaseType() {
        let files = (1...6).map { trackNumber in
            MusicBrainzFileSearchInput(
                id: "beautiful-eyes-\(trackNumber)",
                displayTitle: "Track \(trackNumber)",
                title: "Track \(trackNumber)",
                artist: "Taylor Swift",
                albumArtist: "Taylor Swift",
                album: "Beautiful Eyes - EP",
                trackNumber: String(trackNumber),
                trackTotal: 6,
                releaseDate: "2008-07-15"
            )
        }
        let query = MusicBrainzSearchQuery(mode: .file, fileInputs: files)

        let strongQueries = MusicBrainzLuceneQueryBuilder
            .fileClusterStrongReleaseSearchQueries(from: query)
        let broadQueries = MusicBrainzLuceneQueryBuilder
            .fileClusterBroadReleaseSearchQueries(from: query)

        XCTAssertTrue(
            strongQueries.contains { $0.contains("release:\"Beautiful Eyes\"") },
            "The strict stage must try the canonical MusicBrainz title as well as the tagged title."
        )
        XCTAssertTrue(
            broadQueries.contains { $0.contains("release:\"Beautiful Eyes\"") },
            "The fallback stage must preserve the canonical album-title variant."
        )
    }

    func testAlbumVariantDoesNotRemoveUnqualifiedReleaseTypeWord() {
        let query = MusicBrainzSearchQuery(
            mode: .album,
            artist: "Artist",
            album: "The EP"
        )

        let queries = MusicBrainzLuceneQueryBuilder.releaseSearchQueries(from: query)

        XCTAssertTrue(queries.contains { $0.contains("release:\"The EP\"") })
        XCTAssertFalse(queries.contains { $0.contains("release:\"The\"") })
    }

    func testFileClusterBroadQueriesDoNotFallBackToArtistAloneWhenAlbumIsKnown() {
        let files = (1...6).map { trackNumber in
            MusicBrainzFileSearchInput(
                id: "file-\(trackNumber)",
                displayTitle: "Track \(trackNumber)",
                title: "Track \(trackNumber)",
                artist: "Taylor Swift",
                albumArtist: "Taylor Swift",
                album: "Beautiful Eyes - EP",
                trackNumber: String(trackNumber),
                trackTotal: 6,
                releaseDate: "2008"
            )
        }

        let queries = MusicBrainzLuceneQueryBuilder.fileClusterBroadReleaseSearchQueries(
            from: MusicBrainzSearchQuery(mode: .file, fileInputs: files)
        )

        XCTAssertFalse(queries.contains("artist:\"Taylor Swift\""))
        XCTAssertFalse(queries.contains("(Taylor AND Swift)"))
        XCTAssertTrue(
            queries.contains {
                $0.contains("Beautiful") && $0.contains("Eyes") && $0.contains("artist:\"Taylor Swift\"")
            }
        )
    }
}
