import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
/// E2 real-container persistence lane: exact raw value arrays must round-trip, or
/// the write must fail atomically with unchanged bytes. Temporary fixture copies
/// only; no real music library is touched.
nonisolated final class MetadataEditorRawValueArrayPersistenceTests: XCTestCase {
    private let pipeline = TagLibAudioMetadataPipeline()

    @MainActor
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

    @MainActor
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
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline, writableFixtures: [file])
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

    @MainActor
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
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline, writableFixtures: [file])
        viewModel.mergeQuickImportFiles([file])
        let outcome = await viewModel.applyRawMetadataApplyRequest(request)

        XCTAssertTrue(
            outcome.didApplyAllChanges,
            "FLAC supports multiline LYRICS writes; permissive fallback must not hide a persistence regression"
        )
        XCTAssertEqual(store.completeApply(outcome), .dismiss)
        let saved = try mediaPipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(
            saved["LYRICS"],
            [editedValue],
            "An explicitly edited multiline element must round-trip on the writable FLAC fixture"
        )
        XCTAssertNotEqual(try Data(contentsOf: url), beforeBytes)
    }

    @MainActor
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
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline, writableFixtures: [file])
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
            XCTAssertEqual(outcome.failedTargetIDs, [file.id])
            let issue = try XCTUnwrap(
                viewModel.saveIssueLogStore.entries.first?.issues.first,
                "A folder access failure must not count as a rejected write"
            )
            XCTAssertEqual(issue.fileName, request.pendingTargets.first?.fileName)
            XCTAssertFalse(issue.messages.isEmpty)
            XCTAssertEqual(
                try Data(contentsOf: url),
                beforeBytes,
                "A container that rejects a blank array element must fail atomically"
            )
        }
    }

    @MainActor
    func testRetainedRawDraftEditedDuringApplyCanBeSavedAgainOnRealFLAC() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        try seed(
            [
                "TITLE": ["Initial Title"],
                "ARTIST": ["Initial Artist"]
            ],
            at: url
        )

        let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: url)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()

        // First edit captured into Apply 1.
        store.upsertField(key: "TITLE", values: ["First Apply Title"])
        let firstRequest = try XCTUnwrap(store.startApply())

        // Newer edit staged while Apply 1 is in flight (retained-draft path).
        store.upsertField(key: "COMMENT", values: ["Second Apply Comment"])

        let mediaPipeline = TagLibAudioMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: mediaPipeline, writableFixtures: [file])
        viewModel.mergeQuickImportFiles([file])

        let firstOutcome = await viewModel.applyRawMetadataApplyRequest(firstRequest)
        XCTAssertTrue(firstOutcome.didApplyAllChanges)
        XCTAssertNotNil(firstOutcome.refreshedTargetsByID[file.id])
        XCTAssertEqual(store.completeApply(firstOutcome), .remainReady)

        let retainedTarget = try XCTUnwrap(store.targets.first)
        XCTAssertEqual(retainedTarget.id, file.id)
        XCTAssertFalse(retainedTarget.requiresMetadataRefresh)
        XCTAssertNotEqual(
            retainedTarget.expectedMetadataVersion,
            file.metadataFileVersion,
            "Retained target must refresh its expected metadata version to the post-write observation"
        )
        XCTAssertEqual(
            store.originalPropertyMaps[file.id],
            retainedTarget.metadataConflictBaseline?.values,
            "Retained original map must match the refreshed target conflict baseline"
        )
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["COMMENT"], ["Second Apply Comment"])

        // Follow-up Apply 2 must succeed cleanly and persist only the new COMMENT delta.
        let secondRequest = try XCTUnwrap(store.startApply())
        XCTAssertEqual(secondRequest.pendingChanges.map(\.key), ["COMMENT"])
        let secondOutcome = await viewModel.applyRawMetadataApplyRequest(secondRequest)
        XCTAssertTrue(
            secondOutcome.failedTargetIDs.isEmpty,
            "Second Apply on a retained draft must not fail baseline/revision verification"
        )
        XCTAssertTrue(secondOutcome.didApplyAllChanges)
        XCTAssertEqual(store.completeApply(secondOutcome), .dismiss)

        let persisted = try mediaPipeline.rawMetadataValueMap(for: url)
        XCTAssertEqual(persisted["TITLE"], ["First Apply Title"])
        XCTAssertEqual(persisted["COMMENT"], ["Second Apply Comment"])
        XCTAssertEqual(persisted["ARTIST"], ["Initial Artist"])
    }

    @MainActor
    func testRetainedRawDraftWithoutPostWriteReloadFailsClosedOnSecondApply() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: url)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()

        store.upsertField(key: "TITLE", values: ["First Apply Title"])
        let firstRequest = try XCTUnwrap(store.startApply())
        store.upsertField(key: "COMMENT", values: ["Second Apply Comment"])

        // Simulate a write whose post-write reload failed (no refreshed target returned).
        let unrefreshedOutcome = MetadataEditorApplyOutcome(
            presentationID: firstRequest.presentationID,
            applyID: firstRequest.applyID,
            succeededTargetIDs: [file.id],
            failedTargetIDs: [],
            didApplyAllChanges: true,
            refreshedTargetsByID: [:]
        )
        XCTAssertEqual(store.completeApply(unrefreshedOutcome), .remainReady)
        let retainedTarget = try XCTUnwrap(store.targets.first)
        XCTAssertTrue(retainedTarget.requiresMetadataRefresh)
        XCTAssertNil(retainedTarget.reviewedTarget)

        let secondRequest = try XCTUnwrap(store.startApply())
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline, writableFixtures: [file])
        viewModel.mergeQuickImportFiles([file])
        let secondOutcome = await viewModel.applyRawMetadataApplyRequest(secondRequest)
        XCTAssertEqual(secondOutcome.failedTargetIDs, [file.id])
        XCTAssertFalse(secondOutcome.didApplyAllChanges)
    }

    // MARK: - Helpers

    @MainActor
    private func seed(_ values: RawMetadataValueMap, at url: URL) throws {
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: values),
            to: url
        )
    }

    @MainActor
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
