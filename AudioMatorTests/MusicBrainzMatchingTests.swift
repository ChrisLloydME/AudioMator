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
