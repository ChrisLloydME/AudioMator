import XCTest
@testable import AudioMator

nonisolated final class FilenameMetadataTemplateTests: XCTestCase {
    @MainActor
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

        let values = try XCTUnwrap(plan.rows[0].writeEntry?.previewValues)
        XCTAssertEqual(values[.trackNumberText], "07")
        XCTAssertEqual(values[.artist], "Boards of Canada")
        XCTAssertEqual(values[.title], "Roygbiv")
        XCTAssertEqual(plan.rows[0].writeEntry?.write.target.fingerprint, fingerprint)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    func testFilenameMetadataPlanRejectsAdjacentFields() {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/ArtistTitle.mp3"))

        let plan = makeFilenameMetadataPlan(
            template: "{{artist}}{{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(
            plan.validationMessage,
            "Add text between adjacent fields so AudioMator can tell where each value starts and ends."
        )
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    @MainActor
    func testFilenameMetadataPlanRejectsInvalidTemplates() {
        let file = AudioFileTestFactory.make()

        let templates = [
            ("{{titel}}", "“{{titel}}” isn't a supported field. Choose a field from the available list."),
            ("{{title", "A field is missing its closing }}. Complete it, for example {{title}}.")
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

    @MainActor
    func testFilenameMetadataPlanRejectsOversizedTemplateForSizeReason() {
        let plan = makeFilenameMetadataPlan(
            template: String(repeating: "x", count: maximumFileRenameTemplateUTF8ByteCount + 1),
            targetFiles: [AudioFileTestFactory.make()],
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertEqual(plan.validationMessage, "This filename template is too long. Shorten it before continuing.")
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    @MainActor
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

    /// Pins the deliberate projection difference between the two rename
    /// directions for a file whose numeric pair is populated but whose stored
    /// number text is empty. Filename→metadata change detection compares the
    /// stored raw text (conservatively treating the extracted number as a
    /// change), while metadata→filename rendering falls back to the numeric
    /// pair. This is an intentional conservative raw-text comparison, not
    /// display parity; do not "fix" one side to mirror the other without a
    /// product decision.
    @MainActor
    func testFilenameComparisonUsesStoredRawNumberTextWhileRenameRenderingUsesNumericPair() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/07 - Song.mp3"),
            title: "Song",
            track: 7,
            trackTotal: 12,
            trackNumberText: "",
            discNumberText: ""
        )

        let extractionPlan = makeFilenameMetadataPlan(
            template: "{{trackNumber}} - {{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false
        )
        XCTAssertNil(extractionPlan.validationMessage)
        XCTAssertEqual(extractionPlan.rows.first?.status, .ready)
        let numberChange = try XCTUnwrap(
            extractionPlan.rows.first?.changes.first { $0.field == .trackNumberText }
        )
        XCTAssertEqual(numberChange.currentValue, "", "Change detection compares the stored raw text, not the pair")
        XCTAssertEqual(numberChange.extractedValue, "07")
        XCTAssertEqual(numberChange.status, .different)
        XCTAssertTrue(numberChange.willWrite)
        XCTAssertEqual(extractionPlan.rows.first?.writeEntry?.previewValues[.trackNumberText], "07")

        let renamePlan = makeFileRenamePlan(
            template: "{{trackNumber}} - {{title}}",
            targetFiles: [file]
        )
        XCTAssertNil(renamePlan.validationMessage)
        XCTAssertEqual(renamePlan.rows.first?.status, .ready)
        XCTAssertEqual(
            renamePlan.rows.first?.previewName, "7-12 - Song.mp3",
            "Rendering falls back to the numeric pair when the stored number text is empty"
        )
        XCTAssertEqual(renamePlan.operations.count, 1)
    }
}
