import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class NumberTextDependencyContractTests: XCTestCase {
    @MainActor
    func testUnsupportedNonNumericPairsFailWithoutMutationAndUnrelatedEditsPreserveThem() async throws {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile.flac", withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pipeline = TagLibAudioMetadataPipeline()
        for (number, disc) in [("A1/12", false), ("A1", false), ("B2", true)] {
            let url = root.appendingPathComponent("\(number.replacingOccurrences(of: "/", with: "-"))-\(disc).flac")
            try FileManager.default.copyItem(at: source, to: url)
            _ = try pipeline.eraseAllMetadata(at: url)
            let numberKey = disc ? "DISCNUMBER" : "TRACKNUMBER"
            _ = try pipeline.writeRawMetadataPatch(RawMetadataPatch(valuesToSet: [
                numberKey: [number], "ARTIST": ["Keep A", "Keep B"], "CUSTOM-KEEP": ["untouched"]
            ]), to: url, expectedVersion: nil)
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            var edit = SingleFileEditModel(from: file)
            if disc { edit.setDiscTotalFieldText("13") } else { edit.setTrackTotalFieldText("13") }
            let beforeBytes = try Data(contentsOf: url)
            let beforeMap = try pipeline.rawMetadataValueMap(for: url)
            // Public 0.5.3 behavior: number-text input is unsigned decimal only.
            // This independent contract probe protects the app's safe restriction.
            XCTAssertThrowsError(try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file), to: url,
                expectedVersion: file.metadataFileVersion))
            XCTAssertEqual(try Data(contentsOf: url), beforeBytes)
            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
            viewModel.mergeQuickImportFiles([file])
            guard case .failure(let reason) = await viewModel.persistMetadataEdit(edit, to: file, comparedTo: file) else {
                return XCTFail("Unsupported text must not be reported as saved")
            }
            XCTAssertTrue(reason.contains(disc ? "Non-numeric disc" : "Non-numeric track"))
            XCTAssertEqual(try Data(contentsOf: url), beforeBytes)
            // Unedited text is legal stored metadata and must not block title edits.
            var unrelated = SingleFileEditModel(from: file)
            unrelated.title = "Independent title"
            _ = try pipeline.writeMetadata(MetadataEditPayload(unrelated, comparedTo: file), to: url,
                expectedVersion: file.metadataFileVersion)
            var expected = beforeMap
            expected["TITLE"] = ["Independent title"]
            XCTAssertEqual(try pipeline.rawMetadataValueMap(for: url), expected)

        }
    }
}
