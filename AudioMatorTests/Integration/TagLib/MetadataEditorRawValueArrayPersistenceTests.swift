import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
/// E2 real-container persistence lane: exact raw value arrays must round-trip, or
/// the write must fail atomically with unchanged bytes. Temporary fixture copies
/// only; no real music library is touched.
@MainActor
final class MetadataEditorRawValueArrayPersistenceTests: XCTestCase {
    private let pipeline = TagLibAudioMetadataPipeline()

    func testNoOpMultilineConfirmationLeavesBytesAndRevisionUnchanged() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        try seed(["LYRICS": ["line one\nline two"]], at: url)
        let seededMap = try pipeline.rawMetadataValueMap(for: url)
        let seededLyrics = try XCTUnwrap(seededMap["LYRICS"])

        let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: url)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        XCTAssertTrue(store.isEditable)

        store.selectedFieldKey = "LYRICS"
        let context = try XCTUnwrap(store.makeEditFieldContext())
        XCTAssertFalse(context.isMixed)
        XCTAssertEqual(context.values, seededLyrics)

        let beforeBytes = try Data(contentsOf: url)
        let beforeVersion = try pipeline.metadataFileVersion(at: url)
        let revisionBefore = try TagLibMetadataManager.fileVersion(at: url)

        XCTAssertEqual(
            store.commitFieldEntry(context, typedKey: "", values: context.values),
            .noChange,
            "Opening and confirming an unchanged multiline value must not create a draft change"
        )
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertNil(store.startApply(), "No unchanged draft may be admitted as an apply request")
        XCTAssertEqual(try Data(contentsOf: url), beforeBytes, "No-op confirmation must not touch the file")
        XCTAssertEqual(try pipeline.metadataFileVersion(at: url), beforeVersion)
        XCTAssertEqual(try TagLibMetadataManager.fileVersion(at: url), revisionBefore)
    }

    func testUnrelatedEditPreservesMultilineElementAndIndependentExternalKey() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        try seed(
            [
                "LYRICS": ["line one\nline two"],
                "X-E2-UNRELATED": ["A; B", "Second", "Second"]
            ],
            at: url
        )
        let seededMap = try pipeline.rawMetadataValueMap(for: url)
        let seededLyrics = try XCTUnwrap(seededMap["LYRICS"])

        let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: url)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        store.upsertField(key: "TITLE", values: ["Edited title"])
        let request = try XCTUnwrap(store.startApply())

        let mediaPipeline = TagLibAudioMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline)
        viewModel.mergeQuickImportFiles([file])
        let outcome = await viewModel.applyRawMetadataApplyRequest(request)
        XCTAssertTrue(outcome.failedTargetIDs.isEmpty, "Unexpected raw apply failure")
        XCTAssertTrue(outcome.didApplyAllChanges)
        XCTAssertEqual(store.completeApply(outcome), .dismiss)

        let saved = try mediaPipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(saved["TITLE"], ["Edited title"])
        XCTAssertEqual(
            saved["LYRICS"],
            seededLyrics,
            "One value containing an LF must survive as one value"
        )
        XCTAssertEqual(
            saved["X-E2-UNRELATED"],
            ["A; B", "Second", "Second"],
            "Independent external keys and duplicate values must survive"
        )
    }

    func testExplicitMultilineElementEditRoundTripsOrFailsAtomically() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        try seed(["LYRICS": ["old line one\nold line two"]], at: url)
        let seededMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertNotNil(seededMap["LYRICS"])

        let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: url)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let editedValue = "new line one\nnew line two\nnew line three"
        store.upsertField(key: "LYRICS", values: [editedValue])
        let request = try XCTUnwrap(store.startApply())
        let beforeBytes = try Data(contentsOf: url)

        let mediaPipeline = TagLibAudioMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline)
        viewModel.mergeQuickImportFiles([file])
        let outcome = await viewModel.applyRawMetadataApplyRequest(request)

        if outcome.didApplyAllChanges {
            XCTAssertEqual(store.completeApply(outcome), .dismiss)
            let saved = try mediaPipeline.rawMetadataValueMap(for: url)
            XCTAssertEqual(
                saved["LYRICS"],
                [editedValue],
                "An explicitly edited multiline element must round-trip on the writable FLAC fixture"
            )
        } else {
            XCTAssertFalse(outcome.failedTargetIDs.isEmpty)
            XCTAssertEqual(
                try Data(contentsOf: url),
                beforeBytes,
                "A rejected multiline write must leave the file byte-identical"
            )
            XCTAssertEqual(store.completeApply(outcome), .remainReady)
            XCTAssertEqual(store.draftPropertyMaps[file.id]?["LYRICS"], [editedValue])
        }
    }

    func testDuplicateAndBlankArrayEditRoundTripsOrFailsAtomically() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        try seed(["X-E2-ARRAY": ["A", "A"]], at: url)
        let seededMap = try pipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(seededMap["X-E2-ARRAY"], ["A", "A"], "Duplicate raw values must read back exactly")

        let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: url)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let editedValues = ["A", "A", ""]
        store.setFieldValues(editedValues, forKey: "X-E2-ARRAY")
        let request = try XCTUnwrap(store.startApply())
        let beforeBytes = try Data(contentsOf: url)

        let mediaPipeline = TagLibAudioMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline)
        viewModel.mergeQuickImportFiles([file])
        let outcome = await viewModel.applyRawMetadataApplyRequest(request)

        if outcome.didApplyAllChanges {
            XCTAssertEqual(store.completeApply(outcome), .dismiss)
            let saved = try mediaPipeline.rawMetadataValueMap(for: url)
            XCTAssertEqual(
                saved["X-E2-ARRAY"],
                editedValues,
                "Duplicate and explicit blank elements must round-trip exactly where the container accepts them"
            )
        } else {
            XCTAssertEqual(
                try Data(contentsOf: url),
                beforeBytes,
                "A container that rejects a blank array element must fail atomically"
            )
        }
    }

    // MARK: - Helpers

    private func seed(_ values: RawMetadataValueMap, at url: URL) throws {
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: values),
            to: url
        )
    }

    private func waitUntilLoaded(
        _ store: MetadataEditorStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.isLoading, "Timed out waiting for Metadata Editor load", file: file, line: line)
        XCTAssertNil(store.loadErrorMessage, file: file, line: line)
    }
}
#endif
