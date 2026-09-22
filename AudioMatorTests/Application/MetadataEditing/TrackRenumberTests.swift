import XCTest
@testable import AudioMator

final class TrackRenumberTests: XCTestCase {
    func testPadWidthUsesAtLeastTwoDigitsWhenPaddingIsEnabled() {
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 1, padWithZeros: true), 2)
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 9, padWithZeros: true), 2)
    }

    func testPadWidthExpandsForLargerTrackCounts() {
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 100, padWithZeros: true), 3)
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: -1000, padWithZeros: true), 4)
    }

    func testPadWidthIsZeroWhenPaddingIsDisabled() {
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 100, padWithZeros: false), 0)
    }

    func testStartNumberNormalizationAndPadWidthHandleIntegerExtremes() {
        XCTAssertEqual(normalizedTrackRenumberStartNumber(Int.min), 0)
        XCTAssertEqual(
            normalizedTrackRenumberStartNumber(Int.max),
            maximumTrackRenumberStartNumber
        )
        XCTAssertEqual(
            trackRenumberPadWidth(maxNumber: Int.min, padWithZeros: true),
            String(Int.min.magnitude).count
        )
    }
}
