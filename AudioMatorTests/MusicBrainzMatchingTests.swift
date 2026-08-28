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
}
