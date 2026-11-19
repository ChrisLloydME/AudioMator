import Foundation
import XCTest
@testable import AudioMator

/// Source-policy checks for the retired mixed write forwarding path.
///
/// These are intentionally source scans rather than behavioral assertions: the
/// removed symbols must not come back through an unversioned fallback, and the
/// production metadata routes must never submit a nil expected package revision.
nonisolated final class LegacyWriteRouteRemovalPolicyTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MetadataEditing
            .deletingLastPathComponent() // Application
            .deletingLastPathComponent() // AudioMatorTests
            .deletingLastPathComponent() // repository root
    }

    private var productionSwiftFiles: [URL] {
        let root = repositoryRoot.appendingPathComponent("AudioMator", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    private func productionSources() throws -> [(path: String, contents: String)] {
        try productionSwiftFiles.map { url in
            (
                path: url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""),
                contents: try String(contentsOf: url, encoding: .utf8)
            )
        }
    }

    func testRemovedMixedWriteSymbolsAreAbsentFromProduction() throws {
        let banned = [
            "persistMetadataEdit",
            "executeMetadataFileMutation",
            "executeUnmigrated",
            "MetadataFileMutationAdmission.legacy"
        ]
        for source in try productionSources() {
            for symbol in banned {
                XCTAssertFalse(
                    source.contents.contains(symbol),
                    "\(symbol) must not remain in production source \(source.path)"
                )
            }
        }
    }

    func testProductionNeverForwardsNilExpectedVersion() throws {
        for source in try productionSources() {
            XCTAssertFalse(
                source.contents.contains("expectedVersion: nil"),
                "Production must capture a nonoptional package revision, not pass nil (\(source.path))"
            )
        }
    }

    @MainActor
    func testExecutorAdmissionHasNoOptionalLegacyCase() throws {
        let path = "AudioMator/Features/Main/Application/MetadataFileMutationExecutor.swift"
        let url = repositoryRoot.appendingPathComponent(path)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(contents.contains("expectedFileFingerprint: AudioFileFingerprint?"))
        XCTAssertFalse(contents.contains("case legacy("))
        XCTAssertTrue(contents.contains("case reviewed("))
        XCTAssertTrue(contents.contains("case reviewedDraft("))
    }

    func testReviewedRouteFilesStayFreeOfOptionalRevisionForwarding() throws {
        let writeRouteDirectory = repositoryRoot
            .appendingPathComponent("AudioMator/Features/Main/ViewModels", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: writeRouteDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.contains("Write") && $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("expectedVersion: nil"), file.lastPathComponent)
            XCTAssertFalse(contents.contains("?? file.metadataFileVersion"), file.lastPathComponent)
            XCTAssertFalse(contents.contains("persistMetadataEdit"), file.lastPathComponent)
        }
    }
}
