
import struct Foundation.URL
import class Foundation.FileHandle

extension AudioFile.Format {
    /// Attempts to determine `AudioFile.Format` from given `URL`.
    enum Detector {
        static func format(at url: URL) throws(AudioFile.InitializationError) -> AudioFile.Format? {
            let fileExtension = url.pathExtension.lowercased()
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                throw .unableToOpenFile
            }
            defer {
                try? fileHandle.close()
            }
            var score: Int = 10
            var format: AudioFile.Format? = .none
            for audioFormat in AudioFile.Format.allCases {
                let metatype = audioFormat.formatMetatype
                var formatScore: Int = 0
                if metatype.supportedPathExtensions.contains(fileExtension) {
                    formatScore += 25
                }
                if metatype.isFormatSupported(fileHandle) {
                    formatScore += 75
                }
                if formatScore > score {
                    score = formatScore
                    format = audioFormat
                }
            }
            return format
        }
    }
}
