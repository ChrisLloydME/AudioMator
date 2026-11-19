import XCTest
@testable import AudioMator

@MainActor
final class ArtworkPreviewFallbackTests: XCTestCase {
    private let a1 = URL(string: "https://example.com/a-hires.jpg")!
    private let a2 = URL(string: "https://example.com/a-standard.jpg")!
    private let b1 = URL(string: "https://example.com/b-hires.jpg")!
    private let b2 = URL(string: "https://example.com/b-standard.jpg")!

    func testFallbackStartsAtFirstURLAndAdvancesOnlyForTheCurrentURL() {
        var fallback = ArtworkPreviewFallback(urls: [a1, a2])

        XCTAssertEqual(fallback.currentURL, a1)
        XCTAssertEqual(fallback.index, 0)
        XCTAssertTrue(fallback.hasSuccessor)

        // A delayed notification for another URL must not advance the fallback.
        XCTAssertFalse(fallback.advance(afterFailedURL: a2))
        XCTAssertEqual(fallback.currentURL, a1)

        XCTAssertTrue(fallback.advance(afterFailedURL: a1))
        XCTAssertEqual(fallback.currentURL, a2)
        XCTAssertEqual(fallback.index, 1)
        XCTAssertFalse(fallback.hasSuccessor)
    }

    func testCandidateSwitchStartsAtFirstURLForTheNewCandidate() {
        var candidateAFallback = ArtworkPreviewFallback(urls: [a1, a2])
        XCTAssertTrue(candidateAFallback.advance(afterFailedURL: a1))
        XCTAssertEqual(candidateAFallback.currentURL, a2)

        // A new candidate owns a fresh fallback (the selected preview is keyed by
        // candidate identity), so it starts at its first URL instead of inheriting
        // the previous candidate's index.
        let candidateBFallback = ArtworkPreviewFallback(urls: [b1, b2])
        XCTAssertEqual(candidateBFallback.currentURL, b1)
        XCTAssertEqual(candidateBFallback.index, 0)

        candidateAFallback.reset()
        XCTAssertEqual(candidateAFallback.currentURL, a1)
    }

    func testDelayedFailureOfPreviousCandidateCannotAdvanceNewCandidate() {
        var candidateBFallback = ArtworkPreviewFallback(urls: [b1, b2])
        XCTAssertEqual(candidateBFallback.currentURL, b1)

        // Candidate A's late failure carries a URL that the B fallback never
        // showed; it must be ignored and must not consume B's fallback chain.
        XCTAssertFalse(candidateBFallback.advance(afterFailedURL: a2))
        XCTAssertEqual(candidateBFallback.currentURL, b1)
        XCTAssertTrue(candidateBFallback.advance(afterFailedURL: b1))
        XCTAssertEqual(candidateBFallback.currentURL, b2)
    }

    func testLastURLFailureHasNoSuccessorAndDoesNotLoop() {
        var fallback = ArtworkPreviewFallback(urls: [a1, a2], index: 1)

        XCTAssertEqual(fallback.currentURL, a2)
        XCTAssertFalse(fallback.hasSuccessor)
        XCTAssertFalse(fallback.advance(afterFailedURL: a2))
        XCTAssertEqual(fallback.currentURL, a2)
        XCTAssertEqual(fallback.index, 1)
    }

    func testEmptyURLListHasNoCurrentURL() {
        var fallback = ArtworkPreviewFallback(urls: [])

        XCTAssertNil(fallback.currentURL)
        XCTAssertFalse(fallback.hasSuccessor)
        XCTAssertFalse(fallback.advance(afterFailedURL: a1))
    }

    func testFallbackPreservesPreferredPreviewURLOrder() {
        let hires = URL(string: "https://example.com/hires.jpg")!
        let uncompressed = URL(string: "https://example.com/uncompressed.jpg")!
        let standard = URL(string: "https://example.com/standard.jpg")!
        let thumbnail = URL(string: "https://example.com/thumbnail.jpg")!
        let result = iTunesArtworkSearchResult(
            id: "ordered",
            title: "Ordered Album",
            subtitle: nil,
            thumbnailURL: thumbnail,
            standardURL: standard,
            hiresURL: hires,
            uncompressedURL: uncompressed,
            pixelWidth: 600,
            pixelHeight: 600
        )

        let fallback = ArtworkPreviewFallback(urls: result.preferredPreviewURLs)

        XCTAssertEqual(fallback.urls, [hires, uncompressed, standard, thumbnail])
        XCTAssertEqual(fallback.currentURL, hires)
    }
}
