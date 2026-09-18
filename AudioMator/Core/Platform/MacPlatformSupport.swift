import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum AudiomatorScrollEdgeEffectStyle {
    case soft
}

extension View {
    @ViewBuilder
    func audiomatorScrollEdgeEffect(
        _ style: AudiomatorScrollEdgeEffectStyle = .soft,
        for edges: Edge.Set = .all
    ) -> some View {
        if #available(macOS 26.0, *) {
            switch style {
            case .soft:
                scrollEdgeEffectStyle(.soft, for: edges)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func audiomatorSafeAreaBar<Content: View>(
        edge: VerticalEdge,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: spacing, content: content)
        }
    }

    @ViewBuilder
    func audiomatorRegularGlassRoundedRectangle(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    func audiomatorRegularGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func audiomatorNavigationSubtitle(_ subtitle: String) -> some View {
        navigationSubtitle(subtitle)
    }
}

extension NSImage {
    var audiomatorPNGData: Data? {
        guard
            let tiffData = tiffRepresentation,
            let bitmapRepresentation = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmapRepresentation.representation(using: .png, properties: [:])
    }
}

extension NSColor {
    static var audiomatorWindowBackground: NSColor { .windowBackgroundColor }
    static var audiomatorControlBackground: NSColor { .controlBackgroundColor }
    static var audiomatorTextBackground: NSColor { .textBackgroundColor }
    static var audiomatorSeparator: NSColor { .separatorColor }
    static var audiomatorLabel: NSColor { .labelColor }
    static var audiomatorSecondaryLabel: NSColor { .secondaryLabelColor }
    static var audiomatorTertiaryLabel: NSColor { .tertiaryLabelColor }
}

extension View {
    func audiomatorMacWindowChrome() -> some View {
        background(AudiomatorMacWindowChromeConfigurator())
    }

    func audiomatorMacTitlebarScrollEdgeBar(
        minHeight: CGFloat = 0,
        subtractsExistingSafeArea: Bool = true
    ) -> some View {
        modifier(
            AudiomatorMacTitlebarScrollEdgeBarModifier(
                minHeight: minHeight,
                subtractsExistingSafeArea: subtractsExistingSafeArea
            )
        )
    }
}

private struct AudiomatorMacWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> AudiomatorMacWindowChromeObserverView {
        let view = AudiomatorMacWindowChromeObserverView()
        view.configure = applyConfiguration(to:)
        return view
    }

    func updateNSView(_ nsView: AudiomatorMacWindowChromeObserverView, context: Context) {
        nsView.configure = applyConfiguration(to:)
        DispatchQueue.main.async {
            applyConfiguration(to: nsView.window)
        }
    }

    private func applyConfiguration(to window: NSWindow?) {
        guard let window else { return }

        let requiredMasks: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        if !window.styleMask.isSuperset(of: requiredMasks) {
            window.styleMask.formUnion(requiredMasks)
        }

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
    }
}

private final class AudiomatorMacWindowChromeObserverView: NSView {
    var configure: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure?(window)
    }
}

private struct AudiomatorMacTitlebarScrollEdgeBarModifier: ViewModifier {
    let minHeight: CGFloat
    let subtractsExistingSafeArea: Bool
    @State private var titlebarHeight: CGFloat = 0
    @State private var safeAreaTop: CGFloat = 0

    private var barHeight: CGFloat {
        let baseHeight = max(titlebarHeight, minHeight)
        let existingSafeArea = subtractsExistingSafeArea ? safeAreaTop : 0
        return max(0, baseHeight - existingSafeArea)
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: AudiomatorMacSafeAreaTopPreferenceKey.self,
                            value: proxy.safeAreaInsets.top
                        )
                }
            }
            .onPreferenceChange(AudiomatorMacSafeAreaTopPreferenceKey.self) { safeAreaTop = $0 }
            .audiomatorSafeAreaBar(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: barHeight)
                    .background(AudiomatorMacTitlebarInsetReader(inset: $titlebarHeight))
            }
    }
}

private struct AudiomatorMacSafeAreaTopPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AudiomatorMacTitlebarInsetReader: NSViewRepresentable {
    @Binding var inset: CGFloat

    func makeNSView(context: Context) -> AudiomatorMacTitlebarInsetObserverView {
        let view = AudiomatorMacTitlebarInsetObserverView()
        view.onUpdate = updateInset(from:)
        return view
    }

    func updateNSView(_ nsView: AudiomatorMacTitlebarInsetObserverView, context: Context) {
        nsView.onUpdate = updateInset(from:)
        DispatchQueue.main.async {
            updateInset(from: nsView)
        }
    }

    private func updateInset(from view: NSView) {
        guard let window = view.window, let contentView = window.contentView else { return }

        let contentBounds = contentView.convert(contentView.bounds, to: nil)
        let titlebarInset = max(0, contentBounds.maxY - window.contentLayoutRect.maxY)

        if abs(inset - titlebarInset) > 0.5 {
            inset = titlebarInset
        }
    }
}

private final class AudiomatorMacTitlebarInsetObserverView: NSView {
    var onUpdate: ((NSView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onUpdate?(self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        onUpdate?(self)
    }
}

enum MacApplication {
    static func terminate() {
        NSApplication.shared.terminate(nil)
    }

    static var appIconImage: NSImage? {
        NSApplication.shared.applicationIconImage
    }
}

enum MacPasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static var image: NSImage? {
        NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage
    }
}

enum MacWorkspace {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

enum SecurityScopedResourceAccess {
    static func withAccess<Result>(
        to url: URL,
        startAccessing: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccessing: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        perform: () throws -> Result
    ) rethrows -> Result {
        let didStartAccess = startAccessing(url)
        defer {
            if didStartAccess {
                stopAccessing(url)
            }
        }

        return try perform()
    }
}

enum MacDocumentPicker {
    static func pickAudioFiles(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioFormatSupport.openPanelContentTypes
        panel.title = "Choose Audio Files"
        completion(panel.runModal() == .OK ? panel.urls : [])
    }

    static func pickImage(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Artwork Image"
        completion(panel.runModal() == .OK ? panel.url : nil)
    }

    static func pickTextFile(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
        panel.title = "Choose a Text File"
        panel.prompt = "Choose"
        completion(panel.runModal() == .OK ? panel.url : nil)
    }
}
