import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
@MainActor
final class MetadataEditorRawValueArrayTests: XCTestCase {
    // MARK: - Entry context and commit

    func testEntryContextKeepsMultilineElementAndUnchangedConfirmationIsNoOp() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/raw-multiline.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["LYRICS": ["line one\nline two"], "TITLE": ["Title"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.selectedFieldKey = "LYRICS"

        let context = try XCTUnwrap(store.makeEditFieldContext())
        XCTAssertEqual(context.mode, .edit)
        XCTAssertEqual(context.key, "LYRICS")
        XCTAssertEqual(context.values, ["line one\nline two"])
        XCTAssertEqual(context.beforeValuesByTarget[file.id] ?? nil, ["line one\nline two"])
        XCTAssertFalse(context.isMixed)

        let generationBefore = store.draftGeneration
        let outcome = store.commitFieldEntry(context, typedKey: "", values: context.values)
        XCTAssertEqual(outcome, .noChange)
        XCTAssertEqual(store.draftGeneration, generationBefore, "An unchanged confirmation is not a draft mutation")
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertNil(store.startApply())
        XCTAssertEqual(pipeline.rawMapWriteCount, 0)
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["LYRICS"], ["line one\nline two"])
    }

    func testEntryExplicitEditStagesExactArrayAndDoneCapturesBeforeAfterValues() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/raw-explicit.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["LYRICS": ["old one\nold two"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.selectedFieldKey = "LYRICS"

        let context = try XCTUnwrap(store.makeEditFieldContext())
        let newValues = ["new one\nnew two", "second value"]
        XCTAssertEqual(store.commitFieldEntry(context, typedKey: "", values: newValues), .applied)
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["LYRICS"], newValues)
        XCTAssertTrue(store.hasUnsavedChanges)

        let request = try XCTUnwrap(store.startApply())
        XCTAssertEqual(request.pendingTargets.map(\.id), [file.id])
        XCTAssertEqual(
            request.pendingChanges,
            [
                RawFieldValueChange(
                    targetID: file.id,
                    key: "LYRICS",
                    beforeValues: ["old one\nold two"],
                    afterValues: newValues
                )
            ]
        )
        XCTAssertEqual(request.submittedOriginalPropertyMaps[file.id]?["LYRICS"], ["old one\nold two"])
        XCTAssertEqual(request.submittedPropertyMaps[file.id]?["LYRICS"], newValues)
        XCTAssertEqual(request.draftGeneration, store.draftGeneration)
        XCTAssertEqual(pipeline.rawMapWriteCount, 0)
    }

    func testEntryCommitRejectsEmptyValueListAndStaleContextWithoutMutating() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/raw-reject.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [file.url: ["TITLE": ["Original"]]])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.selectedFieldKey = "TITLE"

        let context = try XCTUnwrap(store.makeEditFieldContext())
        XCTAssertEqual(
            store.commitFieldEntry(context, typedKey: "", values: []),
            .rejected(.emptyValueList)
        )
        XCTAssertEqual(store.draftPropertyMaps[file.id], ["TITLE": ["Original"]])
        XCTAssertFalse(store.hasUnsavedChanges)

        store.upsertField(key: "COMMENT", value: "newer")
        XCTAssertEqual(
            store.commitFieldEntry(context, typedKey: "", values: ["Stale"]),
            .rejected(.staleDraft),
            "A context captured before a draft mutation must not stage anything"
        )
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Original"])
    }

    func testMixedSelectionStartsWithNoElementsAndRequiresExplicitReplacement() async throws {
        let first = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-mixed-01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let second = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-mixed-02.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            first.url: ["TITLE": ["First title"]],
            second.url: ["ALBUM": ["Second album"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [first, second])
        try await waitUntilLoaded(store)
        store.selectedFieldKey = "TITLE"

        let context = try XCTUnwrap(store.makeEditFieldContext())
        XCTAssertTrue(context.isMixed)
        XCTAssertEqual(context.values, [])
        XCTAssertEqual(context.emptyStartReason, .mixedSelection)
        XCTAssertEqual(
            store.commitFieldEntry(context, typedKey: "", values: []),
            .rejected(.emptyValueList)
        )

        let replaced = ["Shared title"]
        XCTAssertEqual(store.commitFieldEntry(context, typedKey: "", values: replaced), .applied)
        XCTAssertEqual(store.draftPropertyMaps[first.id]?["TITLE"], replaced)
        XCTAssertEqual(
            store.draftPropertyMaps[second.id]?["TITLE"],
            replaced,
            "An explicit mixed replacement creates the key on a target that did not have it"
        )
    }

    func testExistingEmptyArrayIsPreservedUntilExplicitValueOrDeleteField() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-empty-array.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [file.url: ["CUSTOM": []]])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        XCTAssertEqual(store.originalPropertyMaps[file.id]?["CUSTOM"], [])

        let rows = MetadataEditorDraftRows.makeRows(
            targets: store.targets,
            draftPropertyMaps: store.draftPropertyMaps
        )
        XCTAssertEqual(rows.map(\.key), ["CUSTOM"])
        store.selectedFieldKey = "CUSTOM"
        let context = try XCTUnwrap(store.makeEditFieldContext())
        XCTAssertEqual(context.values, [])
        XCTAssertEqual(context.emptyStartReason, .existingEmptyArray)

        XCTAssertEqual(store.commitFieldEntry(context, typedKey: "", values: []), .noChange)
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["CUSTOM"], [])
        XCTAssertFalse(store.hasUnsavedChanges)

        XCTAssertEqual(
            store.commitFieldEntry(context, typedKey: "", values: ["Explicit"]),
            .applied
        )
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["CUSTOM"], ["Explicit"])
    }

    func testDeleteFieldRemainsTheOnlyKeyRemovalPath() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-delete.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["COMMENT": ["Keep until Delete"], "TITLE": ["Title"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.selectedFieldKey = "COMMENT"

        XCTAssertEqual(
            store.commitFieldEntry(
                try XCTUnwrap(store.makeEditFieldContext()),
                typedKey: "",
                values: []
            ),
            .rejected(.emptyValueList)
        )
        XCTAssertNotNil(store.draftPropertyMaps[file.id]?["COMMENT"])

        store.deleteField(named: "COMMENT")
        XCTAssertNil(store.draftPropertyMaps[file.id]?["COMMENT"])
    }

    // MARK: - Utilities preview and apply

    func testWholeValueReplacementOnFirstOfTwoValuesPreviewsAndAppliesExactArrays() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-whole.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["TITLE": ["Alpha", "Beta"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let textPipeline = TextEditPipeline(steps: [
            .replaceText(TextFindReplacement(
                findText: "Alpha",
                replacementText: "Changed",
                options: TextFindReplacementOptions(matchesCase: false, matchesWholeText: true)
            ))
        ])
        let preview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: textPipeline,
            fieldKeys: ["TITLE"]
        ))
        XCTAssertEqual(preview.rows.count, 1)
        let row = try XCTUnwrap(preview.rows.first)
        XCTAssertEqual(row.beforeValues, ["Alpha", "Beta"])
        XCTAssertEqual(row.afterValues, ["Changed", "Beta"])
        XCTAssertTrue(row.changed)
        XCTAssertEqual(preview.changedRows.count, 1)

        XCTAssertEqual(
            store.applyTextUtilityPreview(preview),
            .applied(changeCount: 1)
        )
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Changed", "Beta"])
    }

    func testPrefixSuffixCaseAndTrimTransformEveryValueIndependently() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-every-value.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["GENRE": ["  rock  ", "  Pop ", ""]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let trim = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.trimEdges(.whitespacesAndNewlines)]),
            fieldKeys: ["GENRE"]
        ))
        XCTAssertEqual(trim.rows.first?.afterValues, ["rock", "Pop", ""])
        XCTAssertEqual(store.applyTextUtilityPreview(trim), .applied(changeCount: 1))
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["GENRE"], ["rock", "Pop", ""])

        let prefixed = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.insertText("P-", position: .prefix)]),
            fieldKeys: ["GENRE"]
        ))
        XCTAssertEqual(prefixed.rows.first?.afterValues, ["P-rock", "P-Pop", "P-"])
        XCTAssertEqual(store.applyTextUtilityPreview(prefixed), .applied(changeCount: 1))
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["GENRE"], ["P-rock", "P-Pop", "P-"])

        let uppercase = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.transformCase(.uppercase)]),
            fieldKeys: ["GENRE"]
        ))
        XCTAssertEqual(uppercase.rows.first?.afterValues, ["P-ROCK", "P-POP", "P-"])
        XCTAssertEqual(store.applyTextUtilityPreview(uppercase), .applied(changeCount: 1))
    }

    func testUtilitiesKeepDuplicatesEmptyElementsAndOrder() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-duplicates.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["ARTIST": ["dup", "dup", ""]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let prefix = TextEditPipeline(steps: [.insertText("[", position: .prefix)])
        let preview = try XCTUnwrap(store.makeTextUtilityPreview(pipeline: prefix, fieldKeys: ["ARTIST"]))
        XCTAssertEqual(preview.rows.first?.afterValues, ["[dup", "[dup", "["])
        XCTAssertEqual(store.applyTextUtilityPreview(preview), .applied(changeCount: 1))
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["ARTIST"], ["[dup", "[dup", "["])
    }

    func testUtilitiesSkipMissingFieldsAndNeverInsertKeys() async throws {
        let first = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-missing-01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let second = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-missing-02.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            first.url: ["TITLE": [" first "]],
            second.url: ["ALBUM": ["album"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [first, second])
        try await waitUntilLoaded(store)

        let preview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.trimEdges(.whitespacesAndNewlines)]),
            fieldKeys: ["TITLE"]
        ))
        XCTAssertEqual(preview.rows.map(\.targetID), [first.id])
        XCTAssertEqual(store.applyTextUtilityPreview(preview), .applied(changeCount: 1))
        XCTAssertEqual(store.draftPropertyMaps[first.id]?["TITLE"], ["first"])
        XCTAssertNil(store.draftPropertyMaps[second.id]?["TITLE"])
    }

    func testUtilitiesApplyRejectsStaleGenerationAndKeepsMutatedDraft() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-stale.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [
            file.url: ["TITLE": ["Before"], "COMMENT": ["comment"]]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let preview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.insertText("P-", position: .prefix)]),
            fieldKeys: ["TITLE"]
        ))
        store.upsertField(key: "TITLE", values: ["Mutated directly"])
        XCTAssertEqual(
            store.applyTextUtilityPreview(preview),
            .stale,
            "A preview captured before a draft mutation must not apply"
        )
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Mutated directly"])

        let freshPreview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.insertText("P-", position: .prefix)]),
            fieldKeys: ["TITLE"]
        ))
        XCTAssertEqual(store.applyTextUtilityPreview(freshPreview), .applied(changeCount: 1))
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["P-Mutated directly"])
    }

    func testUtilitiesApplyRejectsStalePresentationAndTargetSet() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-stale-session.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [file.url: ["TITLE": ["Before"]]])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let preview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.insertText("P-", position: .prefix)]),
            fieldKeys: ["TITLE"]
        ))
        store.recordAppliedTargets([file.id])
        XCTAssertTrue(store.targets.isEmpty)
        XCTAssertEqual(store.applyTextUtilityPreview(preview), .stale)

        store.presentNew(targetFiles: [file])
        try await waitUntilLoaded(store)
        XCTAssertEqual(
            store.applyTextUtilityPreview(preview),
            .stale,
            "A preview from a superseded presentation must not apply"
        )
    }

    func testUtilitiesPreviewUnavailableWithoutSelectionOrChanges() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-empty-preview.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [file.url: ["TITLE": ["Same"]]])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        XCTAssertNil(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: []),
            fieldKeys: []
        ))

        let identityPreview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: []),
            fieldKeys: ["TITLE"]
        ))
        XCTAssertTrue(identityPreview.changedRows.isEmpty)
        XCTAssertEqual(store.applyTextUtilityPreview(identityPreview), .noChanges)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testUnsupportedArrayEditFailsClosedAndLeavesBytesUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-E2-Unsupported-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("note.xyz")
        try Data(repeating: 0x41, count: 32).write(to: url)
        let beforeBytes = try Data(contentsOf: url)

        let file = AudioFileTestFactory.make(
            url: url,
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [url: ["CUSTOM": ["A", "A"]]])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.selectedFieldKey = "CUSTOM"

        let context = try XCTUnwrap(store.makeEditFieldContext())
        XCTAssertEqual(context.values, ["A", "A"])
        XCTAssertEqual(
            store.commitFieldEntry(context, typedKey: "", values: ["B", "B", ""]),
            .applied
        )
        let request = try XCTUnwrap(store.startApply())

        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        let outcome = await viewModel.applyRawMetadataApplyRequest(request)

        XCTAssertFalse(outcome.didApplyAllChanges)
        XCTAssertEqual(outcome.failedTargetIDs, [file.id])
        XCTAssertEqual(pipeline.rawMapWriteCount, 0, "An unsupported array edit must not reach a writer")
        XCTAssertEqual(try Data(contentsOf: url), beforeBytes, "A rejected write must leave bytes unchanged")
        XCTAssertEqual(store.completeApply(outcome), .remainReady)
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["CUSTOM"], ["B", "B", ""])
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
    }

    func testArrayRequestWithoutCapturedChangesFallsBackToReviewedBaseline() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/raw-baseline-fallback.mp3"),
            includeDefaultFileFingerprint: false
        )
        let pipeline = ArrayMetadataEditorPipeline(valuesByURL: [file.url: ["TITLE": ["Original"]]])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let legacyRequest = MetadataEditorApplyRequest(
            presentationID: MetadataEditorPresentationID(),
            applyID: MetadataEditorApplyID(),
            targets: store.targets,
            pendingTargets: store.targets,
            submittedPropertyMaps: store.draftPropertyMaps,
            draftGeneration: 0
        )
        XCTAssertFalse(legacyRequest.hasCapturedChanges)

        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        let outcome = await viewModel.applyRawMetadataApplyRequest(legacyRequest)

        XCTAssertEqual(pipeline.rawMapWriteCount, 0, "A display-only target has no reviewed authority")
        XCTAssertFalse(outcome.didApplyAllChanges)
    }

    // MARK: - Helpers

    private func waitUntilLoaded(
        _ store: MetadataEditorStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.isLoading, "Timed out waiting for Metadata Editor load", file: file, line: line)
    }
}

// MARK: - Array-backed fake pipeline

private nonisolated final class ArrayMetadataEditorPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private let valuesByURL: [URL: RawMetadataValueMap]
    private var writeCount = 0

    init(valuesByURL: [URL: RawMetadataValueMap]) {
        self.valuesByURL = valuesByURL
    }

    var rawMapWriteCount: Int {
        lock.withLock { writeCount }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        valuesByURL[url] ?? [:]
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock { writeCount += 1 }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
#endif
