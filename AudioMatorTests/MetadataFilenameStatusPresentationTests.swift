import XCTest
@testable import AudioMator

final class MetadataFilenameStatusPresentationTests: XCTestCase {
    func testRenameMessagesPreserveReadyAndDuplicateTargetSummaries() {
        let readyFile = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/source.mp3"),
            title: "Renamed"
        )
        let readyPlan = makeFileRenamePlan(template: "{{title}}", targetFiles: [readyFile])

        XCTAssertEqual(
            MetadataFilenameStatusPresentation.renameMessage(
                targetCount: 1,
                template: "{{title}}",
                plan: readyPlan
            ),
            "1 file(s) will be renamed. File extensions stay the same."
        )

        let duplicatePlan = makeFileRenamePlan(
            template: "{{title}}",
            targetFiles: [
                AudioFileTestFactory.make(
                    url: URL(fileURLWithPath: "/tmp/one.mp3"),
                    title: "Duplicate"
                ),
                AudioFileTestFactory.make(
                    url: URL(fileURLWithPath: "/tmp/two.mp3"),
                    title: "Duplicate"
                )
            ]
        )

        XCTAssertEqual(
            MetadataFilenameStatusPresentation.renameMessage(
                targetCount: 2,
                template: "{{title}}",
                plan: duplicatePlan
            ),
            "0 file(s) are ready. 2 file(s) will be skipped: 2 duplicate target."
        )
    }

    func testFilenameMetadataMessagesPreserveReadyAndNoMatchSummaries() {
        let matchingFile = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/07 - Artist - Title.mp3")
        )
        let readyPlan = makeFilenameMetadataPlan(
            template: "{{trackNumber}} - {{artist}} - {{title}}",
            targetFiles: [matchingFile],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(
            MetadataFilenameStatusPresentation.filenameMetadataMessage(
                targetCount: 1,
                template: readyPlan.template,
                plan: readyPlan
            ),
            "1 file(s) will have metadata updated from their filenames."
        )

        let noMatchPlan = makeFilenameMetadataPlan(
            template: "{{trackNumber}} - {{artist}} - {{title}}",
            targetFiles: [AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/Unmatched.mp3"))],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(
            MetadataFilenameStatusPresentation.filenameMetadataMessage(
                targetCount: 1,
                template: noMatchPlan.template,
                plan: noMatchPlan
            ),
            "0 file(s) are ready. 1 file(s) could not be parsed: 1 no match."
        )
    }

    func testExchangeMessagesPreserveExportAndImportCounts() {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/song.flac"),
            title: "Song"
        )
        let exportPlan = MetadataExchangePlanner.makeTextExportPlan(
            template: "{{title}}",
            targetFiles: [file]
        )
        let importPlan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: "Imported Song",
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertEqual(
            MetadataFilenameStatusPresentation.textExportMessage(
                targetCount: 1,
                plan: exportPlan
            ),
            "1 line(s) will be exported."
        )
        XCTAssertEqual(
            MetadataFilenameStatusPresentation.importMessage(
                targetCount: 1,
                plan: importPlan
            ),
            "1 file(s) will have metadata updated."
        )
    }
}
