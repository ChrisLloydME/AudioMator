import Foundation
import TagLibAudioMetadata
import UniformTypeIdentifiers

enum AudioFormatSupport {
    nonisolated private static let supportSnapshot: AudioFormatSupportSnapshot = {
        AudioFormatSupportCore.snapshot(
            readableExtensions: TagLibMetadataManager.readableExtensions,
            writableExtensions: TagLibMetadataManager.writableExtensions,
            capabilities: TagLibMetadataManager.formatCapabilities.map { capability in
                AudioFormatCapabilityCore(
                    extensions: capability.extensions,
                    isWritable: capability.isWritable,
                    canWriteArtwork: capability.canWriteArtwork
                )
            }
        )
    }()

    nonisolated private static let orderedSupportedExtensions: [String] = {
        supportSnapshot.orderedReadableExtensions
    }()

    nonisolated private static let orderedWritableExtensions: [String] = {
        Array(supportSnapshot.metadataWritableExtensions)
    }()

    nonisolated private static let orderedArtworkWritableExtensions: [String] = {
        Array(supportSnapshot.artworkWritableExtensions)
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
