
import struct Foundation.Data
import protocol Foundation.LocalizedError

struct ID3v2ShallowHeader {
    /// both header size and footer size.
    static var size: Int { 10 }

    let bytes: Data

    enum Error: Swift.Error, LocalizedError {
        case dataIsNotID3v2Header
        public var errorDescription: String? {
            switch self {
                case .dataIsNotID3v2Header: "data is not ID3v2 header"
            }
        }
    }

    /**
     An `ID3v2` tag can be detected with the following pattewrn: `$49 44 33 yy yy xx zz zz zz zz`
     Where `yy` is less than `$FF`, `xx` is the `flags` byte and `zz` is less than `$80`.
     */
    init(_ bytes: Data) throws(Error) {
        guard bytes.count >= Self.size else { throw .dataIsNotID3v2Header }

        if bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33 {
            throw .dataIsNotID3v2Header
        }
        if bytes[3] >= 0xFF || bytes[4] >= 0xFF {
            throw .dataIsNotID3v2Header
        }
        if bytes[5] & 0xF != 0x0 {
            throw .dataIsNotID3v2Header
        }
        if bytes[6] >= 0x80 || bytes[7] >= 0x80 || bytes[8] >= 0x80 || bytes[9] >= 0x80 {
            throw .dataIsNotID3v2Header
        }
        self.bytes = bytes
    }

    var totalSize: Int {
        guard bytes.count >= Self.size else { return 0 }
        let size = UInt32(bytes[6] << 21) | UInt32(bytes[7] << 14) | UInt32(bytes[8] << 7) | UInt32(bytes[9])
        let additionalOffset = bytes[5] & 0x10 != 0x0 ? Self.size : 0
        return Self.size + Int(size) + Int(additionalOffset)
    }
}
