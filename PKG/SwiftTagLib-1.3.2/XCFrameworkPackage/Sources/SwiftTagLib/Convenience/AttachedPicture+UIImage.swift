
#if ImageDataTransformationEnabled && canImport(UIKit)
import class UIKit.UIImage
internal import class CoreGraphics.CGImage

public extension AudioFile.Metadata.AttachedPicture {
    /// Creates `AttachedPicture` from `UIImage` with `kind` and `description`.
    init(image: UIImage, kind: Kind, description: String) throws(ImageDataExtractionError) {
        guard let image = image.cgImage else {
            throw .noCGImageBehindUIImage
        }
        try self.init(image: image, kind: kind, description: description)
    }
    /// Attempts to construct `UIImage` from `CGImage` from **raw** `Data`.
    var image: UIImage? {
        guard let image: CGImage = cgImage else { return .none }
        return UIImage(cgImage: image)
    }
}
#endif
