import SwiftUI
import WebKit

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
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.loadIfNeeded(
            url: url,
            reloadToken: reloadToken,
            in: webView
        )
    }
}

private final class Coordinator {
    private var loadedURL: URL?
    private var loadedReloadToken: Int?

    func loadIfNeeded(url: URL, reloadToken: Int, in webView: WKWebView) {
        guard loadedURL != url || loadedReloadToken != reloadToken else { return }

        loadedURL = url
        loadedReloadToken = reloadToken
        webView.load(URLRequest(url: url))
    }
}
