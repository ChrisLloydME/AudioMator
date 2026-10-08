import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AudioMator

@MainActor
final class InspectorArtworkPreviewTests: XCTestCase {
    func testPreviewIsBoundedAndReusesDecodedImageAcrossRefreshesAndReselection() async throws {
        let source = InspectorArtworkSource(id: UUID(), data: try makePNG(width: 1200, height: 800))
        let preview = InspectorArtworkPreview()
        preview.update(source)
        try await waitUntil { preview.image != nil }
        let image = try XCTUnwrap(preview.image)
        let representation = try XCTUnwrap(image.representations.first)
        XCTAssertLessThanOrEqual(max(representation.pixelsWide, representation.pixelsHigh), 440)
        preview.update(source)
        XCTAssertTrue(preview.image === image)
        preview.update(nil)
        XCTAssertNil(preview.image)
        preview.update(source)
        XCTAssertTrue(preview.image === image)
    }

    func testSlowDecodeDoesNotBlockMainActorOrPublishAfterSelectionChanges() async throws {
        let gate = PreviewDecodeGate()
        let preview = InspectorArtworkPreview { _ in
            await gate.decode()
        }
        preview.update(InspectorArtworkSource(id: UUID(), data: Data([1])))
        await gate.waitUntilStarted()
        // We can change selection on the main actor while decoding is suspended.
        preview.update(nil)
        XCTAssertNil(preview.sourceID)
        let staleImage = expectation(description: "Cancelled decode must not publish its image")
        staleImage.isInverted = true
        let observation = preview.$image.dropFirst().sink { image in
            if image != nil { staleImage.fulfill() }
        }
        await gate.release(InspectorArtworkPreview.thumbnail(from: try makePNG(width: 16, height: 16)))
        await fulfillment(of: [staleImage], timeout: 0.1)
        withExtendedLifetime(observation) {}
        XCTAssertNil(preview.image)
    }

    func testNewSnapshotForSameFileInvalidatesPreview() async throws {
        let fileID = UUID()
        let original = AudioFileTestFactory.make(id: fileID, artworkData: try makePNG(width: 16, height: 16))
        let refreshed = AudioFileTestFactory.make(id: fileID, artworkData: try makePNG(width: 32, height: 32))
        XCTAssertNotEqual(original.snapshotID, refreshed.snapshotID)
        let copy = original
        XCTAssertEqual(copy.snapshotID, original.snapshotID)
        let preview = InspectorArtworkPreview()
        preview.update(InspectorArtworkSource(id: original.snapshotID, data: try XCTUnwrap(original.artworkData)))
        try await waitUntil { preview.image != nil }
        let previousImage = preview.image
        preview.update(InspectorArtworkSource(id: refreshed.snapshotID, data: try XCTUnwrap(refreshed.artworkData)))
        XCTAssertNil(preview.image)
        try await waitUntil { preview.image != nil }
        XCTAssertFalse(preview.image === previousImage)
    }

    func testInvalidAndOversizedInputDoesNotProducePreview() {
        XCTAssertNil(InspectorArtworkPreview.thumbnail(from: Data([1, 2, 3])))
        XCTAssertNil(InspectorArtworkPreview.thumbnail(
            from: Data(repeating: 0, count: ArtworkImageNormalizer.maximumInputByteCount + 1)
        ))
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for artwork preview")
    }
}

private actor PreviewDecodeGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var decodeWaiter: CheckedContinuation<CGImage?, Never>?

    func decode() async -> CGImage? {
        await withCheckedContinuation { continuation in
            decodeWaiter = continuation
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release(_ image: CGImage?) {
        decodeWaiter?.resume(returning: image)
        decodeWaiter = nil
    }
}
