
struct DSF: AudioFormat, CompositeHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["dsf"]
    static let supportedMIMETypes: Set<String> = ["audio/dsf"]

    typealias Implementation = ImplementationClass.DSF

    struct HeaderLayout: CompositeHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 32
        let offset: Int = 28
        let primaryId: String = "DSD"
        let secondaryId: String = "fmt "

        func validate(_ binaryData: BinaryData) throws -> Bool {
            let primaryId = try binaryData.getUTF8(0, length: 4)
            guard primaryId == self.primaryId else { return false }
            let secondaryId = try binaryData.getUTF8(offset, length: 4)
            guard secondaryId == self.secondaryId else { return false }
            return true
        }
    }
}
