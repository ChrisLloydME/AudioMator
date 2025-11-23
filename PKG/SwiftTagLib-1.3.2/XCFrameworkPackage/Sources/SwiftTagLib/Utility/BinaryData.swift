
import struct Foundation.Data
import protocol Foundation.LocalizedError

/// A helper to easily read `UTF8` strings from file headers.
struct BinaryData {
    let data: [UInt8]

    enum Error: Swift.Error, LocalizedError {
        case notEnoughData
        case failedToConvertToString

        public var errorDescription: String? {
            switch self {
                case .notEnoughData: "not enough data"
                case .failedToConvertToString: "failed to convert to string"
            }
        }
    }

    init(data: Data) {
        var buffer: [UInt8] = .init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        self.data = buffer
    }

    func getUTF8(_ offset: Int, length: Int) throws(Error) -> String {
        var utf8 = UTF8()
        var string = ""
        guard offset >= 0 && offset <= data.count && length >= 0 && (offset + length) <= data.count else {
            throw .notEnoughData
        }
        var iterator = Array(data[offset ..< (offset + length)]).makeIterator()
        while true {
            switch utf8.decode(&iterator) {
                case .scalarValue(let scalar): string.append(String(scalar))
                case .emptyInput: return string
                case .error: throw .failedToConvertToString
            }
        }
    }
}
