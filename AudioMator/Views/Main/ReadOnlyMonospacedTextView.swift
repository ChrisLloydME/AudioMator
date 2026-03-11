import SwiftUI
import AppKit

// MARK: - Read-only monospaced text view (AppKit-backed)
struct ReadOnlyMonospacedTextView: NSViewRepresentable {
    var text: String
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    var textColor: NSColor = .labelColor

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = textColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = font

        // Seed initial content (SwiftUI may not call update before first draw in some sheet transitions)
        textView.string = text

        // Allow horizontal scrolling for very long lines
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Important: give the container an effectively unbounded width so the scroll view can scroll horizontally
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Give the document view a non-zero frame so it actually renders inside the scroll view
        textView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.font != font {
            textView.font = font
        }

        if textView.textColor != textColor {
            textView.textColor = textColor
        }

        // Avoid resetting selection/scroll if the text didn't actually change
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }
}
