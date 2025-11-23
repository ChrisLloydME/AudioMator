
#if ImageDataTransformationEnabled
import struct UniformTypeIdentifiers.UTType
import ImageIO

public extension AudioFile.Metadata.AttachedPicture {
    /// Provides `UTType` of image in **raw** `Data`, presumably should only ever be `public.jpeg`.
    var type: UTType? {
        guard
            let imageSource = CGImageSourceCreateWithData(data as CFData, .none),
            let identifier = CGImageSourceGetType(imageSource) as? String,
            let type = UTType(identifier)
        else {
            return .none
        }
        return type
    }
}
#endif
