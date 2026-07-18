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

    func testCSVDelimiterDetectionSupportsSemicolonPipeAndQuotedDelimiterNoise() {
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}};{{title}};{{artist}}"), ";")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}}|{{title}}|{{artist}}"), "|")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}}\t{{title}}\t{{artist}}"), "\t")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}},\"{{title}}; live\" ,{{artist}}"), ",")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{title}},{{artist}};{{album}}"), ",")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{title}}"), ",")
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

    func testCSVParserEnforcesStreamingRowColumnAndFieldLimits() {
        XCTAssertThrowsError(
            try MetadataExchangeCSV.parseFields("a\nb", maximumRowCount: 1)
        )
        XCTAssertThrowsError(
            try MetadataExchangeCSV.parseFields("a,b", maximumFieldCountPerRow: 1)
        )
        XCTAssertThrowsError(
            try MetadataExchangeCSV.parseFields("abcd", maximumFieldUTF8ByteCount: 3)
        )
    }

    func testCSVImportStillRejectsMalformedCommaCSVQuotes() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "song.flac,Room 404: \"Do Not Wake\"",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    func testPlainDelimitedImportsAllowLiteralQuotesInUnquotedFields() throws {
        for delimiter in ["\t", "|"] {
            let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))
            let plan = MetadataExchangePlanner.makeCSVImportPlan(
                template: ["{{fileName}}", "{{title}}"].joined(separator: delimiter),
                sourceText: ["song.flac", "Room 404: \"Do Not Wake\""].joined(separator: delimiter),
                firstRowIsHeader: false,
                targetFiles: [file],
                clearBlankImportedValues: false
            )

            XCTAssertNil(plan.validationMessage, delimiter)
            XCTAssertEqual(plan.rows.first?.status, .ready, delimiter)
            let values = try XCTUnwrap(plan.rows.first?.writeEntry?.values, delimiter)
            XCTAssertEqual(values[.title], "Room 404: \"Do Not Wake\"", delimiter)
        }
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

    func testCSVExportProtectsSpreadsheetFormulasAndRoundTripsOriginalValues() throws {
        let values = [
            "=HYPERLINK(\"https://example.invalid\")",
            "+1+1",
            "-2+3",
            "@SUM(A1:A2)",
            "\t=1+1",
            "'=literal",
            "plain"
        ]

        let serialized = MetadataExchangeCSV.serialize([values])
        XCTAssertFalse(serialized.hasPrefix("="))
        XCTAssertTrue(serialized.contains("'=HYPERLINK"))
        XCTAssertTrue(serialized.contains("''=literal"))
        XCTAssertEqual(try MetadataExchangeCSV.parse(serialized), [values])
        XCTAssertEqual(
            try MetadataExchangeCSV.parseFields(serialized).map { row in row.map(\.importedValue) },
            [values]
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
            "{{discTotal}}",
            "{{trackNumber}}",
            "{{trackTotal}}",
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
        XCTAssertEqual(values[.discTotal], "2")
        XCTAssertEqual(values[.trackNumber], "3")
        XCTAssertEqual(values[.trackTotal], "12")
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
        XCTAssertEqual(duplicatePlan.rows[0].status, .ambiguousMatch)
        XCTAssertEqual(duplicatePlan.rows[1].status, .ambiguousMatch)
        XCTAssertTrue(duplicatePlan.writeEntries.isEmpty)
        XCTAssertEqual(duplicatePlan.rows.last?.status, .missingExternalRecord)
    }

    func testTextImportPreservesInternalBlankRecordsWhenClearingIsEnabled() throws {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: "Old A"),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"), title: "Old B"),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/C.flac"), title: "Old C")
        ]

        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "New A\n\nNew C\n",
            targetFiles: files,
            clearBlankImportedValues: true
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.map(\.status), [.ready, .ready, .ready])
        XCTAssertEqual(plan.writeEntries.map { $0.values[.title] }, ["New A", "", "New C"])
    }

    func testTextImportRejectsAmbiguousAndPathologicalSeparatorMatches() {
        let file = AudioFileTestFactory.make()
        let ambiguous = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{artist}} - {{title}}",
            sourceText: "A - B - C",
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(ambiguous.rows.first?.status, .parseError)
        XCTAssertTrue(ambiguous.writeEntries.isEmpty)

        let pathological = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{artist}}-{{title}}",
            sourceText: String(repeating: "-", count: 4_098),
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(pathological.rows.first?.status, .parseError)
        XCTAssertTrue(pathological.writeEntries.isEmpty)
    }

    func testTextImportStripsByteOrderMarkBeforeFilenameMatching() throws {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{fileName}} | {{title}}",
            sourceText: "\u{FEFF}song.flac | Imported",
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.first?.status, .ready)
        XCTAssertEqual(try XCTUnwrap(plan.writeEntries.first?.values[.title]), "Imported")
    }

    func testTextTemplatesRejectUnknownUnterminatedAndMultilineFields() {
        let file = AudioFileTestFactory.make()

        for template in ["{{title}} | {{titel}}", "{{title", "{{title}}\n{{artist}}"] {
            let exportPlan = MetadataExchangePlanner.makeTextExportPlan(
                template: template,
                targetFiles: [file]
            )
            let importPlan = MetadataExchangePlanner.makeTextImportPlan(
                template: template,
                sourceText: "Value",
                targetFiles: [file],
                clearBlankImportedValues: false
            )

            XCTAssertNotNil(exportPlan.validationMessage, template)
            XCTAssertNotNil(importPlan.validationMessage, template)
        }
    }

    func testTextExportBlocksMetadataValuesContainingLineBreaks() {
        let file = AudioFileTestFactory.make(title: "Line One\r\nLine Two")
        let plan = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{title}}",
            targetFiles: [file]
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertFalse(plan.canExport)
        XCTAssertEqual(plan.rows.first?.output, "Line One\r\nLine Two")
    }

    func testTextExportRejectsAnOversizedRenderedRecord() {
        let file = AudioFileTestFactory.make(
            title: String(
                repeating: "a",
                count: MetadataExchangeResourceLimits.maximumTextRecordUTF8ByteCount + 1
            )
        )
        let plan = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{title}}",
            targetFiles: [file]
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canExport)
    }

    func testCSVImportMatchesReorderedRowsByIndex() throws {
        let first = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: "Old A")
        let second = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"), title: "Old B")
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{index}},{{title}}",
            sourceText: "2,New B\n1,New A",
            firstRowIsHeader: false,
            targetFiles: [first, second],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.map(\.fileID), [second.id, first.id])
        XCTAssertEqual(plan.writeEntries.map { $0.values[.title] }, ["New B", "New A"])
    }

    func testCSVImportIntersectsRelativePathToDisambiguateDuplicateNames() throws {
        let first = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/Library/Album/Disc 1/Song.flac"))
        let second = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/Library/Album/Disc 2/Song.flac"))
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{relativePath}},{{title}}",
            sourceText: "song.FLAC,Disc 2/Song.flac,New Two",
            firstRowIsHeader: false,
            targetFiles: [first, second],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.first?.fileID, second.id)
        XCTAssertEqual(try XCTUnwrap(plan.writeEntries.first?.values[.title]), "New Two")
        XCTAssertEqual(plan.rows.last?.fileID, first.id)
        XCTAssertEqual(plan.rows.last?.status, .missingExternalRecord)
    }

    func testPathLocatorsAreExactAndRelativePathsSurviveSubsetImports() throws {
        let upper = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/Library/Album/Disc 1/Song.flac")
        )

        let wrongCase = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{path}},{{title}}",
            sourceText: "/library/album/disc 1/song.flac,Wrong",
            firstRowIsHeader: false,
            targetFiles: [upper],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(wrongCase.rows.first?.status, .noMatch)
        XCTAssertTrue(wrongCase.writeEntries.isEmpty)

        let remoteURL = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{path}},{{title}}",
            sourceText: "file://example.com/Library/Album/Disc 1/Song.flac,Wrong",
            firstRowIsHeader: false,
            targetFiles: [upper],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(remoteURL.rows.first?.status, .noMatch)
        XCTAssertTrue(remoteURL.writeEntries.isEmpty)

        let subset = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{relativePath}},{{title}}",
            sourceText: "Disc 1/Song.flac,Right",
            firstRowIsHeader: false,
            targetFiles: [upper],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(subset.rows.first?.status, .ready)
        XCTAssertEqual(try XCTUnwrap(subset.writeEntries.first?.values[.title]), "Right")
    }

    func testCSVImportRejectsContradictoryMultipleLocators() {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac")),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"))
        ]
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{index}},{{title}}",
            sourceText: "A.flac,2,Wrong Target",
            firstRowIsHeader: false,
            targetFiles: files,
            clearBlankImportedValues: false
        )

        XCTAssertEqual(plan.rows.first?.status, .noMatch)
        XCTAssertTrue(plan.writeEntries.isEmpty)
    }

    func testCSVImportSupportsStructuredTotalsAndExpandedMetadataFields() throws {
        let fingerprint = AudioFileFingerprint(
            normalizedPath: "/tmp/song.flac",
            fileSize: 12,
            contentModificationDate: .distantPast,
            fileSystemNumber: 1,
            fileNumber: 2
        )
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/song.flac"),
            track: 9,
            trackTotal: 12,
            disc: 2,
            discTotal: 3,
            trackNumberText: "9/12",
            discNumberText: "2/3",
            fileFingerprint: fingerprint
        )
        let template = [
            "{{fileName}}", "{{trackNumber}}", "{{trackTotal}}", "{{discNumber}}",
            "{{discTotal}}", "{{isrc}}", "{{lyricist}}", "{{contentAdvisory}}"
        ].joined(separator: ",")
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: template,
            sourceText: "song.flac,2,10,1,2,USABC1234567,Writer,true",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        let entry = try XCTUnwrap(plan.writeEntries.first)
        XCTAssertEqual(entry.values[.trackNumber], "2")
        XCTAssertEqual(entry.values[.trackTotal], "10")
        XCTAssertEqual(entry.values[.discNumber], "1")
        XCTAssertEqual(entry.values[.discTotal], "2")
        XCTAssertEqual(entry.values[.isrc], "USABC1234567")
        XCTAssertEqual(entry.values[.lyricist], "Writer")
        XCTAssertEqual(entry.values[.contentAdvisory], "1")
        XCTAssertEqual(entry.expectedFileFingerprint, fingerprint)
    }

    func testStructuredNumberAndContentAdvisoryExportsAreRoundTripStable() {
        let file = AudioFileTestFactory.make(
            track: 9,
            trackTotal: 12,
            disc: 2,
            discTotal: 3,
            trackNumberText: "09/12",
            discNumberText: "02/03",
            contentAdvisory: .explicit
        )
        let plan = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{trackNumber}},{{trackTotal}},{{discNumber}},{{discTotal}},{{contentAdvisory}}",
            includeHeaderRow: false,
            targetFiles: [file]
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows, [["09", "12", "02", "03", "1"]])
    }

    func testCSVExportRejectsAFieldThatOwnImportLimitCouldNotRead() {
        let title = "=" + String(
            repeating: "a",
            count: MetadataExchangeResourceLimits.maximumCSVFieldUTF8ByteCount - 1
        )
        let file = AudioFileTestFactory.make(title: title)
        let plan = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{title}}",
            includeHeaderRow: false,
            targetFiles: [file]
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canExport)
    }

    func testCSVImportRejectsInvalidStructuredNumbersAndHeaderWidth() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))
        let invalidNumber = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{trackNumber}}",
            sourceText: "song.flac,-1",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(invalidNumber.rows.first?.status, .parseError)

        let invalidHeader = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}}",
            sourceText: "Only One Header\nsong.flac,Title",
            firstRowIsHeader: true,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(invalidHeader.validationMessage)
        XCTAssertTrue(invalidHeader.rows.isEmpty)
    }

    func testCSVImportCanClearAnExplicitlyBlankRow() throws {
        let file = AudioFileTestFactory.make(title: "Existing", artist: "Artist")
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}},{{artist}}",
            sourceText: ",",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: true
        )

        let values = try XCTUnwrap(plan.writeEntries.first?.values)
        XCTAssertEqual(values[.title], "")
        XCTAssertEqual(values[.artist], "")
    }

    func testExchangePlansDeduplicateRepeatedTargetIDs() {
        let file = AudioFileTestFactory.make(title: "Title")
        let exportPlan = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{title}}",
            targetFiles: [file, file]
        )
        let importPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "Imported",
            firstRowIsHeader: false,
            targetFiles: [file, file],
            clearBlankImportedValues: false
        )

        XCTAssertEqual(exportPlan.rows.count, 1)
        XCTAssertEqual(importPlan.writeEntries.count, 1)
    }
}
