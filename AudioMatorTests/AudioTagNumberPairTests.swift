import XCTest
@testable import AudioMator

final class AudioTagNumberPairTests: XCTestCase {
    func testDisplayTextPrefersRawComponentsAndPreservesPadding() {
        let pair = AudioTagNumberPair(rawText: "  03 / 12  ", number: 3, total: 12)

        XCTAssertEqual(pair.displayedNumberText, "03")
        XCTAssertEqual(pair.displayedTotalText, "12")
        XCTAssertEqual(pair.canonicalRawText, "03 / 12")
    }

    func testDisplayTextFallsBackToNumericValuesWhenRawTextIsEmpty() {
        let pair = AudioTagNumberPair(rawText: "", number: 7, total: 14)

        XCTAssertEqual(pair.displayedNumberText, "7")
        XCTAssertEqual(pair.displayedTotalText, "14")
        XCTAssertEqual(pair.canonicalRawText, "7/14")
    }

    func testMakeParsesNumberAndTotalFromEditedText() {
        let pair = AudioTagNumberPair.make(numberText: " 08 ", totalText: " 10 ")

        XCTAssertEqual(pair.number, 8)
        XCTAssertEqual(pair.total, 10)
        XCTAssertEqual(pair.rawText, "08/10")
    }

    func testReplacingNumberWithBlankClearsThePair() {
        let pair = AudioTagNumberPair(rawText: "05/11", number: 5, total: 11)
            .replacingNumberText("")

        XCTAssertEqual(pair.number, 0)
        XCTAssertEqual(pair.total, 11)
        XCTAssertEqual(pair.canonicalRawText, "")
    }
}
