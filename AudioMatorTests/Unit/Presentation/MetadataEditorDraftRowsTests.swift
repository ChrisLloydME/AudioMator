import XCTest
@testable import AudioMator

nonisolated final class MetadataEditorDraftRowsTests: XCTestCase {
    @MainActor
    func testMakeRowsSortsKeysAndMarksMixedValues() {
        let first = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.flac"))
        let second = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.flac"))
        let targets = [MetadataEditorTarget(file: first), MetadataEditorTarget(file: second)]

        let rows = MetadataEditorDraftRows.makeRows(
            targets: targets,
            draftPropertyMaps: [
                first.id: ["TITLE": ["One"], "ALBUM": ["Shared"]],
                second.id: ["TITLE": ["Two"], "ALBUM": ["Shared"], "ARTIST": ["Only Second"]]
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

    @MainActor
    func testFieldLabelsKeepRawKeysAndIndependentDateMeanings() throws {
        for ext in ["m4a", "flac"] {
            let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/example.\(ext)"))
            let rows = MetadataEditorDraftRows.makeRows(targets: [MetadataEditorTarget(file: file)], draftPropertyMaps: [
                file.id: ["DATE": ["2004"], "STANDALONEDATE": ["2017-06-09"], "ENCODING": ["Encoder"], "RELEASETIME": ["2018"], "CUSTOM": ["Keep"]]
            ])
            let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
            XCTAssertEqual(byKey["DATE"]?.displayName, ext == "flac" ? "Date" : "Year")
            XCTAssertEqual(byKey["STANDALONEDATE"]?.displayName, "Date")
            XCTAssertEqual(byKey["ENCODING"]?.displayName, "Encoder Settings")
            XCTAssertEqual(byKey["RELEASETIME"]?.displayName, "Release Date")
            XCTAssertEqual(byKey["CUSTOM"]?.displayName, "CUSTOM")
            XCTAssertEqual(byKey["DATE"]?.value, "2004")
            XCTAssertEqual(Set(byKey.keys), ["DATE", "STANDALONEDATE", "ENCODING", "RELEASETIME", "CUSTOM"])
        }
        XCTAssertEqual(MetadataFieldGuide.displayName(forRawKey: "DATE", fileExtensions: ["flac", "mp3"]), "Year / Date")
        XCTAssertEqual(MetadataFieldGuide.displayName(forRawKey: "PERFORMER:GUITAR"), "Performer (GUITAR)")
    }

    @MainActor
    func testSuggestionsUseSharedNamesPurposesAndSeparateDisplayFromStorage() throws {
        let suggestions = MetadataFieldSuggestion.allSupported
        let total = try XCTUnwrap(suggestions.first { $0.canonicalKey == "TRACKTOTAL" })
        XCTAssertEqual(total.displayName, "Total Tracks")
        XCTAssertEqual(total.detailText, total.purpose)
        XCTAssertFalse(total.detailText.contains(total.canonicalKey))
        XCTAssertTrue(total.detailText.contains("How many tracks"))
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "Date"), "STANDALONEDATE")
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "DATE"), "DATE")
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "Year"), "YEAR")
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "ALBUM ARTIST"), "ALBUM ARTIST")
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "Album Artist"), "ALBUMARTIST")
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "MY_CUSTOM"), "MY_CUSTOM")
        XCTAssertEqual(MetadataFieldSuggestion.resolvedKey(for: "  "), "")
    }

    @MainActor
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
