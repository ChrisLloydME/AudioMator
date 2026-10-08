import AppKit
import Combine
import ImageIO
import SwiftUI

struct InspectorArtworkSource: Sendable {
    let id: UUID
    let data: Data
}

/// Keeps image work out of selection handling and SwiftUI body evaluation.
@MainActor
final class InspectorArtworkPreview: ObservableObject {
    @Published private(set) var image: NSImage?
    private(set) var sourceID: UUID?
    private var cache: [(id: UUID, image: NSImage?)] = []
    private var worker: Task<CGImage?, Never>?
    private var completion: Task<Void, Never>?
    private let decode: @Sendable (Data) async -> CGImage?

    init(decode: (@Sendable (Data) async -> CGImage?)? = nil) {
        let decoder = InspectorArtworkDecoder()
        self.decode = decode ?? { await decoder.thumbnail(from: $0) }
    }

    deinit {
        worker?.cancel()
        completion?.cancel()
    }

    func update(_ source: InspectorArtworkSource?) {
        guard sourceID != source?.id else { return }
        worker?.cancel()
        completion?.cancel()
        sourceID = source?.id
        image = nil
        guard let source else { return }

        if let index = cache.firstIndex(where: { $0.id == source.id }) {
            let entry = cache.remove(at: index)
            cache.append(entry)
            image = entry.image
            return
        }

        let decode = decode
        let worker = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return nil as CGImage? }
            return await decode(source.data)
        }
        self.worker = worker
        completion = Task { [weak self] in
            let decoded = await worker.value
            guard !Task.isCancelled, let self, self.sourceID == source.id else { return }
            let image = decoded.map { decoded in
                let representation = NSBitmapImageRep(cgImage: decoded)
                let image = NSImage(size: representation.size)
                image.addRepresentation(representation)
                return image
            }
            self.cache.append((source.id, image))
            if self.cache.count > 8 { self.cache.removeFirst() }
            self.image = image
            self.worker = nil
            self.completion = nil
        }
    }

    nonisolated static func thumbnail(from data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= ArtworkImageNormalizer.maximumInputByteCount,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary), CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 440,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

// Serializes ImageIO work within this inspector. Cancelled queued selections
// are discarded before decoding rather than spawning concurrent image work.
private actor InspectorArtworkDecoder {
    func thumbnail(from data: Data) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return InspectorArtworkPreview.thumbnail(from: data)
    }
}

struct InspectorArtworkPreviewView<Placeholder: View>: View {
    @ObservedObject var preview: InspectorArtworkPreview
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if let image = preview.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 220)
                .cornerRadius(8)
        } else {
            placeholder()
        }
    }
}
