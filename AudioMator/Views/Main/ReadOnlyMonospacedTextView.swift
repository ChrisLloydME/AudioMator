import SwiftUI

#if os(macOS)
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
        textView.string = text
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
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

        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
    }
}
#else
struct ReadOnlyMonospacedTextView: View {
    var text: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }
}
#endif
