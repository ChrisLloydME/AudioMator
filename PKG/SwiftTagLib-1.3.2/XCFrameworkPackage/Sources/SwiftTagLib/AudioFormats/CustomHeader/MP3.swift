
struct MP3: AudioFormat, CustomHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["mp3"]
    static let supportedMIMETypes: Set<String> = ["audio/mpeg"]

    typealias Implementation = ImplementationClass.MP3

    struct HeaderLayout: CustomHeaderLayout {
        let shouldSkipID3v2Tag: Bool = true
        let length: Int = 3
        func validate(_ bytes: Data) -> Bool {
            if bytes[0] != 0xFF || (bytes[1] & 0xE0 != 0xE0) {
                return false
            } else if bytes[1] & 0x18 == 0x08 {
                return false
            } else if bytes[1] & 0x06 == 0x0 {
                return false
            } else if bytes[2] & 0xF0 == 0xF0 {
                return false
            } else if bytes[2] & 0x0C == 0x0C {
                return false
            } else {
                return true
            }
        }
    }
}
