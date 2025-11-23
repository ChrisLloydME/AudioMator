
import struct Foundation.Data

protocol CustomHeaderLayout {
    typealias Data = Foundation.Data
    
    var shouldSkipID3v2Tag: Bool { get }
    var length: Int { get }
    func validate(_ bytes: Data) -> Bool
    init()
}

/// The kind of file where header needs some custom logic to be sure it's truly this format.
protocol CustomHeaderFormat {
    associatedtype HeaderLayout: CustomHeaderLayout
}

import class Foundation.FileHandle

extension CustomHeaderFormat where Self: AudioFormat {
    static func isFormatSupported(_ fileHandle: FileHandle) -> Bool {
        let layout = HeaderLayout()
        guard let bytes = try? fileHandle.readHeader(
            length: layout.length,
            skipID3v2Tag: layout.shouldSkipID3v2Tag
        ) else {
            return false
        }
        return layout.validate(bytes)
    }
}
