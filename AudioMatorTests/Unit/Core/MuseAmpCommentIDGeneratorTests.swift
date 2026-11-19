import XCTest
@testable import AudioMator

nonisolated final class MuseAmpCommentIDGeneratorTests: XCTestCase {
    @MainActor
    func testTracksWithSameAlbumAndAlbumArtistShareAlbumID() {
        let assignments = MuseAmpCommentIDGenerator.assignments(for: [
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "The Band", trackKey: "disc1-track1"),
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "The Band", trackKey: "disc1-track2")
        ])

        XCTAssertEqual(assignments[0].albumID, assignments[1].albumID)
        XCTAssertNotEqual(assignments[0].trackID, assignments[1].trackID)
    }

    @MainActor
    func testDifferentAlbumOrAlbumArtistGetsDifferentAlbumID() {
        let assignments = MuseAmpCommentIDGenerator.assignments(for: [
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "The Band", trackKey: "1"),
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "Another Band", trackKey: "2"),
            MuseAmpTrackIdentity(album: "Red Hour", albumArtist: "The Band", trackKey: "3")
        ])

        XCTAssertEqual(Set(assignments.map(\.albumID)).count, 3)
    }

    @MainActor
    func testGeneratedIDsAreNumericStrings() {
        let assignment = MuseAmpCommentIDGenerator.assignments(for: [
            MuseAmpTrackIdentity(album: "Album", albumArtist: "Artist", trackKey: "track")
        ])[0]

        XCTAssertTrue(assignment.albumID.allSatisfy(\.isNumber))
        XCTAssertTrue(assignment.trackID.allSatisfy(\.isNumber))
    }

    @MainActor
    func testCommentTextMatchesMuseAmpPayloadFormat() {
        XCTAssertEqual(
            MuseAmpCommentIDGenerator.commentText(albumID: "13868407145376506873", trackID: "4906269179403622017"),
            "{\"albumID\":\"13868407145376506873\",\"trackID\":\"4906269179403622017\",\"v\":1}"
        )
    }

    @MainActor
    func testNumericIDIsStableForSameInput() {
        XCTAssertEqual(
            MuseAmpCommentIDGenerator.numericID(for: "track", key: "Album\u{1F}Artist\u{1F}1"),
            MuseAmpCommentIDGenerator.numericID(for: "track", key: "Album\u{1F}Artist\u{1F}1")
        )
    }
}
