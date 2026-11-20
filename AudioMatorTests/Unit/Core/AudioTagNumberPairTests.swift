import XCTest
@testable import AudioMator

nonisolated final class AudioTagNumberPairTests: XCTestCase {
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

    @MainActor
    func testSharedNumberTextParserPreservesLegacyPairSemantics() {
        let components = AudioTagNumberText.components(from: " 03 / 12 ")
        let clampedComponents = AudioTagNumberText.components(from: "-1/9")

        XCTAssertEqual(components.number, "03")
        XCTAssertEqual(components.total, "12")
        XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: components.number), 3)
        XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: components.total ?? ""), 12)
        XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: clampedComponents.number), 0)
        XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: clampedComponents.total ?? ""), 9)
        XCTAssertEqual(AudioTagNumberText.positiveIndex(from: " 003 / 12 "), 3)
        XCTAssertNil(AudioTagNumberText.positiveIndex(from: "000"))
    }

    func testMakeParsesCombinedTextInsteadOfConcatenatingComponents() {
        let pair = AudioTagNumberPair.make(numberText: "1/2", totalText: "3/4")

        XCTAssertEqual(pair.number, 1)
        XCTAssertEqual(pair.total, 2)
        XCTAssertEqual(pair.rawText, "1/2")

        let totalOnly = AudioTagNumberPair.make(numberText: "", totalText: "12")
        XCTAssertEqual(totalOnly.number, 0)
        XCTAssertEqual(totalOnly.total, 12)
        XCTAssertEqual(totalOnly.rawText, "/12")
    }

    @MainActor
    func testReplacingNumberWithBlankPreservesTotal() {
        let pair = AudioTagNumberPair(rawText: "05/11", number: 5, total: 11)
            .replacingNumberText("")

        XCTAssertEqual(pair.number, 0)
        XCTAssertEqual(pair.total, 11)
        XCTAssertEqual(pair.canonicalRawText, "/11")
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testSingleFileEditCombinedFieldTextReplacesBothComponents() {
        var edit = SingleFileEditModel(
            track: 9,
            trackTotal: 12,
            disc: 9,
            discTotal: 12,
            trackNumberText: "9/12",
            discNumberText: "9/12"
        )

        edit.setTrackNumberFieldText("7/10")
        edit.setDiscNumberFieldText("2/3")

        XCTAssertEqual(edit.track, 7)
        XCTAssertEqual(edit.trackTotal, 10)
        XCTAssertEqual(edit.trackNumberText, "7/10")
        XCTAssertEqual(edit.disc, 2)
        XCTAssertEqual(edit.discTotal, 3)
        XCTAssertEqual(edit.discNumberText, "2/3")
    }

    @MainActor
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

    /// Pins the intentional difference between the loader's snapshot text rule
    /// (`AudioFile.normalizedNumberText`) and the Core pair's canonical text
    /// (`AudioTagNumberPair.canonicalRawText`). Both canonicalize pair text but
    /// with different rules; these exact current values must survive any future
    /// consolidation attempt (DOM-22 investigation).
    @MainActor
    func testSnapshotNumberTextDiffersFromCanonicalPairText() {
        // Total-only layout: the snapshot helper drops the empty number text,
        // while the pair canonicalizes it to "/12".
        XCTAssertEqual(AudioFile.normalizedNumberText(rawText: "", number: 0, total: 12), "")
        XCTAssertEqual(AudioTagNumberPair(rawText: "", number: 0, total: 12).canonicalRawText, "/12")

        // A stored total-only text that already carries the slash survives the
        // loader rule and agrees with the pair's canonical text.
        XCTAssertEqual(AudioFile.normalizedNumberText(rawText: "/12", number: 0, total: 12), "/12")
        XCTAssertEqual(AudioTagNumberPair(rawText: "/12", number: 0, total: 12).canonicalRawText, "/12")

        // Number text without a slash plus a positive total: the snapshot helper
        // appends "/total", while the pair preserves the stored raw text.
        XCTAssertEqual(AudioFile.normalizedNumberText(rawText: "07", number: 7, total: 12), "07/12")
        XCTAssertEqual(AudioTagNumberPair(rawText: "07", number: 7, total: 12).canonicalRawText, "07")

        // Both rules agree when the stored raw text is empty and a number exists,
        // and when no total exists to append.
        XCTAssertEqual(AudioFile.normalizedNumberText(rawText: "", number: 7, total: 12), "7/12")
        XCTAssertEqual(AudioTagNumberPair(rawText: "", number: 7, total: 12).canonicalRawText, "7/12")
        XCTAssertEqual(AudioFile.normalizedNumberText(rawText: "07", number: 7, total: 0), "07")
        XCTAssertEqual(AudioTagNumberPair(rawText: "07", number: 7, total: 0).canonicalRawText, "07")
    }
}
