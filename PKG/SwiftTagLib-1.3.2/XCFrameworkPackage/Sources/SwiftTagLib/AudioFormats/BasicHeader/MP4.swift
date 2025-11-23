
struct MP4: AudioFormat, BasicHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["m4a", "m4r", "mp4"]
    static let supportedMIMETypes: Set<String> = ["audio/mpeg-4"]

    typealias Implementation = ImplementationClass.MP4

    struct HeaderLayout: BasicHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 8
        let id: String = "ftyp"
    }
}
