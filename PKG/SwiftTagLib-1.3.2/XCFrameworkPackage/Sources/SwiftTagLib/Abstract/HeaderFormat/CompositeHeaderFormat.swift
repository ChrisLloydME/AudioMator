
protocol CompositeHeaderLayout {    
    var shouldSkipID3v2Tag: Bool { get }
    var length: Int { get }
    func validate(_ binaryData: BinaryData) throws -> Bool
    init()
}

/// The kind of file where header can be safely identified by primary and secondary ID in the header.
protocol CompositeHeaderFormat {
    associatedtype HeaderLayout: CompositeHeaderLayout
}

import class Foundation.FileHandle

extension CompositeHeaderFormat where Self: AudioFormat {
    static func isFormatSupported(_ fileHandle: FileHandle) -> Bool {
        let layout = HeaderLayout()
        guard let binaryData = try? fileHandle.readFileHeaderBinaryData(
            length: layout.length,
            skipID3v2Tag: layout.shouldSkipID3v2Tag
        ) else {
            return false
        }
        do {
            return try layout.validate(binaryData)
        } catch {
            return false
        }
    }
}

