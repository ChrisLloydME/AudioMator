
import class Foundation.FileHandle
@_implementationOnly import CxxTagLibBridge

/// Describes details to identify file as corresponding to specific format and abstracts away implementation.
protocol AudioFormat {
    static var supportedPathExtensions: Set<String> { get }
    static var supportedMIMETypes: Set<String> { get }
    static func isFormatSupported(_ fileHandle: FileHandle) -> Bool

    /// import escaping.
    typealias ImplementationClass = CxxTagLibBridge.AudioFile
    associatedtype Implementation: AudioFileImplementation
}

extension AudioFormat {
    static var implementationMetatype: Implementation.Type { Implementation.self }
}
