import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MetadataFilenameRenameSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    let targetFileIDs: [AudioFile.ID]
    @Binding var isPresented: Bool

    @State private var renameTemplate: String = ""
    @State private var isApplying: Bool = false
    @State private var pendingFieldInsertion: FileRenameTemplateEditorInsertion?

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18

    private var targetFiles: [AudioFile] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        return targetFileIDs.compactMap { filesByID[$0] }
    }

    private var renamePlan: FileRenamePlan {
        makeFileRenamePlan(template: renameTemplate, targetFiles: targetFiles)
    }

    private var selectionSummaryText: String {
        targetFiles.count == 1
            ? "1 selected file"
            : "\(targetFiles.count) selected files"
    }

    private var previewStatusMessage: String {
        if targetFiles.isEmpty {
            return "Select files in the center list first."
        }

        if renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a template or drag metadata chips into the field."
        }

        if renamePlan.hasIssues {
            return "\(renamePlan.readyCount) file(s) are ready. \(renameIssueSummaryText)"
        }

        if renamePlan.readyCount == 0 {
            return "The filenames already match."
        }

        return "\(renamePlan.readyCount) file(s) will be renamed. File extensions stay the same."
    }

    private var renameIssueSummaryText: String {
        let issueRows = renamePlan.rows.filter { $0.status.isError }
        guard !issueRows.isEmpty else { return "No conflicts." }

        var countsByTitle: [String: Int] = [:]
        for row in issueRows {
            countsByTitle[row.status.title, default: 0] += 1
        }

        let summary = countsByTitle
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key.lowercased())" }
            .joined(separator: ", ")

        return "\(issueRows.count) file(s) will be skipped: \(summary)."
    }

    private var previewStatusSymbolName: String {
        if renamePlan.hasIssues {
            return "exclamationmark.triangle.fill"
        }

        if renamePlan.readyCount > 0 {
            return "checkmark.circle.fill"
        }

        return "info.circle.fill"
    }

    private var previewStatusTint: Color {
        if renamePlan.hasIssues {
            return .orange
        }

        if renamePlan.readyCount > 0 {
            return .green
        }

        return .secondary
    }

    private var canApply: Bool {
        renamePlan.canApply && !isApplying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    setupSection
                    previewSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .padding(20)
        .frame(width: 760, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rename Files from Metadata")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Type the punctuation and spacing you want. Click or drag a field to insert it at the caret.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(selectionSummaryText, systemImage: "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text("AudioMator keeps each file's current extension. The template changes only the filename.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(FileRenameMetadataField.allCases, id: \.self) { field in
                        metadataChip(for: field)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rename template")
                        .font(.headline)

                    ZStack(alignment: .topLeading) {
                        if renameTemplate.isEmpty {
                            Text("Type separators, then insert fields where you want them.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                        }

                        FileRenameTemplateEditor(
                            template: $renameTemplate,
                            pendingInsertion: $pendingFieldInsertion,
                            isEnabled: !isApplying
                        )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .disabled(isApplying)
                    }
                    .frame(minHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Label(previewStatusMessage, systemImage: previewStatusSymbolName)
                    .font(.subheadline)
                    .foregroundStyle(previewStatusTint)

                if renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Add a Template",
                        systemImage: "text.cursor",
                        description: Text("Add text or metadata fields to preview the new filenames.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    MetadataFilenameRenamePreviewList(rows: renamePlan.rows)
                        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background(
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Button("Rename") {
                applyRename()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
    }

    private func metadataChip(for field: FileRenameMetadataField) -> some View {
        Button {
            insertFieldToken(field)
        } label: {
            Text(field.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help("Click to insert at the caret, or drag into the template")
        .onDrag {
            NSItemProvider(object: field.token as NSString)
        }
    }

    private func insertFieldToken(_ field: FileRenameMetadataField) {
        guard !isApplying else { return }
        pendingFieldInsertion = FileRenameTemplateEditorInsertion(field: field)
    }

    private func applyRename() {
        let plan = renamePlan
        guard plan.canApply else { return }

        isApplying = true

        Task { @MainActor in
            let result = await viewModel.renameFiles(using: plan)
            isApplying = false

            if result.didSucceed && renamePlan.issueCount == 0 {
                isPresented = false
            }
        }
    }
}

private struct MetadataFilenameRenamePreviewList: View {
    let rows: [FileRenamePreviewRow]

    var body: some View {
        MetadataSectionCard(title: "Filename Comparison", symbolName: "arrow.left.arrow.right") {
            MetadataFilenameRenameComparisonHeader()

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                MetadataFilenameRenameComparisonRowView(row: row)

                if index < rows.count - 1 {
                    MetadataCardDivider()
                }
            }
        }
    }
}

private struct MetadataFilenameRenameComparisonHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Status")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Current Name")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Preview")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct MetadataFilenameRenameComparisonRowView: View {
    let row: FileRenamePreviewRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.status.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.status.tint)
                    .multilineTextAlignment(.leading)

                if row.status != .ready {
                    Text(row.status.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: 118, alignment: .leading)

            MetadataFilenameRenameComparisonValue(
                row.currentName,
                foregroundColor: .primary
            )

            Image(systemName: row.status.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.status.tint)
                .help(row.status.message)
                .frame(width: 18)
                .padding(.top, 1)

            MetadataFilenameRenameComparisonValue(
                row.previewName,
                foregroundColor: row.status.isError ? .orange : .primary
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct MetadataFilenameRenameComparisonValue: View {
    let value: String
    let foregroundColor: Color

    init(_ value: String, foregroundColor: Color) {
        self.value = value
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Text(value.isEmpty ? "—" : value)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(value.isEmpty ? Color(nsColor: .tertiaryLabelColor) : foregroundColor)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FileRenameTemplateEditorInsertion: Equatable {
    let id = UUID()
    let field: FileRenameMetadataField
}

private struct FileRenameTemplateEditor: NSViewRepresentable {
    @Binding var template: String
    @Binding var pendingInsertion: FileRenameTemplateEditorInsertion?
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.font = Self.editorFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.applyTemplate(template, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.isEditable != isEnabled {
            textView.isEditable = isEnabled
        }

        context.coordinator.refreshLiteralStyling(in: textView)

        let serializedTemplate = context.coordinator.serialize(textStorage: textView.textStorage)
        if serializedTemplate != template {
            context.coordinator.applyTemplate(template, to: textView)
        }

        if context.coordinator.lastAppliedInsertionID != pendingInsertion?.id,
           let insertion = pendingInsertion {
            context.coordinator.insert(field: insertion.field, into: textView)
            context.coordinator.lastAppliedInsertionID = insertion.id
        }
    }

    private static let editorFont = NSFont.monospacedSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FileRenameTemplateEditor
        weak var textView: NSTextView?
        var isApplyingProgrammaticUpdate = false
        var selectedRange = NSRange(location: 0, length: 0)
        var lastAppliedInsertionID: UUID?

        init(parent: FileRenameTemplateEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView, notification.object as AnyObject? === textView else { return }

            refreshLiteralStyling(in: textView)

            let serializedTemplate = serialize(textStorage: textView.textStorage)
            guard serializedTemplate != parent.template else { return }

            parent.template = serializedTemplate
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, notification.object as AnyObject? === textView else { return }
            selectedRange = textView.selectedRange()
            textView.typingAttributes = literalAttributes()
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingProgrammaticUpdate else { return true }
            guard let replacementString, !replacementString.isEmpty else { return true }

            let document = FileRenameTemplateDocument(rawValue: replacementString)
            guard document.containsFieldSegments else { return true }

            replaceCharacters(in: affectedCharRange, with: document, in: textView)
            return false
        }

        func applyTemplate(_ template: String, to textView: NSTextView) {
            let document = FileRenameTemplateDocument(rawValue: template)
            let attributed = attributedString(for: document)
            let clampedRange = clampSelectedRange(selectedRange, textLength: attributed.length)

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(clampedRange)
            selectedRange = clampedRange
            refreshLiteralStyling(in: textView)
            isApplyingProgrammaticUpdate = false
        }

        func insert(field: FileRenameMetadataField, into textView: NSTextView) {
            let insertionRange = clampSelectedRange(
                selectedRange,
                textLength: textView.textStorage?.length ?? 0
            )
            replaceCharacters(
                in: insertionRange,
                with: FileRenameTemplateDocument(rawValue: field.token),
                in: textView,
                clearPendingInsertion: true
            )
            textView.window?.makeFirstResponder(textView)
        }

        func serialize(textStorage: NSTextStorage?) -> String {
            guard let textStorage else { return "" }

            var serialized = ""
            var index = 0

            while index < textStorage.length {
                if let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? FileRenameFieldAttachment {
                    serialized += attachment.field.token
                    index += 1
                    continue
                }

                var effectiveRange = NSRange(location: 0, length: 0)
                _ = textStorage.attribute(.attachment, at: index, effectiveRange: &effectiveRange)
                let literalRange = effectiveRange.length > 0
                    ? effectiveRange
                    : NSRange(location: index, length: 1)
                serialized += textStorage.attributedSubstring(from: literalRange).string
                index = literalRange.location + literalRange.length
            }

            return serialized
        }

        private func replaceCharacters(
            in affectedCharRange: NSRange,
            with document: FileRenameTemplateDocument,
            in textView: NSTextView,
            clearPendingInsertion: Bool = false
        ) {
            let replacement = attributedString(for: document)
            let clampedRange = clampSelectedRange(
                affectedCharRange,
                textLength: textView.textStorage?.length ?? 0
            )

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: clampedRange, with: replacement)
            let insertionLocation = clampedRange.location + replacement.length
            let newSelection = NSRange(location: insertionLocation, length: 0)
            textView.setSelectedRange(newSelection)
            selectedRange = newSelection
            refreshLiteralStyling(in: textView)
            textView.didChangeText()
            isApplyingProgrammaticUpdate = false

            scheduleTemplateStateSync(
                from: textView,
                clearPendingInsertion: clearPendingInsertion
            )
        }

        private func attributedString(for document: FileRenameTemplateDocument) -> NSAttributedString {
            let attributed = NSMutableAttributedString()

            for segment in document.segments {
                switch segment {
                case .literal(let literal):
                    attributed.append(NSAttributedString(string: literal, attributes: literalAttributes()))
                case .field(let field):
                    attributed.append(NSAttributedString(attachment: FileRenameFieldAttachment(field: field)))
                }
            }

            if attributed.length == 0 {
                attributed.append(NSAttributedString(string: "", attributes: literalAttributes()))
            }

            return attributed
        }

        private func literalAttributes() -> [NSAttributedString.Key: Any] {
            [
                .font: FileRenameTemplateEditor.editorFont,
                .foregroundColor: parent.isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
        }

        func refreshLiteralStyling(in textView: NSTextView) {
            let literalColor = parent.isEnabled ? NSColor.labelColor : NSColor.secondaryLabelColor
            textView.textColor = literalColor
            textView.insertionPointColor = literalColor
            textView.typingAttributes = literalAttributes()

            guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }

            let attributes = literalAttributes()
            textStorage.beginEditing()

            var index = 0
            while index < textStorage.length {
                var effectiveRange = NSRange(location: 0, length: 0)
                let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: &effectiveRange)
                let range = effectiveRange.length > 0
                    ? effectiveRange
                    : NSRange(location: index, length: 1)

                if !(attachment is FileRenameFieldAttachment) {
                    textStorage.addAttributes(attributes, range: range)
                }

                index = range.location + range.length
            }

            textStorage.endEditing()
        }

        private func scheduleTemplateStateSync(
            from textView: NSTextView,
            clearPendingInsertion: Bool
        ) {
            let serializedTemplate = serialize(textStorage: textView.textStorage)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if self.parent.template != serializedTemplate {
                    self.parent.template = serializedTemplate
                }

                if clearPendingInsertion {
                    self.parent.pendingInsertion = nil
                }
            }
        }

        private func clampSelectedRange(_ range: NSRange, textLength: Int) -> NSRange {
            let location = min(max(range.location, 0), textLength)
            let length = min(max(range.length, 0), textLength - location)
            return NSRange(location: location, length: length)
        }
    }
}

private final class FileRenameFieldAttachment: NSTextAttachment {
    let field: FileRenameMetadataField

    init(field: FileRenameMetadataField) {
        self.field = field
        super.init(data: nil, ofType: nil)
        attachmentCell = NSTextAttachmentCell(imageCell: Self.makeChipImage(title: field.displayName))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private static func makeChipImage(title: String) -> NSImage {
        let chipFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 4
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: chipFont,
            .foregroundColor: NSColor.controlAccentColor
        ]
        let textSize = title.size(withAttributes: textAttributes)
        let size = NSSize(
            width: ceil(textSize.width) + (horizontalPadding * 2),
            height: ceil(textSize.height) + (verticalPadding * 2)
        )

        let image = NSImage(size: size)
        image.lockFocus()

        let drawingFrame = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 1.5)
        let backgroundPath = NSBezierPath(
            roundedRect: drawingFrame,
            xRadius: drawingFrame.height / 2,
            yRadius: drawingFrame.height / 2
        )

        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        backgroundPath.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.24).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let textRect = NSRect(
            x: round((size.width - textSize.width) / 2),
            y: round((size.height - textSize.height) / 2),
            width: textSize.width,
            height: textSize.height
        )
        title.draw(in: textRect, withAttributes: textAttributes)

        image.unlockFocus()
        return image
    }
}

private extension FileRenamePreviewStatus {
    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .emptyName, .duplicateTarget, .existingFile:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged:
            return .secondary
        case .emptyName, .duplicateTarget, .existingFile:
            return .orange
        }
    }
}
