import Foundation
import TagLibAudioMetadata
import UniformTypeIdentifiers

enum AudioFormatSupport {
    nonisolated private static let orderedSupportedExtensions: [String] = {
        TagLibMetadataManager.readableExtensions.map { $0.lowercased() }
    }()

    nonisolated private static let orderedWritableExtensions: [String] = {
        TagLibMetadataManager.writableExtensions.map { $0.lowercased() }
    }()

    nonisolated private static let orderedArtworkWritableExtensions: [String] = {
        var seenExtensions = Set<String>()

        return TagLibMetadataManager.formatCapabilities.flatMap { capability in
            guard capability.isWritable, capability.canWriteArtwork else { return [String]() }

            return capability.extensions.compactMap { ext in
                let normalized = ext.lowercased()
                guard seenExtensions.insert(normalized).inserted else { return nil }
                return normalized
            }
        }
    }()

    nonisolated static let readableExtensions: Set<String> = Set(orderedSupportedExtensions)
    nonisolated static let metadataWritableExtensions: Set<String> = Set(orderedWritableExtensions)
    nonisolated static let artworkWritableExtensions: Set<String> = Set(orderedArtworkWritableExtensions)

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
