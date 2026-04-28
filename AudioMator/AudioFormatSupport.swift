import Foundation
import TagLibAudioMetadata
import UniformTypeIdentifiers

enum AudioFormatSupport {
    nonisolated private static let metadataOnlyWritableExtensions: Set<String> = [
        "mod",
        "module",
        "nst",
        "wow",
        "s3m",
        "it",
        "xm"
    ]

    nonisolated private static let orderedSupportedExtensions: [String] = {
        TagLibMetadataManager.readableExtensions.map { $0.lowercased() }
    }()

    nonisolated private static let orderedWritableExtensions: [String] = {
        TagLibMetadataManager.writableExtensions.map { $0.lowercased() }
    }()

    nonisolated static let readableExtensions: Set<String> = Set(orderedSupportedExtensions)
    nonisolated static let metadataWritableExtensions: Set<String> = Set(orderedWritableExtensions)
    nonisolated static let artworkWritableExtensions: Set<String> = metadataWritableExtensions
        .subtracting(metadataOnlyWritableExtensions)

    nonisolated static let openPanelContentTypes: [UTType] = {
        var seenIdentifiers = Set<String>()

        return orderedSupportedExtensions.compactMap { ext in
            guard let type = UTType(filenameExtension: ext) else {
                return nil
            }

            guard seenIdentifiers.insert(type.identifier).inserted else {
                return nil
            }

            return type
        }
    }()
}
