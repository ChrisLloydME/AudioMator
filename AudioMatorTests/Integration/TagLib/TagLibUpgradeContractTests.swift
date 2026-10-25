import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class TagLibUpgradeContractTests: XCTestCase {
    @MainActor
    func testExactDependencyPinMatchesProjectAndCurrentDisclosures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resolved = try Data(contentsOf: root.appendingPathComponent("AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: resolved) as? [String: Any])
        let pins = try XCTUnwrap(object["pins"] as? [[String: Any]])
        let pin = try XCTUnwrap(pins.first { $0["identity"] as? String == "taglibaudiometadata" })
        let state = try XCTUnwrap(pin["state"] as? [String: String])
        let version = try XCTUnwrap(state["version"])
        let revision = try XCTUnwrap(state["revision"])
        let project = try String(contentsOf: root.appendingPathComponent("AudioMator.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("kind = exactVersion;\n\t\t\t\tversion = \(version);"))
        XCTAssertEqual(LicenseDisclosure.entry(for: .tagLibAudioMetadata)?.version, version)
        for path in ["AGENTS.md", "Docs/Development/BUILD.md", "Docs/Reference/CONFIGURATION.md", "Docs/THIRD_PARTY_NOTICES.md"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains(version), path)
            XCTAssertTrue(text.contains(revision), path)
        }
    }

    @MainActor
    func testExistentialRawProjectionAndValueMapDeltaKeepAdapterContract() async throws {
        let url = try fixture()
        let concrete = TagLibAudioMetadataPipeline()
        let pipeline: any AudioMetadataPipeline = concrete
        _ = try pipeline.writeRawMetadataPatch(RawMetadataPatch(valuesToSet: [
            "TRACKNUMBER": ["07/12"], "CUSTOM-KEEP": ["A", "B"]
        ]), to: url, expectedVersion: nil)
        XCTAssertEqual(try pipeline.rawMetadataPropertyMap(for: url), try concrete.rawMetadataPropertyMap(for: url))
        var values = try pipeline.rawMetadataValueMap(for: url)
        values["TITLE"] = ["Via existential"]
        _ = try pipeline.writeRawMetadataValueMap(values, to: url, expectedVersion: pipeline.metadataFileVersion(at: url))
        XCTAssertEqual(try pipeline.rawMetadataValueMap(for: url), values)
    }

    func testFLACSemanticCommentSetReplaceAndClearContract() throws {
        let url = try fixture()
        for text in ["Probe Comment", "Replacement Comment"] {
            let before = try Data(contentsOf: url)
            do {
                _ = try TagLibMetadataManager.applyMetadataPatch(
                    MetadataPatch(fields: [.comment: .text(text)]), to: url
                )
            } catch {
                XCTAssertEqual(try Data(contentsOf: url), before, "A rejected package write must preserve the original")
                throw error // Keep the upstream blocker visible; never substitute a raw patch.
            }
            XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: url).comment, text)
        }
        _ = try TagLibMetadataManager.applyMetadataPatch(MetadataPatch(fields: [.comment: .remove]), to: url)
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: url).comment, "")
    }

    @MainActor
    func testUnavailableAudioIdentityRequiresReloadAfterRevisionChange() async throws {
        let url = try fixture(extension: "m4a")
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let baseline = try XCTUnwrap(file.metadataConflictBaseline)
        XCTAssertNil(baseline.audioContentIdentity)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let bytes = try Data(contentsOf: url)
        var edit = SingleFileEditModel(from: file)
        edit.title = "Stale title"
        var raw = baseline.values
        raw["TITLE"] = [edit.title]
        for policy in MetadataConflictPolicy.allCases {
            XCTAssertThrowsError(try MetadataConflictResolver.writeMetadata(
                MetadataEditPayload(edit, comparedTo: file), original: baseline,
                originalFingerprint: try XCTUnwrap(file.fileFingerprint), originalVersion: try XCTUnwrap(file.metadataFileVersion),
                policy: policy, pipeline: pipeline, url: url
            ))
            XCTAssertThrowsError(try MetadataConflictResolver.writeRawMetadata(
                raw, original: baseline, originalFingerprint: try XCTUnwrap(file.fileFingerprint),
                originalVersion: try XCTUnwrap(file.metadataFileVersion), policy: policy, pipeline: pipeline, url: url
            ))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    private func fixture(extension ext: String = "flac") throws -> URL {
        let bundle = Bundle(for: Self.self)
        let name = "testAudioFile.\(ext)"
        let source = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: name, withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }
}
