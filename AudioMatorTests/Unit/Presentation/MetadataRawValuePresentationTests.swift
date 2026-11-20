import XCTest
@testable import AudioMator

nonisolated final class MetadataRawValuePresentationTests: XCTestCase {
    @MainActor
    func testElementTextShowsEmbeddedLineBreakWithoutCreatingAnotherElement() {
        XCTAssertEqual(
            MetadataRawValueDisplay.elementText("line one\nline two"),
            "line one\u{23CE}\nline two"
        )
    }

    @MainActor
    func testCompactElementTextKeepsOneLineForListRows() {
        XCTAssertEqual(
            MetadataRawValueDisplay.compactElementText("line one\r\nline two\rline three"),
            "line one \u{23CE} line two \u{23CE} line three"
        )
    }

    @MainActor
    func testJoinedLabelIsDisplayOnlyAndPreservesElementOrder() {
        XCTAssertEqual(MetadataRawValueDisplay.joinedLabel(["Alpha", "Beta"]), "Alpha\nBeta")
        XCTAssertEqual(MetadataRawValueDisplay.joinedLabel([]), MetadataRawValueDisplay.noValuesPlaceholder)
    }

    @MainActor
    func testElementLabelUsesExplicitEmptyValuePlaceholder() {
        XCTAssertEqual(MetadataRawValueDisplay.elementLabel(""), MetadataRawValueDisplay.emptyValuePlaceholder)
        XCTAssertEqual(MetadataRawValueDisplay.elementLabel("A"), "A")
    }

    @MainActor
    func testDraftChangesDistinguishMissingKeyEmptyArrayAndBlankElement() {
        let targetID = UUID()
        let changes = MetadataEditorDraftChanges.changes(
            original: [targetID: ["MISSING_TO_EMPTY": ["x"], "BLANK": ["x"], "KEEP": ["same"]]],
            draft: [targetID: ["MISSING_TO_EMPTY": [], "BLANK": [""], "KEEP": ["same"], "NEW_KEY": []]],
            targetIDs: [targetID]
        )

        XCTAssertEqual(changes.map(\.key), ["BLANK", "MISSING_TO_EMPTY", "NEW_KEY"])
        XCTAssertEqual(
            changes.first { $0.key == "MISSING_TO_EMPTY" }?.afterValues,
            [],
            "An empty array is an existing key with no values, not a missing key"
        )
        XCTAssertEqual(changes.first { $0.key == "BLANK" }?.afterValues, [""])
        XCTAssertEqual(
            changes.first { $0.key == "NEW_KEY" }?.beforeValues,
            nil,
            "A missing key must remain distinguishable from an empty array"
        )
        XCTAssertFalse(changes.contains { $0.key == "KEEP" }, "Unchanged arrays never produce a change")
    }

    @MainActor
    func testDraftChangesEncodeDeleteFieldAsNilAfterValues() {
        let targetID = UUID()
        let changes = MetadataEditorDraftChanges.changes(
            original: [targetID: ["COMMENT": ["Delete me"]]],
            draft: [targetID: [:]],
            targetIDs: [targetID]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.key, "COMMENT")
        XCTAssertEqual(changes.first?.beforeValues, ["Delete me"])
        XCTAssertNil(changes.first?.afterValues)
    }

    @MainActor
    func testDraftChangesKeepReorderingAndDuplicatesAsChanges() {
        let targetID = UUID()
        let changes = MetadataEditorDraftChanges.changes(
            original: [targetID: ["GENRE": ["A", "B", "B"]]],
            draft: [targetID: ["GENRE": ["B", "A", "B"]]],
            targetIDs: [targetID]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.afterValues, ["B", "A", "B"])
        XCTAssertFalse(changes.first?.isNoOp == true)
    }
}
