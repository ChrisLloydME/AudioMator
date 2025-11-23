
struct Musepack: AudioFormat, CustomHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["mpc"]
    static let supportedMIMETypes: Set<String> = ["audio/musepack", "audio/x-musepack"]

    typealias Implementation = ImplementationClass.Musepack

    struct HeaderLayout: CustomHeaderLayout {
        let shouldSkipID3v2Tag: Bool = true
        let length: Int = 4
        func validate(_ bytes: Data) -> Bool {
            if let id = try? BinaryData(data: bytes).getUTF8(0, length: 4), id == "MPCK" {
                return true
            } else if let id = try? BinaryData(data: bytes).getUTF8(0, length: 3), id == "MP+" {
                return true
            } else {
                return false
            }
        }
    }
}
