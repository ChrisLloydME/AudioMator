import Foundation

/// Candidate-scoped preview URL fallback. The value is recreated for each
/// selected candidate, so a candidate switch always starts at the first
/// preferred preview URL, and a delayed failure can only advance the fallback
/// when it reports the URL this value is currently showing.
struct ArtworkPreviewFallback: Equatable {
    let urls: [URL]
    private(set) var index: Int

    init(urls: [URL], index: Int = 0) {
        self.urls = urls
        self.index = urls.indices.contains(index) ? index : 0
    }

    var currentURL: URL? {
        guard urls.indices.contains(index) else { return nil }
        return urls[index]
    }

    var hasSuccessor: Bool {
        currentURL != nil && urls.indices.contains(index + 1)
    }

    /// Advances to the next URL only when `url` is the URL currently shown and
    /// a successor exists. Returns whether the fallback advanced.
    @discardableResult
    mutating func advance(afterFailedURL url: URL) -> Bool {
        guard currentURL == url, hasSuccessor else { return false }
        index += 1
        return true
    }

    mutating func reset() {
        index = 0
    }
}
