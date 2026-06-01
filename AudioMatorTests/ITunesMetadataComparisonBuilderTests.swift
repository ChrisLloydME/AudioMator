import XCTest
@testable import AudioMator

final class ITunesMetadataComparisonBuilderTests: XCTestCase {
    func testRowClassifiesTrimmedAndNormalizedValues() {
        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.row(
                id: "artist",
                title: "Artist",
                local: "  Beyonce  ",
                remote: "Beyonce",
                monospaced: false
            )?.status,
            .same
        )

        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.row(
                id: "title",
                title: "Title",
                local: "Local",
                remote: "Remote"
            )?.status,
            .different
        )

        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.row(
                id: "missing-local",
                title: "Missing Local",
                local: " ",
                remote: "Remote"
            )?.status,
            .missingLocal
        )

        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.row(
                id: "missing-remote",
                title: "Missing Remote",
                local: "Local",
                remote: "\n"
            )?.status,
            .missingRemote
        )

        XCTAssertNil(
            ITunesMetadataComparisonBuilder.row(
                id: "blank",
                title: "Blank",
                local: " ",
                remote: "\n"
            )
        )
    }

    func testRemoteValuesPreserveAlbumFallbackRules() {
        let detail = makeAlbumDetail(
            albumArtistName: "Album Artist",
            albumGenre: "Album Genre",
            albumCopyright: "Album Copyright",
            albumExplicitness: "explicit",
            track: Self.makeTrack(
                collectionArtistName: "",
                primaryGenreName: "",
                releaseDate: "",
                copyright: "",
                discCount: 1,
                trackExplicitness: "notExplicit"
            )
        )
        let assignment = makeAssignment(track: detail.tracks[0])

        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.remoteValue(
                for: .albumArtist,
                assignment: assignment,
                detail: detail
            ),
            "Album Artist"
        )
        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.remoteValue(for: .genre, assignment: assignment, detail: detail),
            "Album Genre"
        )
        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.remoteValue(for: .copyright, assignment: assignment, detail: detail),
            "Album Copyright"
        )
        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.remoteValue(for: .discTotal, assignment: assignment, detail: detail),
            ""
        )
        XCTAssertEqual(
            ITunesMetadataComparisonBuilder.remoteValue(for: .isExplicit, assignment: assignment, detail: detail),
            "Yes"
        )
    }

    func testRowsPreferLoadedFileValuesOverSearchFallbackValues() {
        let fileID = UUID()
        let loadedFile = AudioFileTestFactory.make(
            id: fileID,
            title: "Loaded Title",
            artist: "Loaded Artist",
            album: "Loaded Album",
            track: 2,
            trackTotal: 9
        )
        let fallback = makeFileInput(
            id: fileID.uuidString,
            title: "Fallback Title",
            artist: "Fallback Artist",
            album: "Fallback Album",
            trackNumber: "7",
            trackTotal: 12
        )
        let track = Self.makeTrack(trackName: "Remote Title", artistName: "Remote Artist", trackNumber: 2, trackCount: 9)
        let detail = makeAlbumDetail(track: track)
        let assignment = ITunesAlbumMatchAssignment(
            id: "assignment",
            file: fallback,
            track: track,
            score: 1,
            reason: "test"
        )

        let rows = ITunesMetadataComparisonBuilder.rows(
            for: assignment,
            detail: detail,
            loadedFiles: [loadedFile]
        )

        XCTAssertEqual(rows.first { $0.id == ITunesTagWriteField.title.id }?.localValue, "Loaded Title")
        XCTAssertEqual(rows.first { $0.id == ITunesTagWriteField.artist.id }?.localValue, "Loaded Artist")
        XCTAssertEqual(rows.first { $0.id == ITunesTagWriteField.album.id }?.localValue, "Loaded Album")
        XCTAssertEqual(rows.first { $0.id == ITunesTagWriteField.trackNumber.id }?.localValue, "2")
        XCTAssertEqual(rows.first { $0.id == ITunesTagWriteField.trackTotal.id }?.localValue, "9")
    }

    private func makeAssignment(track: ITunesTrackResult) -> ITunesAlbumMatchAssignment {
        ITunesAlbumMatchAssignment(
            id: "assignment",
            file: makeFileInput(),
            track: track,
            score: 1,
            reason: "test"
        )
    }

    private func makeFileInput(
        id: String = UUID().uuidString,
        title: String = "Local Title",
        artist: String = "Local Artist",
        album: String = "Local Album",
        trackNumber: String = "1",
        trackTotal: Int = 10
    ) -> ITunesFileSearchInput {
        ITunesFileSearchInput(
            id: id,
            displayTitle: title,
            title: title,
            artist: artist,
            albumArtist: "Local Album Artist",
            album: album,
            trackNumber: trackNumber,
            discNumber: "1",
            trackTotal: trackTotal,
            durationMilliseconds: nil,
            releaseDate: "2024-01-01T00:00:00Z",
            barcode: "123456789012",
            itunesAlbumID: "100",
            itunesArtistID: "200",
            itunesCatalogID: "300"
        )
    }

    private func makeAlbumDetail(
        albumArtistName: String = "Album Artist",
        albumGenre: String = "Album Genre",
        albumCopyright: String = "",
        albumExplicitness: String = "notExplicit",
        track: ITunesTrackResult? = nil
    ) -> ITunesAlbumDetail {
        let resolvedTrack = track ?? Self.makeTrack()

        return ITunesAlbumDetail(
            album: ITunesAlbumResult(
                collectionID: 100,
                artistID: 200,
                collectionArtistID: 201,
                collectionName: "Remote Album",
                artistName: albumArtistName,
                collectionArtistName: albumArtistName,
                trackCount: 10,
                releaseDate: "2024-01-01T00:00:00Z",
                primaryGenreName: albumGenre,
                country: "USA",
                copyright: albumCopyright,
                contentAdvisoryRating: "",
                collectionExplicitness: albumExplicitness,
                collectionViewURL: nil,
                artistViewURL: nil,
                selectionMatchPreview: nil,
                selectionMatchScore: nil
            ),
            tracks: [resolvedTrack],
            selectionMatchPreview: nil
        )
    }

    private static func makeTrack(
        trackName: String = "Remote Title",
        artistName: String = "Remote Artist",
        collectionArtistName: String = "Remote Album Artist",
        primaryGenreName: String = "Remote Genre",
        releaseDate: String = "2024-01-01T00:00:00Z",
        copyright: String = "Remote Copyright",
        discCount: Int = 2,
        trackNumber: Int = 1,
        trackCount: Int = 10,
        trackExplicitness: String = "notExplicit"
    ) -> ITunesTrackResult {
        ITunesTrackResult(
            trackID: 300,
            collectionID: 100,
            artistID: 200,
            collectionArtistID: 201,
            trackName: trackName,
            artistName: artistName,
            collectionArtistName: collectionArtistName,
            collectionName: "Remote Album",
            trackNumber: trackNumber,
            trackCount: trackCount,
            discNumber: 1,
            discCount: discCount,
            durationMilliseconds: nil,
            releaseDate: releaseDate,
            primaryGenreName: primaryGenreName,
            country: "USA",
            copyright: copyright,
            contentAdvisoryRating: "",
            kind: "song",
            wrapperType: "track",
            trackExplicitness: trackExplicitness,
            collectionExplicitness: "notExplicit",
            trackViewURL: nil,
            collectionViewURL: nil,
            artistViewURL: nil
        )
    }
}
