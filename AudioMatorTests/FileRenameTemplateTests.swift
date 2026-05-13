import XCTest
@testable import AudioMator

final class FileRenameTemplateTests: XCTestCase {
    func testTemplateParserSplitsLiteralsAndKnownFields() {
        let document = FileRenameTemplateDocument(rawValue: "{{trackNumber}} - {{artist}} - {{title}}")

        XCTAssertEqual(
            document.segments,
            [
                .field(.trackNumberText),
                .literal(" - "),
                .field(.artist),
                .literal(" - "),
                .field(.title)
            ]
        )
        XCTAssertTrue(document.containsFieldSegments)
    }

    func testUnknownPlaceholderRemainsLiteral() {
        let document = FileRenameTemplateDocument(rawValue: "{{artist}} - {{unknown}} - {{title}}")

        XCTAssertEqual(
            document.segments,
            [
                .field(.artist),
                .literal(" - {{unknown}} - "),
                .field(.title)
            ]
        )
    }

    func testRenamePlanSanitizesInvalidFilenameCharactersAndPreservesExtension() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/source.mp3"),
            title: "Track/Name: Mix",
            artist: "Artist"
        )

        let plan = makeFileRenamePlan(template: "{{artist}} - {{title}}", targetFiles: [file])

        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertEqual(plan.rows[0].previewName, "Artist - Track-Name- Mix.mp3")
        XCTAssertEqual(plan.rows[0].status, .ready)
        XCTAssertEqual(plan.operations.count, 1)
    }
}
