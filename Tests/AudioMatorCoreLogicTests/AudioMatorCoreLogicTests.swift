import XCTest
@testable import AudioMatorCoreLogic

final class AudioMatorCoreLogicTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    func testAudioTagNumberTextParsesPaddedNumberAndOptionalTotal() {
        let components = AudioTagNumberText.components(from: " 003 / 012 ")

        XCTAssertEqual(components.number, "003")
        XCTAssertEqual(components.total, "012")
        let parsedPair = AudioTagNumberText.parsedPair(from: " 003 / 012 ")
        XCTAssertEqual(parsedPair.number, 3)
        XCTAssertEqual(parsedPair.total, 12)
        XCTAssertEqual(AudioTagNumberText.positiveIndex(from: "003/012"), 3)
        XCTAssertNil(AudioTagNumberText.positiveIndex(from: "000/012"))
    }

    func testAudioTagNumberPairPreservesUserFacingRawTextUntilCleared() {
        let pair = AudioTagNumberPair(rawText: " 04 / 11 ", number: 4, total: 11)

        XCTAssertEqual(pair.displayedNumberText, "04")
        XCTAssertEqual(pair.displayedTotalText, "11")
        XCTAssertEqual(pair.canonicalRawText, "04 / 11")
        XCTAssertEqual(pair.replacingNumberText("").canonicalRawText, "")
    }

    func testTextEditPipelineAppliesDeterministicOrderedTransforms() {
        let pipeline = TextEditPipeline(steps: [
            .trimEdges(.whitespacesAndNewlines),
            .replaceText(TextFindReplacement(findText: "demo", replacementText: "live")),
            .transformCase(.lowercase),
            .transformCase(.capitalizeFirstLetter),
            .insertText(" (2026)", position: .suffix)
        ])

        XCTAssertEqual(
            pipeline.applying(
                to: " DEMO QUIET STORM ",
                context: TextEditPipelineContext(locale: locale)
            ),
            "Live quiet storm (2026)"
        )
    }

    func testFindReplacementCanRespectWholeTextAndCaseSensitivity() {
        let wholeText = TextFindReplacement(
            findText: "mix",
            replacementText: "version",
            options: TextFindReplacementOptions(matchesCase: true, matchesWholeText: true)
        )

        XCTAssertEqual(wholeText.applied(to: "mix", locale: locale), "version")
        XCTAssertEqual(wholeText.applied(to: "Mix", locale: locale), "Mix")
        XCTAssertEqual(wholeText.applied(to: "radio mix", locale: locale), "radio mix")
    }

    func testLRCLIBQueryTreatsWhitespaceOnlyInputAsEmpty() {
        let query = LRCLIBSearchQuery(
            trackName: " \n ",
            artistName: "\t",
            albumName: " ",
            durationSeconds: 240
        )

        XCTAssertTrue(query.isEmpty)
    }

    func testLRCLIBRankerScoresExactSyncedDurationMatchHighest() {
        let query = LRCLIBSearchQuery(
            trackName: "Cafe del Mar",
            artistName: "Energy 52",
            albumName: "Classic Remixes",
            durationSeconds: 233
        )
        let ranked = LRCLIBCandidateRanker.rankedCandidates(
            [
                makeCandidate(id: 1, track: "Café del Mar", artist: "Energy 52", album: "Classic Remixes", duration: 233, syncedLyrics: "[00:01.00]Line"),
                makeCandidate(id: 2, track: "Cafe del Mar", artist: "Energy 52", album: "Classic Remixes", duration: 248, plainLyrics: "Line"),
                makeCandidate(id: 3, track: "Cafe", artist: "Other Artist", album: "Other", duration: 233, syncedLyrics: "[00:01.00]Line")
            ],
            for: query
        )

        XCTAssertEqual(ranked.map(\.id), [1, 2, 3])
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testLRCLIBRankerUsesSyncedLyricsAsTieBreaker() {
        let query = LRCLIBSearchQuery(
            trackName: "Track",
            artistName: "Artist",
            albumName: "Album",
            durationSeconds: 180
        )
        let ranked = LRCLIBCandidateRanker.rankedCandidates(
            [
                makeCandidate(id: 1, track: "Track", artist: "Artist", album: "Album", duration: 180, plainLyrics: "Line"),
                makeCandidate(id: 2, track: "Track", artist: "Artist", album: "Album", duration: 180, syncedLyrics: "[00:01.00]Line")
            ],
            for: query
        )

        XCTAssertEqual(ranked.map(\.id), [2, 1])
    }

    func testTrackRenumberPadWidthIsFastPurePolicy() {
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 9, padWithZeros: true), 2)
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 100, padWithZeros: true), 3)
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 100, padWithZeros: false), 0)
    }
}

private func makeCandidate(
    id: Int,
    track: String,
    artist: String,
    album: String,
    duration: Double?,
    plainLyrics: String? = nil,
    syncedLyrics: String? = nil,
    instrumental: Bool = false
) -> LRCLIBLyricsCandidate {
    LRCLIBLyricsCandidate(
        id: id,
        name: track,
        trackName: track,
        artistName: artist,
        albumName: album,
        duration: duration,
        instrumental: instrumental,
        plainLyrics: plainLyrics,
        syncedLyrics: syncedLyrics
    )
}
