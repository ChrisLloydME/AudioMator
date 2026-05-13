import XCTest
@testable import AudioMator

final class FilenameMetadataTemplateTests: XCTestCase {
    func testFilenameMetadataPlanExtractsWritableFields() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/07 - Boards_of_Canada - Roygbiv.mp3")
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

    func testFilenameMetadataPlanRejectsAdjacentFields() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/ArtistTitle.mp3"))

        let plan = makeFilenameMetadataPlan(
            template: "{{artist}}{{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertNotNil(plan.validationMessage)
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }
}
