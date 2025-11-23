
@_implementationOnly import CxxTagLibBridge

import struct Foundation.TimeInterval

public extension AudioFile {
    struct Properties: CxxRepresentable, Hashable {
        public private(set) var lengthInSeconds: Int32 = 0
        public private(set) var channels: Int32 = 0
        public private(set) var sampleRate: Int32 = 0
        public private(set) var bitrate: Int32 = 0

        public var duration: TimeInterval { TimeInterval(lengthInSeconds) }

        internal init() {}

        init(cxxRepresentation properties: AudioProperties) {
            lengthInSeconds = properties.lengthInSeconds
            channels = properties.channels
            sampleRate = properties.sampleRate
            bitrate = properties.bitrate
        }

        var cxxRepresentation: AudioProperties {
            var properties = AudioProperties()
            properties.lengthInSeconds = lengthInSeconds
            properties.channels = channels
            properties.sampleRate = sampleRate
            properties.bitrate = bitrate
            return properties
        }
    }
}
