import XCTest
@testable import AudioMator

final class MetadataExchangeTests: XCTestCase {
    func testTextImportSkipsBlankLinesAndPreservesRecordWhitespaceForMatching() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/track.mp3")
        )

        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "  {{title}}  ",
            sourceText: "\n  Quiet Storm  \n\n",
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertEqual(plan.rows[0].status, .ready)

        let values = try XCTUnwrap(plan.rows[0].writeEntry?.values)
        XCTAssertEqual(values[.title], "Quiet Storm")
    }

    func testTextImportRejectsAdjacentFields() {
        let file = AudioFileTestFactory.make()

        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{artist}}{{title}}",
            sourceText: "ArtistTitle",
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    func testTextImportMarksConflictingRepeatedCapturesAsParseError() {
        let file = AudioFileTestFactory.make()

        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{artist}} - {{artist}}",
            sourceText: "Boards of Canada - Aphex Twin",
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows[0].status, .parseError)
        XCTAssertNil(plan.rows[0].writeEntry)
    }

    func testCSVParserHandlesCommonValidForms() throws {
        XCTAssertEqual(
            try MetadataExchangeCSV.parse("\u{FEFF}Title,Artist\r\n\"A, B\",\"C\"\"D\"\n\"Line\nBreak\",Tail\rLast,"),
            [
                ["Title", "Artist"],
                ["A, B", "C\"D"],
                ["Line\nBreak", "Tail"],
                ["Last", ""]
            ]
        )
    }

    func testCSVParserHandlesEmptyInputAndTrailingEmptyFields() throws {
        XCTAssertEqual(try MetadataExchangeCSV.parse(""), [])
        XCTAssertEqual(try MetadataExchangeCSV.parse(","), [["", ""]])
        XCTAssertEqual(try MetadataExchangeCSV.parse("a,b,"), [["a", "b", ""]])
    }

    func testCSVParserRejectsMalformedQuotes() {
        XCTAssertThrowsError(try MetadataExchangeCSV.parse("\"unterminated"))
        XCTAssertThrowsError(try MetadataExchangeCSV.parse("a\"b,c"))
        XCTAssertThrowsError(try MetadataExchangeCSV.parse("\"a\"b,c"))
    }

    func testCSVSerializeEscapesSpecialValues() {
        XCTAssertEqual(
            MetadataExchangeCSV.serialize([["Plain", "A, B", "C\"D", "Line\nBreak"]]),
            "Plain,\"A, B\",\"C\"\"D\",\"Line\nBreak\""
        )
    }

    func testCSVImportRejectsEmptyAndHeaderOnlySources() {
        let file = AudioFileTestFactory.make()

        let emptyPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(emptyPlan.validationMessage)
        XCTAssertFalse(emptyPlan.canApply)

        let headerOnlyPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "Title\n",
            firstRowIsHeader: true,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(headerOnlyPlan.validationMessage)
        XCTAssertFalse(headerOnlyPlan.canApply)
    }

    func testCSVImportMarksMissingAndExtraColumnsAsParseErrors() {
        let file = AudioFileTestFactory.make()

        let missingPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}},{{artist}}",
            sourceText: "Quiet Storm",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNil(missingPlan.validationMessage)
        XCTAssertEqual(missingPlan.rows[0].status, .parseError)
        XCTAssertNil(missingPlan.rows[0].writeEntry)

        let extraPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "Quiet Storm,Extra",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNil(extraPlan.validationMessage)
        XCTAssertEqual(extraPlan.rows[0].status, .parseError)
        XCTAssertNil(extraPlan.rows[0].writeEntry)
    }

    func testCSVImportBlankCellsOnlyClearWhenEnabled() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/song.mp3"),
            title: "Existing"
        )

        let keepPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "song.mp3,",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(keepPlan.rows[0].status, .unchanged)
        XCTAssertNil(keepPlan.rows[0].writeEntry)

        let clearPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "song.mp3,",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: true
        )
        XCTAssertEqual(clearPlan.rows[0].status, .ready)
        let values = try XCTUnwrap(clearPlan.rows[0].writeEntry?.values)
        XCTAssertEqual(values[.title], "")
    }

    func testCSVImportMatchesFilenamesWithTrimCaseAndDiacriticNormalization() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/Café.mp3")
        )

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: " cafe.mp3 ,Quiet Storm",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows[0].status, .ready)
        let values = try XCTUnwrap(plan.rows[0].writeEntry?.values)
        XCTAssertEqual(values[.title], "Quiet Storm")
    }

    func testCSVImportMarksAmbiguousSelectedMatches() {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/Song.mp3")),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.mp3"))
        ]

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "SONG.MP3,Quiet Storm",
            firstRowIsHeader: false,
            targetFiles: files,
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows[0].status, .ambiguousMatch)
        XCTAssertNil(plan.rows[0].writeEntry)
    }

    func testCSVImportMarksNoMatchAndDuplicateExternalMatches() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.mp3"))

        let noMatchPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "other.mp3,Quiet Storm",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(noMatchPlan.rows[0].status, .noMatch)
        XCTAssertNil(noMatchPlan.rows[0].writeEntry)

        let duplicatePlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "song.mp3,First\nsong.mp3,Second",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(duplicatePlan.rows[0].status, .ready)
        XCTAssertEqual(duplicatePlan.rows[1].status, .ambiguousMatch)
        XCTAssertNil(duplicatePlan.rows[1].writeEntry)
    }
}
