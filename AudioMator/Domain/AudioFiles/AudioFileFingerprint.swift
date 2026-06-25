import Foundation

struct AudioFileFingerprint: Equatable, Hashable, Sendable {
    let normalizedPath: String
    let fileSize: UInt64
    let contentModificationDate: Date
    let fileSystemNumber: UInt64?
    let fileNumber: UInt64?

    nonisolated static func == (lhs: AudioFileFingerprint, rhs: AudioFileFingerprint) -> Bool {
        lhs.normalizedPath == rhs.normalizedPath &&
        lhs.fileSize == rhs.fileSize &&
        lhs.contentModificationDate == rhs.contentModificationDate &&
        lhs.fileSystemNumber == rhs.fileSystemNumber &&
        lhs.fileNumber == rhs.fileNumber
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedPath)
        hasher.combine(fileSize)
        hasher.combine(contentModificationDate)
        hasher.combine(fileSystemNumber)
        hasher.combine(fileNumber)
    }

    nonisolated static func capture(at url: URL) throws -> AudioFileFingerprint {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: normalizedURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast

        return AudioFileFingerprint(
            normalizedPath: normalizedURL.path.precomposedStringWithCanonicalMapping,
            fileSize: size,
            contentModificationDate: modificationDate,
            fileSystemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }
}

enum AudioFileFingerprintValidationError: LocalizedError, Sendable {
    case unavailable(fileName: String)
    case changedSincePreview(fileName: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let fileName):
            return "\(fileName): The file version could not be verified. Refresh the preview and try again."
        case .changedSincePreview(let fileName):
            return "\(fileName): The file changed after the preview was shown. Refresh the preview before applying tags."
        }
    }
}
