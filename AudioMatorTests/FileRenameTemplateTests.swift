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

    func testUnknownAndUnterminatedPlaceholdersAreReported() {
        let document = FileRenameTemplateDocument(rawValue: "{{artist}} - {{unknown}} - {{title}}")

        XCTAssertEqual(
            document.segments,
            [
                .field(.artist),
                .literal(" - {{unknown}} - "),
                .field(.title)
            ]
        )
        XCTAssertEqual(document.unknownPlaceholderNames, ["unknown"])
        XCTAssertFalse(document.hasUnterminatedPlaceholder)

        let unterminated = FileRenameTemplateDocument(rawValue: "{{artist}} - {{title")
        XCTAssertTrue(unterminated.hasUnterminatedPlaceholder)
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

    func testRenamePlanRejectsInvalidTemplatesAndOverlongNames() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/source.mp3"),
            title: String(repeating: "a", count: 253)
        )

        let unknown = makeFileRenamePlan(template: "{{titel}}", targetFiles: [file])
        XCTAssertNotNil(unknown.validationMessage)
        XCTAssertFalse(unknown.canApply)

        let oversizedTemplate = makeFileRenamePlan(
            template: String(repeating: "a", count: maximumFileRenameTemplateUTF8ByteCount + 1),
            targetFiles: [file]
        )
        XCTAssertNotNil(oversizedTemplate.validationMessage)
        XCTAssertFalse(oversizedTemplate.canApply)

        let overlongName = makeFileRenamePlan(template: "{{title}}", targetFiles: [file])
        XCTAssertEqual(overlongName.rows.first?.status, .nameTooLong)
        XCTAssertTrue(overlongName.operations.isEmpty)
        XCTAssertFalse(overlongName.canApply)
    }
}
