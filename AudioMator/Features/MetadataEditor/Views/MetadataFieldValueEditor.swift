import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MetadataFieldValueEditor: View {
    @Binding var text: String
    let placeholder: String
    var minimumHeight: CGFloat = 300

    #if os(macOS)
    private let editorFont = NSFont(name: "Menlo-Regular", size: 13) ??
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    #endif

    private var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    private var borderColor: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.55)
        #else
        Color.secondary.opacity(0.25)
        #endif
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)

            #if os(macOS)
            MetadataFieldValueTextEditor(text: $text, font: editorFont)
                .padding(1)
            #else
            TextEditor(text: $text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .padding(8)
            #endif

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .frame(minHeight: minimumHeight)
    }
}

#if os(macOS)
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
