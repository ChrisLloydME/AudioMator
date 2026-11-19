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

        let values = try XCTUnwrap(plan.rows[0].writeEntry?.previewValues)
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

        XCTAssertEqual(
            plan.validationMessage,
            "Add text between adjacent fields so AudioMator can tell their values apart."
        )
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    func testTextImportRejectsWritesWhenFileVersionIsUnavailable() {
        let file = AudioFileTestFactory.make(includeDefaultFileFingerprint: false)

        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "Imported Title",
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertEqual(plan.rows.first?.status, .sourceUnavailable)
        XCTAssertNil(plan.rows.first?.writeEntry)
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

    func testCSVColumnTemplateRejectsOversizedInputBeforeParsing() {
        let internalPadding = String(repeating: " ", count: 16_385)
        let result = MetadataExchangePlanner.parseCSVColumnTemplate(
            "{{title}}\(internalPadding),{{artist}}"
        )

        XCTAssertEqual(result.validationMessage, "This column template is too long. Shorten it before continuing.")
        XCTAssertTrue(result.columns.isEmpty)
        XCTAssertEqual(result.delimiter, ",")
    }

    func testCSVColumnTemplateAcceptsIntersectingLocatorsOnProductionPlanner() {
        let result = MetadataExchangePlanner.parseCSVColumnTemplate(
            "{{fileName}},{{baseName}},{{title}}"
        )

        XCTAssertNil(result.validationMessage)
        XCTAssertEqual(result.columns, [.fileName, .baseName, .title])
        XCTAssertEqual(result.delimiter, ",")
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

        XCTAssertEqual(plan.validationMessage, "A CSV cell contains a quote in the wrong place. Enclose the whole cell in quotes and write quotes inside it as two double quotes.")
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
            let values = try XCTUnwrap(plan.rows.first?.writeEntry?.previewValues, delimiter)
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
            "\u{00A0}=2+2",
            "'=literal",
            "''=A1",
            "'''=A1",
            "plain"
        ]

        let serialized = MetadataExchangeCSV.serialize([values])
        XCTAssertFalse(serialized.hasPrefix("="))
        XCTAssertTrue(serialized.contains("'=HYPERLINK"))
        XCTAssertTrue(serialized.contains("''=literal"))
        // Lexical parsing keeps the protection bytes; the marked-profile codec
        // reverses AudioMator's own export protection.
        let lexical = try MetadataExchangeCSV.parse(serialized)
        XCTAssertEqual(lexical.count, 1)
        XCTAssertEqual(lexical[0].count, values.count)
        XCTAssertEqual(lexical[0].first, "'=HYPERLINK(\"https://example.invalid\")")
        let codec = MetadataExchangeCSVCodec(profileVersion: 2)
        XCTAssertEqual(
            try MetadataExchangeCSV.parseFields(serialized).map { row in row.map(codec.importedValue) },
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
        XCTAssertEqual(emptyPlan.validationMessage, "Add at least one CSV data row to import.")
        XCTAssertFalse(emptyPlan.canApply)

        let headerOnlyPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "Title\n",
            firstRowIsHeader: true,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(headerOnlyPlan.validationMessage, "Add at least one CSV data row to import.")
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
            "Title\tArtist\tComposer\tAlbum\tGrouping\tGenre\tDisc Number\tTotal Discs\tTrack Number\tTotal Tracks\tYear\tComment",
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
        let values = try XCTUnwrap(plan.rows[0].writeEntry?.previewValues)
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

    func testCSVImportRejectsReorderedHeaderNames() throws {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{artist}},{{title}}",
            sourceText: "Title,Artist\nSong,Performer",
            firstRowIsHeader: true,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.rows.isEmpty)
    }

    func testCSVImportAcceptsCommonExternalHeaderAliasesWithoutRelaxingOrder() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{comment}},{{trackNumber}},{{discNumber}}",
            sourceText: "Name,Comments,Track #,Disc #\nsong.flac,Keep this,3,2",
            firstRowIsHeader: true, targetFiles: [file], clearBlankImportedValues: false)
        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.writeEntries.count, 1)
        XCTAssertEqual(plan.writeEntries.first?.previewValues[.comment], "Keep this")
        XCTAssertEqual(plan.writeEntries.first?.previewValues[.trackNumber], "3")
        XCTAssertEqual(plan.writeEntries.first?.previewValues[.discNumber], "2")
        let reordered = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{comment}},{{trackNumber}}", sourceText: "Track #,Comments\n3,Keep this",
            firstRowIsHeader: true, targetFiles: [file], clearBlankImportedValues: false)
        XCTAssertNotNil(reordered.validationMessage)
        XCTAssertTrue(reordered.writeEntries.isEmpty)
    }

    func testCSVImportAcceptsFieldKeysAsHeaders() throws {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/song.flac"))
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{artist}},{{title}}",
            sourceText: "ARTIST,TITLE\nPerformer,Song",
            firstRowIsHeader: true,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.writeEntries.first?.previewValues[.artist], "Performer")
        XCTAssertEqual(plan.writeEntries.first?.previewValues[.title], "Song")
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
        let values = try XCTUnwrap(clearPlan.rows[0].writeEntry?.previewValues)
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
        let values = try XCTUnwrap(plan.rows[0].writeEntry?.previewValues)
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
        XCTAssertEqual(plan.writeEntries.map { $0.previewValues[.title] }, ["New A", "", "New C"])
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
        XCTAssertEqual(try XCTUnwrap(plan.writeEntries.first?.previewValues[.title]), "Imported")
    }

    func testTextTemplatesRejectUnknownUnterminatedAndMultilineFields() {
        let file = AudioFileTestFactory.make()

        let templates = [
            ("{{title}} | {{titel}}", "“{{titel}}” isn't a supported field. Choose a field from the available list."),
            ("{{title", "A field is missing its closing }}. Complete it, for example {{title}}."),
            ("{{title}}\n{{artist}}", "Keep this template on one line. Use CSV for metadata that contains line breaks.")
        ]
        for (template, expectedMessage) in templates {
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

            XCTAssertEqual(exportPlan.validationMessage, expectedMessage, template)
            XCTAssertEqual(importPlan.validationMessage, expectedMessage, template)
        }
    }

    func testTextExportBlocksMetadataValuesContainingLineBreaks() {
        let file = AudioFileTestFactory.make(title: "Line One\r\nLine Two")
        let plan = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{title}}",
            targetFiles: [file]
        )

        XCTAssertEqual(
            plan.validationMessage,
            "Some values contain line breaks. Use CSV export to keep those values intact."
        )
        XCTAssertFalse(plan.canExport)
        XCTAssertEqual(plan.rows.first?.output, "Line One\r\nLine Two")
    }

    func testTextExportUsesSelectionIndexesAndRelativePathsOnProductionPlanner() {
        let files = [
            AudioFileTestFactory.make(
                url: URL(fileURLWithPath: "/Volumes/Library/Album/01.flac"),
                title: "One"
            ),
            AudioFileTestFactory.make(
                url: URL(fileURLWithPath: "/Volumes/Library/Album/02.flac"),
                title: "Two"
            )
        ]
        let plan = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{index}}|{{relativePath}}|{{title}}",
            targetFiles: files
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.map(\.output), ["1|01.flac|One", "2|02.flac|Two"])
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

        XCTAssertEqual(
            plan.validationMessage,
            "One exported record would exceed 256 KB. Use CSV export or shorten the values in that record."
        )
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
        XCTAssertEqual(plan.writeEntries.map { $0.previewValues[.title] }, ["New B", "New A"])
    }

    func testCSVImportIndexesLargeReorderedSelections() {
        let count = 1_000
        let files = (0..<count).map { index in
            let url = URL(fileURLWithPath: "/music/\(index).flac")
            return AudioFileTestFactory.make(id: UUID(), url: url, title: "Old")
        }
        let source = (1...count).reversed().map { "\($0),Title \($0)" }.joined(separator: "\n")

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{index}},{{title}}",
            sourceText: source,
            firstRowIsHeader: false,
            targetFiles: files,
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.readyCount, count)
        XCTAssertEqual(plan.rows.first?.fileID, files.last?.id)
        XCTAssertEqual(plan.rows.last?.fileID, files.first?.id)
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
        XCTAssertEqual(try XCTUnwrap(plan.writeEntries.first?.previewValues[.title]), "New Two")
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
        XCTAssertEqual(try XCTUnwrap(subset.writeEntries.first?.previewValues[.title]), "Right")
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
        XCTAssertEqual(entry.previewValues[.trackNumber], "2")
        XCTAssertEqual(entry.previewValues[.trackTotal], "10")
        XCTAssertEqual(entry.previewValues[.discNumber], "1")
        XCTAssertEqual(entry.previewValues[.discTotal], "2")
        XCTAssertEqual(entry.previewValues[.isrc], "USABC1234567")
        XCTAssertEqual(entry.previewValues[.lyricist], "Writer")
        XCTAssertEqual(entry.previewValues[.contentAdvisory], "1")
        XCTAssertEqual(entry.write.target.fingerprint, fingerprint)
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

        XCTAssertEqual(
            plan.validationMessage,
            "One CSV cell would exceed 1 MB. Shorten that field's value before exporting."
        )
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
        XCTAssertEqual(
            invalidHeader.validationMessage,
            "The CSV header and template have different column counts (1 and 2). Make them match before importing."
        )
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

        let values = try XCTUnwrap(plan.writeEntries.first?.previewValues)
        XCTAssertEqual(values[.title], "")
        XCTAssertEqual(values[.artist], "")
    }

    func testTextMarkedV2PreservesLeadingInteriorAndFinalEmptyRecords() {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: ""),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"), title: "Old B"),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/C.flac"), title: "")
        ]
        let export = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{title}}",
            targetFiles: files
        )
        XCTAssertEqual(export.outputText, "# AudioMator-Metadata-Profile: 2\n\nOld B\n")

        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: export.outputText,
            targetFiles: files,
            clearBlankImportedValues: false
        )
        XCTAssertNil(plan.validationMessage)
        XCTAssertNil(plan.blockingMessage)
        XCTAssertEqual(plan.rows.map(\.fileID), files.map(\.id))
        XCTAssertEqual(plan.rows.map(\.status), [.unchanged, .unchanged, .unchanged])
        XCTAssertTrue(plan.writeEntries.isEmpty)
    }

    func testTextUnmarkedLeadingBlankRecordDoesNotShiftLaterValues() {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: "Old A"),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"), title: "Old B")
        ]
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "\nOld B",
            targetFiles: files,
            clearBlankImportedValues: false
        )
        XCTAssertNil(plan.validationMessage)
        XCTAssertNil(plan.blockingMessage)
        XCTAssertEqual(plan.rows.map(\.fileID), files.map(\.id))
        XCTAssertEqual(plan.rows.map(\.status), [.unchanged, .unchanged])
        XCTAssertTrue(plan.writeEntries.isEmpty)
    }

    func testTextPositionalCountMismatchBlocksApplyBeforeAnyWrite() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/A.flac"),
            title: "Old A"
        )
        let marked = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "# AudioMator-Metadata-Profile: 2\nNew A\n",
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(marked.blockingMessage)
        XCTAssertTrue(marked.writeEntries.isEmpty)
        XCTAssertFalse(marked.canApply)
        XCTAssertEqual(marked.rows.first?.fileID, file.id)
        XCTAssertNil(marked.rows.first?.writeEntry)
        XCTAssertTrue(marked.rows.contains { $0.status == .extraExternalRecord })

        let tooManyLegacy = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "A-tag\n\n\n",
            targetFiles: [
                AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac")),
                AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"))
            ],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(tooManyLegacy.blockingMessage)
        XCTAssertTrue(tooManyLegacy.writeEntries.isEmpty)

        let incompleteMarker = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "# AudioMator-Metadata-Profile: 2",
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(incompleteMarker.validationMessage)
        XCTAssertTrue(incompleteMarker.rows.isEmpty)
    }

    func testTextLegacyTerminatorAndOneFilePaddingRules() {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: "Old A"),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"), title: "Old B")
        ]
        let terminalBlank = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "A-tag\n",
            targetFiles: files,
            clearBlankImportedValues: false
        )
        XCTAssertNil(terminalBlank.blockingMessage)
        XCTAssertEqual(terminalBlank.rows.map(\.status), [.ready, .unchanged])
        XCTAssertEqual(terminalBlank.writeEntries.map { $0.previewValues[.title] }, ["A-tag"])

        let trailingTerminator = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "A-tag\nB-tag\n",
            targetFiles: files,
            clearBlankImportedValues: false
        )
        XCTAssertNil(trailingTerminator.blockingMessage)
        XCTAssertEqual(trailingTerminator.writeEntries.map { $0.previewValues[.title] }, ["A-tag", "B-tag"])

        let single = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: "Old A")
        let padded = MetadataExchangePlanner.makeTextImportPlan(
            template: "  {{title}}  ",
            sourceText: "\n  Quiet Storm  \n\n",
            targetFiles: [single],
            clearBlankImportedValues: false
        )
        XCTAssertNil(padded.blockingMessage)
        XCTAssertEqual(padded.writeEntries.map { $0.previewValues[.title] }, ["Quiet Storm"])

        let blankSlot = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "\n",
            targetFiles: [single],
            clearBlankImportedValues: true
        )
        XCTAssertNil(blankSlot.blockingMessage)
        XCTAssertEqual(blankSlot.writeEntries.map { $0.previewValues[.title] }, [""])
    }

    func testTextBlankWithClearEnabledOnlyClearsCapturedFields() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/A.flac"),
            title: "Existing",
            artist: "Keep Artist"
        )
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "",
            targetFiles: [file],
            clearBlankImportedValues: true
        )
        // Empty unmarked input still has no records.
        XCTAssertNotNil(plan.validationMessage)

        let blankRecord = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "\n",
            targetFiles: [file],
            clearBlankImportedValues: true
        )
        let entry = blankRecord.writeEntries.first
        XCTAssertEqual(entry?.previewValues[.title], "")
        XCTAssertNil(entry?.previewValues[.artist])
    }

    func testCSVSoleEmptyCellRoundTrips() {
        let files = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: ""),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"), title: "Old B")
        ]
        let export = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{title}}",
            includeHeaderRow: false,
            targetFiles: files
        )
        XCTAssertNil(export.validationMessage)
        XCTAssertEqual(export.outputText, "# AudioMator-Metadata-Profile: 2\r\n\"\"\r\nOld B")

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: export.outputText,
            firstRowIsHeader: false,
            targetFiles: files,
            clearBlankImportedValues: false
        )
        XCTAssertNil(plan.validationMessage)
        XCTAssertNil(plan.blockingMessage)
        XCTAssertEqual(plan.rows.map(\.fileID), files.map(\.id))
        XCTAssertEqual(plan.rows.map(\.status), [.unchanged, .unchanged])
        XCTAssertTrue(plan.writeEntries.isEmpty)

        let single = [AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/A.flac"), title: "")]
        let singleExport = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{title}}", includeHeaderRow: false, targetFiles: single
        )
        XCTAssertEqual(singleExport.outputText, "# AudioMator-Metadata-Profile: 2\r\n\"\"")
        let singleImport = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}", sourceText: singleExport.outputText, firstRowIsHeader: false,
            targetFiles: single, clearBlankImportedValues: false
        )
        XCTAssertNil(singleImport.validationMessage)
        XCTAssertEqual(singleImport.rows.map(\.status), [.unchanged])
    }

    func testCSVPositionalCountMismatchBlocksApply() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/A.flac"),
            title: "Old A"
        )
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "New A\nNew B",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        XCTAssertNil(plan.validationMessage)
        XCTAssertNotNil(plan.blockingMessage)
        XCTAssertTrue(plan.writeEntries.isEmpty)
        XCTAssertFalse(plan.canApply)
        XCTAssertEqual(plan.rows.first?.fileID, file.id)
        XCTAssertNil(plan.rows.first?.writeEntry)
    }

    func testUnmarkedExternalCSVCellsKeepLiteralApostrophesAndLeadingEmptyCells() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/A.flac"),
            title: "Old",
            artist: "Old Artist"
        )
        let literalApostrophe = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: "'+44",
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(literalApostrophe.writeEntries.first).previewValues[.title], "'+44")

        let leadingEmpty = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}},{{artist}}",
            sourceText: ",New Artist",
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(leadingEmpty.writeEntries.first)
        XCTAssertEqual(entry.previewValues[.artist], "New Artist")
        XCTAssertNil(entry.previewValues[.title], "A leading empty cell stays an unchanged field, not a shifted one")
    }

    func testMarkedCSVReversesItsOwnSpreadsheetProtection() throws {
        let original = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/A.flac"),
            title: "=1+1"
        )
        let export = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{title}}",
            includeHeaderRow: false,
            targetFiles: [original]
        )
        XCTAssertTrue(export.outputText.contains("'=1+1"))
        let imported = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: export.outputText,
            firstRowIsHeader: false,
            targetFiles: [AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/B.flac"))],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(imported.writeEntries.first).previewValues[.title], "=1+1")
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
