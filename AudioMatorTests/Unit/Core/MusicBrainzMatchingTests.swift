import XCTest
@testable import AudioMator

final class MusicBrainzMatchingTests: XCTestCase {
    func testOptimalAssignmentsAvoidGreedyTrackConflict() {
        let fileA = makeFile(id: "a")
        let fileB = makeFile(id: "b")
        let trackX = makeTrack(id: "x")
        let trackY = makeTrack(id: "y")
        let candidates = [
            makeAssignment(file: fileA, track: trackX, score: 0.90),
            makeAssignment(file: fileA, track: trackY, score: 0.80),
            makeAssignment(file: fileB, track: trackX, score: 0.85)
        ]

        let assignments = MusicBrainzFileSelectionMatcher.optimalAssignments(from: candidates)

        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(Set(assignments.map(\.id)), ["a::y", "b::x"])
        XCTAssertEqual(assignments.map(\.score).reduce(0, +), 1.65, accuracy: 0.000_001)
    }

    func testRepresentativeLookupPrefersStrongIdentifiersAndCompleteMetadata() {
        let sparse = MusicBrainzFileSearchInput(
            id: "sparse",
            displayTitle: "01 Track",
            title: "Track",
            artist: "",
            albumArtist: "",
            album: "",
            trackNumber: "1"
        )
        let identified = MusicBrainzFileSearchInput(
            id: "identified",
            displayTitle: "02 Track",
            title: "Track",
            artist: "Artist",
            albumArtist: "Artist",
            album: "Album",
            trackNumber: "2",
            durationMilliseconds: 180_000,
            releaseDate: "2026",
            isrc: "USAAA2600001"
        )

        let representatives = MusicBrainzClient.representativeFilesForReleaseLookup(
            from: [sparse, identified]
        )

        XCTAssertEqual(representatives.first?.id, "identified")
    }

    func testRepresentativeLookupAvoidsTitleThatDuplicatesAlbumName() {
        let titleTrack = MusicBrainzFileSearchInput(
            id: "title-track",
            displayTitle: "Beautiful Eyes",
            title: "Beautiful Eyes",
            artist: "Taylor Swift",
            albumArtist: "Taylor Swift",
            album: "Beautiful Eyes - EP",
            trackNumber: "1",
            trackTotal: 6,
            releaseDate: "2008"
        )
        let distinctiveTrack = MusicBrainzFileSearchInput(
            id: "distinctive-track",
            displayTitle: "Should've Said No (Alternate Version)",
            title: "Should've Said No (Alternate Version)",
            artist: "Taylor Swift",
            albumArtist: "Taylor Swift",
            album: "Beautiful Eyes - EP",
            trackNumber: "2",
            trackTotal: 6,
            releaseDate: "2008"
        )

        let representatives = MusicBrainzClient.representativeFilesForReleaseLookup(
            from: [titleTrack, distinctiveTrack]
        )

        XCTAssertEqual(representatives.first?.id, "distinctive-track")
    }

    func testReleaseDetailVerificationStopsOnlyForClearHighConfidenceLead() {
        let file = makeFile(id: "a")
        let track = makeTrack(id: "x")
        let assignment = makeAssignment(file: file, track: track, score: 0.94)
        let preview = MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [assignment],
            unmatchedFiles: [],
            unassignedTracks: [],
            averageTrackScore: 0.94,
            overallScore: 1_100,
            selectionLooksMixed: false
        )
        let leader = makeReleaseResult(id: "leader", score: 98)
        let distantRunnerUp = makeReleaseResult(id: "runner-up", score: 86)
        let closeRunnerUp = makeReleaseResult(id: "close", score: 94)

        XCTAssertTrue(MusicBrainzClient.shouldStopReleaseDetailVerification(
            candidate: leader,
            nextCandidate: distantRunnerUp,
            preview: preview,
            evidence: 0
        ))
        XCTAssertFalse(MusicBrainzClient.shouldStopReleaseDetailVerification(
            candidate: leader,
            nextCandidate: closeRunnerUp,
            preview: preview,
            evidence: 0
        ))
    }

    func testReleaseCandidateCredibilityRejectsArtistOnlyNoise() {
        let query = MusicBrainzSearchQuery(
            mode: .album,
            artist: "Taylor Swift",
            album: "Beautiful Eyes - EP",
            releaseDate: "2008"
        )
        let target = MusicBrainzReleaseSearchResult(
            id: "target",
            title: "Beautiful Eyes",
            artistCredit: "Taylor Swift",
            score: 100,
            date: "2008-07-15",
            country: "US",
            status: "Official",
            mediaFormats: ["CD"],
            releaseGroup: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
        let noise = MusicBrainzReleaseSearchResult(
            id: "noise",
            title: "Back to December",
            artistCredit: "Taylor Swift",
            score: 49,
            date: "2013-06-04",
            country: "JP",
            status: "Withdrawn",
            mediaFormats: ["Digital Media"],
            releaseGroup: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )

        XCTAssertTrue(MusicBrainzResultRanker.hasCredibleReleaseCandidate([target], query: query))
        XCTAssertFalse(MusicBrainzResultRanker.hasCredibleReleaseCandidate([noise], query: query))
    }

    func testMultiMediumReleaseIgnoresUnselectedVideoMedium() {
        let files = (1...6).map { trackNumber in
            MusicBrainzFileSearchInput(
                id: "file-\(trackNumber)",
                displayTitle: "Track \(trackNumber)",
                title: "Track \(trackNumber)",
                artist: "Taylor Swift",
                albumArtist: "Taylor Swift",
                album: "Beautiful Eyes - EP",
                trackNumber: String(trackNumber),
                discNumber: "1",
                trackTotal: 6,
                releaseDate: "2008"
            )
        }
        let audioTracks = (1...6).map { trackNumber in
            makeDetailTrack(
                id: "audio-\(trackNumber)",
                number: String(trackNumber),
                title: "Track \(trackNumber)"
            )
        }
        let videoTracks = (1...9).map { trackNumber in
            makeDetailTrack(
                id: "video-\(trackNumber)",
                number: String(trackNumber),
                title: "Video \(trackNumber)"
            )
        }
        let release = makeReleaseDetail(
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "cd",
                    title: "",
                    format: "CD",
                    trackCount: 6,
                    discIDs: [],
                    tracks: audioTracks
                ),
                MusicBrainzReleaseDetail.Medium(
                    id: "dvd",
                    title: "",
                    format: "DVD-Video",
                    trackCount: 9,
                    discIDs: [],
                    tracks: videoTracks
                )
            ]
        )

        let preview = MusicBrainzFileSelectionMatcher.match(
            selection: MusicBrainzFileSelectionSummary(files: files),
            release: release
        )

        XCTAssertEqual(preview.matchedFileCount, 6)
        XCTAssertTrue(preview.unmatchedFiles.isEmpty)
        XCTAssertTrue(
            preview.unassignedTracks.isEmpty,
            "Tracks on an unselected DVD medium must not count as missing album tracks."
        )
        XCTAssertGreaterThan(preview.overallScore, 1_300)
    }

    private func makeFile(id: String) -> MusicBrainzFileSearchInput {
        MusicBrainzFileSearchInput(
            id: id,
            displayTitle: id,
            title: id,
            artist: "Artist",
            albumArtist: "Artist",
            album: "Album",
            trackNumber: ""
        )
    }

    private func makeTrack(id: String) -> MusicBrainzReleaseMatchTrack {
        MusicBrainzReleaseMatchTrack(
            id: id,
            mediumTitle: "Album",
            mediumFormat: "Digital Media",
            mediumPosition: 1,
            mediumTrackCount: 2,
            releaseMediumCount: 1,
            number: "",
            title: id,
            artistCredit: "Artist",
            durationMilliseconds: nil,
            recordingID: id,
            isrcs: []
        )
    }

    private func makeDetailTrack(
        id: String,
        number: String,
        title: String
    ) -> MusicBrainzReleaseDetail.Medium.Track {
        MusicBrainzReleaseDetail.Medium.Track(
            id: id,
            number: number,
            title: title,
            artistCredit: "Taylor Swift",
            durationMilliseconds: nil,
            recordingID: id,
            isrcs: []
        )
    }

    private func makeReleaseDetail(
        media: [MusicBrainzReleaseDetail.Medium]
    ) -> MusicBrainzReleaseDetail {
        MusicBrainzReleaseDetail(
            id: "beautiful-eyes",
            title: "Beautiful Eyes",
            artistCredit: "Taylor Swift",
            date: "2008-07-15",
            country: "US",
            status: "Official",
            barcode: "",
            packaging: "",
            asin: "",
            quality: "normal",
            language: "eng",
            script: "Latn",
            annotation: "",
            genres: [],
            tags: [],
            releaseGroupTitle: "Beautiful Eyes",
            releaseGroupID: "beautiful-eyes-group",
            releaseGroupPrimaryType: "EP",
            releaseGroupSecondaryTypes: [],
            labels: [],
            media: media,
            selectionMatchPreview: nil
        )
    }

    private func makeAssignment(
        file: MusicBrainzFileSearchInput,
        track: MusicBrainzReleaseMatchTrack,
        score: Double
    ) -> MusicBrainzReleaseMatchAssignment {
        MusicBrainzReleaseMatchAssignment(
            id: "\(file.id)::\(track.id)",
            file: file,
            track: track,
            score: score,
            reason: "fixture"
        )
    }

    private func makeReleaseResult(id: String, score: Int) -> MusicBrainzReleaseSearchResult {
        MusicBrainzReleaseSearchResult(
            id: id,
            title: "Album",
            artistCredit: "Artist",
            score: score,
            date: "2026",
            country: "US",
            status: "Official",
            mediaFormats: ["Digital Media"],
            releaseGroup: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }
}
