import Foundation
import UniformTypeIdentifiers

enum AudioFormatSupport {
    nonisolated private static let orderedSupportedExtensions: [String] = {
        TagLibMetadataExtractor.supportedExtensions().map { $0.lowercased() }
    }()

    nonisolated static let readableExtensions: Set<String> = Set(orderedSupportedExtensions)
    nonisolated static let metadataWritableExtensions: Set<String> = readableExtensions
    nonisolated static let artworkWritableExtensions: Set<String> = readableExtensions

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
