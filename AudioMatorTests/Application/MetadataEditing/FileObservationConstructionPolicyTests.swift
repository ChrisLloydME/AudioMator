import Foundation
import XCTest

/// F1 policy guard: only a validated full read may manufacture write authority.
///
/// The package revision token is opaque and the observation carries it together
/// with the baseline and fingerprint, so a new construction site that composes a
/// token pair with retained display metadata would re-open AM-03. Production
/// sources may construct `AudioFile.Observation` only in the allowlisted files;
/// tests construct deliberate fake observations through `AudioFileTestFactory`.
final class FileObservationConstructionPolicyTests: XCTestCase {
    private let allowedFilesCreatingObservations: Set<String> = [
        // Type/initializer definition and the projections that always clear it.
        "AudioFile.swift",
        // The single validated full-read constructor.
        "AudioFile+TagLibLoading.swift",
        // The verified conflict-snapshot factory used for raw-editor baselines.
        "MetadataConflictResolver.swift",
    ]

    func testOnlyAuthorizedReadsConstructWriteAuthority() throws {
        let repositoryRoot = try locateRepositoryRoot()
        let sourceRoot = repositoryRoot.appendingPathComponent("AudioMator", isDirectory: true)
        let fileManager = FileManager.default
        let enumerator = try XCTUnwrap(
            fileManager.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("AudioFile.Observation(") else { continue }
            let fileName = url.lastPathComponent
            if !allowedFilesCreatingObservations.contains(fileName) {
                offenders.append(url.path)
            }
        }

        XCTAssertEqual(
            offenders.sorted(), [],
            "Only the validated loader and the verified conflict-snapshot factory may construct a write-authorizing observation."
        )
    }

    func testGeneralURLRewriteAPIStaysRemoved() throws {
        let repositoryRoot = try locateRepositoryRoot()
        let sourceRoot = repositoryRoot.appendingPathComponent("AudioMator", isDirectory: true)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("withUpdatedURL") else { continue }
            offenders.append(url.path)
        }

        XCTAssertEqual(
            offenders.sorted(), [],
            "Moving or recovery-projecting a display snapshot must clear authority; no general token-attaching URL rewrite may return."
        )
    }

    private func locateRepositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("AudioMator.xcodeproj").path
            ) {
                return candidate
            }
            candidate = candidate.deletingLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
