
struct OggFLAC: AudioFormat, CompositeHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["oga"]
    static let supportedMIMETypes: Set<String> = ["audio/ogg; codec=flac"]

    typealias Implementation = ImplementationClass.OggFLAC

    struct HeaderLayout: CompositeHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 33
        let offset: Int = 28
        let primaryId: String = "OggS\0"
        let secondaryId: String = "\u{7F}FLAC"

        func validate(_ binaryData: BinaryData) throws -> Bool {
            let primaryId = try binaryData.getUTF8(0, length: 5)
            guard primaryId == self.primaryId else { return false }
            let secondaryId = try binaryData.getUTF8(offset, length: 5)
            guard secondaryId == self.secondaryId else { return false }
            return true
        }
    }
}
