import XCTest
@testable import AudioMator

final class MusicBrainzFilenameFallbackTests: XCTestCase {
    func testFallbackUsesFilenameAndDirectoriesWhenMetadataIsMissing() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/Boards of Canada - Music Has the Right to Children/CD 02/03 - Olson.mp3")
        )

        let fallback = MusicBrainzFilenameFallbackResolver.resolve(for: file)

        XCTAssertEqual(fallback.title, "Olson")
        XCTAssertEqual(fallback.artist, "Boards of Canada")
        XCTAssertEqual(fallback.albumArtist, "Boards of Canada")
        XCTAssertEqual(fallback.album, "Music Has the Right to Children")
        XCTAssertEqual(fallback.trackNumber, "3")
        XCTAssertEqual(fallback.discNumber, "2")
    }

    func testFallbackPrefersExistingMetadataOverFilenameGuesses() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/Guessed Artist - Guessed Album/CD 01/04 - Guessed Title.mp3"),
            title: "Tagged Title",
            artist: "Tagged Artist",
            album: "Tagged Album",
            trackNumberText: "04/12",
            discNumberText: "01/02",
            albumArtist: "Tagged Album Artist"
        )

        let fallback = MusicBrainzFilenameFallbackResolver.resolve(for: file)

        XCTAssertEqual(fallback.title, "Tagged Title")
        XCTAssertEqual(fallback.artist, "Tagged Artist")
        XCTAssertEqual(fallback.albumArtist, "Tagged Album Artist")
        XCTAssertEqual(fallback.album, "Tagged Album")
        XCTAssertEqual(fallback.trackNumber, "04/12")
        XCTAssertEqual(fallback.discNumber, "01/02")
    }
}
