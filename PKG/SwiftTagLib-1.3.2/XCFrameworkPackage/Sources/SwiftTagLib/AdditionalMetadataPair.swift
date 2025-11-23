
@_implementationOnly import CxxTagLibBridge

extension AudioFile.Metadata {
    /// Additional metadat key value pair.
    public struct AdditionalMetadataPair: CxxRepresentable, Hashable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }

        init(cxxRepresentation pair: AudioMetadata.AdditionalMetadataPair) {
            self.key = String(pair.first)
            self.value = String(pair.second)
        }

        var cxxRepresentation: AudioMetadata.AdditionalMetadataPair {
            .init(first: std.string(key), second: std.string(value))
        }
    }
}
