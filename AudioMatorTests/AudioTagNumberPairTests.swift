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

    func testSharedNumberTextParserPreservesLegacyPairSemantics() {
        let parsedPair = AudioTagNumberText.parsedPair(from: " 03 / 12 ")
        let clampedPair = AudioTagNumberText.parsedPair(from: "-1/9")

        XCTAssertEqual(AudioTagNumberText.components(from: " 03 / 12 ").number, "03")
        XCTAssertEqual(AudioTagNumberText.components(from: " 03 / 12 ").total, "12")
        XCTAssertEqual(parsedPair.number, 3)
        XCTAssertEqual(parsedPair.total, 12)
        XCTAssertEqual(clampedPair.number, 0)
        XCTAssertEqual(clampedPair.total, 9)
        XCTAssertEqual(AudioTagNumberText.positiveIndex(from: " 003 / 12 "), 3)
        XCTAssertNil(AudioTagNumberText.positiveIndex(from: "000"))
    }

    func testMakeKeepsIndividualNumberFieldsStrictlyNumeric() {
        let pair = AudioTagNumberPair.make(numberText: "1/2", totalText: "3/4")

        XCTAssertEqual(pair.number, 0)
        XCTAssertEqual(pair.total, 0)
        XCTAssertEqual(pair.rawText, "1/2/3/4")
    }

    func testReplacingNumberWithBlankClearsThePair() {
        let pair = AudioTagNumberPair(rawText: "05/11", number: 5, total: 11)
            .replacingNumberText("")

        XCTAssertEqual(pair.number, 0)
        XCTAssertEqual(pair.total, 11)
        XCTAssertEqual(pair.canonicalRawText, "")
    }

    func testWriteExpectationWithoutTotalAcceptsPreservedTotal() {
        XCTAssertTrue(
            AudioTagNumberText.writeExpectationMatches(
                expectedText: "07",
                actualNumber: 7,
                actualTotal: 12
            )
        )
        XCTAssertFalse(
            AudioTagNumberText.writeExpectationMatches(
                expectedText: "07/10",
                actualNumber: 7,
                actualTotal: 12
            )
        )
        XCTAssertFalse(
            AudioTagNumberText.writeExpectationMatches(
                expectedText: "07",
                actualNumber: 8,
                actualTotal: 12
            )
        )
    }

    func testSingleFileEditNumberTextWithSlashReplacesNumberAndTotal() {
        var edit = SingleFileEditModel(
            track: 9,
            trackTotal: 12,
            disc: 9,
            discTotal: 12,
            trackNumberText: "9/12",
            discNumberText: "9/12"
        )

        edit.setTrackNumberText("2/3")
        edit.setDiscNumberText("2/3")

        XCTAssertEqual(edit.track, 2)
        XCTAssertEqual(edit.trackTotal, 3)
        XCTAssertEqual(edit.trackNumberText, "2/3")
        XCTAssertEqual(edit.disc, 2)
        XCTAssertEqual(edit.discTotal, 3)
        XCTAssertEqual(edit.discNumberText, "2/3")
    }

    func testSingleFileEditBlankNumberTextClearsNumberAndTotal() {
        var edit = SingleFileEditModel(
            track: 9,
            trackTotal: 12,
            disc: 9,
            discTotal: 12,
            trackNumberText: "9/12",
            discNumberText: "9/12"
        )

        edit.setTrackNumberText("  \n")
        edit.setDiscNumberText("")

        XCTAssertEqual(edit.track, 0)
        XCTAssertEqual(edit.trackTotal, 0)
        XCTAssertEqual(edit.trackNumberText, "")
        XCTAssertEqual(edit.disc, 0)
        XCTAssertEqual(edit.discTotal, 0)
        XCTAssertEqual(edit.discNumberText, "")
    }

    func testSingleFileEditNumberOnlyTextPreservesTotalAndFormatting() {
        var edit = SingleFileEditModel(
            track: 9,
            trackTotal: 12,
            disc: 4,
            discTotal: 5,
            trackNumberText: "9/12",
            discNumberText: "4/5"
        )

        edit.setTrackNumberText(" 02 ")
        edit.setDiscNumberText("03")

        XCTAssertEqual(edit.track, 2)
        XCTAssertEqual(edit.trackTotal, 12)
        XCTAssertEqual(edit.trackNumberText, "02")
        XCTAssertEqual(edit.disc, 3)
        XCTAssertEqual(edit.discTotal, 5)
        XCTAssertEqual(edit.discNumberText, "03")
    }
}
