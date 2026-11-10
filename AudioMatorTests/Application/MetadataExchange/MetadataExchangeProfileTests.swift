import XCTest
@testable import AudioMator

@MainActor
final class MetadataExchangeProfileTests: XCTestCase {
    private let fourDateTemplate = "{{year}},{{date}},{{releaseDate}},{{originalReleaseDate}}"
    private let fourDateHeader = "Year,Date,Release Date,Original Release Date"

    private func file() -> AudioFile {
        AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/exchange-date.flac"),
            year: "2004",
            date: "2008-03-04",
            releaseDate: "2017-06-09",
            originalReleaseDate: "1999-11-12"
        )
    }

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
        XCTAssertEqual(entry?.values[.year], "2004")
        XCTAssertEqual(entry?.values[.date], "2008-03-04")
        XCTAssertEqual(entry?.values[.releaseDate], "2017-06-09")
        XCTAssertEqual(entry?.values[.originalReleaseDate], "1999-11-12")

        // Preview values are the values the write path applies.
        var edit = SingleFileEditModel(from: blankTarget)
        for field in MetadataExchangeField.allCases {
            guard let value = entry?.values[field] else { continue }
            field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: true)
        }
        XCTAssertEqual(edit.year, "2004")
        XCTAssertEqual(edit.date, "2008-03-04")
        XCTAssertEqual(edit.releaseDate, "2017-06-09")
        XCTAssertEqual(edit.originalReleaseDate, "1999-11-12")
    }

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
        XCTAssertEqual(removalEntry.values[.date], MetadataExchangeProfile.removalSentinel)
        XCTAssertNil(removalEntry.values[.year], "Unchanged fields are not written")
        XCTAssertNil(removalEntry.values[.releaseDate])
        XCTAssertEqual(
            removalPlan.rows.first?.changes.first { $0.field == .date }?.displayImportedValue,
            "<remove>"
        )
        var removalEdit = SingleFileEditModel(from: target)
        for field in MetadataExchangeField.allCases {
            guard let value = removalEntry.values[field] else { continue }
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
        XCTAssertEqual(literalTextEntry.values[.title], "<remove>")

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
        XCTAssertNil(omittedEntry.values[.releaseDate])
    }

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
        XCTAssertEqual(yearEntry.values[.year], "2005")
        XCTAssertNil(yearEntry.values[.date])

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
        XCTAssertEqual(importPlan.writeEntries.first?.values[.year], "2004")
        XCTAssertEqual(importPlan.writeEntries.first?.values[.date], "2008-03-04")
        XCTAssertEqual(importPlan.writeEntries.first?.values[.releaseDate], "2017-06-09")
        XCTAssertEqual(importPlan.writeEntries.first?.values[.originalReleaseDate], "1999-11-12")
    }
}
