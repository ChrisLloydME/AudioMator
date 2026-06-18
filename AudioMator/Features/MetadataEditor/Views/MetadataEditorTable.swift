import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

struct MetadataEditorTable: NSViewRepresentable {
    let rows: [MetadataEditorRow]
    @Binding var selectedFieldKeys: Set<String>
    let onEditField: () -> Void
    let onDeleteField: (String) -> Void

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

private final class MetadataEditorNSTableView: NSTableView {
    weak var metadataCoordinator: MetadataEditorTable.Coordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        metadataCoordinator?.prepareContextMenu(forRow: row(at: point))
        return super.menu(for: event)
    }
}

extension MetadataEditorTable {
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        fileprivate var parent: MetadataEditorTable

        private weak var tableView: MetadataEditorNSTableView?
        private var isApplyingSelection = false
        private var currentRows: [MetadataEditorRow] = []

        private let fieldColumnIdentifier = NSUserInterfaceItemIdentifier("metadata-field")
        private let valueColumnIdentifier = NSUserInterfaceItemIdentifier("metadata-value")

        init(parent: MetadataEditorTable) {
            self.parent = parent
        }

        func makeScrollView() -> NSScrollView {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true

            let tableView = MetadataEditorNSTableView(frame: .zero)
            tableView.metadataCoordinator = self
            tableView.delegate = self
            tableView.dataSource = self
            tableView.headerView = NSTableHeaderView()
            tableView.usesAlternatingRowBackgroundColors = false
            tableView.allowsMultipleSelection = true
            tableView.allowsEmptySelection = true
            tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            tableView.selectionHighlightStyle = .regular
            tableView.rowSizeStyle = .default
            tableView.intercellSpacing = NSSize(width: 0, height: 0)
            tableView.usesAutomaticRowHeights = true
            tableView.focusRingType = .none
            tableView.backgroundColor = .clear
            tableView.gridStyleMask = []
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleAction)
            tableView.menu = makeRowMenu()

            configureColumns(on: tableView)

            scrollView.documentView = tableView
            self.tableView = tableView

            update(scrollView: scrollView)
            return scrollView
        }

        func update(scrollView: NSScrollView) {
            guard let tableView = scrollView.documentView as? MetadataEditorNSTableView else { return }

            self.tableView = tableView
            tableView.metadataCoordinator = self

            let previousRows = currentRows
            currentRows = parent.rows

            if previousRows != currentRows {
                tableView.reloadData()
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<currentRows.count))
            } else if let valueColumn = tableView.tableColumn(withIdentifier: valueColumnIdentifier) {
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<currentRows.count), columnIndexes: IndexSet(integer: tableView.column(withIdentifier: valueColumn.identifier)))
            }

            syncSelection(on: tableView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            currentRows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < currentRows.count, let tableColumn else { return nil }

            let rowModel = currentRows[row]
            let identifier = tableColumn.identifier
            let cellView = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MetadataEditorCellView)
                ?? makeCellView(identifier: identifier)

            switch identifier {
            case fieldColumnIdentifier:
                cellView.configure(
                    text: rowModel.key,
                    font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                    textColor: .labelColor,
                    wraps: false
                )
                cellView.textField?.toolTip = rowModel.key

            case valueColumnIdentifier:
                cellView.configure(
                    text: rowModel.displayValue,
                    font: NSFont.systemFont(ofSize: 13),
                    textColor: rowModel.isMixed ? .secondaryLabelColor : .labelColor,
                    wraps: true
                )
                cellView.textField?.toolTip = rowModel.displayValue

            default:
                return nil
            }

            return cellView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView else { return }

            let newSelection = Set(tableView.selectedRowIndexes.compactMap { row in
                row >= 0 && row < currentRows.count ? currentRows[row].key : nil
            })

            if parent.selectedFieldKeys != newSelection {
                parent.selectedFieldKeys = newSelection
            }
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row >= 0, row < currentRows.count else { return 28 }

            let rowModel = currentRows[row]
            let valueWidth = max(valueColumnWidth(in: tableView) - 20, 120)
            let fieldWidth = max(fieldColumnWidth(in: tableView) - 20, 120)

            let fieldHeight = textHeight(
                for: rowModel.key,
                font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                width: fieldWidth
            )
            let valueHeight = textHeight(
                for: rowModel.displayValue,
                font: NSFont.systemFont(ofSize: 13),
                width: valueWidth
            )

            return max(30, max(fieldHeight, valueHeight) + 12)
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let tableView else { return }
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<currentRows.count))
        }

        @objc
        private func handleDoubleAction() {
            guard
                let tableView,
                tableView.clickedRow >= 0,
                tableView.clickedRow < currentRows.count
            else {
                return
            }

            let key = currentRows[tableView.clickedRow].key
            if parent.selectedFieldKeys != [key] {
                parent.selectedFieldKeys = [key]
                syncSelection(on: tableView)
            }
            parent.onEditField()
        }

        fileprivate func prepareContextMenu(forRow row: Int) {
            guard row >= 0, row < currentRows.count else { return }

            let key = currentRows[row].key
            guard !parent.selectedFieldKeys.contains(key) else { return }

            parent.selectedFieldKeys = [key]
            if let tableView {
                syncSelection(on: tableView)
            }
        }

        @objc
        private func editSelectedFieldAction() {
            parent.onEditField()
        }

        @objc
        private func deleteSelectedFieldAction() {
            guard let key = parent.selectedFieldKeys.sorted().first else { return }
            parent.onDeleteField(key)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let hasSingleSelection = parent.selectedFieldKeys.count == 1
            for item in menu.items {
                switch item.action {
                case #selector(editSelectedFieldAction), #selector(deleteSelectedFieldAction):
                    item.isEnabled = hasSingleSelection
                default:
                    break
                }
            }
        }

        private func configureColumns(on tableView: NSTableView) {
            if tableView.tableColumn(withIdentifier: fieldColumnIdentifier) == nil {
                let fieldColumn = NSTableColumn(identifier: fieldColumnIdentifier)
                fieldColumn.title = L10n.string("Field")
                fieldColumn.width = 230
                fieldColumn.minWidth = 180
                fieldColumn.maxWidth = 320
                fieldColumn.resizingMask = .userResizingMask
                tableView.addTableColumn(fieldColumn)
            }

            if tableView.tableColumn(withIdentifier: valueColumnIdentifier) == nil {
                let valueColumn = NSTableColumn(identifier: valueColumnIdentifier)
                valueColumn.title = L10n.string("Value")
                valueColumn.width = 520
                valueColumn.minWidth = 240
                valueColumn.resizingMask = .autoresizingMask
                tableView.addTableColumn(valueColumn)
            }
        }

        private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> MetadataEditorCellView {
            let cellView = MetadataEditorCellView(frame: .zero)
            cellView.identifier = identifier
            return cellView
        }

        private func makeRowMenu() -> NSMenu {
            let menu = NSMenu(title: L10n.string("Metadata"))
            menu.autoenablesItems = false
            menu.delegate = self
            menu.addItem(makeMenuItem(title: L10n.string("Edit…"), action: #selector(editSelectedFieldAction)))
            menu.addItem(makeMenuItem(title: L10n.string("Delete Field"), action: #selector(deleteSelectedFieldAction)))
            return menu
        }

        private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func syncSelection(on tableView: NSTableView) {
            let selectedIndexes = IndexSet(
                currentRows.enumerated().compactMap { index, row in
                    parent.selectedFieldKeys.contains(row.key) ? index : nil
                }
            )

            guard tableView.selectedRowIndexes != selectedIndexes else { return }

            isApplyingSelection = true
            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
            if let firstIndex = selectedIndexes.first {
                tableView.scrollRowToVisible(firstIndex)
            }
            isApplyingSelection = false
        }

        private func fieldColumnWidth(in tableView: NSTableView) -> CGFloat {
            tableView.tableColumn(withIdentifier: fieldColumnIdentifier)?.width ?? 230
        }

        private func valueColumnWidth(in tableView: NSTableView) -> CGFloat {
            tableView.tableColumn(withIdentifier: valueColumnIdentifier)?.width ?? 520
        }

        private func textHeight(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let bounds = (text as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            return ceil(bounds.height)
        }
    }
}

private final class MetadataEditorCellView: NSTableCellView {
    private let label: NSTextField
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        label = NSTextField(labelWithString: "")
        super.init(frame: frameRect)

        wantsLayer = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.usesSingleLineMode = false

        addSubview(label)
        textField = label

        topConstraint = label.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        bottomConstraint = label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            topConstraint!,
            bottomConstraint!
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(text: String, font: NSFont, textColor: NSColor, wraps: Bool) {
        label.stringValue = text
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        label.maximumNumberOfLines = wraps ? 0 : 1
        label.cell?.wraps = wraps
        label.cell?.isScrollable = false
        label.usesSingleLineMode = !wraps
    }
}

#endif
