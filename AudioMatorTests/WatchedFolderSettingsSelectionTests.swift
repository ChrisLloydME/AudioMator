import XCTest
@testable import AudioMator

#if os(macOS)
final class WatchedFolderSettingsSelectionTests: XCTestCase {
    func testSelectNewFoldersSelectsOnlyFoldersAddedByLatestEdit() {
        let existingID = UUID()
        let firstAddedID = UUID()
        let secondAddedID = UUID()
        var selection = WatchedFolderSettingsSelection(ids: [existingID])

        selection.selectNewFolders(
            previousIDs: [existingID],
            currentIDs: [existingID, firstAddedID, secondAddedID]
        )

        XCTAssertEqual(selection.ids, [firstAddedID, secondAddedID])
    }

    func testRetainAvailableFoldersDropsSelectionsRemovedElsewhere() {
        let retainedID = UUID()
        let removedID = UUID()
        var selection = WatchedFolderSettingsSelection(ids: [retainedID, removedID])

        selection.retainAvailableFolders([retainedID])

        XCTAssertEqual(selection.ids, [retainedID])
    }

    func testConsumeForRemovalReturnsAndClearsSelection() {
        let firstID = UUID()
        let secondID = UUID()
        var selection = WatchedFolderSettingsSelection(ids: [firstID, secondID])

        let removedIDs = selection.consumeForRemoval()

        XCTAssertEqual(removedIDs, [firstID, secondID])
        XCTAssertTrue(selection.ids.isEmpty)
    }
}
#endif
