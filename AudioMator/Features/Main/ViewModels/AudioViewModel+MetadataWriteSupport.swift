import Foundation

private let supportedTagWriteExtensions = AudioFormatSupport.metadataWritableExtensions

private let supportedArtworkWriteExtensions = AudioFormatSupport.artworkWritableExtensions

func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    supportedTagWriteExtensions.contains(ext.lowercased())
}

func isArtworkWriteSupportedExtension(_ ext: String) -> Bool {
    supportedArtworkWriteExtensions.contains(ext.lowercased())
}

struct MetadataWriteSuccessOutcome {
    let warnings: [String]
    let didRefreshFileModel: Bool
}

enum MetadataWriteExecutionResult {
    case success(MetadataWriteSuccessOutcome)
    case failure(String)
}

func fileCountLabel(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(count) files"
}

extension AudioViewModel {
    func beginMetadataSaveProgress(
        title: String,
        subtitle: String,
        totalUnitCount: Int
    ) {
        metadataSaveProgress = MetadataSaveProgress(
            title: title,
            subtitle: subtitle,
            completedUnitCount: 0,
            totalUnitCount: max(totalUnitCount, 1)
        )
    }

    func updateMetadataSaveProgress(
        subtitle: String,
        completedUnitCount: Int
    ) {
        guard let current = metadataSaveProgress else { return }
        metadataSaveProgress = MetadataSaveProgress(
            title: current.title,
            subtitle: subtitle,
            completedUnitCount: min(max(completedUnitCount, 0), current.totalUnitCount),
            totalUnitCount: current.totalUnitCount
        )
    }

    func endMetadataSaveProgress() {
        metadataSaveProgress = nil
    }

    func writeMetadataOffMainActor(
        _ edit: MetadataEditPayload,
        to url: URL
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.writeMetadata(edit, to: url)
        }.value
    }

    func rawMetadataPropertyMapOffMainActor(for url: URL) async throws -> [String: String] {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.rawMetadataPropertyMap(for: url)
        }.value
    }

    func writeRawMetadataPropertyMapOffMainActor(
        _ propertyMap: [String: String],
        to url: URL
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
        }.value
    }

    func eraseAllMetadataOffMainActor(at url: URL) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline

        return try await Task.detached(priority: .userInitiated) {
            try metadataPipeline.eraseAllMetadata(at: url)
        }.value
    }
}
