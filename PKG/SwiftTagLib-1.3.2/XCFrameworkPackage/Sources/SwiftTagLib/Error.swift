
import protocol Foundation.LocalizedError

public extension AudioFile {
    /// Exception caught in `C++`.
    struct CxxException {
        public enum Kind: String {
            case runtimeError
            case exception
            case unknown
        }
        public let kind: Kind
        public let message: String?
    }

    /// Error during initialization or when attempting to reading metadata & properties.
    enum InitializationError: Swift.Error, LocalizedError {
        case unableToDetermineAudioFormat
        case unableToOpenFile
        case invalidFile
        case exception(CxxException)
        case unknown

        public var errorDescription: String? {
            switch self {
                case .unableToDetermineAudioFormat: "unable to determine audio format"
                case .unableToOpenFile: "unable to open file"
                case .invalidFile: "invalid file"
                case .exception(let exception): "exception: \(exception)"
                case .unknown: "unknown error"
            }
        }
    }

    /// Error during writing metadat to disc.
    enum MetadataWritingError: Swift.Error, LocalizedError {
        case unableToOpenFile
        case invalidFile
        case saveError
        case exception(CxxException)
        case unknown

        public var errorDescription: String? {
            switch self {
                case .unableToOpenFile: "unable to open file"
                case .invalidFile: "invalid file"
                case .saveError: "save error"
                case .exception(let exception): "exception: \(exception)"
                case .unknown: "unknown error"
            }
        }
    }
}

@_implementationOnly import CxxTagLibBridge

extension AudioFile.InitializationError {
    static func throwIfNeeded(
        _ outcome: MetadataReadingOutcome,
        _ errorDescription: String
    ) throws(Self) {
        switch outcome {
            case .success: return
            case .fileIsNotOpen: throw .unableToOpenFile
            case .invalidFile: throw .invalidFile
            case .runtimeError: throw .exception(.init(kind: .runtimeError, message: errorDescription))
            case .exception: throw .exception(.init(kind: .exception, message: errorDescription))
            case .unknownException: throw .exception(.init(kind: .unknown, message: .none))
            @unknown default: throw .unknown
        }
    }
}

extension AudioFile.MetadataWritingError {
    static func throwIfNeeded(
        _ outcome: MetadataWritingOutcome,
        _ errorDescription: String
    ) throws(Self) {
        switch outcome {
            case .success: return
            case .fileIsNotOpen: throw .unableToOpenFile
            case .invalidFile: throw .invalidFile
            case .saveError: throw .saveError
            case .runtimeError: throw .exception(.init(kind: .runtimeError, message: errorDescription))
            case .exception: throw .exception(.init(kind: .exception, message: errorDescription))
            case .unknownException: throw .exception(.init(kind: .unknown, message: .none))
            @unknown default: throw .unknown
        }
    }
}
