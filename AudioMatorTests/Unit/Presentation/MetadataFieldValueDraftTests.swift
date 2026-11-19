import XCTest
@testable import AudioMator

final class MetadataFieldValueDraftTests: XCTestCase {
    private func context(
        mode: MetadataFieldEditorMode,
        values: [String] = [],
        isMixed: Bool = false,
        emptyStartReason: MetadataFieldEmptyStartReason? = nil
    ) -> MetadataFieldEditorContext {
        MetadataFieldEditorContext(
            mode: mode,
            key: mode == .edit ? "LYRICS" : nil,
            values: values,
            targetIDs: [UUID()],
            beforeValuesByTarget: [:],
            selectedValueIndex: values.isEmpty ? nil : 0,
            isMixed: isMixed,
            presentationID: MetadataEditorPresentationID(),
            draftGeneration: 1,
            emptyStartReason: emptyStartReason
        )
    }

    func testUniformEditStartsWithExactOrderedElements() {
        let draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: ["Alpha", "Beta", ""]
        ))

        XCTAssertEqual(draft.values, ["Alpha", "Beta", ""])
        XCTAssertEqual(draft.elements.count, 3)
        XCTAssertEqual(draft.selectedElementIndex, 0)
        XCTAssertTrue(draft.canCommit)
        XCTAssertTrue(draft.isUnchangedConfirmation)
    }

    func testAddFieldStartsWithOneBlankElement() {
        let draft = MetadataFieldValueDraft(context: context(
            mode: .add,
            emptyStartReason: .newField
        ))

        XCTAssertEqual(draft.values, [""])
        XCTAssertEqual(draft.emptyStartReason, .newField)
        XCTAssertTrue(draft.canCommit)
        XCTAssertFalse(draft.isUnchangedConfirmation)
    }

    func testLastElementRemovalIsBlocked() {
        var draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: ["Only"]
        ))
        let onlyID = try? XCTUnwrap(draft.elements.first?.id)

        XCTAssertEqual(onlyID.map { draft.removeValue(id: $0) }, false)
        XCTAssertEqual(draft.values, ["Only"])
    }

    func testRemoveValueKeepsOrderAndSelectsNeighbor() throws {
        var draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: ["A", "B", "C"]
        ))
        let middle = try XCTUnwrap(draft.elements.dropFirst().first?.id)

        XCTAssertTrue(draft.removeValue(id: middle))
        XCTAssertEqual(draft.values, ["A", "C"])
        XCTAssertEqual(draft.selectedElementID, draft.elements.first?.id)
    }

    func testDuplicateElementsAreIndependentlyAddressable() throws {
        var draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: ["dup", "dup", ""]
        ))
        let secondID = try XCTUnwrap(draft.elements.dropFirst().first?.id)

        draft.setText("dup changed", for: secondID)

        XCTAssertEqual(draft.values, ["dup", "dup changed", ""])
        XCTAssertEqual(draft.text(for: draft.elements[0].id), "dup")

        XCTAssertTrue(draft.removeValue(id: draft.elements[0].id))
        XCTAssertEqual(draft.values, ["dup changed", ""])
    }

    func testMixedSelectionRequiresAnExplicitAddedValue() throws {
        let mixedContext = context(
            mode: .edit,
            isMixed: true,
            emptyStartReason: .mixedSelection
        )
        var draft = MetadataFieldValueDraft(context: mixedContext)

        XCTAssertEqual(draft.values, [])
        XCTAssertFalse(draft.canCommit)
        XCTAssertNil(draft.selectedElementID)

        draft.addValue()

        XCTAssertEqual(draft.values, [""])
        XCTAssertTrue(draft.canCommit)
        XCTAssertNil(draft.emptyStartReason)
    }

    func testExistingEmptyArrayIsOnlyAnUnchangedConfirmation() {
        var draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: [],
            emptyStartReason: .existingEmptyArray
        ))

        XCTAssertEqual(draft.values, [])
        XCTAssertTrue(draft.isUnchangedConfirmation)
        XCTAssertTrue(draft.canCommit, "Preserving an existing empty array is a no-op confirmation")

        draft.addValue(text: "Explicit")
        XCTAssertEqual(draft.values, ["Explicit"])
        XCTAssertFalse(draft.isUnchangedConfirmation)
        XCTAssertTrue(draft.canCommit)
    }

    func testMultilineElementStaysInsideOneElement() {
        let draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: ["line one\nline two"]
        ))

        XCTAssertEqual(draft.elements.count, 1)
        XCTAssertEqual(draft.values, ["line one\nline two"])
        XCTAssertTrue(draft.isUnchangedConfirmation)
    }

    func testReorderingByRemoveAndAddPreservesRequestedOrder() throws {
        var draft = MetadataFieldValueDraft(context: context(
            mode: .edit,
            values: ["B", "A"]
        ))
        let secondID = try XCTUnwrap(draft.elements.dropFirst().first?.id)
        XCTAssertTrue(draft.removeValue(id: secondID))
        draft.addValue(text: "C")

        XCTAssertEqual(draft.values, ["B", "C"])
        XCTAssertNotEqual(draft.values, ["C", "B"])
    }
}
