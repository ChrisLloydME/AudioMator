
protocol BasicHeaderLayout {
    var shouldSkipID3v2Tag: Bool { get }
    var length: Int { get }
    var id: String { get }
    init()
}

/// The kind of file where header can be safely identified by single ID in the header.
protocol BasicHeaderFormat {
    associatedtype HeaderLayout: BasicHeaderLayout
}

import class Foundation.FileHandle

extension BasicHeaderFormat where Self: AudioFormat {
    static func isFormatSupported(_ fileHandle: FileHandle) -> Bool {
        let layout = HeaderLayout()
        guard
            let binaryData = try? fileHandle.readFileHeaderBinaryData(
                length: layout.length,
                skipID3v2Tag: layout.shouldSkipID3v2Tag
            ),
            let id = try? binaryData.getUTF8(0, length: 4)
        else {
            return false
        }
        return id == layout.id
    }
}
