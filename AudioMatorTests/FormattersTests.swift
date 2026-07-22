import XCTest
@testable import AudioMator

final class FormattersTests: XCTestCase {
    func testDurationFormatterRejectsInvalidAndOutOfRangeValues() {
        XCTAssertEqual(formatDuration(.nan), "00:00")
        XCTAssertEqual(formatDuration(.infinity), "00:00")
        XCTAssertEqual(formatDuration(.greatestFiniteMagnitude), "00:00")
        XCTAssertEqual(formatDuration(-1), "00:00")
    }

    func testDurationFormatterFloorsValidDuration() {
        XCTAssertEqual(formatDuration(125.9), "02:05")
        XCTAssertEqual(formatDuration(4_294_967_296), "71582788:16")
    }

    func testSampleRateFormatterRejectsInvalidAndOutOfRangeValues() {
        XCTAssertEqual(formatSampleRate(.nan), "")
        XCTAssertEqual(formatSampleRate(.infinity), "")
        XCTAssertEqual(formatSampleRate(.greatestFiniteMagnitude), "")
        XCTAssertEqual(formatSampleRate(0), "")
    }

    func testSampleRateFormatterRoundsValidValue() {
        XCTAssertEqual(formatSampleRate(44_100.4), "44100 Hz")
    }
}
