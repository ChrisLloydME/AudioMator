
struct DSDIFF: AudioFormat, CompositeHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["dff"]
    static let supportedMIMETypes: Set<String> = ["audio/dff"]

    typealias Implementation = ImplementationClass.DSDIFF

    struct HeaderLayout: CompositeHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 16
        let offset: Int = 12
        let primaryId: String = "FRM8"
        let secondaryId: String = "DSD "

        func validate(_ binaryData: BinaryData) throws -> Bool {
            let primaryId = try binaryData.getUTF8(0, length: 4)
            guard primaryId == self.primaryId else { return false }
            let secondaryId = try binaryData.getUTF8(offset, length: 4)
            guard secondaryId == self.secondaryId else { return false }
            return true
        }
    }
}
