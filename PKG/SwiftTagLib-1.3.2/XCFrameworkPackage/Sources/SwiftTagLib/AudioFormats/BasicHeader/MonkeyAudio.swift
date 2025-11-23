
struct MonkeyAudio: AudioFormat, BasicHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["ape"]
    static let supportedMIMETypes: Set<String> = ["audio/monkeys-audio", "audio/x-monkeys-audio"]

    typealias Implementation = ImplementationClass.MonkeyAudio

    struct HeaderLayout: BasicHeaderLayout {
        let shouldSkipID3v2Tag: Bool = true
        let length: Int = 4
        let id: String = "MAC "
    }
}
