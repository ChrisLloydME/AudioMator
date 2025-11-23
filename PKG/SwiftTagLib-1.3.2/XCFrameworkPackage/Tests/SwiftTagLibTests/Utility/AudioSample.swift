
import struct Foundation.URL

struct AudioSample: Hashable, Equatable, CustomStringConvertible {
    let url: URL
    var filename: String { url.lastPathComponent }
    var description: String { filename }
}

extension AudioSample {
    static var supported: [Self] {[
        .aiff,
        .flac,
        .mp3,
        .mp4,
        .m4a,
        .ogg,
        .wav,
        .opus,
    ]}

    static var unsupported: [Self] {[
        .aac,
        .ac3,
        .ts,
        .wma,
    ]}

    static var all: [Self] {[
        .aiff,
        .flac,
        .mp3,
        .mp4,
        .m4a,
        .ogg,
        .wav,
        .opus,
        .aac,
        .ac3,
        .ts,
        .wma,
    ]}
}

extension AudioSample {
    static var aac: Self { sample("aac") }
    static var ac3: Self { sample("ac3") }
    static var aiff: Self { sample("aiff") }
    static var flac: Self { sample("flac") }
    static var m4a: Self { sample("m4a") }
    static var mp3: Self { sample("mp3") }
    static var mp4: Self { sample("mp4") }
    static var ogg: Self { sample("ogg") }
    static var ts: Self { sample("ts") }
    static var wav: Self { sample("wav") }
    static var wma: Self { sample("wma") }
    static var opus: Self { sample("opus.ogg") }
}

fileprivate extension AudioSample {
    static func sample(_ format: String) -> Self {
        .init(url: Constants.Directory.audio.appending(path: "sample." + format))
    }
}
