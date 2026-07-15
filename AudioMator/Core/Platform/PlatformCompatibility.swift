import SwiftUI
import UniformTypeIdentifiers

extension View {
    func audiomatorScrollEdgeEffect(
        _ style: ScrollEdgeEffectStyle = .soft,
        for edges: Edge.Set = .all
    ) -> some View {
        scrollEdgeEffectStyle(style, for: edges)
    }
}

#if os(macOS)
import AppKit

typealias PlatformImage = NSImage
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        self.init(nsColor: platformColor)
    }
}

extension PlatformImage {
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

extension PlatformColor {
    static var audiomatorWindowBackground: PlatformColor { .windowBackgroundColor }
    static var audiomatorControlBackground: PlatformColor { .controlBackgroundColor }
    static var audiomatorTextBackground: PlatformColor { .textBackgroundColor }
    static var audiomatorSeparator: PlatformColor { .separatorColor }
    static var audiomatorLabel: PlatformColor { .labelColor }
    static var audiomatorSecondaryLabel: PlatformColor { .secondaryLabelColor }
    static var audiomatorTertiaryLabel: PlatformColor { .tertiaryLabelColor }
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
            .safeAreaBar(edge: .top, spacing: 0) {
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
#else
import UIKit

typealias PlatformImage = UIImage
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        self.init(uiColor: platformColor)
    }
}

extension PlatformImage {
    var audiomatorPNGData: Data? {
        pngData()
    }
}

extension PlatformColor {
    static var audiomatorWindowBackground: PlatformColor { .systemBackground }
    static var audiomatorControlBackground: PlatformColor { .secondarySystemGroupedBackground }
    static var audiomatorTextBackground: PlatformColor { .secondarySystemBackground }
    static var audiomatorSeparator: PlatformColor { .separator }
    static var audiomatorLabel: PlatformColor { .label }
    static var audiomatorSecondaryLabel: PlatformColor { .secondaryLabel }
    static var audiomatorTertiaryLabel: PlatformColor { .tertiaryLabel }
}

extension View {
    func audiomatorMacWindowChrome() -> some View {
        self
    }

    func audiomatorMacTitlebarScrollEdgeBar(
        minHeight: CGFloat = 0,
        subtractsExistingSafeArea: Bool = true
    ) -> some View {
        self
    }

    @ViewBuilder
    func iPadRoundedGroupedListStyle() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .audiomatorScrollEdgeEffect()
    }

    @ViewBuilder
    func iPadRoundedGroupedFormStyle() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .audiomatorScrollEdgeEffect()
    }

    @ViewBuilder
    func iPadRoundedGroupedSurface(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct IPadRoundedRowGroup<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iPadRoundedGroupedSurface(cornerRadius: cornerRadius)
    }
}

struct IPadDismissibleSheet<Content: View>: View {
    let title: String
    let isCloseDisabled: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    init(
        title: String = "",
        isCloseDisabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isCloseDisabled = isCloseDisabled
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                        .disabled(isCloseDisabled)
                    }
                }
        }
        .presentationDetents([.large])
    }
}
#endif

enum PlatformApplication {
    static var supportsWatchedFolders: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    static func terminate() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #endif
    }

    static var appIconImage: PlatformImage? {
        #if os(macOS)
        NSApplication.shared.applicationIconImage
        #else
        UIImage(named: "AppIconPreview")
        #endif
    }
}

enum PlatformPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static var image: PlatformImage? {
        #if os(macOS)
        return NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage
        #else
        return UIPasteboard.general.image
        #endif
    }
}

enum PlatformWorkspace {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    static func reveal(_ urls: [URL]) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #else
        guard let firstURL = urls.first else { return }
        UIApplication.shared.open(firstURL)
        #endif
    }
}

enum PlatformDocumentPicker {
    static func pickAudioFiles(completion: @escaping ([URL]) -> Void) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioFormatSupport.openPanelContentTypes
        panel.title = "Choose Audio Files"
        completion(panel.runModal() == .OK ? panel.urls : [])
        #else
        present(
            contentTypes: AudioFormatSupport.openPanelContentTypes,
            allowsMultipleSelection: true,
            completion: completion
        )
        #endif
    }

    static func pickImage(completion: @escaping (URL?) -> Void) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Choose Artwork Image"
        completion(panel.runModal() == .OK ? panel.url : nil)
        #else
        present(contentTypes: [.image], allowsMultipleSelection: false) { urls in
            completion(urls.first)
        }
        #endif
    }

    static func pickTextFile(completion: @escaping (URL?) -> Void) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.plainText, .utf8PlainText, .text]
        panel.title = "Choose a Text File"
        panel.prompt = "Choose"
        completion(panel.runModal() == .OK ? panel.url : nil)
        #else
        present(contentTypes: [.plainText, .utf8PlainText, .text], allowsMultipleSelection: false) { urls in
            completion(urls.first)
        }
        #endif
    }

    #if os(iOS)
    private static var activeDelegates: [DocumentPickerDelegate] = []

    private static func present(
        contentTypes: [UTType],
        allowsMultipleSelection: Bool,
        completion: @escaping ([URL]) -> Void
    ) {
        guard let presenter = topViewController() else {
            completion([])
            return
        }

        let delegate = DocumentPickerDelegate(completion: completion)
        activeDelegates.append(delegate)

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: false
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = delegate
        delegate.onFinish = {
            activeDelegates.removeAll { $0 === delegate }
        }

        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let root = windowScene?.windows.first { $0.isKeyWindow }?.rootViewController
        return topViewController(from: root)
    }

    private static func topViewController(from controller: UIViewController?) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }
        if let tabBarController = controller as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(from: presented)
        }
        return controller
    }

    private final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        var onFinish: (() -> Void)?

        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
            onFinish?()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion([])
            onFinish?()
        }
    }
    #endif
}
