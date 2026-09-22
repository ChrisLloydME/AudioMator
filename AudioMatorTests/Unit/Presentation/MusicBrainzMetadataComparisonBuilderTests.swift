import XCTest
@testable import AudioMator

final class MusicBrainzMetadataComparisonBuilderTests: XCTestCase {
    func testPresentationBuildsFallbackPreviewAndComparisonRows() throws {
        let file = MusicBrainzFileSearchInput(
            id: "file-id",
            displayTitle: "Local title",
            title: "Local title",
            artist: "artist",
            albumArtist: "Artist",
            album: "Album",
            trackNumber: "01",
            discNumber: "1",
            trackTotal: 1,
            releaseDate: "",
            isrc: "LOCAL-ISRC",
            barcode: "123"
        )
        let release = makeRelease()

        let presentation = MusicBrainzMetadataComparisonBuilder.presentation(
            for: release,
            fallbackFiles: [file]
        )

        let preview = try XCTUnwrap(presentation.preview)
        XCTAssertEqual(preview.matchedFileCount, 1)

        let rows = try XCTUnwrap(presentation.comparisonGroups.first?.rows)
        XCTAssertEqual(row("title", in: rows)?.status, .different)
        XCTAssertEqual(row("artist", in: rows)?.status, .same)
        XCTAssertEqual(row("album", in: rows)?.status, .same)
        XCTAssertEqual(row("release-date", in: rows)?.status, .missingLocal)
        XCTAssertEqual(row("isrc", in: rows)?.status, .different)
        XCTAssertEqual(row("barcode", in: rows)?.status, .same)
    }

    func testPresentationPreservesProviderPreviewInsteadOfRematching() throws {
        let release = makeRelease()
        let assignment = MusicBrainzReleaseMatchAssignment(
            id: "provider-assignment",
            file: MusicBrainzFileSearchInput(
                id: "provider-file",
                displayTitle: "Provider file",
                title: "Remote title",
                artist: "Artist",
                albumArtist: "Artist",
                album: "Album",
                trackNumber: "1"
            ),
            track: MusicBrainzReleaseMatchTrack(
                id: "provider-track",
                mediumTitle: "",
                mediumFormat: "Digital Media",
                mediumPosition: 1,
                mediumTrackCount: 1,
                releaseMediumCount: 1,
                number: "1",
                title: "Remote title",
                artistCredit: "Artist",
                durationMilliseconds: nil,
                recordingID: "recording-id",
                isrcs: []
            ),
            score: 0.75,
            reason: "provider preview"
        )
        var releaseWithPreview = release
        releaseWithPreview.selectionMatchPreview = MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [assignment],
            unmatchedFiles: [],
            unassignedTracks: [],
            averageTrackScore: 0.75,
            overallScore: 0.75,
            selectionLooksMixed: false
        )

        let presentation = MusicBrainzMetadataComparisonBuilder.presentation(
            for: releaseWithPreview,
            fallbackFiles: []
        )

        XCTAssertEqual(presentation.preview?.matchedAssignments.first?.id, "provider-assignment")
        XCTAssertEqual(presentation.comparisonGroups.first?.assignment.id, "provider-assignment")
    }

    private func row(
        _ id: String,
        in rows: [MusicBrainzMetadataComparisonRow]
    ) -> MusicBrainzMetadataComparisonRow? {
        rows.first { $0.id == id }
    }

    private func makeRelease() -> MusicBrainzReleaseDetail {
        MusicBrainzReleaseDetail(
            id: "release-id",
            title: "Album",
            artistCredit: "Artist",
            date: "2024-01-01",
            country: "US",
            status: "Official",
            barcode: "123",
            packaging: "",
            asin: "",
            quality: "",
            language: "",
            script: "",
            annotation: "",
            genres: [],
            tags: [],
            releaseGroupTitle: "Album",
            releaseGroupID: "release-group-id",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: [],
            labels: [],
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "medium-id",
                    title: "",
                    format: "Digital Media",
                    trackCount: 1,
                    discIDs: [],
                    tracks: [
                        MusicBrainzReleaseDetail.Medium.Track(
                            id: "track-id",
                            number: "1",
                            title: "Remote title",
                            artistCredit: "Artist",
                            durationMilliseconds: nil,
                            recordingID: "recording-id",
                            isrcs: ["REMOTE-ISRC"]
                        )
                    ]
                )
            ],
            selectionMatchPreview: nil
        )
    }
}
