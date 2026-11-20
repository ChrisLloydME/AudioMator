import Foundation
import TagLibAudioMetadata
@testable import AudioMator

/// Test-only helpers that manufacture coherent reviewed observations from
/// disposable fixture copies.
///
/// The package revision token is opaque and has no observed public initializer, so
/// tests must never fabricate one. Mint a real token from a real file instead of
/// assuming a package initializer, then reuse that exact token for synthetic
/// storage.
nonisolated enum MetadataTestTokens {
    enum HelperError: Error, CustomStringConvertible, Sendable {
        case fixtureMissing(String)
        case targetUnavailable(URL)

        var description: String {
            switch self {
            case .fixtureMissing(let name):
                return "Test fixture missing from the app-hosted test bundle: \(name)"
            case .targetUnavailable(let url):
                return "Could not build a coherent reviewed target for \(url.lastPathComponent)"
            }
        }
    }

    private final class BundleToken {}

    /// Copies a committed audio fixture into a fresh disposable directory.
    ///
    /// The caller owns the directory and should remove
    /// `url.deletingLastPathComponent()` in teardown.
    static func makeFixtureCopy(fileExtension: String = "flac") throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        let fixtureName = "testAudioFile.\(fileExtension)"
        guard
            let sourceURL = bundle.url(
                forResource: fixtureName,
                withExtension: nil,
                subdirectory: "Fixtures/Audio"
            ) ?? bundle.url(forResource: fixtureName, withExtension: nil)
        else {
            throw HelperError.fixtureMissing(fixtureName)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataTestTokens-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent(fixtureName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func removeFixtureCopy(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Mints the package's opaque revision token from real file bytes.
    static func mintedVersion(at url: URL) throws -> MetadataFileVersion {
        try TagLibMetadataManager.fileVersion(at: url)
    }

    /// Captures the real fingerprint and opaque revision of a fixture copy so a
    /// deliberately manufactured observation still authorizes the strict route.
    static func mintedTokens(
        at url: URL
    ) throws -> (fingerprint: AudioFileFingerprint, version: MetadataFileVersion) {
        (
            fingerprint: try AudioFileFingerprint.capture(at: url),
            version: try TagLibMetadataManager.fileVersion(at: url)
        )
    }

    /// Loads a coherent `AudioFile` observation with both disk tokens present.
    static func makeVerifiedAudioFile(at url: URL, id: UUID = UUID()) async throws -> AudioFile {
        try await TagLibAudioMetadataPipeline().loadAudioFile(at: url, id: id)
    }

    /// Loads a coherent observation and its reviewed write target.
    static func makeReviewedTarget(
        at url: URL,
        id: UUID = UUID()
    ) async throws -> (file: AudioFile, target: ReviewedMetadataTarget) {
        let file = try await makeVerifiedAudioFile(at: url, id: id)
        guard let target = ReviewedMetadataTarget(verified: file) else {
            throw HelperError.targetUnavailable(url)
        }
        return (file, target)
    }
}
