
struct TrueAudio: AudioFormat, BasicHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["tta"]
    static let supportedMIMETypes: Set<String> = ["audio/x-tta"]

    typealias Implementation = ImplementationClass.TrueAudio

    struct HeaderLayout: BasicHeaderLayout {
        let shouldSkipID3v2Tag: Bool = true
        let length: Int = 4
        let id: String = "TTA1"
    }
}
