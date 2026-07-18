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
    func canStartExternalFileMutation() -> Bool {
        guard hasUnsavedInspectorChanges else { return true }

        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Unsaved Changes"),
            subtitle: String(localized: "Save or discard the pending inspector edits before changing files from another tool.")
        )
        return false
    }

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
        to url: URL,
        expectedFileFingerprint: AudioFileFingerprint? = nil
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline
        let fileMutationCoordinator = self.fileMutationCoordinator

        return try await fileMutationCoordinator.withExclusiveAccess(to: [url]) {
            try await Task.detached(priority: .userInitiated) {
                try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)

                return try metadataPipeline.writeMetadata(edit, to: url)
            }.value
        }
    }

    func writeRawMetadataPropertyMapOffMainActor(
        _ propertyMap: [String: String],
        to url: URL,
        expectedFileFingerprint: AudioFileFingerprint? = nil
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline
        let fileMutationCoordinator = self.fileMutationCoordinator

        return try await fileMutationCoordinator.withExclusiveAccess(to: [url]) {
            try await Task.detached(priority: .userInitiated) {
                try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
                return try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
            }.value
        }
    }

    func eraseAllMetadataOffMainActor(
        at url: URL,
        expectedFileFingerprint: AudioFileFingerprint? = nil
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline
        let fileMutationCoordinator = self.fileMutationCoordinator

        return try await fileMutationCoordinator.withExclusiveAccess(to: [url]) {
            try await Task.detached(priority: .userInitiated) {
                try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
                return try metadataPipeline.eraseAllMetadata(at: url)
            }.value
        }
    }

    func updateRawMetadataPropertyMapOffMainActor(
        at url: URL,
        expectedFileFingerprint: AudioFileFingerprint? = nil,
        transform: @escaping @Sendable (inout [String: String]) -> Void
    ) async throws -> AudioMetadataWriteResult {
        let metadataPipeline = self.metadataPipeline
        let fileMutationCoordinator = self.fileMutationCoordinator

        return try await fileMutationCoordinator.withExclusiveAccess(to: [url]) {
            try await Task.detached(priority: .userInitiated) {
                try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
                var propertyMap = try metadataPipeline.rawMetadataPropertyMap(for: url)
                transform(&propertyMap)
                return try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
            }.value
        }
    }

}

nonisolated func validateExpectedFileFingerprint(
    _ expectedFileFingerprint: AudioFileFingerprint?,
    at url: URL
) throws {
    guard let expectedFileFingerprint else { return }

    let currentFingerprint: AudioFileFingerprint
    do {
        currentFingerprint = try AudioFileFingerprint.capture(at: url)
    } catch {
        throw AudioFileFingerprintValidationError.unavailable(fileName: url.lastPathComponent)
    }

    guard currentFingerprint == expectedFileFingerprint else {
        throw AudioFileFingerprintValidationError.changedSincePreview(fileName: url.lastPathComponent)
    }
}
