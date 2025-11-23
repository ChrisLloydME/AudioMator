
struct FLAC: AudioFormat, BasicHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["flac"]
    static let supportedMIMETypes: Set<String> = ["audio/flac"]

    typealias Implementation = ImplementationClass.FLAC

    struct HeaderLayout: BasicHeaderLayout {
        let shouldSkipID3v2Tag: Bool = true
        let length: Int = 4
        let id: String = "fLaC"
    }
}
