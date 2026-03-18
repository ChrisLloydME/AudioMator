import Foundation
import UniformTypeIdentifiers

enum AudioFormatSupport {
    private static let orderedSupportedExtensions: [String] = {
        TagLibMetadataExtractor.supportedExtensions().map { $0.lowercased() }
    }()

    static let readableExtensions: Set<String> = Set(orderedSupportedExtensions)
    static let metadataWritableExtensions: Set<String> = readableExtensions
    static let artworkWritableExtensions: Set<String> = readableExtensions

    static let openPanelContentTypes: [UTType] = {
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
