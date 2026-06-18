import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

enum MetadataFieldEditorMode {
    case add
    case edit
}

struct MetadataFieldEditorContext: Identifiable {
    let mode: MetadataFieldEditorMode
    let key: String?
    let initialValue: String
    let isMixed: Bool

    var id: String {
        switch mode {
        case .add:
            return "add"
        case .edit:
            return "edit:\(key ?? "")"
        }
    }
}

struct MetadataFieldEntrySheet: View {
    let context: MetadataFieldEditorContext
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fieldKey: String
    @State private var fieldValue: String

    init(
        context: MetadataFieldEditorContext,
        onSave: @escaping (String, String) -> Void
    ) {
        self.context = context
        self.onSave = onSave
        _fieldKey = State(initialValue: context.key ?? "")
        _fieldValue = State(initialValue: context.initialValue)
    }

    private var trimmedFieldKey: String {
        fieldKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFieldValue: String {
        fieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        switch context.mode {
        case .add:
            return !trimmedFieldKey.isEmpty && !trimmedFieldValue.isEmpty
        case .edit:
            return !trimmedFieldKey.isEmpty
        }
    }

    private var titleText: String {
        switch context.mode {
        case .add:
            return L10n.string("Add Metadata Field")
        case .edit:
            return L10n.string("Edit Metadata Field")
        }
    }

    private var descriptionText: String {
        switch context.mode {
        case .add:
            return L10n.string("Enter the property-map field name and the value to write.")
        case .edit:
            if context.isMixed {
                return L10n.string("Selected files currently contain different values. Saving replaces them with one shared value.")
            }
            return L10n.string("Update the selected metadata field for every file in the current selection.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(titleText)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if context.mode == .add {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field")
                        .font(.headline)

                    MetadataFieldKeyAutocompleteField(
                        text: $fieldKey,
                        suggestions: MetadataFieldSuggestion.allSupported,
                        placeholder: "For example: MUSICBRAINZ_ALBUMID"
                    )
                    .frame(height: 24)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field")
                        .font(.headline)

                    Text(context.key ?? "")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Value")
                        .font(.headline)

                    Spacer()

                    Text("Hidden characters are shown while editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                MetadataFieldValueEditor(
                    text: $fieldValue,
                    placeholder: context.isMixed ? "Type the value to apply to all selected files." : "Enter the metadata value"
                )
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(context.mode == .add ? "Add" : "Save") {
                    onSave(trimmedFieldKey, trimmedFieldValue)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 860, height: 540)
    }
}

private struct MetadataFieldKeyAutocompleteField: NSViewRepresentable {
    @Binding var text: String
    let suggestions: [MetadataFieldSuggestion]
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MetadataFieldAutocompleteSearchField {
        let textField = MetadataFieldAutocompleteSearchField()
        textField.delegate = context.coordinator
        textField.focusDelegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.controlSize = .regular
        textField.focusRingType = .default
        textField.sendsSearchStringImmediately = true
        textField.sendsWholeSearchString = false
        textField.stringValue = text
        context.coordinator.textField = textField
        context.coordinator.refreshSuggestions(for: text)
        return textField
    }

    func updateNSView(_ textField: MetadataFieldAutocompleteSearchField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textField = textField
        textField.focusDelegate = context.coordinator

        if textField.currentEditor() == nil, textField.stringValue != text {
            textField.stringValue = text
        }

        context.coordinator.refreshSuggestions(for: textField.stringValue)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, MetadataFieldAutocompleteSearchFieldFocusDelegate {
        var parent: MetadataFieldKeyAutocompleteField
        weak var textField: NSSearchField?

        private var filteredSuggestions: [MetadataFieldSuggestion] = []
        private var dropdownWindow: NSPanel?
        private var outsideClickMonitor: Any?
        private var tableView: MetadataFieldSuggestionTableView?
        private let rowHeight: CGFloat = 42
        private let dropdownInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        private let highlightCornerRadius: CGFloat = 5

        init(parent: MetadataFieldKeyAutocompleteField) {
            self.parent = parent
            self.filteredSuggestions = parent.suggestions
        }

        func refreshSuggestions(for query: String) {
            let nextSuggestions = Self.filteredSuggestions(from: parent.suggestions, query: query)
            guard nextSuggestions != filteredSuggestions else { return }
            filteredSuggestions = nextSuggestions
            tableView?.reloadData()
            selectFirstRowIfNeeded()
            updateDropdownFrame()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSSearchField else { return }
            refreshSuggestions(for: textField.stringValue)
            showDropdown()
        }

        func autocompleteSearchFieldDidBecomeActive(_ textField: MetadataFieldAutocompleteSearchField) {
            refreshSuggestions(for: textField.stringValue)
            showDropdown()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSSearchField else { return }

            let newText = textField.stringValue
            parent.text = newText
            refreshSuggestions(for: newText)
            showDropdown()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            closeDropdown()
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
                guard dropdownWindow?.isVisible == true, tableView?.selectedRow ?? -1 >= 0 else { return false }
                selectHighlightedSuggestion()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard dropdownWindow?.isVisible == true else { return false }
                closeDropdown()
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

            let identifier = NSUserInterfaceItemIdentifier("metadata-field-suggestion")
            let cellView = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MetadataFieldSuggestionCellView) ?? {
                let view = MetadataFieldSuggestionCellView()
                view.identifier = identifier
                return view
            }()
            cellView.configure(with: filteredSuggestions[row])
            return cellView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {}

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            true
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            MetadataFieldSuggestionRowView(cornerRadius: highlightCornerRadius)
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

        fileprivate func selectSuggestion(at row: Int) {
            guard
                filteredSuggestions.indices.contains(row),
                let textField
            else {
                return
            }

            let suggestion = filteredSuggestions[row]
            textField.stringValue = suggestion.canonicalKey
            parent.text = suggestion.canonicalKey
            closeDropdown()

            if let editor = textField.currentEditor() {
                editor.selectedRange = NSRange(location: suggestion.canonicalKey.utf16.count, length: 0)
                textField.window?.makeFirstResponder(editor)
            }
        }

        private func moveSelection(offset: Int) -> Bool {
            guard !filteredSuggestions.isEmpty else { return false }
            showDropdown()
            let selectedRow = tableView?.selectedRow ?? (offset > 0 ? -1 : filteredSuggestions.count)
            let nextRow = min(max(selectedRow + offset, 0), filteredSuggestions.count - 1)
            selectRow(nextRow)
            return true
        }

        private func showDropdown() {
            guard
                let textField,
                textField.currentEditor() != nil,
                !filteredSuggestions.isEmpty
            else {
                closeDropdown()
                return
            }

            if dropdownWindow == nil {
                dropdownWindow = makeDropdownWindow()
            }

            selectFirstRowIfNeeded()
            updateDropdownFrame()

            if dropdownWindow?.isVisible != true {
                textField.window?.addChildWindow(dropdownWindow!, ordered: .above)
                dropdownWindow?.orderFront(nil)
                installOutsideClickMonitor()
                if let editor = textField.currentEditor() {
                    textField.window?.makeFirstResponder(editor)
                }
            }
        }

        private func makeDropdownWindow() -> NSPanel {
            let tableView = MetadataFieldSuggestionTableView()
            tableView.autocompleteCoordinator = self
            tableView.delegate = self
            tableView.dataSource = self
            tableView.headerView = nil
            tableView.rowHeight = rowHeight
            tableView.intercellSpacing = NSSize(width: 0, height: 2)
            tableView.selectionHighlightStyle = .regular
            tableView.backgroundColor = .clear

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("field"))
            tableView.addTableColumn(column)

            let scrollView = NSScrollView()
            scrollView.documentView = tableView
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            let materialView = NSVisualEffectView()
            materialView.material = .menu
            materialView.blendingMode = .behindWindow
            materialView.state = .active
            materialView.wantsLayer = true
            materialView.layer?.cornerRadius = dropdownInsets.top + highlightCornerRadius
            materialView.layer?.cornerCurve = .continuous
            materialView.layer?.masksToBounds = true
            materialView.addSubview(scrollView)

            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: dropdownInsets.left),
                scrollView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -dropdownInsets.right),
                scrollView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: dropdownInsets.top),
                scrollView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor, constant: -dropdownInsets.bottom)
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

        private func updateDropdownFrame() {
            guard
                let textField,
                let sourceWindow = textField.window,
                let dropdownWindow,
                let tableView
            else {
                return
            }

            let visibleRows = min(max(filteredSuggestions.count, 1), 10)
            let width = max(textField.bounds.width, 430)
            let height = CGFloat(visibleRows) * rowHeight
                + CGFloat(max(visibleRows - 1, 0)) * tableView.intercellSpacing.height
                + dropdownInsets.top
                + dropdownInsets.bottom

            let fieldScreenRect = sourceWindow.convertToScreen(textField.convert(textField.bounds, to: nil))
            let frame = NSRect(
                x: fieldScreenRect.minX,
                y: fieldScreenRect.minY - height - 4,
                width: width,
                height: height
            )

            dropdownWindow.setFrame(frame, display: true)
            tableView.tableColumns.first?.width = width - dropdownInsets.left - dropdownInsets.right - 18
        }

        private func closeDropdown() {
            if let dropdownWindow, let parentWindow = textField?.window {
                parentWindow.removeChildWindow(dropdownWindow)
            }
            dropdownWindow?.orderOut(nil)

            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
        }

        private func installOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }

            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard self.dropdownWindow?.isVisible == true else { return event }

                if self.event(event, isInside: self.textField) || self.event(event, isInside: self.dropdownWindow?.contentView) {
                    return event
                }

                self.closeDropdown()
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

        private static func filteredSuggestions(
            from suggestions: [MetadataFieldSuggestion],
            query: String
        ) -> [MetadataFieldSuggestion] {
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedQuery.isEmpty else { return suggestions }

            return suggestions.filter { suggestion in
                suggestion.matches(query: normalizedQuery)
            }
        }
    }
}

private protocol MetadataFieldAutocompleteSearchFieldFocusDelegate: AnyObject {
    func autocompleteSearchFieldDidBecomeActive(_ textField: MetadataFieldAutocompleteSearchField)
}

private final class MetadataFieldAutocompleteSearchField: NSSearchField {
    weak var focusDelegate: MetadataFieldAutocompleteSearchFieldFocusDelegate?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            notifyActive()
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        notifyActive()
    }

    private func notifyActive() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusDelegate?.autocompleteSearchFieldDidBecomeActive(self)
        }
    }
}

private final class MetadataFieldSuggestionTableView: NSTableView {
    weak var autocompleteCoordinator: MetadataFieldKeyAutocompleteField.Coordinator?
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

private final class MetadataFieldSuggestionRowView: NSTableRowView {
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

private final class MetadataFieldSuggestionCellView: NSTableCellView {
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

    func configure(with suggestion: MetadataFieldSuggestion) {
        keyLabel.stringValue = suggestion.displayName
        detailLabel.stringValue = suggestion.detailText
        toolTip = "\(suggestion.displayName)\n\(suggestion.detailText)"
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

#endif
