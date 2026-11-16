import XCTest
import TagLibAudioMetadata
@testable import AudioMator

@MainActor
final class AutomaticNumberRecoveryTests: XCTestCase {
    private func fixture() throws -> URL {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "testAudioFile", withExtension: "m4a", subdirectory: "Fixtures/Audio")
            ?? Bundle(for: Self.self).url(forResource: "testAudioFile", withExtension: "m4a"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try FileManager.default.copyItem(at: source, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPrivateOnlyValuesAreRecoveredWithoutWritingTheFile() async throws {
        for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"] {
            let url = try fixture()
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                .init(key: "trkn", type: "intPair", remove: true),
                .init(key: "disk", type: "intPair", remove: true),
                .init(key: "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"]),
                .init(key: "----:com.apple.iTunes:\(prefix)_DISCNUMBER_TEXT", type: "stringList", values: ["01/02"])
            ]), to: url)
            let before = try Data(contentsOf: url)
            let pipeline = TagLibAudioMetadataPipeline()
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(file.track, 3)
            XCTAssertEqual(file.trackTotal, 12)
            XCTAssertEqual(file.disc, 1)
            XCTAssertEqual(file.discTotal, 2)
            XCTAssertEqual(file.trackNumberText, "3/12")
            XCTAssertEqual(try Data(contentsOf: url), before)
            var edit = SingleFileEditModel(from: file)
            edit.title = "Title-only compatibility"
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            let after = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(after.trackTotal, 12)
            XCTAssertEqual(after.discTotal, 2)
            let atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertEqual(atoms.first { $0.key == "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT" }?.values, ["03/12"])
            XCTAssertFalse(atoms.contains { $0.key == "trkn" })
        }
    }

    func testUnresolvedCandidatesAreNotDisplayedAsAChosenValue() {
        let group = MetadataNumberGroupInventory(
            number: .init(state: .native, nativeValue: 3),
            total: .init(state: .ambiguous, candidates: ["12", "14"]))
        let result = TagLibNumberingProjection.pair(number: 3, total: 12, text: "3/12", inventory: group)
        XCTAssertEqual(result.number, 3)
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.text, "3")
    }
    func testOrdinarySaveMigratesEditedPairWithTitleAndClearDoesNotResurrectIt() async throws {
        for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"] {
            let url = try fixture()
            let identity = "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT"
            let other = "----:com.apple.iTunes:\(prefix)_DISCNUMBER_TEXT"
            let foreign = "----:org.example:\(prefix)_TRACKNUMBER_TEXT"
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                .init(key: "trkn", type: "intPair", remove: true),
                .init(key: identity, type: "stringList", values: ["03/12"]),
                .init(key: other, type: "stringList", values: ["01/02"]),
                .init(key: foreign, type: "stringList", values: ["99/99"])
            ]), to: url)
            let pipeline = TagLibAudioMetadataPipeline()
            var file = try await pipeline.loadAudioFile(at: url, id: UUID())
            var edit = SingleFileEditModel(from: file)
            edit.setTrackNumberFieldText("5")
            edit.title = "Normal save"
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            file = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(file.track, 5); XCTAssertEqual(file.trackTotal, 12)
            XCTAssertEqual(file.title, "Normal save")
            var atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertFalse(atoms.contains { $0.key == identity })
            XCTAssertEqual(atoms.first { $0.key == other }?.values, ["01/02"])
            XCTAssertEqual(atoms.first { $0.key == foreign }?.values, ["99/99"])
            edit = SingleFileEditModel(from: file)
            edit.setTrackNumberFieldText(""); edit.setTrackTotalFieldText("")
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            file = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(file.track, 0); XCTAssertEqual(file.trackTotal, 0)
            atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertFalse(atoms.contains { $0.key == identity || $0.key == "trkn" })
        }
    }

    func testCanonicalValuesAreUsedWithoutAskingForAStoragePolicy() async throws {
        let url = try fixture()
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "trkn", type: "intPair", first: 3, second: 6),
            .init(key: "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"])
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let before = try Data(contentsOf: url)
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.track, 3); XCTAssertEqual(file.trackTotal, 6)
        XCTAssertEqual(try Data(contentsOf: url), before)
        var edit = SingleFileEditModel(from: file); edit.setTrackNumberFieldText("4")
        _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
        let after = try await pipeline.loadAudioFile(at: url, id: file.id)
        XCTAssertEqual(after.track, 4); XCTAssertEqual(after.trackTotal, 6)
    }

    func testAmbiguityRequestsOrdinaryTotalAndAcceptsItsReplacement() async throws {
        let url = try fixture()
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "trkn", type: "intPair", remove: true),
            .init(key: "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"]),
            .init(key: "----:com.apple.iTunes:TAGLIBAUDIOMETADATA_TRACKNUMBER_TEXT", type: "stringList", values: ["04/14"])
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.track, 0); XCTAssertEqual(file.trackTotal, 0)
        var edit = SingleFileEditModel(from: file); edit.setTrackNumberFieldText("5")
        let before = try Data(contentsOf: url)
        do {
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            XCTFail("An unknown untouched total must not be guessed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Total Tracks"))
            XCTAssertFalse(error.localizedDescription.contains("AUDIOMATOR"))
            XCTAssertFalse(error.localizedDescription.contains("legacy"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
        edit.setTrackTotalFieldText("16")
        _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
        let after = try await pipeline.loadAudioFile(at: url, id: file.id)
        XCTAssertEqual(after.track, 5); XCTAssertEqual(after.trackTotal, 16)
    }

    func testStalePrivateRecoveryCannotBeCommittedAgainstAnotherRevision() async throws {
        let url = try fixture()
        let identity = "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT"
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "trkn", type: "intPair", remove: true),
            .init(key: identity, type: "stringList", values: ["03/12"])
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: identity, type: "stringList", values: ["04/14"])
        ]), to: url)
        let before = try Data(contentsOf: url)
        var edit = SingleFileEditModel(from: file); edit.setTrackNumberFieldText("5")
        XCTAssertThrowsError(try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

}
