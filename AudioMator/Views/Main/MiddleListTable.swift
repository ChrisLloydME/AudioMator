#if os(macOS)
import AppKit
import SwiftUI

struct MiddleListTable: NSViewRepresentable {
    let files: [AudioFile]
    @Binding var selection: Set<AudioFile.ID>
    @Binding var visibleColumns: Set<MiddleListColumn>
    @Binding var customOrder: [AudioFile.ID]
    @Binding var middleListSort: MiddleListSort?
    let onOpenSelectedFiles: () -> Void
    let onRevealSelectedFilesInFinder: () -> Void
    let onCopySelectedFilePaths: () -> Void
    let onCopySelectedFileNames: () -> Void
    let onFindSelectedFileInMusicBrainz: () -> Void
    let onRequestEraseAllTags: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scrollView: nsView)
    }
}

private final class MiddleListNSTableView: NSTableView {
    weak var middleListCoordinator: MiddleListTable.Coordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        middleListCoordinator?.prepareContextMenu(forRow: row(at: point))
        return super.menu(for: event)
    }
}

extension MiddleListTable {
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        private struct RowSnapshot: Equatable {
            let id: AudioFile.ID
            let contentFingerprint: Int
        }

        fileprivate var parent: MiddleListTable

        private weak var tableView: MiddleListNSTableView?
        private var isApplyingSelection = false
        private var isApplyingSortDescriptors = false
        private var currentColumnLayout: [MiddleListColumn] = []
        private var currentRowSnapshots: [RowSnapshot] = []
        private var draggedIDs: [AudioFile.ID] = []
        private let rowDragType = NSPasteboard.PasteboardType("com.audiomator.middle-list.row")

        init(parent: MiddleListTable) {
            self.parent = parent
        }

        func makeScrollView() -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder

            let tableView = MiddleListNSTableView(frame: .zero)
            tableView.middleListCoordinator = self
            tableView.delegate = self
            tableView.dataSource = self
            tableView.usesAlternatingRowBackgroundColors = false
            tableView.allowsMultipleSelection = true
            tableView.allowsEmptySelection = true
            tableView.columnAutoresizingStyle = .noColumnAutoresizing
            tableView.headerView = NSTableHeaderView()
            tableView.rowSizeStyle = .default
            tableView.intercellSpacing = NSSize(width: 6, height: 2)
            tableView.setDraggingSourceOperationMask(.move, forLocal: true)
            tableView.registerForDraggedTypes([rowDragType])
            tableView.menu = makeRowMenu()

            scrollView.documentView = tableView
            self.tableView = tableView

            _ = configureColumnsIfNeeded(on: tableView)
            updateMenus(on: tableView)
            syncSelection(on: tableView)

            return scrollView
        }

        func update(scrollView: NSScrollView) {
            guard let tableView = scrollView.documentView as? MiddleListNSTableView else { return }
            self.tableView = tableView
            tableView.middleListCoordinator = self

            let columnsChanged = configureColumnsIfNeeded(on: tableView)
            let newSnapshots = makeRowSnapshots(for: parent.files)
            let fileIDsChanged = newSnapshots.map(\.id) != currentRowSnapshots.map(\.id)
            let changedRows = rowIndexesNeedingRefresh(from: currentRowSnapshots, to: newSnapshots)
            currentRowSnapshots = newSnapshots

            if columnsChanged || fileIDsChanged {
                tableView.reloadData()
            } else if !changedRows.isEmpty, tableView.numberOfColumns > 0 {
                tableView.reloadData(
                    forRowIndexes: changedRows,
                    columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
                )
            }

            syncSortDescriptors(on: tableView)
            updateMenus(on: tableView)
            syncSelection(on: tableView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.files.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard
                row >= 0,
                row < parent.files.count,
                let tableColumn,
                let column = MiddleListColumn(rawValue: tableColumn.identifier.rawValue)
            else {
                return nil
            }

            let cellIdentifier = NSUserInterfaceItemIdentifier(column.rawValue)
            let cellView = (tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView)
                ?? makeCellView(identifier: cellIdentifier)

            cellView.textField?.stringValue = column.text(for: parent.files[row])
            cellView.textField?.toolTip = column.text(for: parent.files[row])
            return cellView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView else { return }

            let newSelection = Set<AudioFile.ID>(
                tableView.selectedRowIndexes.compactMap { index in
                    guard index >= 0, index < parent.files.count else { return nil }
                    return parent.files[index].id
                }
            )

            parent.selection = newSelection
            syncSelection(on: tableView)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row >= 0, row < parent.files.count else { return nil }

            let item = NSPasteboardItem()
            item.setString(parent.files[row].id.uuidString, forType: rowDragType)
            return item
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            if parent.middleListSort == nil, parent.customOrder.isEmpty {
                parent.customOrder = parent.files.map(\.id)
            }

            draggedIDs = rowIndexes.compactMap { index in
                guard index >= 0, index < parent.files.count else { return nil }
                return parent.files[index].id
            }
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            draggedIDs.removeAll()
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard info.draggingSource as AnyObject? === tableView else { return [] }

            let boundedRow = max(0, min(row, parent.files.count))
            tableView.setDropRow(boundedRow, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            defer { draggedIDs.removeAll() }

            guard info.draggingSource as AnyObject? === tableView else { return false }

            let currentIDs = parent.files.map(\.id)
            let movingIDs = draggedIDs.isEmpty ? currentIDsForPasteboard(info.draggingPasteboard) : draggedIDs
            guard !movingIDs.isEmpty else { return false }

            let draggingSet = Set(movingIDs)
            let boundedRow = max(0, min(row, currentIDs.count))
            let draggedBeforeRow = currentIDs.prefix(boundedRow).filter(draggingSet.contains).count
            let insertionIndex = boundedRow - draggedBeforeRow

            var reorderedIDs = currentIDs.filter { !draggingSet.contains($0) }
            reorderedIDs.insert(contentsOf: movingIDs, at: insertionIndex)

            guard reorderedIDs != currentIDs else { return false }

            parent.customOrder = reorderedIDs
            parent.middleListSort = nil
            return true
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplyingSortDescriptors else { return }

            guard
                let descriptor = tableView.sortDescriptors.first,
                let key = descriptor.key,
                let column = MiddleListColumn(rawValue: key)
            else {
                parent.middleListSort = nil
                return
            }

            let newSort = MiddleListSort(column: column, ascending: descriptor.ascending)
            guard parent.middleListSort != newSort else { return }
            parent.middleListSort = newSort
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let hasSelection = !parent.selection.isEmpty
            for item in menu.items {
                switch item.action {
                case #selector(openSelectedFilesAction):
                    item.isEnabled = hasSelection
                case #selector(revealSelectedFilesAction):
                    item.isEnabled = hasSelection
                case #selector(copySelectedFilePathsAction):
                    item.isEnabled = hasSelection
                case #selector(copySelectedFileNamesAction):
                    item.isEnabled = hasSelection
                case #selector(findSelectedFilesInMusicBrainzAction):
                    item.isEnabled = hasSelection
                case #selector(requestEraseAllTagsAction):
                    item.isEnabled = hasSelection
                default:
                    break
                }
            }
        }

        @objc
        private func openSelectedFilesAction() {
            parent.onOpenSelectedFiles()
        }

        @objc
        private func revealSelectedFilesAction() {
            parent.onRevealSelectedFilesInFinder()
        }

        @objc
        private func copySelectedFilePathsAction() {
            parent.onCopySelectedFilePaths()
        }

        @objc
        private func copySelectedFileNamesAction() {
            parent.onCopySelectedFileNames()
        }

        @objc
        private func findSelectedFilesInMusicBrainzAction() {
            parent.onFindSelectedFileInMusicBrainz()
        }

        @objc
        private func requestEraseAllTagsAction() {
            parent.onRequestEraseAllTags()
        }

        @objc
        private func toggleColumn(_ sender: NSMenuItem) {
            guard
                let rawValue = sender.representedObject as? String,
                let column = MiddleListColumn(rawValue: rawValue)
            else {
                return
            }

            var updated = parent.visibleColumns
            if updated.contains(column) {
                guard updated.count > 1 else { return }
                updated.remove(column)
            } else {
                updated.insert(column)
            }

            parent.visibleColumns = updated
            if !updated.contains(column), parent.middleListSort?.column == column {
                parent.middleListSort = nil
            }
            if let tableView {
                updateMenus(on: tableView)
            }
        }

        @objc
        private func useManualOrderAction() {
            parent.middleListSort = nil
        }

        fileprivate func prepareContextMenu(forRow row: Int) {
            guard row >= 0, row < parent.files.count else { return }

            let rowID = parent.files[row].id
            guard !parent.selection.contains(rowID) else { return }

            parent.selection = [rowID]
            if let tableView {
                syncSelection(on: tableView)
            }
        }

        private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cellView = NSTableCellView(frame: .zero)
            cellView.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

            cellView.addSubview(textField)
            cellView.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])

            return cellView
        }

        private func configureColumnsIfNeeded(on tableView: NSTableView) -> Bool {
            let desiredColumns = MiddleListColumn.allCases.filter(parent.visibleColumns.contains)
            guard desiredColumns != currentColumnLayout else { return false }

            currentColumnLayout = desiredColumns

            for column in tableView.tableColumns.reversed() {
                tableView.removeTableColumn(column)
            }

            for column in desiredColumns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
                tableColumn.title = column.displayName
                tableColumn.minWidth = 48
                tableColumn.width = defaultWidth(for: column)
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
                tableView.addTableColumn(tableColumn)
            }

            updateMenus(on: tableView)
            return true
        }

        private func updateMenus(on tableView: NSTableView) {
            tableView.menu = makeRowMenu()
            tableView.headerView?.menu = makeHeaderMenu()
        }

        private func syncSelection(on tableView: NSTableView) {
            let selectedIndexes = IndexSet(
                parent.files.enumerated().compactMap { index, file in
                    parent.selection.contains(file.id) ? index : nil
                }
            )

            guard tableView.selectedRowIndexes != selectedIndexes else { return }

            isApplyingSelection = true
            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
            isApplyingSelection = false
        }

        private func currentIDsForPasteboard(_ pasteboard: NSPasteboard) -> [AudioFile.ID] {
            guard let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String] else { return [] }
            return strings.compactMap(UUID.init(uuidString:)).filter { id in
                parent.files.contains { $0.id == id }
            }
        }

        private func syncSortDescriptors(on tableView: NSTableView) {
            let desiredDescriptors: [NSSortDescriptor]
            if let middleListSort = parent.middleListSort,
               currentColumnLayout.contains(middleListSort.column) {
                desiredDescriptors = [NSSortDescriptor(key: middleListSort.column.rawValue, ascending: middleListSort.ascending)]
            } else {
                desiredDescriptors = []
            }

            guard !sortDescriptorsMatch(tableView.sortDescriptors, desiredDescriptors) else { return }

            isApplyingSortDescriptors = true
            tableView.sortDescriptors = desiredDescriptors
            isApplyingSortDescriptors = false
        }

        private func sortDescriptorsMatch(_ lhs: [NSSortDescriptor], _ rhs: [NSSortDescriptor]) -> Bool {
            guard lhs.count == rhs.count else { return false }

            for (left, right) in zip(lhs, rhs) {
                if left.key != right.key || left.ascending != right.ascending {
                    return false
                }
            }

            return true
        }

        private func makeRowSnapshots(for files: [AudioFile]) -> [RowSnapshot] {
            files.map { file in
                RowSnapshot(id: file.id, contentFingerprint: file.middleListContentFingerprint)
            }
        }

        private func rowIndexesNeedingRefresh(
            from previous: [RowSnapshot],
            to current: [RowSnapshot]
        ) -> IndexSet {
            guard previous.count == current.count else { return IndexSet(integersIn: 0..<current.count) }

            var changed = IndexSet()
            for index in current.indices where previous[index] != current[index] {
                changed.insert(index)
            }
            return changed
        }

        private func makeRowMenu() -> NSMenu {
            let menu = NSMenu(title: "Middle List")
            menu.autoenablesItems = false
            menu.delegate = self

            menu.addItem(makeMenuItem(title: "Open", action: #selector(openSelectedFilesAction)))
            menu.addItem(makeMenuItem(title: "Reveal in Finder", action: #selector(revealSelectedFilesAction)))
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: "Copy Path", action: #selector(copySelectedFilePathsAction)))
            menu.addItem(makeMenuItem(title: "Copy Filename", action: #selector(copySelectedFileNamesAction)))
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: "Find in MusicBrainz", action: #selector(findSelectedFilesInMusicBrainzAction)))
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: "Erase All Tags…", action: #selector(requestEraseAllTagsAction)))

            return menu
        }

        private func makeHeaderMenu() -> NSMenu {
            let menu = NSMenu(title: "Columns")
            menu.autoenablesItems = false

            let manualOrderItem = makeMenuItem(title: "Manual Order", action: #selector(useManualOrderAction))
            manualOrderItem.state = parent.middleListSort == nil ? .on : .off
            manualOrderItem.isEnabled = parent.middleListSort != nil
            menu.addItem(manualOrderItem)
            menu.addItem(.separator())

            for column in MiddleListColumn.allCases {
                let item = NSMenuItem(
                    title: column.displayName,
                    action: #selector(toggleColumn(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = column.rawValue
                item.state = parent.visibleColumns.contains(column) ? .on : .off
                item.isEnabled = parent.visibleColumns.count > 1 || !parent.visibleColumns.contains(column)
                menu.addItem(item)
            }

            return menu
        }

        private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func defaultWidth(for column: MiddleListColumn) -> CGFloat {
            switch column {
            case .filename, .title, .album:
                return 240
            case .artist, .albumArtist, .composer, .publisher, .copyright, .credits:
                return 180
            case .genre, .comment:
                return 160
            case .releaseDate:
                return 130
            case .year:
                return 70
            case .track, .disc, .explicit, .channels, .format:
                return 72
            case .duration:
                return 84
            case .bitrate:
                return 88
            case .sampleRate:
                return 96
            }
        }
    }
}
#endif
