import XCTest
@testable import AudioMator

final class MetadataEditorDraftRowsTests: XCTestCase {
    func testMakeRowsSortsKeysAndMarksMixedValues() {
        let first = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.flac"))
        let second = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.flac"))
        let targets = [MetadataEditorTarget(file: first), MetadataEditorTarget(file: second)]

        let rows = MetadataEditorDraftRows.makeRows(
            targets: targets,
            draftPropertyMaps: [
                first.id: ["TITLE": "One", "ALBUM": "Shared"],
                second.id: ["TITLE": "Two", "ALBUM": "Shared", "ARTIST": "Only Second"]
            ]
        )

        XCTAssertEqual(rows.map(\.key), ["ALBUM", "ARTIST", "TITLE"])
        XCTAssertEqual(rows[0].value, "Shared")
        XCTAssertFalse(rows[0].isMixed)
        XCTAssertEqual(rows[1].value, "Only Second")
        XCTAssertTrue(rows[1].isMixed)
        XCTAssertEqual(rows[1].displayValue, "Multiple Values")
        XCTAssertEqual(rows[2].value, "One")
        XCTAssertTrue(rows[2].isMixed)
    }

    func testRealignedSelectionKeepsValidSelectionBeforePreferredOrFirstRow() {
        let rows = [
            MetadataEditorRow(key: "ALBUM", value: "Album", isMixed: false),
            MetadataEditorRow(key: "TITLE", value: "Title", isMixed: false)
        ]

        XCTAssertEqual(
            MetadataEditorDraftRows.realignedSelection(
                currentSelection: ["TITLE", "MISSING"],
                preferred: "ALBUM",
                rows: rows
            ),
            ["TITLE"]
        )

        XCTAssertEqual(
            MetadataEditorDraftRows.realignedSelection(
                currentSelection: ["MISSING"],
                preferred: "ALBUM",
                rows: rows
            ),
            ["ALBUM"]
        )

        XCTAssertEqual(
            MetadataEditorDraftRows.realignedSelection(
                currentSelection: [],
                preferred: nil,
                rows: rows
            ),
            ["ALBUM"]
        )

        XCTAssertEqual(
            MetadataEditorDraftRows.realignedSelection(
                currentSelection: ["MISSING"],
                preferred: nil,
                rows: []
            ),
            []
        )
    }
}
