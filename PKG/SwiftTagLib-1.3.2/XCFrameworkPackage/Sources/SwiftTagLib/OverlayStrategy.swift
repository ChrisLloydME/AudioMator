
@_implementationOnly import CxxTagLibBridge

public extension AudioFile.Metadata {
    /// Influences how duplicate fields are being handled when overlaying one `AudioMetadata` with another.
    enum OverlayStrategy: UInt8, RawRepresentable, CxxRepresentable, CustomStringConvertible {
        /// checks if value is already read, and if not replaces only with new if its not `std::nullopt`.
        case graceful = 0
        /// does not check if value is already read, replaces when new if its not `std::nullopt`.
        case override = 1
        /// no checks, newest value is written
        case regardless = 2

        init(cxxRepresentation: MetadataOverlayStrategy) {
            self.init(rawValue: cxxRepresentation.rawValue)!
        }

        var cxxRepresentation: MetadataOverlayStrategy {
            MetadataOverlayStrategy(rawValue: rawValue)!
        }

        public var description: String {
            switch self {
                case .graceful: "Graceful"
                case .override: "Override"
                case .regardless: "Regardless"
            }
        }
    }
}
