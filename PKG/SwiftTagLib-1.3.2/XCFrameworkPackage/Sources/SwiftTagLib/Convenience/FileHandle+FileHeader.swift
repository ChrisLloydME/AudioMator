
import class Foundation.FileHandle
import struct Foundation.Data
import protocol Foundation.LocalizedError

enum FileHeaderReadError: Swift.Error, LocalizedError {
    case unableToReadHeaderOfFile
    case insufficientLength

    public var errorDescription: String? {
        switch self {
            case .unableToReadHeaderOfFile: "unable to read header of file"
            case .insufficientLength: "insufficient length"
        }
    }
}

extension FileHandle {
    func readHeader(length: Int, skipID3v2Tag: Bool) throws -> Data {
        let originalOffset = try offset()
        defer {
            try? seek(toOffset: originalOffset)
        }
        try seek(toOffset: 0)
        if skipID3v2Tag {
            if
                let data = try? read(upToCount: ID3v2ShallowHeader.size),
                let id3v2header = try? ID3v2ShallowHeader(data)
            {
                try seek(toOffset: UInt64(id3v2header.totalSize))
            } else {
                try seek(toOffset: 0)
            }
        }
        guard let data = try read(upToCount: length) else {
            throw FileHeaderReadError.unableToReadHeaderOfFile
        }
        return data
    }
}

extension FileHandle {
    func readFileHeaderBinaryData(
        length: Int,
        skipID3v2Tag: Bool
    ) throws -> BinaryData {
        let data = try readHeader(length: length, skipID3v2Tag: skipID3v2Tag)
        guard data.count >= length else { throw FileHeaderReadError.insufficientLength }
        return BinaryData(data: data)
    }
}
