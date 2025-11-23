
#if ImageDataTransformationEnabled
import ImageIO
internal import class CoreGraphics.CGImage
import struct Foundation.Data
import protocol Foundation.LocalizedError

internal extension AudioFile.Metadata.AttachedPicture {
    /// Creates `AttachedPicture` from `CGImage` with `kind` and `description`.
    init(image: CGImage, kind: Kind, description: String) throws(ImageDataExtractionError) {
        guard let dataProvider = image.dataProvider else {
            throw .noDataProvider
        }
        guard let data = dataProvider.data as? Data else {
            throw .noDataInDataProvider
        }
        self.init(data: data, kind: kind, description: description)
    }
    /// Attempts to construct `CGImage` from **raw** `Data`.
    var cgImage: CGImage? {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, .none),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, .none)
        else {
            return .none
        }
        return image
    }
}

public extension AudioFile.Metadata.AttachedPicture {
    /// Descrbies error occuring when creating `AttachedPicture` from either `CGImage`, `NSImage` or `UIImage`.
    enum ImageDataExtractionError: Swift.Error, LocalizedError {
        // CGImage:
        case noDataProvider
        case noDataInDataProvider
        // UIImage:
        case noCGImageBehindUIImage
        // NSImage:
        case noTiffRepresentationBehindNSImage
        case failedToCreateImageSource
        case failedToCreateCGImage

        public var errorDescription: String? {
            switch self {
                case .noDataProvider: "no CGDataProvider in CGImage"
                case .noDataInDataProvider: "no Data in CGDataProvider"
                case .noCGImageBehindUIImage: "no CGImage behind UIImage"
                case .noTiffRepresentationBehindNSImage: "no TIFF representation behind NSImage"
                case .failedToCreateImageSource: "failed to create CGImageSource"
                case .failedToCreateCGImage: "failed to create CGImage"
            }
        }
    }
}
#endif
