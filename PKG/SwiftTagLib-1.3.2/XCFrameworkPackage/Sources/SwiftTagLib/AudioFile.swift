
import struct Foundation.URL

/// Facade to easily read/write metadata to/from audio file.
public struct AudioFile {
    /// file url.
    public let url: URL
    /// file format, derived from file header and path extensions.
    public let format: Format
    /// attached metadata.
    public var metadata: Metadata
    /// audio file properties.
    public let properties: Properties

    /// attempts to create `AudioFile` from `URL`.
    public init(
        url: URL,
        options: Metadata.ReadingOptions = [],
        overlayStrategy: Metadata.OverlayStrategy = .override
    ) throws(InitializationError) {
        guard let format = try Format.Detector.format(at: url) else {
            throw .unableToDetermineAudioFormat
        }
        self.url = url
        self.format = format
        let (metadata, properties) = try Metadata.readMetadataAndProperties(
            from: url,
            format: format,
            options: options,
            overlayStrategy: overlayStrategy
        )
        self.metadata = metadata
        self.properties = properties
    }

    /// writes changes to `Metadata`.
    public func write() throws(MetadataWritingError) {
        try metadata.write(to: url, format: format)
    }
}
