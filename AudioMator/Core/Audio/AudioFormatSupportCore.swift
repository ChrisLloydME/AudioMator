import Foundation

struct AudioFormatCapabilityCore: Equatable {
    let extensions: [String]
    let isWritable: Bool
    let canWriteArtwork: Bool
    let writableFieldKeys: Set<String>
}

struct AudioFormatSupportSnapshot: Equatable {
    let readableExtensions: Set<String>
    let metadataWritableExtensions: Set<String>
    let artworkWritableExtensions: Set<String>
    let orderedReadableExtensions: [String]
    let writableFieldKeysByExtension: [String: Set<String>]
}

enum AudioFormatSupportCore {
    static func snapshot(
        readableExtensions: [String],
        writableExtensions: [String],
        capabilities: [AudioFormatCapabilityCore]
    ) -> AudioFormatSupportSnapshot {
        let orderedReadable = readableExtensions.map { $0.lowercased() }
        let orderedWritable = writableExtensions.map { $0.lowercased() }
        var seenArtworkExtensions = Set<String>()
        var writableFieldKeysByExtension: [String: Set<String>] = [:]
        let orderedArtworkWritable = capabilities.flatMap { capability -> [String] in
            guard capability.isWritable else { return [] }
            for ext in capability.extensions {
                writableFieldKeysByExtension[ext.lowercased()] = capability.writableFieldKeys
            }
            guard capability.canWriteArtwork else { return [] }
            return capability.extensions.compactMap { ext in
                let normalized = ext.lowercased()
                guard seenArtworkExtensions.insert(normalized).inserted else { return nil }
                return normalized
            }
        }

        return AudioFormatSupportSnapshot(
            readableExtensions: Set(orderedReadable),
            metadataWritableExtensions: Set(orderedWritable),
            artworkWritableExtensions: Set(orderedArtworkWritable),
            orderedReadableExtensions: orderedReadable,
            writableFieldKeysByExtension: writableFieldKeysByExtension
        )
    }
}
