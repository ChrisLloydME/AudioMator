import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class TagLibUpgradeContractTests: XCTestCase {
    @MainActor
    func testExactDependencyPinMatchesProjectAndCurrentDisclosures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let version = "0.7.1"
        let project = try String(contentsOf: root.appendingPathComponent("AudioMator.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("kind = exactVersion;\n\t\t\t\tversion = \(version);"))
        XCTAssertTrue(project.contains("repositoryURL = \"https://github.com/ChrisLloydME/TagLibAudioMetadata.git\";"))
        XCTAssertFalse(project.contains("XCLocalSwiftPackageReference"), "A local path override must never be committed")
        XCTAssertEqual(LicenseDisclosure.entry(for: .tagLibAudioMetadata)?.version, version)
        // The maintainer publishes 0.7.1 after local-override acceptance. Never
        // fabricate a lock resolution for a tag that does not yet exist.
        let resolvedURL = root.appendingPathComponent("AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: resolvedURL)) as? [String: Any])
            let pins = try XCTUnwrap(object["pins"] as? [[String: Any]])
            let pin = try XCTUnwrap(pins.first { $0["identity"] as? String == "taglibaudiometadata" })
            let state = try XCTUnwrap(pin["state"] as? [String: String])
            XCTAssertEqual(state["version"], version)
            XCTAssertEqual(state["revision"]?.count, 40)
        }
        XCTAssertEqual(MetadataMappingCatalog.contractVersion, "AM-TLAM-MAPPING-2.2")
        XCTAssertEqual(MetadataFieldRegistry.schema(for: .year)?.semanticKey, "YEAR")
        XCTAssertEqual(MetadataFieldRegistry.schema(for: .date)?.semanticKey, "YEAR")
        XCTAssertEqual(MetadataFieldRegistry.schema(for: .standaloneDate)?.semanticKey, "DATE")
        XCTAssertEqual(MetadataFieldRegistry.schema(for: .releaseDate)?.semanticKey, "RELEASEDATE")
        XCTAssertEqual(MetadataFieldRegistry.schema(for: .originalReleaseDate)?.semanticKey, "ORIGINALDATE")
        XCTAssertNotNil(MetadataFieldRegistry.schema(for: .standaloneDate)?.writeTarget(for: MetadataNativeFamily.mp4))
        XCTAssertEqual(
            MetadataFieldRegistry.schema(for: .rate)?.capability(for: MetadataNativeFamily.mp4),
            .readOnly
        )
        for path in ["AGENTS.md", "Docs/Development/BUILD.md", "Docs/Reference/CONFIGURATION.md", "Docs/THIRD_PARTY_NOTICES.md"] {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains(version), path)
            XCTAssertTrue(text.contains("https://github.com/ChrisLloydME/TagLibAudioMetadata"), path)
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

    @MainActor
    func testSemanticNumberOnlyEditsPreserveExistingTotals() async throws {
        for ext in ["mp3", "m4a", "flac", "aac", "ogg", "wav"] {
            let url = try fixture(extension: ext)
            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(numberText: MetadataNumberTextPatch(trackNumberText: "07/12", discNumberText: "02/03")), to: url
            )
            let pipeline = TagLibAudioMetadataPipeline()
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            var edit = SingleFileEditModel(from: file)
            edit.setTrackNumberText("08")
            edit.setDiscNumberText("03")
            _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            let saved = try TagLibMetadataManager.readMetadataResult(from: url)
            XCTAssertEqual(saved.track, 8, ext)
            XCTAssertEqual(saved.trackTotal, 12, ext)
            XCTAssertEqual(saved.disc, 3, ext)
            XCTAssertEqual(saved.discTotal, 3, ext)
            XCTAssertEqual(saved.title, file.title, ext)
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
