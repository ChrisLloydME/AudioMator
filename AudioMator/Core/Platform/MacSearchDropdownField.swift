import AppKit
import SwiftUI

struct MacSearchDropdownField: NSViewRepresentable {
    struct Suggestion: Equatable {
        let id: String
        let title: String
        let detail: String
        var selectionText: String? = nil
    }

    let text: String
    let placeholder: String
    let accessibilityLabel: String
    var restoresTextOnDismiss = false
    var minimumDropdownWidth: CGFloat = 430
    let suggestions: (String) -> [Suggestion]
    var onTextChange: (String) -> Void = { _ in }
    let onSelect: (Suggestion) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let textField = DropdownSearchField()
        textField.delegate = context.coordinator
        textField.focusDelegate = context.coordinator
        textField.selectsTextOnActivation = restoresTextOnDismiss
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.font = .systemFont(ofSize: 13)
        textField.controlSize = .regular
        textField.focusRingType = .default
        textField.sendsSearchStringImmediately = true
        textField.sendsWholeSearchString = false
        textField.stringValue = text
        context.coordinator.textField = textField
        return textField
    }

    func updateNSView(_ textField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if let dropdownField = textField as? DropdownSearchField {
            dropdownField.focusDelegate = context.coordinator
            dropdownField.selectsTextOnActivation = restoresTextOnDismiss
        }
        context.coordinator.synchronizeText(in: textField)
        context.coordinator.refreshVisibleSuggestions()
    }

    static func dismantleNSView(_ textField: NSSearchField, coordinator: Coordinator) {
        textField.delegate = nil
        (textField as? DropdownSearchField)?.focusDelegate = nil
        coordinator.teardown()
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, DropdownSearchFieldFocusDelegate {
        var parent: MacSearchDropdownField
        weak var textField: NSSearchField?

        private var filteredSuggestions: [Suggestion] = []
        private var hasEditedText = false
        private var dropdownWindow: NSPanel?
        nonisolated(unsafe) private var outsideClickMonitor: Any?
        private var tableView: DropdownTableView?
        private let rowHeight: CGFloat = 42
        private let dropdownVerticalInset: CGFloat = 6
        private let highlightCornerRadius: CGFloat = 5

        init(parent: MacSearchDropdownField) {
            self.parent = parent
        }

        deinit {
            if let monitor = outsideClickMonitor {
                outsideClickMonitor = nil
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        NSEvent.removeMonitor(monitor)
                    }
                } else {
                    let box = UncheckedEventMonitorBox(monitor: monitor)
                    DispatchQueue.main.async {
                        NSEvent.removeMonitor(box.monitor)
                    }
                }
            }
        }

        var shouldSelectTextOnClick: Bool {
            parent.restoresTextOnDismiss && !hasEditedText
        }

        func synchronizeText(in textField: NSSearchField) {
            guard textField.stringValue != parent.text else { return }
            if let editor = textField.currentEditor() {
                guard parent.restoresTextOnDismiss, !hasEditedText, dropdownWindow?.isVisible != true else { return }
                editor.string = parent.text
                editor.selectedRange = NSRange(location: 0, length: parent.text.utf16.count)
            }
            textField.stringValue = parent.text
        }

        func refreshVisibleSuggestions() {
            if dropdownWindow?.isVisible == true { refreshSuggestions() }
        }

        func refreshSuggestions() {
            let query = parent.restoresTextOnDismiss && !hasEditedText ? "" : textField?.stringValue ?? ""
            let nextSuggestions = parent.suggestions(query)
            guard nextSuggestions != filteredSuggestions else { return }
            filteredSuggestions = nextSuggestions
            tableView?.reloadData()
            selectFirstRowIfNeeded()
            if filteredSuggestions.isEmpty { closeDropdown() }
            updateDropdownFrame()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            showDropdown()
        }

        fileprivate func autocompleteSearchFieldDidBecomeActive(_ textField: DropdownSearchField) {
            showDropdown()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSSearchField else { return }

            hasEditedText = true
            parent.onTextChange(textField.stringValue)
            showDropdown()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            dismissDropdown()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                return moveSelection(offset: 1)
            case #selector(NSResponder.moveUp(_:)):
                return moveSelection(offset: -1)
            case #selector(NSResponder.insertNewline(_:)):
                guard dropdownWindow?.isVisible == true, tableView?.selectedRow ?? -1 >= 0 else {
                    if parent.restoresTextOnDismiss && hasEditedText {
                        dismissDropdown()
                        return true
                    }
                    return false
                }
                selectHighlightedSuggestion()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard dropdownWindow?.isVisible == true || (parent.restoresTextOnDismiss && hasEditedText) else { return false }
                dismissDropdown()
                return true
            default:
                return false
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            filteredSuggestions.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard filteredSuggestions.indices.contains(row) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("search-dropdown-suggestion")
            let cellView = (tableView.makeView(withIdentifier: identifier, owner: nil) as? DropdownCellView) ?? {
                let view = DropdownCellView()
                view.identifier = identifier
                return view
            }()
            cellView.configure(with: filteredSuggestions[row])
            return cellView
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            DropdownRowView(cornerRadius: highlightCornerRadius)
        }

        fileprivate func hoverSuggestion(at row: Int) {
            guard filteredSuggestions.indices.contains(row) else { return }
            selectRow(row, scrollToVisible: false)
        }

        @objc
        private func selectHighlightedSuggestion() {
            guard let tableView else { return }
            selectSuggestion(at: tableView.selectedRow)
        }

        func selectSuggestion(at row: Int) {
            guard
                filteredSuggestions.indices.contains(row),
                let textField
            else {
                return
            }

            let suggestion = filteredSuggestions[row]
            let selectedText = suggestion.selectionText ?? suggestion.title
            hasEditedText = false
            let accepted = parent.onSelect(suggestion)
            let displayedText = (accepted || !parent.restoresTextOnDismiss) ? selectedText : parent.text
            textField.stringValue = displayedText
            closeDropdown()

            if let editor = textField.currentEditor() {
                editor.string = displayedText
                editor.selectedRange = parent.restoresTextOnDismiss
                    ? NSRange(location: 0, length: displayedText.utf16.count)
                    : NSRange(location: displayedText.utf16.count, length: 0)
                textField.window?.makeFirstResponder(editor)
            }
        }

        private func moveSelection(offset: Int) -> Bool {
            showDropdown()
            guard dropdownWindow?.isVisible == true else { return false }
            let selectedRow = tableView?.selectedRow ?? (offset > 0 ? -1 : filteredSuggestions.count)
            let nextRow = min(max(selectedRow + offset, 0), filteredSuggestions.count - 1)
            selectRow(nextRow)
            return true
        }

        private func showDropdown() {
            refreshSuggestions()
            guard
                let textField,
                let sourceWindow = textField.window,
                !textField.visibleRect.isEmpty,
                textField.currentEditor() != nil,
                !filteredSuggestions.isEmpty
            else {
                closeDropdown()
                return
            }

            let panel = dropdownWindow ?? makeDropdownWindow()
            dropdownWindow = panel

            selectFirstRowIfNeeded()
            guard updateDropdownFrame() else { return }

            if !panel.isVisible {
                sourceWindow.addChildWindow(panel, ordered: .above)
                panel.orderFront(nil)
                installOutsideClickMonitor()
                if let editor = textField.currentEditor() {
                    textField.window?.makeFirstResponder(editor)
                }
            }
        }

        private func makeDropdownWindow() -> NSPanel {
            let tableView = DropdownTableView()
            tableView.autocompleteCoordinator = self
            tableView.delegate = self
            tableView.dataSource = self
            tableView.style = .plain
            tableView.headerView = nil
            tableView.rowHeight = rowHeight
            tableView.intercellSpacing = NSSize(width: 0, height: 2)
            tableView.selectionHighlightStyle = .regular
            tableView.backgroundColor = .clear
            tableView.autoresizingMask = [.width]
            tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("field"))
            tableView.addTableColumn(column)

            let scrollView = NSScrollView()
            scrollView.documentView = tableView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScrollElasticity = .none
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            let materialView = NSVisualEffectView()
            materialView.material = .menu
            materialView.blendingMode = .behindWindow
            materialView.state = .active
            materialView.wantsLayer = true
            materialView.layer?.cornerRadius = dropdownVerticalInset + highlightCornerRadius
            materialView.layer?.cornerCurve = .continuous
            materialView.layer?.masksToBounds = true
            materialView.addSubview(scrollView)

            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: dropdownVerticalInset),
                scrollView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor, constant: -dropdownVerticalInset)
            ])

            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = true
            panel.hasShadow = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .popUpMenu
            panel.acceptsMouseMovedEvents = true
            panel.contentView = materialView

            self.tableView = tableView
            return panel
        }

        private func selectFirstRowIfNeeded() {
            guard !filteredSuggestions.isEmpty, let tableView else { return }
            if tableView.selectedRow < 0 || tableView.selectedRow >= filteredSuggestions.count {
                selectRow(0)
            }
        }

        private func selectRow(_ row: Int, scrollToVisible: Bool = true) {
            guard filteredSuggestions.indices.contains(row), let tableView else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if scrollToVisible {
                tableView.scrollRowToVisible(row)
            }
        }

        @discardableResult
        private func updateDropdownFrame() -> Bool {
            guard
                let textField,
                let sourceWindow = textField.window,
                let dropdownWindow,
                let tableView,
                let screen = sourceWindow.screen ?? NSScreen.main
            else {
                return false
            }

            let visibleRows = min(max(filteredSuggestions.count, 1), 10)
            let height = CGFloat(visibleRows) * rowHeight
                + CGFloat(max(visibleRows - 1, 0)) * tableView.intercellSpacing.height
                + 2 * dropdownVerticalInset

            let fieldScreenRect = sourceWindow.convertToScreen(textField.convert(textField.bounds, to: nil))
            let frame = Self.dropdownFrame(
                anchor: fieldScreenRect, screen: screen.visibleFrame,
                width: max(textField.bounds.width, parent.minimumDropdownWidth), height: height
            )
            guard !frame.isEmpty else {
                closeDropdown()
                return false
            }

            dropdownWindow.setFrame(frame, display: false)
            dropdownWindow.contentView?.layoutSubtreeIfNeeded()
            if let scrollView = tableView.enclosingScrollView {
                tableView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: tableView.frame.height))
                tableView.sizeLastColumnToFit()
            }
            dropdownWindow.displayIfNeeded()
            return true
        }

        static func dropdownFrame(anchor: CGRect, screen: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
            let gap: CGFloat = 4
            let above = screen.maxY - anchor.maxY - gap
            let below = anchor.minY - screen.minY - gap
            let opensAbove = below < height && above > below
            let width = min(width, screen.width)
            let height = min(height, max(0, opensAbove ? above : below))
            return CGRect(
                x: min(max(anchor.minX, screen.minX), screen.maxX - width),
                y: opensAbove ? anchor.maxY + gap : anchor.minY - gap - height,
                width: width, height: height
            )
        }

        func teardown() {
            closeDropdown()
            tableView?.autocompleteCoordinator = nil
            tableView?.delegate = nil
            tableView?.dataSource = nil
            tableView = nil
            dropdownWindow = nil
            textField = nil
        }

        fileprivate func closeDropdown() {
            if let dropdownWindow, let parentWindow = dropdownWindow.parent {
                parentWindow.removeChildWindow(dropdownWindow)
            }
            dropdownWindow?.orderOut(nil)

            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
        }

        private func dismissDropdown() {
            closeDropdown()
            guard parent.restoresTextOnDismiss, hasEditedText else { return }
            hasEditedText = false
            textField?.stringValue = parent.text
            if let editor = textField?.currentEditor() {
                editor.string = parent.text
                editor.selectedRange = NSRange(location: 0, length: parent.text.utf16.count)
            }
        }

        private func installOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }

            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                guard let self else { return event }
                guard self.dropdownWindow?.isVisible == true else { return event }

                if event.type == .scrollWheel {
                    if event.window === self.textField?.window { self.dismissDropdown() }
                    return event
                }

                if self.event(event, isInside: self.textField) || self.event(event, isInside: self.dropdownWindow?.contentView) {
                    return event
                }

                self.dismissDropdown()
                return event
            }
        }

        private func event(_ event: NSEvent, isInside view: NSView?) -> Bool {
            guard let view, let eventWindow = event.window, eventWindow === view.window else {
                return false
            }

            let point = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(point)
        }

    }
}

private nonisolated struct UncheckedEventMonitorBox: @unchecked Sendable {
    let monitor: Any
}

private protocol DropdownSearchFieldFocusDelegate: AnyObject {
    var shouldSelectTextOnClick: Bool { get }
    func autocompleteSearchFieldDidBecomeActive(_ textField: DropdownSearchField)
}

private final class DropdownSearchField: NSSearchField {
    weak var focusDelegate: DropdownSearchFieldFocusDelegate?
    var selectsTextOnActivation = false

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            notifyActive()
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        let selectsText = selectsTextOnActivation
            && (currentEditor() == nil || focusDelegate?.shouldSelectTextOnClick == true)
        super.mouseDown(with: event)
        if selectsText { currentEditor()?.selectAll(nil) }
        notifyActive()
    }

    private func notifyActive() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusDelegate?.autocompleteSearchFieldDidBecomeActive(self)
        }
    }
}

private final class DropdownTableView: NSTableView {
    weak var autocompleteCoordinator: MacSearchDropdownField.Coordinator?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)

        if row >= 0 {
            autocompleteCoordinator?.hoverSuggestion(at: row)
        }

        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)

        guard row >= 0 else {
            super.mouseDown(with: event)
            return
        }

        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        autocompleteCoordinator?.selectSuggestion(at: row)
    }
}

private final class DropdownRowView: NSTableRowView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        self.cornerRadius = 5
        super.init(coder: coder)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let selectionRect = bounds.insetBy(dx: 2, dy: 1)
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: selectionRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()
    }
}

private final class DropdownCellView: NSTableCellView {
    private let keyLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(with suggestion: MacSearchDropdownField.Suggestion) {
        keyLabel.stringValue = suggestion.title
        detailLabel.stringValue = suggestion.detail
        toolTip = "\(suggestion.title)\n\(suggestion.detail)"
    }

    private func configureView() {
        keyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.textColor = .secondaryLabelColor

        let stackView = NSStackView(views: [keyLabel, detailLabel])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
