
public extension AudioFile.Metadata {
    /// Tells from which `Tag's` the `AudioFile.Metadata` was read.
    struct TagSource: OptionSet, Hashable, Equatable, CustomStringConvertible {
        /// One of the following: `TagLib::Tag`, `DSDIFF::DIIN::Tag`, `RIFF::Info::Tag`.
        public static var abstract: Self { .init(rawValue: 1 << 0) }
        /// ID3v1 metadata tag.
        public static var id3v1: Self { .init(rawValue: 1 << 1) }
        /// ID3v2 metadata tag.
        public static var id3v2: Self { .init(rawValue: 1 << 2) }
        /// MP4 metadata tag.
        public static var mp4: Self { .init(rawValue: 1 << 3) }
        /// APE metadata tag.
        public static var ape: Self { .init(rawValue: 1 << 4) }
        /// XiphComment metadata.
        public static var xiph: Self { .init(rawValue: 1 << 5) }

        internal static var undefined: Self { .init(rawValue: 0) }

        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public var description: String {
            var descriptions: [String] = []
            if contains(.abstract) {
                descriptions.append("Abstract")
            }
            if contains(.id3v1) {
                descriptions.append("ID3v1")
            }
            if contains(.id3v2) {
                descriptions.append("ID3v2")
            }
            if contains(.mp4) {
                descriptions.append("MP4")
            }
            if contains(.ape) {
                descriptions.append("APE")
            }
            if contains(.xiph) {
                descriptions.append("XiphComment")
            }

            return "TagSource(" + descriptions.joined(separator: ", ") + ")"
        }
    }
}
