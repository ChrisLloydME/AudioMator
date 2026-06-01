import XCTest
@testable import AudioMator

final class FuzzyStringSimilarityTests: XCTestCase {
    func testNormalizeFoldsCaseDiacriticsWidthAndPunctuation() {
        let normalized = FuzzyStringSimilarity.normalize("  Café / ＤＥＬ—Mar!  ")

        XCTAssertEqual(normalized, "cafe del mar")
    }

    func testScorePreservesProviderMatchingThresholdSemantics() {
        XCTAssertEqual(FuzzyStringSimilarity.score("Beyoncé / JAY-Z", "beyonce jay z"), 1)
        XCTAssertEqual(FuzzyStringSimilarity.score("Roygbiv", "Boards of Canada Roygbiv"), 0.92)
        XCTAssertEqual(FuzzyStringSimilarity.score("", "Roygbiv"), 0)
        XCTAssertEqual(FuzzyStringSimilarity.score("Boats of Canada", "Boards of Canada"), 0.69375, accuracy: 0.00001)
        XCTAssertLessThan(FuzzyStringSimilarity.score("Roygbiv", "Telephasic Workshop"), 0.4)
    }

    func testTokenSequenceContainsOrderedTokenRunsOnly() {
        let value = FuzzyStringSimilarity.normalize("Track Title - 2026 Remaster")
        let sequence = FuzzyStringSimilarity.normalize("Title 2026")
        let reversedSequence = FuzzyStringSimilarity.normalize("2026 Title")

        XCTAssertTrue(FuzzyStringSimilarity.tokenSequenceContains(value, sequence: sequence))
        XCTAssertFalse(FuzzyStringSimilarity.tokenSequenceContains(value, sequence: reversedSequence))
    }
}
