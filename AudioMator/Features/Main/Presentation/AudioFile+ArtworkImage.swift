import AppKit

extension AudioFile {
    /// UI-only projection of the immutable, sendable artwork payload.
    @MainActor
    var artwork: NSImage? {
        artworkData.flatMap(NSImage.init(data:))
    }
}
