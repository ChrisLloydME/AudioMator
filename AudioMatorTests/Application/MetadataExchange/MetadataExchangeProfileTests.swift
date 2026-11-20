import XCTest
import TagLibAudioMetadata
@testable import AudioMator

nonisolated final class MetadataExchangeProfileTests: XCTestCase {
    private let fourDateTemplate = "{{year}},{{date}},{{releaseDate}},{{originalReleaseDate}}"
    private let fourDateHeader = "Year,Date,Release Date,Original Release Date"

    @MainActor
    private func file() -> AudioFile {
        AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/exchange-date.flac"),
            year: "2004",
            date: "2008-03-04",
            releaseDate: "2017-06-09",
            originalReleaseDate: "1999-11-12"
        )
    }

    @MainActor
    func testCSVExportCarriesProfileMarkerAndIndependentColumns() {
        let target = file()
        let plan = MetadataExchangePlanner.makeCSVExportPlan(
            template: fourDateTemplate,
            includeHeaderRow: true,
            targetFiles: [target]
        )
        XCTAssertNil(plan.validationMessage)
        XCTAssertTrue(plan.outputText.hasPrefix(MetadataExchangeProfile.markerLine() + "\r\n"))
        XCTAssertTrue(plan.outputText.contains("2004,2008-03-04,2017-06-09,1999-11-12"))
        XCTAssertTrue(plan.outputText.contains(fourDateHeader))
    }

    @MainActor
    func testVersionedCSVRoundTripsFourDatesAndPreviewMatchesWriteEntry() {
        let target = file()
        let blankTarget = AudioFileTestFactory.make(url: target.url)
        let export = MetadataExchangePlanner.makeCSVExportPlan(
            template: fourDateTemplate,
            includeHeaderRow: true,
            targetFiles: [target]
        )
        let extraction = MetadataExchangeProfile.extract(from: export.outputText)
        XCTAssertEqual(extraction.version, 2, "\(extraction.errorMessage ?? "") :: \(export.outputText.prefix(80))")
        let importPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: fourDateTemplate,
            sourceText: export.outputText,
            firstRowIsHeader: true,
            targetFiles: [blankTarget],
            clearBlankImportedValues: false
        )
        XCTAssertNil(importPlan.validationMessage)
        let entry = importPlan.writeEntries.first
        XCTAssertEqual(entry?.previewValues[.year], "2004")
        XCTAssertEqual(entry?.previewValues[.date], "2008-03-04")
        XCTAssertEqual(entry?.previewValues[.releaseDate], "2017-06-09")
        XCTAssertEqual(entry?.previewValues[.originalReleaseDate], "1999-11-12")

        // Preview values are the values the write path applies.
        var edit = SingleFileEditModel(from: blankTarget)
        for field in MetadataExchangeField.allCases {
            guard let value = entry?.previewValues[field] else { continue }
            field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: true)
        }
        XCTAssertEqual(edit.year, "2004")
        XCTAssertEqual(edit.date, "2008-03-04")
        XCTAssertEqual(edit.releaseDate, "2017-06-09")
        XCTAssertEqual(edit.originalReleaseDate, "1999-11-12")
    }

    @MainActor
    func testExplicitRemovalTokenIsDistinctFromOmittedAndLiteralText() throws {
        let target = file()
        let removalCSV = """
        \(MetadataExchangeProfile.markerLine())
        \(fourDateHeader)
        2004,<remove>,2017-06-09,1999-11-12
        """
        let removalPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: fourDateTemplate,
            sourceText: removalCSV,
            firstRowIsHeader: true,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertNil(removalPlan.validationMessage)
        let removalEntry = try XCTUnwrap(removalPlan.writeEntries.first)
        XCTAssertEqual(removalEntry.previewValues[.date], "")
        XCTAssertNil(removalEntry.previewValues[.year], "Unchanged fields are not written")
        XCTAssertNil(removalEntry.previewValues[.releaseDate])
        XCTAssertEqual(
            removalPlan.rows.first?.changes.first { $0.field == .date }?.displayImportedValue,
            "<remove>"
        )
        let removalOperations = removalEntry.resolvedIntent?.operations.filter { operation in
            if case .removeText = operation { return true }
            return false
        }
        XCTAssertEqual(removalOperations, [.removeText(.date)])
        XCTAssertEqual(removalEntry.frozenPayload?.requestedFields, [.standaloneDate])
        var removalEdit = SingleFileEditModel(from: target)
        for field in MetadataExchangeField.allCases {
            guard let value = removalEntry.previewValues[field] else { continue }
            field.applyImportedValue(value, to: &removalEdit, preservingNumberPairComponents: true)
        }
        XCTAssertEqual(removalEdit.date, "")
        XCTAssertEqual(removalEdit.year, "2004")

        let literalCSV = """
        \(MetadataExchangeProfile.markerLine())
        \(fourDateHeader)
        2004,"<remove>",2017-06-09,1999-11-12
        """
        let literalPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: fourDateTemplate,
            sourceText: literalCSV,
            firstRowIsHeader: true,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        // A quoted token is literal data, not a removal; as DATE text it is
        // invalid and must be rejected rather than clearing the field.
        XCTAssertTrue(literalPlan.writeEntries.isEmpty)
        XCTAssertNotNil(literalPlan.rows.first?.issueMessage)

        // The same quoted token is valid literal text for a text field.
        let literalTextCSV = """
        \(MetadataExchangeProfile.markerLine())
        Title
        "<remove>"
        """
        let literalTextPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: literalTextCSV,
            firstRowIsHeader: true,
            targetFiles: [AudioFileTestFactory.make(url: target.url, title: "Old Title")],
            clearBlankImportedValues: false
        )
        let literalTextEntry = try XCTUnwrap(literalTextPlan.writeEntries.first)
        XCTAssertEqual(literalTextEntry.previewValues[.title], "<remove>")

        // An omitted column (template without releaseDate) is unchanged, not a
        // removal.
        let omittedTemplate = "{{year}},{{date}},{{originalReleaseDate}}"
        let omittedCSV = """
        \(MetadataExchangeProfile.markerLine())
        Year,Date,Original Release Date
        2004,<remove>,1999-11-12
        """
        let omittedPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: omittedTemplate,
            sourceText: omittedCSV,
            firstRowIsHeader: true,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let omittedEntry = try XCTUnwrap(omittedPlan.writeEntries.first)
        XCTAssertNil(omittedEntry.previewValues[.releaseDate])
    }

    @MainActor
    func testUnknownProfileVersionIsRejectedBeforeAnyWrite() {
        let target = file()
        let futureCSV = """
        # AudioMator-Metadata-Profile: 99
        \(fourDateHeader)
        2004,2008-03-04,2017-06-09,1999-11-12
        """
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: fourDateTemplate,
            sourceText: futureCSV,
            firstRowIsHeader: true,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.validationMessage?.contains("newer") == true)
        XCTAssertTrue(plan.writeEntries.isEmpty)
    }

    @MainActor
    func testLegacyDATEHeaderKeepsYearMeaningAndIsNotStandaloneDate() throws {
        let target = file()
        let legacyCSV = """
        DATE
        2005
        """
        let yearPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{year}}",
            sourceText: legacyCSV,
            firstRowIsHeader: true,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let yearEntry = try XCTUnwrap(yearPlan.writeEntries.first)
        XCTAssertEqual(yearEntry.previewValues[.year], "2005")
        XCTAssertNil(yearEntry.previewValues[.date])

        let datePlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{date}}",
            sourceText: legacyCSV,
            firstRowIsHeader: true,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertNotNil(datePlan.validationMessage, "A legacy DATE header must not silently map to standalone Date")
        XCTAssertTrue(datePlan.writeEntries.isEmpty)
    }

    @MainActor
    func testCSVNumberRemovalResolvesOneComponentOnly() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac"),
            track: 3,
            trackTotal: 12,
            disc: 2,
            discTotal: 4,
            trackNumberText: "3/12",
            discNumberText: "2/4"
        )
        let csv = """
        \(MetadataExchangeProfile.markerLine())
        <remove>
        """
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}}",
            sourceText: csv,
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(plan.writeEntries.first)
        XCTAssertEqual(entry.previewValues[.trackNumber], "")
        XCTAssertEqual(entry.resolvedIntent?.operations, [.removeNumber(.trackNumber)])
        XCTAssertEqual(entry.frozenPayload?.requestedFields, [.track])
        XCTAssertEqual(entry.frozenProjection.requestedFields, [.track])
        let payload = try XCTUnwrap(entry.frozenPayload)
        XCTAssertEqual(
            try TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields,
            [.track: .remove]
        )
    }

    @MainActor
    func testTextV2NumberRemovalIsRecognizedBeforeNumericValidation() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac"),
            track: 3,
            trackTotal: 12,
            trackNumberText: "3/12"
        )
        let text = """
        \(MetadataExchangeProfile.markerLine())
        <remove>
        """
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{trackNumber}}",
            sourceText: text,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertNil(plan.validationMessage, "\(String(describing: plan.validationMessage))")
        let entry = try XCTUnwrap(plan.writeEntries.first)
        XCTAssertEqual(entry.frozenPayload?.requestedFields, [.track])
        XCTAssertEqual(plan.rows.first?.status, .ready)
    }

    @MainActor
    func testUnknownAdvisoryRemovalRequestsExplicitUnset() throws {
        // Seed a genuine unknown advisory raw value (170) whose semantic
        // contentAdvisory projection is nil so the test exercises
        // clearsUnknownAdvisory rather than a known .explicit value.
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/advisory.m4a"),
            contentAdvisory: nil,
            advisoryRawValue: "170"
        )
        let csv = """
        \(MetadataExchangeProfile.markerLine())
        <remove>
        """
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{contentAdvisory}}",
            sourceText: csv,
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(plan.writeEntries.first)
        XCTAssertEqual(entry.previewValues[.contentAdvisory], "")
        XCTAssertEqual(entry.resolvedIntent?.operations, [.removeText(.contentAdvisory)])
        XCTAssertEqual(entry.frozenPayload?.contentAdvisoryChanged, true)
        XCTAssertNil(entry.frozenPayload?.contentAdvisory)
        XCTAssertEqual(entry.frozenPayload?.requestedFields, [.explicitContent])
        XCTAssertEqual(plan.rows.first?.changes.first?.displayImportedValue, "<remove>")
    }

    @MainActor
    func testLiteralMatchingRetiredRemovalSentinelDisplaysLiterally() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/sentinel.flac"),
            title: "Before"
        )
        let sentinelLiteral = MetadataExchangeProfile.removalSentinel
        let csv = """
        \(MetadataExchangeProfile.markerLine())
        "\(sentinelLiteral)"
        """
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: csv,
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let change = try XCTUnwrap(plan.rows.first?.changes.first)
        XCTAssertFalse(change.isExplicitRemoval)
        XCTAssertEqual(change.displayImportedValue, sentinelLiteral)
        XCTAssertNotEqual(change.displayImportedValue, MetadataExchangeProfile.removalToken)
    }

    @MainActor
    func testLegacyUnmarkedTextDoesNotUnescapeBackslashRemovalToken() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/legacy.flac"),
            title: "Before"
        )
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "\\<remove>",
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(plan.writeEntries.first)
        XCTAssertEqual(entry.previewValues[.title], "\\<remove>")
        XCTAssertEqual(entry.frozenPayload?.title, "\\<remove>")
    }

    @MainActor
    func testExportBudgetsAccountForProfileMarkerBytes() {
        // Every budgeted text or CSV export must produce outputText within the
        // 32 MB import document limit, including the prepended profile marker.
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/budget.flac"),
            title: "Track"
        )
        let textPlan = MetadataExchangePlanner.makeTextExportPlan(template: "{{title}}", targetFiles: [file])
        XCTAssertNil(textPlan.validationMessage)
        XCTAssertLessThanOrEqual(
            textPlan.outputText.utf8.count,
            MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount
        )
        let csvPlan = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{title}}",
            includeHeaderRow: true,
            targetFiles: [file]
        )
        XCTAssertNil(csvPlan.validationMessage)
        XCTAssertLessThanOrEqual(
            csvPlan.outputText.utf8.count,
            MetadataExchangeResourceLimits.maximumDocumentUTF8ByteCount
        )
    }

    @MainActor
    func testNumberZeroAndSlashPairResolvePerComponent() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac"),
            track: 3,
            trackTotal: 12,
            disc: 2,
            discTotal: 4,
            trackNumberText: "3/12",
            discNumberText: "2/4"
        )

        let zeroPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}}", sourceText: "0", firstRowIsHeader: false,
            targetFiles: [target], clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(zeroPlan.writeEntries.first).frozenPayload?.requestedFields, [.track])

        let pairPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}}", sourceText: "4/12", firstRowIsHeader: false,
            targetFiles: [target], clearBlankImportedValues: false
        )
        let pairEntry = try XCTUnwrap(pairPlan.writeEntries.first)
        XCTAssertEqual(pairEntry.previewValues[.trackNumber], "4")
        XCTAssertEqual(pairEntry.previewValues[.trackTotal], "12")
        XCTAssertEqual(pairEntry.frozenPayload?.requestedFields, [.track])

        let totalOnlyPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackTotal}}", sourceText: "0", firstRowIsHeader: false,
            targetFiles: [target], clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(totalOnlyPlan.writeEntries.first).frozenPayload?.requestedFields, [.trackTotal])
    }

    @MainActor
    func testTotalColumnWinsOverEmbeddedTotalEvenWhenEqual() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac"),
            track: 3,
            trackTotal: 12,
            trackNumberText: "3/12"
        )
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}},{{trackTotal}}",
            sourceText: "4/9,12",
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(plan.writeEntries.first)
        XCTAssertEqual(entry.previewValues[.trackNumber], "4")
        XCTAssertEqual(entry.previewValues[.trackTotal], "12")
        XCTAssertEqual(entry.frozenPayload?.requestedFields, [.track], "Explicit total equal to the baseline must not write the embedded total")
    }

    @MainActor
    func testInvalidNumberSpellingsRejectWholeRow() {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac")
        )
        for source in ["-1", "2147483648", "/12", "3/", "1/2/3", "abc"] {
            let plan = MetadataExchangePlanner.makeCSVImportPlan(
                template: "{{title}},{{trackNumber}}",
                sourceText: "Title,\(source)",
                firstRowIsHeader: false,
                targetFiles: [target],
                clearBlankImportedValues: false
            )
            XCTAssertTrue(plan.writeEntries.isEmpty, source)
            XCTAssertEqual(plan.rows.first?.status, .parseError, source)
        }
        let mp4Target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.m4a")
        )
        let tooLarge = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}}", sourceText: "65536", firstRowIsHeader: false,
            targetFiles: [mp4Target], clearBlankImportedValues: false
        )
        XCTAssertTrue(tooLarge.writeEntries.isEmpty)
        XCTAssertEqual(tooLarge.rows.first?.status, .parseError)
    }

    @MainActor
    func testEscapedAndQuotedRemovalTokensRemainLiteral() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac"),
            title: "Keep"
        )
        let escapedText = """
        \(MetadataExchangeProfile.markerLine())
        \\<remove>
        """
        let textPlan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: escapedText,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(textPlan.writeEntries.first).previewValues[.title], "<remove>")

        let quotedCSV = """
        \(MetadataExchangeProfile.markerLine())
        "<remove>"
        """
        let csvPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}",
            sourceText: quotedCSV,
            firstRowIsHeader: false,
            targetFiles: [target],
            clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(csvPlan.writeEntries.first).previewValues[.title], "<remove>")
    }

    @MainActor
    func testMalformedRawNumberRemovalUsesExplicitComponentOperation() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/malformed.flac"),
            track: 0,
            trackTotal: 0,
            trackNumberText: "A1"
        )
        let csv = """
        \(MetadataExchangeProfile.markerLine())
        <remove>
        """
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{trackNumber}}",
            sourceText: csv,
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(plan.writeEntries.first)
        let payload = try XCTUnwrap(entry.frozenPayload)
        XCTAssertEqual(entry.resolvedIntent?.operations, [.removeNumber(.trackNumber)])
        XCTAssertEqual(payload.explicitComponentRemovals, [.track])
        XCTAssertEqual(payload.requestedFields, [.track])
        XCTAssertEqual(
            try TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields,
            [.track: .remove]
        )
    }

    @MainActor
    func testQuotedWhitespaceOnlyCellFollowsClearOption() throws {
        let target = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/numbers.flac"),
            title: "Existing"
        )
        let keep = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}", sourceText: "\"   \"", firstRowIsHeader: false,
            targetFiles: [target], clearBlankImportedValues: false
        )
        XCTAssertEqual(keep.rows.first?.status, .unchanged)
        XCTAssertTrue(keep.writeEntries.isEmpty)

        let clear = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}", sourceText: "\"   \"", firstRowIsHeader: false,
            targetFiles: [target], clearBlankImportedValues: true
        )
        XCTAssertEqual(clear.rows.first?.status, .ready)
        XCTAssertEqual(try XCTUnwrap(clear.writeEntries.first).previewValues[.title], "")
    }

    @MainActor
    func testTextExportAndImportCarryProfileMarkerAndIndependentDates() {
        let target = file()
        let blankTarget = AudioFileTestFactory.make(url: target.url)
        let template = "{{year}}|{{date}}|{{releaseDate}}|{{originalReleaseDate}}"
        let export = MetadataExchangePlanner.makeTextExportPlan(template: template, targetFiles: [target])
        XCTAssertTrue(export.outputText.hasPrefix(MetadataExchangeProfile.markerLine() + "\n"))

        let importPlan = MetadataExchangePlanner.makeTextImportPlan(
            template: template,
            sourceText: export.outputText,
            targetFiles: [blankTarget],
            clearBlankImportedValues: false
        )
        XCTAssertNil(importPlan.validationMessage)
        XCTAssertEqual(importPlan.writeEntries.first?.previewValues[.year], "2004")
        XCTAssertEqual(importPlan.writeEntries.first?.previewValues[.date], "2008-03-04")
        XCTAssertEqual(importPlan.writeEntries.first?.previewValues[.releaseDate], "2017-06-09")
        XCTAssertEqual(importPlan.writeEntries.first?.previewValues[.originalReleaseDate], "1999-11-12")
    }
}
