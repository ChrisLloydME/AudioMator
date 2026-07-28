import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ArtworkImageNormalizerError: LocalizedError, Equatable {
    case inputTooLarge
    case invalidImage
    case unsafeDimensions
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .inputTooLarge:
            return "The artwork file is too large to process safely."
        case .invalidImage:
            return "The selected artwork image could not be opened."
        case .unsafeDimensions:
            return "The artwork dimensions are too large to process safely."
        case .encodingFailed:
            return "The selected artwork image could not be converted to PNG."
        }
    }
}

nonisolated enum ArtworkImageNormalizer {
    static let maximumInputByteCount = 50 * 1_024 * 1_024
    static let maximumPixelDimension = 4_096
    static let maximumSourcePixelCount = 4_096 * 4_096
    private static let maximumSourcePixelDimension = 32_768

    static func normalizedPNGData(
        from url: URL,
        maximumInputByteCount: Int = maximumInputByteCount,
        maximumPixelDimension: Int = maximumPixelDimension,
        maximumSourcePixelCount: Int = maximumSourcePixelCount
    ) throws -> Data {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            throw ArtworkImageNormalizerError.invalidImage
        }
        if let fileSize = resourceValues.fileSize, fileSize > maximumInputByteCount {
            throw ArtworkImageNormalizerError.inputTooLarge
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try normalizedPNGData(
            from: data,
            maximumInputByteCount: maximumInputByteCount,
            maximumPixelDimension: maximumPixelDimension,
            maximumSourcePixelCount: maximumSourcePixelCount
        )
    }

    static func normalizedPNGData(
        from data: Data,
        maximumInputByteCount: Int = maximumInputByteCount,
        maximumPixelDimension: Int = maximumPixelDimension,
        maximumSourcePixelCount: Int = maximumSourcePixelCount
    ) throws -> Data {
        guard !data.isEmpty else { throw ArtworkImageNormalizerError.invalidImage }
        guard data.count <= maximumInputByteCount else {
            throw ArtworkImageNormalizerError.inputTooLarge
        }
        guard maximumPixelDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw ArtworkImageNormalizerError.invalidImage
        }
        let (sourcePixelCount, didOverflow) = width.multipliedReportingOverflow(by: height)
        guard !didOverflow,
              sourcePixelCount <= maximumSourcePixelCount,
              width <= maximumSourcePixelDimension,
              height <= maximumSourcePixelDimension else {
            throw ArtworkImageNormalizerError.unsafeDimensions
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw ArtworkImageNormalizerError.invalidImage
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ArtworkImageNormalizerError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ArtworkImageNormalizerError.encodingFailed
        }

        return encodedData as Data
    }
}
