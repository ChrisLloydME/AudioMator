
import struct Foundation.Data
@_implementationOnly import CxxTagLibBridge

public extension AudioFile.Metadata {
    /// `Image` attached to `AudioFile` and packed in any of the tags, specific to `AudioFile.Format`.
    struct AttachedPicture: CxxRepresentable, Hashable, Equatable {
        /// raw bytes.
        public let data: Data
        /// image description.
        public let description: String
        /// kind of image.
        public let kind: Kind

        public init(data: Data, kind: Kind, description: String) {
            self.data = data
            self.kind = kind
            self.description = description
        }

        internal init(cxxRepresentation picture: AudioMetadata.Picture) {
            data = Data(bytes: Array(picture.bytes), count: Int(picture.size))
            description = String(picture.description)
            kind = .init(cxxRepresentation: picture.kind)
        }

        var cxxRepresentation: AudioMetadata.Picture {
            .create_from_CFData(data as CFData, std.string(description), kind.cxxRepresentation)
        }
    }
}

// MARK: - AudioFile.Metadata.AttachedPicture.Kind
public extension AudioFile.Metadata.AttachedPicture {
    enum Kind: UInt32, RawRepresentable, CxxRepresentable, CustomStringConvertible {
        /// A type not otherwise enumerated
        case other = 0x00
        /// 32x32 PNG image that should be used as the file icon
        case fileIcon = 0x01
        /// File icon of a different size or format
        case otherFileIcon = 0x02
        /// Front cover image of the album
        case frontCover = 0x03
        /// Back cover image of the album
        case backCover = 0x04
        /// Inside leaflet page of the album
        case leafletPage = 0x05
        /// Image from the album itself
        case media = 0x06
        /// Picture of the lead artist or soloist
        case leadArtist = 0x07
        /// Picture of the artist or performer
        case artist = 0x08
        /// Picture of the conductor
        case conductor = 0x09
        /// Picture of the band or orchestra
        case band = 0x0A
        /// Picture of the composer
        case composer = 0x0B
        /// Picture of the lyricist or text writer
        case lyricist = 0x0C
        /// Picture of the recording location or studio
        case recordingLocation = 0x0D
        /// Picture of the artists during recording
        case duringRecording = 0x0E
        /// Picture of the artists during performance
        case duringPerformance = 0x0F
        /// Picture from a movie or video related to the track
        case movieScreenCapture = 0x10
        /// Picture of a large, coloured fish
        case colouredFish = 0x11
        /// Illustration related to the track
        case illustration = 0x12
        /// Logo of the band or performer
        case bandLogo = 0x13
        /// Logo of the publisher (record company)
        case publisherLogo = 0x14

        init(cxxRepresentation: AudioMetadata.Picture.Kind) {
            self.init(rawValue: cxxRepresentation.rawValue)!
        }

        var cxxRepresentation: AudioMetadata.Picture.Kind {
            AudioMetadata.Picture.Kind(rawValue: rawValue)!
        }

        public var description: String {
            switch self {
                case .other: "other"
                case .fileIcon: "file icon"
                case .otherFileIcon: "other file icon"
                case .frontCover: "front cover"
                case .backCover: "back cover"
                case .leafletPage: "leaflet page"
                case .media: "media"
                case .leadArtist: "lead artist"
                case .artist: "artist"
                case .conductor: "conductor"
                case .band: "band"
                case .composer: "composer"
                case .lyricist: "lyricist"
                case .recordingLocation: "recording location"
                case .duringRecording: "during recording"
                case .duringPerformance: "during performance"
                case .movieScreenCapture: "movie screen capture"
                case .colouredFish: "coloured fish"
                case .illustration: "illustration"
                case .bandLogo: "band logo"
                case .publisherLogo: "publisher logo"
                @unknown default: "@unknown default"
            }
        }
    }
}
