
struct WavPack: AudioFormat, BasicHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["wv"]
    static let supportedMIMETypes: Set<String> = ["audio/wavpack", "audio/x-wavpack"]

    typealias Implementation = ImplementationClass.WavPack

    struct HeaderLayout: BasicHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 4
        let id: String = "wvpk"
    }
}
