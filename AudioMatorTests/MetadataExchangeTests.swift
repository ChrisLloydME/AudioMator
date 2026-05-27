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

    func testDelimitedParserHandlesTabSeparatedMusicStyleExport() throws {
        let source = [
            "Name\tArtist\tComposer\tAlbum\tGrouping\tGenre\tDisc Number\tDisc Count\tTrack Number\tTrack Count\tYear\tComments",
            "Example Song\tExample Artist\tExample Composer\tExample Album\t\tPop\t1\t2\t3\t12\t2026\tExample Comment"
        ].joined(separator: "\r")

        XCTAssertEqual(
            try MetadataExchangeCSV.parse(source, delimiter: "\t"),
            [
                ["Name", "Artist", "Composer", "Album", "Grouping", "Genre", "Disc Number", "Disc Count", "Track Number", "Track Count", "Year", "Comments"],
                ["Example Song", "Example Artist", "Example Composer", "Example Album", "", "Pop", "1", "2", "3", "12", "2026", "Example Comment"]
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

        XCTAssertEqual(
            MetadataExchangeCSV.serialize([["Plain", "A\tB"]], delimiter: "\t"),
            "Plain\t\"A\tB\""
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

    func testCSVImportSupportsTabDelimitedTemplatesWithIgnoredColumns() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/example.m4a")
        )
        let template = [
            "{{title}}",
            "{{artist}}",
            "{{composer}}",
            "{{album}}",
            "{{_ignore}}",
            "{{genre}}",
            "{{discNumber}}",
            "{{_ignore}}",
            "{{trackNumber}}",
            "{{_ignore}}",
            "{{year}}",
            "{{comment}}"
        ].joined(separator: "\t")
        let source = [
            "Name\tArtist\tComposer\tAlbum\tGrouping\tGenre\tDisc Number\tDisc Count\tTrack Number\tTrack Count\tYear\tComments",
            "Example Song\tExample Artist\tExample Composer\tExample Album\t\tPop\t1\t2\t3\t12\t2026\tExample Comment"
        ].joined(separator: "\r")

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: template,
            sourceText: source,
            firstRowIsHeader: true,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows[0].status, .ready)
        let values = try XCTUnwrap(plan.rows[0].writeEntry?.values)
        XCTAssertEqual(values[.title], "Example Song")
        XCTAssertEqual(values[.artist], "Example Artist")
        XCTAssertEqual(values[.composer], "Example Composer")
        XCTAssertEqual(values[.album], "Example Album")
        XCTAssertEqual(values[.genre], "Pop")
        XCTAssertEqual(values[.discNumber], "1")
        XCTAssertEqual(values[.trackNumber], "3")
        XCTAssertEqual(values[.year], "2026")
        XCTAssertEqual(values[.comment], "Example Comment")
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
