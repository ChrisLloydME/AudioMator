import AppKit
import SwiftUI
import XCTest
@testable import AudioMator

@MainActor
final class MiddleListSelectionTests: XCTestCase {
    func testOrderingCacheSurvivesSelectionAndInvalidatesForSortManualOrderAndReload() {
        let state = SharedState()
        let previousSort = state.middleListSort
        defer { state.middleListSort = previousSort }
        state.middleListSort = nil
        let first = makeFile(title: "Zulu")
        let second = makeFile(title: "Alpha")
        let files = [first, second]
        let revision = UUID()
        let initial = state.middleListPresentation(from: files, revision: revision)
        XCTAssertEqual(state.middleListPresentation(from: files, revision: revision).revision, initial.revision)

        state.customOrder = [second.id, first.id]
        let manual = state.middleListPresentation(from: files, revision: revision)
        XCTAssertNotEqual(manual.revision, initial.revision)
        XCTAssertEqual(manual.files.map(\.id), [second.id, first.id])

        state.middleListSort = MiddleListSort(column: .title, ascending: false)
        let sorted = state.middleListPresentation(from: files, revision: revision)
        XCTAssertEqual(sorted.files.map(\.id), [first.id, second.id])
        XCTAssertNotEqual(sorted.revision, manual.revision)

        let reloaded = AudioFileTestFactory.make(id: first.id, url: first.url, title: "Aardvark")
        let refreshed = state.middleListPresentation(from: [reloaded, second], revision: UUID())
        XCTAssertEqual(refreshed.files.map(\.id), [second.id, first.id])
        XCTAssertEqual(refreshed.files.last?.title, "Aardvark")
        XCTAssertNotEqual(refreshed.revision, sorted.revision)
    }

    func testNativeSelectionAndRejectedDraftDiscardStayInSync() throws {
        let files = [makeFile(title: "First"), makeFile(title: "Second")]
        let bindings = TableBindings()
        let parent = makeTable(files: files, bindings: bindings)
        let coordinator = parent.makeCoordinator()
        let scrollView = coordinator.makeScrollView()
        coordinator.update(parent: parent, scrollView: scrollView)
        let table = try XCTUnwrap(scrollView.documentView as? NSTableView)

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        XCTAssertEqual(bindings.selection, [files[0].id])

        bindings.rejectSelection = true
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        coordinator.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        XCTAssertEqual(bindings.selection, [files[0].id])
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))

        bindings.rejectSelection = false
        bindings.selection = Set(files.map(\.id))
        coordinator.update(parent: parent, scrollView: scrollView)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integersIn: 0..<2))
    }

    func testReorderReloadColumnChangeAndRemovalPreserveIDSelection() throws {
        let first = makeFile(title: "First")
        let second = makeFile(title: "Second")
        let bindings = TableBindings()
        bindings.selection = [second.id]
        var parent = makeTable(files: [first, second], bindings: bindings)
        let coordinator = parent.makeCoordinator()
        let scrollView = coordinator.makeScrollView()
        coordinator.update(parent: parent, scrollView: scrollView)
        let table = try XCTUnwrap(scrollView.documentView as? NSTableView)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))

        parent = makeTable(files: [second, first], bindings: bindings)
        coordinator.update(parent: parent, scrollView: scrollView)
        XCTAssertEqual(bindings.selection, [second.id])
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))

        let refreshed = AudioFileTestFactory.make(id: second.id, url: second.url, title: "Updated")
        parent = makeTable(files: [refreshed, first], bindings: bindings)
        coordinator.update(parent: parent, scrollView: scrollView)
        let cell = try XCTUnwrap(coordinator.tableView(table, viewFor: table.tableColumns.first, row: 0) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "Updated")
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))

        bindings.columns = [.title, .artist]
        coordinator.update(parent: parent, scrollView: scrollView)
        XCTAssertEqual(table.numberOfColumns, 2)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))

        bindings.selection = []
        parent = makeTable(files: [first], bindings: bindings)
        coordinator.update(parent: parent, scrollView: scrollView)
        XCTAssertEqual(table.numberOfRows, 1)
        XCTAssertTrue(table.selectedRowIndexes.isEmpty)
    }

    private func makeFile(title: String) -> AudioFile {
        AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/\(UUID()).mp3"), title: title)
    }

    private func makeTable(files: [AudioFile], bindings: TableBindings) -> MiddleListTable {
        MiddleListTable(
            files: files, filesRevision: UUID(),
            selection: Binding(get: { bindings.selection }, set: {
                if !bindings.rejectSelection { bindings.selection = $0 }
            }),
            visibleColumns: Binding(get: { bindings.columns }, set: { bindings.columns = $0 }),
            customOrder: .constant([]), middleListSort: .constant(nil),
            onOpenSelectedFiles: {}, onRevealSelectedFilesInFinder: {},
            onCopySelectedFilePaths: {}, onCopySelectedFileNames: {},
            onFindSelectedFileInMusicBrainz: {}, onRequestCreateMuseAmpIDs: {}, onRequestEraseAllTags: {},
            onReloadSelectedFiles: {}, isFileReloadEnabled: true,
            isMuseAmpSupportEnabled: false, isMuseAmpIDCreationEnabled: true
        )
    }
}

@MainActor
private final class TableBindings {
    var selection: Set<AudioFile.ID> = []
    var columns: Set<MiddleListColumn> = [.title]
    var rejectSelection = false
}
