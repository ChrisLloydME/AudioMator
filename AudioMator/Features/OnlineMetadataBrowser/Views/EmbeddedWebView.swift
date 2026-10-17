import SwiftUI
import WebKit

nonisolated enum EmbeddedWebURLPolicy {
    /// Only HTTPS pages from the metadata providers AudioMator renders may
    /// enter the embedded web container. Provider JSON is untrusted input.
    static func validatedURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return nil
        }
        let allowedSuffixes = ["apple.com", "musicbrainz.org"]
        guard allowedSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else {
            return nil
        }
        return url
    }
}

struct EmbeddedWebView: View {
    let url: URL
    let reloadToken: Int

    var body: some View {
        WebViewRepresentable(url: url, reloadToken: reloadToken)
    }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.loadIfNeeded(
            url: url,
            reloadToken: reloadToken,
            in: webView
        )
    }
}

private final class Coordinator: NSObject, WKNavigationDelegate {
    private var loadedURL: URL?
    private var loadedReloadToken: Int?

    func loadIfNeeded(url: URL, reloadToken: Int, in webView: WKWebView) {
        guard loadedURL != url || loadedReloadToken != reloadToken else { return }
        guard let validatedURL = EmbeddedWebURLPolicy.validatedURL(url) else { return }

        loadedURL = validatedURL
        loadedReloadToken = reloadToken
        webView.load(URLRequest(url: validatedURL))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              EmbeddedWebURLPolicy.validatedURL(url) != nil else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
