import SwiftUI
#if os(macOS)
import AppKit
#endif
import Combine
import TagLibAudioMetadata

#if os(macOS)

struct MetadataEditorTarget: Identifiable, Hashable {
    let id: AudioFile.ID
    let url: URL

    init(file: AudioFile) {
        self.id = file.id
        self.url = file.url
    }

    nonisolated var fileName: String {
        url.lastPathComponent
    }
}

private struct MetadataEditorRow: Identifiable, Hashable {
    let key: String
    let value: String
    let isMixed: Bool

    var id: String { key }

    var displayValue: String {
        isMixed ? "Multiple Values" : value
    }
}

private enum MetadataFieldEditorMode {
    case add
    case edit
}

private struct MetadataFieldEditorContext: Identifiable {
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

@MainActor
final class MetadataEditorStore: ObservableObject {
    private struct LoadedState {
        let propertyMaps: [AudioFile.ID: [String: String]]
        let errorMessage: String?
    }

    @Published private(set) var targets: [MetadataEditorTarget] = []
    @Published private(set) var originalPropertyMaps: [AudioFile.ID: [String: String]] = [:]
    @Published private(set) var draftPropertyMaps: [AudioFile.ID: [String: String]] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadErrorMessage: String?
    @Published var selectedFieldKey: String?

    private let metadataPipeline: any AudioMetadataPipeline
    private var loadToken = UUID()

    init(metadataPipeline: any AudioMetadataPipeline) {
        self.metadataPipeline = metadataPipeline
    }

    var hasUnsavedChanges: Bool {
        draftPropertyMaps != originalPropertyMaps
    }

    fileprivate var rows: [MetadataEditorRow] {
        let allKeys = Set(draftPropertyMaps.values.flatMap(\.keys))

        return allKeys
            .map { key in
                let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
                let firstValue = values.first ?? ""
                let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }

                return MetadataEditorRow(
                    key: key,
                    value: firstValue,
                    isMixed: !isUniform
                )
            }
            .sorted { lhs, rhs in
                lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }

    var selectionSummaryText: String {
        if targets.count == 1, let target = targets.first {
            return target.fileName
        }

        return "\(targets.count) selected files"
    }

    var selectionDetailText: String {
        if targets.count == 1, let target = targets.first {
            return target.url.path
        }

        return L10n.string("Only non-empty metadata fields are shown. Mixed values appear as Multiple Values, and changes apply to every selected file.")
    }

    func present(targetFiles: [AudioFile]) {
        let targets = targetFiles.map(MetadataEditorTarget.init(file:))
        let token = UUID()

        self.targets = targets
        self.originalPropertyMaps = [:]
        self.draftPropertyMaps = [:]
        self.loadErrorMessage = nil
        self.selectedFieldKey = nil
        self.isLoading = true
        self.loadToken = token
        let metadataPipeline = self.metadataPipeline

        Task.detached(priority: .userInitiated) { [targets, token, metadataPipeline] in
            let loadedState = Self.loadState(for: targets, metadataPipeline: metadataPipeline)

            await MainActor.run {
                guard self.loadToken == token else { return }
                self.originalPropertyMaps = loadedState.propertyMaps
                self.draftPropertyMaps = loadedState.propertyMaps
                self.loadErrorMessage = loadedState.errorMessage
                self.isLoading = false
                self.realignSelection(preferred: self.selectedFieldKey)
            }
        }
    }

    func discardChanges() {
        draftPropertyMaps = originalPropertyMaps
        realignSelection(preferred: selectedFieldKey)
    }

    fileprivate func makeAddFieldContext() -> MetadataFieldEditorContext {
        MetadataFieldEditorContext(
            mode: .add,
            key: nil,
            initialValue: "",
            isMixed: false
        )
    }

    fileprivate func makeEditFieldContext() -> MetadataFieldEditorContext? {
        guard let key = selectedFieldKey else { return nil }

        let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
        let firstValue = values.first ?? ""
        let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }

        return MetadataFieldEditorContext(
            mode: .edit,
            key: key,
            initialValue: isUniform ? firstValue : "",
            isMixed: !isUniform
        )
    }

    func upsertField(key: String, value: String) {
        let normalizedKey = Self.normalizedFieldKey(key)
        let normalizedValue = Self.normalizedFieldValue(value)

        guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap[normalizedKey] = normalizedValue
            draftPropertyMaps[target.id] = propertyMap
        }

        selectedFieldKey = normalizedKey
    }

    func deleteSelectedField() {
        guard let selectedFieldKey else { return }
        deleteField(named: selectedFieldKey)
    }

    func deleteField(named key: String) {
        guard !key.isEmpty else { return }

        for target in targets {
            var propertyMap = draftPropertyMaps[target.id] ?? [:]
            propertyMap.removeValue(forKey: key)
            draftPropertyMaps[target.id] = propertyMap
        }

        realignSelection(preferred: nil)
    }

    private func realignSelection(preferred: String?) {
        let validKeys = Set(rows.map(\.key))

        if let preferred, validKeys.contains(preferred) {
            selectedFieldKey = preferred
        } else {
            selectedFieldKey = rows.first?.key
        }
    }

    nonisolated private static func loadState(
        for targets: [MetadataEditorTarget],
        metadataPipeline: any AudioMetadataPipeline
    ) -> LoadedState {
        var propertyMaps: [AudioFile.ID: [String: String]] = [:]
        var failures: [String] = []

        for target in targets {
            do {
                propertyMaps[target.id] = try metadataPipeline.rawMetadataPropertyMap(for: target.url)
            } catch {
                propertyMaps[target.id] = [:]
                failures.append("\(target.fileName): \((error as NSError).localizedDescription)")
            }
        }

        let errorMessage: String?
        if failures.isEmpty {
            errorMessage = nil
        } else if failures.count == 1 {
            errorMessage = failures[0]
        } else {
            errorMessage = ([ "\(failures.count) files could not be read." ] + failures.prefix(3)).joined(separator: "\n")
        }

        return LoadedState(propertyMaps: propertyMaps, errorMessage: errorMessage)
    }

    nonisolated private static func normalizedFieldKey(_ key: String) -> String {
        MetadataFieldSuggestion.resolvedKey(for: key)
    }

    nonisolated private static func normalizedFieldValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MetadataEditorWindowView: View {
    static let windowID = "metadata-editor"

    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var store: MetadataEditorStore

    @Environment(\.dismiss) private var dismiss

    @State private var editorContext: MetadataFieldEditorContext?
    @State private var isApplyingChanges: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
                footer
            }
            .padding(20)
            .frame(minWidth: 820, idealWidth: 920, maxWidth: 1040, minHeight: 540, idealHeight: 640)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Metadata Editor")
        }
        .sheet(item: $editorContext) { context in
            MetadataFieldEntrySheet(context: context) { key, value in
                store.upsertField(key: key, value: value)
            }
        }
        .onDisappear {
            if !isApplyingChanges {
                store.discardChanges()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if store.hasUnsavedChanges {
                    Text("Unsaved Changes")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        )
                }
            }

            Text(store.selectionSummaryText)
                .font(.headline)

            Text(store.selectionDetailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            VStack(spacing: 10) {
                Spacer()
                ProgressView("Loading metadata…")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = store.loadErrorMessage, store.rows.isEmpty {
            ContentUnavailableView(
                "Unable to Read Metadata",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.rows.isEmpty {
            ContentUnavailableView(
                "No Metadata Fields",
                systemImage: "tag",
                description: Text(
                    store.loadErrorMessage ?? "No non-empty TagLib metadata fields were found for the current selection."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MetadataEditorTable(
                rows: store.rows,
                selectedFieldKey: $store.selectedFieldKey,
                onEditField: {
                    editorContext = store.makeEditFieldContext()
                },
                onDeleteField: { key in
                    store.deleteField(named: key)
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Edit Selected…") {
                editorContext = store.makeEditFieldContext()
            }
            .disabled(store.selectedFieldKey == nil || store.isLoading || isApplyingChanges)

            Button("Add Field…") {
                editorContext = store.makeAddFieldContext()
            }
            .disabled(store.targets.isEmpty || store.isLoading || isApplyingChanges)

            Button("Delete Field", role: .destructive) {
                store.deleteSelectedField()
            }
            .disabled(store.selectedFieldKey == nil || store.isLoading || isApplyingChanges)

            Spacer()

            if isApplyingChanges {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Cancel") {
                store.discardChanges()
                dismiss()
            }
            .disabled(isApplyingChanges)

            Button("Done") {
                Task {
                    await commitAndDismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.isLoading || isApplyingChanges)
        }
    }

    private func commitAndDismiss() async {
        guard !isApplyingChanges else { return }

        if !store.hasUnsavedChanges {
            dismiss()
            return
        }

        isApplyingChanges = true
        await viewModel.applyRawMetadataPropertyMaps(store.draftPropertyMaps, to: store.targets)
        isApplyingChanges = false
        dismiss()
    }
}

private struct MetadataFieldEntrySheet: View {
    let context: MetadataFieldEditorContext
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fieldKey: String
    @State private var fieldValue: String

    private let editorFont = NSFont(name: "Menlo-Regular", size: 13) ??
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

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
        !trimmedFieldKey.isEmpty && !trimmedFieldValue.isEmpty
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

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))

                    MetadataFieldValueTextEditor(text: $fieldValue, font: editorFont)
                        .padding(1)

                    if fieldValue.isEmpty {
                        Text(context.isMixed ? "Type the value to apply to all selected files." : "Enter the metadata value")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                )
                .frame(minHeight: 300)
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

private struct MetadataEditorTable: NSViewRepresentable {
    let rows: [MetadataEditorRow]
    @Binding var selectedFieldKey: String?
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
            tableView.allowsMultipleSelection = false
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

            let selectedRow = tableView.selectedRow
            let newSelection: String?
            if selectedRow >= 0, selectedRow < currentRows.count {
                newSelection = currentRows[selectedRow].key
            } else {
                newSelection = nil
            }

            if parent.selectedFieldKey != newSelection {
                parent.selectedFieldKey = newSelection
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
            if parent.selectedFieldKey != key {
                parent.selectedFieldKey = key
                syncSelection(on: tableView)
            }
            parent.onEditField()
        }

        fileprivate func prepareContextMenu(forRow row: Int) {
            guard row >= 0, row < currentRows.count else { return }

            let key = currentRows[row].key
            guard parent.selectedFieldKey != key else { return }

            parent.selectedFieldKey = key
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
            guard let key = parent.selectedFieldKey else { return }
            parent.onDeleteField(key)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let hasSelection = parent.selectedFieldKey != nil
            for item in menu.items {
                switch item.action {
                case #selector(editSelectedFieldAction), #selector(deleteSelectedFieldAction):
                    item.isEnabled = hasSelection
                default:
                    break
                }
            }
        }

        private func configureColumns(on tableView: NSTableView) {
            if tableView.tableColumn(withIdentifier: fieldColumnIdentifier) == nil {
                let fieldColumn = NSTableColumn(identifier: fieldColumnIdentifier)
                fieldColumn.title = "Field"
                fieldColumn.width = 230
                fieldColumn.minWidth = 180
                fieldColumn.maxWidth = 320
                fieldColumn.resizingMask = .userResizingMask
                tableView.addTableColumn(fieldColumn)
            }

            if tableView.tableColumn(withIdentifier: valueColumnIdentifier) == nil {
                let valueColumn = NSTableColumn(identifier: valueColumnIdentifier)
                valueColumn.title = "Value"
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
            let menu = NSMenu(title: "Metadata")
            menu.autoenablesItems = false
            menu.delegate = self
            menu.addItem(makeMenuItem(title: "Edit…", action: #selector(editSelectedFieldAction)))
            menu.addItem(makeMenuItem(title: "Delete Field", action: #selector(deleteSelectedFieldAction)))
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
                    row.key == parent.selectedFieldKey ? index : nil
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

private struct MetadataFieldValueTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage(string: text)
        let layoutManager = MetadataFieldInvisibleLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = font
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.drawingFont = font

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView

        DispatchQueue.main.async {
            guard let window = textView.window, window.firstResponder !== textView else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.font != font {
            textView.font = font
        }

        (textView.layoutManager as? MetadataFieldInvisibleLayoutManager)?.drawingFont = font

        guard textView.string != text else { return }

        context.coordinator.isApplyingProgrammaticUpdate = true
        let previousSelection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(
            NSRange(
                location: min(previousSelection.location, (text as NSString).length),
                length: min(previousSelection.length, max((text as NSString).length - previousSelection.location, 0))
            )
        )
        context.coordinator.isApplyingProgrammaticUpdate = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var isApplyingProgrammaticUpdate = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView, notification.object as AnyObject? === textView else { return }
            guard text != textView.string else { return }
            text = textView.string
        }
    }
}

private final class MetadataFieldInvisibleLayoutManager: NSLayoutManager {
    var drawingFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) {
        didSet {
            guard drawingFont != oldValue else { return }
            invalidateDisplay(forCharacterRange: fullCharacterRange)
        }
    }

    var invisiblesColor: NSColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.7) {
        didSet {
            guard invisiblesColor != oldValue else { return }
            invalidateDisplay(forCharacterRange: fullCharacterRange)
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawInvisibles(forGlyphRange: glyphsToShow, at: origin)
    }

    private var fullCharacterRange: NSRange {
        NSRange(location: 0, length: textStorage?.length ?? 0)
    }

    private func drawInvisibles(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard glyphsToShow.length > 0 else { return }
        guard let textStorage else { return }
        guard let textContainer = textContainer(forGlyphAt: glyphsToShow.location, effectiveRange: nil) else { return }

        let text = textStorage.string as NSString
        let characterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        NSGraphicsContext.saveGraphicsState()
        invisiblesColor.setStroke()
        invisiblesColor.setFill()

        var previousCodeUnit: unichar?

        for characterIndex in characterRange.lowerBound..<characterRange.upperBound {
            let codeUnit = text.character(at: characterIndex)
            defer { previousCodeUnit = codeUnit }

            guard let invisible = MetadataInvisibleMarker(codeUnit: codeUnit, previousCodeUnit: previousCodeUnit) else {
                continue
            }

            let glyphIndex = glyphIndexForCharacter(at: characterIndex)
            if propertyForGlyph(at: glyphIndex).contains(.null) {
                continue
            }

            var lineGlyphRange = NSRange(location: 0, length: 0)
            let lineFragment = lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange,
                withoutAdditionalLayout: true
            )
            let glyphLocation = location(forGlyphAt: glyphIndex)
            let glyphOrigin = NSPoint(
                x: origin.x + lineFragment.origin.x + glyphLocation.x,
                y: origin.y + lineFragment.origin.y
            )
            let glyphWidth = widthForInvisible(
                invisible,
                glyphIndex: glyphIndex,
                lineGlyphRange: lineGlyphRange,
                glyphLocation: glyphLocation,
                textContainer: textContainer
            )

            drawInvisible(
                invisible,
                at: glyphOrigin,
                glyphWidth: glyphWidth,
                lineFragment: lineFragment
            )
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func widthForInvisible(
        _ invisible: MetadataInvisibleMarker,
        glyphIndex: Int,
        lineGlyphRange: NSRange,
        glyphLocation: NSPoint,
        textContainer: NSTextContainer
    ) -> CGFloat {
        switch invisible {
        case .lineBreak:
            return max(drawingFont.pointSize * 0.9, 10)
        case .tab:
            if lineGlyphRange.contains(glyphIndex + 1) {
                let nextLocation = location(forGlyphAt: glyphIndex + 1)
                return max(nextLocation.x - glyphLocation.x, drawingFont.pointSize * 1.4)
            }
            return max(
                boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer).width,
                drawingFont.pointSize * 1.4
            )
        case .space, .nonBreakingSpace:
            if lineGlyphRange.contains(glyphIndex + 1) {
                let nextLocation = location(forGlyphAt: glyphIndex + 1)
                return max(nextLocation.x - glyphLocation.x, drawingFont.pointSize * 0.45)
            }
            return max(
                boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer).width,
                drawingFont.pointSize * 0.45
            )
        }
    }

    private func drawInvisible(
        _ invisible: MetadataInvisibleMarker,
        at glyphOrigin: NSPoint,
        glyphWidth: CGFloat,
        lineFragment: NSRect
    ) {
        let midY = glyphOrigin.y + (lineFragment.height * 0.53)

        switch invisible {
        case .space:
            let diameter = max(2.2, (drawingFont.pointSize * 0.18).rounded())
            let rect = NSRect(
                x: glyphOrigin.x + max((glyphWidth - diameter) / 2, 0),
                y: midY - (diameter / 2),
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: rect).fill()

        case .nonBreakingSpace:
            let size = max(4.2, (drawingFont.pointSize * 0.34).rounded())
            let rect = NSRect(
                x: glyphOrigin.x + max((glyphWidth - size) / 2, 0),
                y: midY - (size / 2),
                width: size,
                height: size
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.4, yRadius: 1.4)
            path.lineWidth = 1
            path.stroke()

        case .tab:
            let width = max(glyphWidth - 6, drawingFont.pointSize * 0.9)
            let startX = glyphOrigin.x + 3
            let endX = startX + width
            let arrowSize = min(4.5, max(width * 0.18, 3))
            let path = NSBezierPath()
            path.lineWidth = 1
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: startX, y: midY))
            path.line(to: NSPoint(x: endX, y: midY))
            path.move(to: NSPoint(x: startX, y: midY - 3))
            path.line(to: NSPoint(x: startX, y: midY + 3))
            path.move(to: NSPoint(x: endX, y: midY))
            path.line(to: NSPoint(x: endX - arrowSize, y: midY + arrowSize * 0.7))
            path.move(to: NSPoint(x: endX, y: midY))
            path.line(to: NSPoint(x: endX - arrowSize, y: midY - arrowSize * 0.7))
            path.stroke()

        case .lineBreak:
            let width = max(glyphWidth, drawingFont.pointSize * 0.9)
            let leftX = glyphOrigin.x + 1.5
            let rightX = leftX + width * 0.72
            let topY = midY + 4
            let bottomY = midY - 3
            let path = NSBezierPath()
            path.lineWidth = 1
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: leftX, y: topY))
            path.line(to: NSPoint(x: leftX, y: bottomY))
            path.line(to: NSPoint(x: rightX, y: bottomY))
            path.move(to: NSPoint(x: rightX, y: bottomY))
            path.line(to: NSPoint(x: rightX - 3.5, y: bottomY + 3))
            path.move(to: NSPoint(x: rightX, y: bottomY))
            path.line(to: NSPoint(x: rightX - 3.5, y: bottomY - 3))
            path.stroke()
        }
    }
}

private enum MetadataInvisibleMarker {
    case space
    case tab
    case lineBreak
    case nonBreakingSpace

    init?(codeUnit: unichar, previousCodeUnit: unichar?) {
        switch codeUnit {
        case 0x20:
            self = .space
        case 0x09:
            self = .tab
        case 0x0A:
            guard previousCodeUnit != 0x0D else { return nil }
            self = .lineBreak
        case 0x0D:
            self = .lineBreak
        case 0x00A0:
            self = .nonBreakingSpace
        default:
            return nil
        }
    }
}
#endif
