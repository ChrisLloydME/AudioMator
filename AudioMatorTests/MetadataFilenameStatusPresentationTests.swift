import XCTest
@testable import AudioMator

final class MetadataFilenameStatusPresentationTests: XCTestCase {
    @MainActor
    func testToolStoreDeduplicatesTargetIdentifiersAndStartsANewPresentation() {
        let store = MetadataFilenameToolStore()
        let firstID = UUID()
        let secondID = UUID()
        let originalPresentationID = store.presentationID

        store.present(targetFileIDs: [firstID, secondID, firstID, secondID])

        XCTAssertEqual(store.targetFileIDs, [firstID, secondID])
        XCTAssertNotEqual(store.presentationID, originalPresentationID)
    }

    func testExternalTextLoaderDecodesUTF8AndUTF16ByteOrderMarks() throws {
        let utf8 = Data([0xEF, 0xBB, 0xBF]) + Data("Track – Title".utf8)
        XCTAssertEqual(try MetadataExchangeExternalTextFileLoader.decode(utf8), "Track – Title")

        let utf16LittleEndianData = try XCTUnwrap("曲名".data(using: .utf16LittleEndian))
        let utf16LittleEndian = Data([0xFF, 0xFE]) + utf16LittleEndianData
        XCTAssertEqual(try MetadataExchangeExternalTextFileLoader.decode(utf16LittleEndian), "曲名")

        let utf16BigEndianData = try XCTUnwrap("曲名".data(using: .utf16BigEndian))
        let utf16BigEndian = Data([0xFE, 0xFF]) + utf16BigEndianData
        XCTAssertEqual(try MetadataExchangeExternalTextFileLoader.decode(utf16BigEndian), "曲名")
    }

    func testExternalTextLoaderDetectsUTF16WithoutAByteOrderMark() throws {
        let littleEndian = try XCTUnwrap("Artist | Title".data(using: .utf16LittleEndian))
        XCTAssertEqual(try MetadataExchangeExternalTextFileLoader.decode(littleEndian), "Artist | Title")

        let bigEndian = try XCTUnwrap("Artist | Title".data(using: .utf16BigEndian))
        XCTAssertEqual(try MetadataExchangeExternalTextFileLoader.decode(bigEndian), "Artist | Title")
    }

    func testExternalTextLoaderSupportsLegacySingleByteText() throws {
        let windowsText = "Beyoncé | Déjà Vu"
        let windowsData = try XCTUnwrap(windowsText.data(using: .windowsCP1252))
        XCTAssertEqual(try MetadataExchangeExternalTextFileLoader.decode(windowsData), windowsText)
    }

    func testExternalTextLoaderRejectsBinaryControlData() {
        XCTAssertThrowsError(
            try MetadataExchangeExternalTextFileLoader.decode(Data([0x00]))
        ) { error in
            XCTAssertEqual(
                error as? MetadataExchangeExternalTextFileLoader.LoadingError,
                .unsupportedEncoding
            )
        }
    }

    func testExternalTextLoaderEnforcesItsReadLimit() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("metadata.txt")
        try Data("12345".utf8).write(to: fileURL)

        do {
            _ = try await MetadataExchangeExternalTextFileLoader.load(
                from: fileURL,
                maximumByteCount: 4
            )
            XCTFail("Expected an oversized file to be rejected.")
        } catch let error as MetadataExchangeExternalTextFileLoader.LoadingError {
            XCTAssertEqual(error, .tooLarge(maximumByteCount: 4))
        }
    }

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
