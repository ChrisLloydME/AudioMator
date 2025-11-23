
struct AIFF: AudioFormat, CompositeHeaderFormat {
    static let supportedPathExtensions: Set<String> = ["aiff", "aif"]
    static let supportedMIMETypes: Set<String> = ["audio/aiff"]

    typealias Implementation = ImplementationClass.AIFF

    struct HeaderLayout: CompositeHeaderLayout {
        let shouldSkipID3v2Tag: Bool = false
        let length: Int = 12
        let offset: Int = 8
        let primaryId: String = "FORM"
        let secondaryIds: Set<String> = ["AIFF", "AIFC"]

        func validate(_ binaryData: BinaryData) throws -> Bool {
            let primaryId = try binaryData.getUTF8(0, length: 4)
            guard primaryId == self.primaryId else { return false }
            let secondaryId = try binaryData.getUTF8(offset, length: 4)
            guard secondaryIds.contains(secondaryId) else { return false }
            return true
        }
    }
}
