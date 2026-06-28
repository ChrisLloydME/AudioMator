import SwiftUI

#if os(macOS)
import AppKit

struct MetadataExchangeTemplateEditorInsertion: Equatable {
    let id = UUID()
    let field: MetadataExchangeField
}

struct MetadataExchangeTemplateEditor: NSViewRepresentable {
    @Binding var template: String
    @Binding var pendingInsertion: MetadataExchangeTemplateEditorInsertion?
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
        var parent: MetadataExchangeTemplateEditor
        weak var textView: NSTextView?
        var isApplyingProgrammaticUpdate = false
        var selectedRange = NSRange(location: 0, length: 0)
        var lastAppliedInsertionID: UUID?

        init(parent: MetadataExchangeTemplateEditor) {
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

            let document = MetadataExchangeTemplateDocument(rawValue: replacementString)
            guard document.segments.contains(where: { segment in
                if case .field = segment { return true }
                return false
            }) else {
                return true
            }

            replaceCharacters(in: affectedCharRange, with: document, in: textView)
            return false
        }

        func applyTemplate(_ template: String, to textView: NSTextView) {
            let document = MetadataExchangeTemplateDocument(rawValue: template)
            let attributed = attributedString(for: document)
            let clampedRange = clampSelectedRange(selectedRange, textLength: attributed.length)

            isApplyingProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(attributed)
            textView.setSelectedRange(clampedRange)
            selectedRange = clampedRange
            refreshLiteralStyling(in: textView)
            isApplyingProgrammaticUpdate = false
        }

        func insert(field: MetadataExchangeField, into textView: NSTextView) {
            let insertionRange = clampSelectedRange(
                selectedRange,
                textLength: textView.textStorage?.length ?? 0
            )
            replaceCharacters(
                in: insertionRange,
                with: MetadataExchangeTemplateDocument(rawValue: field.token),
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
                if let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? MetadataExchangeFieldAttachment {
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
            with document: MetadataExchangeTemplateDocument,
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

        private func attributedString(for document: MetadataExchangeTemplateDocument) -> NSAttributedString {
            let attributed = NSMutableAttributedString()

            for segment in document.segments {
                switch segment {
                case .literal(let literal):
                    attributed.append(NSAttributedString(string: literal, attributes: literalAttributes()))
                case .field(let field):
                    attributed.append(NSAttributedString(attachment: MetadataExchangeFieldAttachment(field: field)))
                }
            }

            if attributed.length == 0 {
                attributed.append(NSAttributedString(string: "", attributes: literalAttributes()))
            }

            return attributed
        }

        private func literalAttributes() -> [NSAttributedString.Key: Any] {
            [
                .font: MetadataExchangeTemplateEditor.editorFont,
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

                if !(attachment is MetadataExchangeFieldAttachment) {
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

private final class MetadataExchangeFieldAttachment: NSTextAttachment {
    let field: MetadataExchangeField

    init(field: MetadataExchangeField) {
        self.field = field
        super.init(data: nil, ofType: nil)
        attachmentCell = NSTextAttachmentCell(imageCell: FileRenameFieldAttachment.makeChipImage(title: field.displayName))
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

struct FileRenameTemplateEditorInsertion: Equatable {
    let id = UUID()
    let field: FileRenameMetadataField
}

struct FileRenameTemplateEditor: NSViewRepresentable {
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

    fileprivate static func makeChipImage(title: String) -> NSImage {
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
#endif
