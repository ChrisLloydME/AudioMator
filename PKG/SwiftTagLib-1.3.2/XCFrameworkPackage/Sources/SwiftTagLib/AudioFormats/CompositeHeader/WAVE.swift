
struct WAVE: AudioFormat, CompositeHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["wav", "wave"]
    static let supportedMIMETypes: Set<String> = ["audio/wave"]

    typealias Implementation = ImplementationClass.WAVE

    struct HeaderLayout: CompositeHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 12
        let offset: Int = 8
        let primaryId: String = "RIFF"
        let secondaryId: String = "WAVE"

        func validate(_ binaryData: BinaryData) throws -> Bool {
            let primaryId = try binaryData.getUTF8(0, length: 4)
            guard primaryId == self.primaryId else { return false }
            let secondaryId = try binaryData.getUTF8(offset, length: 4)
            guard secondaryId == self.secondaryId else { return false }
            return true
        }
    }
}
