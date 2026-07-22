import XCTest
@testable import AudioMator

final class FilenameMetadataTemplateTests: XCTestCase {
    func testFilenameMetadataPlanExtractsWritableFields() throws {
        let fingerprint = AudioFileFingerprint(
            normalizedPath: "/tmp/07 - Boards_of_Canada - Roygbiv.mp3",
            fileSize: 123,
            contentModificationDate: .distantPast,
            fileSystemNumber: 1,
            fileNumber: 2
        )
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/07 - Boards_of_Canada - Roygbiv.mp3"),
            fileFingerprint: fingerprint
        )

        let plan = makeFilenameMetadataPlan(
            template: "{{trackNumber}} - {{artist}} - {{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: true
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.readyCount, 1)
        XCTAssertEqual(plan.rows[0].status, .ready)

        let values = try XCTUnwrap(plan.rows[0].writeEntry?.values)
        XCTAssertEqual(values[.trackNumberText], "07")
        XCTAssertEqual(values[.artist], "Boards of Canada")
        XCTAssertEqual(values[.title], "Roygbiv")
        XCTAssertEqual(plan.rows[0].writeEntry?.expectedFileFingerprint, fingerprint)
    }

    func testFilenameMetadataPlanMarksUnchangedRows() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/01 - Artist - Existing Title.mp3"),
            title: "Existing Title",
            artist: "Artist",
            trackNumberText: "01"
        )

        let plan = makeFilenameMetadataPlan(
            template: "{{trackNumber}} - {{artist}} - {{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(plan.readyCount, 0)
        XCTAssertEqual(plan.unchangedCount, 1)
        XCTAssertEqual(plan.rows[0].status, .unchanged)
        XCTAssertNil(plan.rows[0].writeEntry)
    }

    func testFilenameMetadataPlanRejectsWritesWhenFileVersionIsUnavailable() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/unverified.mp3"),
            includeDefaultFileFingerprint: false
        )

        let plan = makeFilenameMetadataPlan(
            template: "{{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(plan.rows.first?.status, .sourceUnavailable)
        XCTAssertNil(plan.rows.first?.writeEntry)
        XCTAssertFalse(plan.canApply)
    }

    func testFilenameMetadataPlanRejectsAdjacentFields() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/ArtistTitle.mp3"))

        let plan = makeFilenameMetadataPlan(
            template: "{{artist}}{{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(
            plan.validationMessage,
            "Add literal separators between metadata fields so AudioMator can parse the filename unambiguously."
        )
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    func testFilenameMetadataPlanRejectsInvalidTemplates() {
        let file = AudioFileTestFactory.make()

        let templates = [
            ("{{titel}}", "{{titel}} is not a supported metadata field."),
            ("{{title", "Close every template field with }}.")
        ]
        for (template, expectedMessage) in templates {
            let plan = makeFilenameMetadataPlan(
                template: template,
                targetFiles: [file],
                replaceUnderscoresWithSpaces: false
            )
            XCTAssertEqual(plan.validationMessage, expectedMessage, String(template.prefix(20)))
            XCTAssertFalse(plan.canApply, String(template.prefix(20)))
        }
    }

    func testFilenameMetadataPlanRejectsOversizedTemplateForSizeReason() {
        let plan = makeFilenameMetadataPlan(
            template: String(repeating: "x", count: maximumFileRenameTemplateUTF8ByteCount + 1),
            targetFiles: [AudioFileTestFactory.make()],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(plan.validationMessage, "The filename template is too large.")
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    func testFilenameMetadataPlanRejectsAmbiguousFieldSplits() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/Boards - Aquarius - Version.mp3")
        )

        let plan = makeFilenameMetadataPlan(
            template: "{{artist}} - {{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(plan.readyCount, 0)
        XCTAssertEqual(plan.noMatchCount, 1)
        XCTAssertEqual(plan.rows.first?.status, .noMatch)
        XCTAssertNil(plan.rows.first?.writeEntry)
        XCTAssertFalse(plan.canApply)
    }
}
