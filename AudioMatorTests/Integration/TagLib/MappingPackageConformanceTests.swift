import XCTest
import TagLibAudioMetadata
@testable import AudioMator

/// Positive contract probes against the released package, without app repair
/// patches. A failure is an integration blocker, not an expected failure.
final class MappingPackageConformanceTests: XCTestCase {
    private func fixture(_ ext: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile", withExtension: ext, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile", withExtension: ext))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: source, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPackageYearMustPreserveIndependentXiphDate() throws {
        let url = try fixture("flac")
        try TagLibMetadataManager.applyMetadataPatch(.init(fields: [
            .year: .text("2004"), .standaloneDate: .text("2008-03-04")
        ]), to: url)
        try TagLibMetadataManager.applyMetadataPatch(.init(fields: [.year: .text("2005")]), to: url)
        XCTAssertEqual(try TagLibMetadataManager.readSnapshot(from: url).basic.date, "2008-03-04")
    }

    func testPackageMP4DateMustNotRequireYearCompanion() throws {
        let url = try fixture("m4a")
        try TagLibMetadataManager.applyMetadataPatch(.init(fields: [.year: .text("2004")]), to: url)
        try TagLibMetadataManager.applyMetadataPatch(.init(fields: [.standaloneDate: .text("2008-03-04")]), to: url)
        let snapshot = try TagLibMetadataManager.readSnapshot(from: url)
        XCTAssertEqual(snapshot.basic.year, "2004")
        XCTAssertEqual(snapshot.basic.date, "2008-03-04")
    }

    func testAppWritesOnlyYearAndPreservesIndependentDate() throws {
        let url = try fixture("flac")
        try TagLibMetadataManager.applyMetadataPatch(.init(fields: [
            .year: .text("2004"), .standaloneDate: .text("2008-03-04")
        ]), to: url)
        var edit = SingleFileEditModel()
        edit.year = "2005"
        var payload = MetadataEditPayload(edit)
        payload.changedFields = [.year]
        payload.trackNumberTextChanged = false
        payload.discNumberTextChanged = false
        XCTAssertEqual(TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields, [.year: .text("2005")])
        _ = try TagLibAudioMetadataPipeline().writeMetadata(payload, to: url, expectedVersion: nil)
        let after = try TagLibMetadataManager.readSnapshot(from: url).basic
        XCTAssertEqual(after.year, "2005")
        XCTAssertEqual(after.date, "2008-03-04")
    }
}
