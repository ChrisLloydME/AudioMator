import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
@MainActor
final class MetadataEditorStoreTests: XCTestCase {
    func testFriendlyNamesNeverRedirectExistingRawDateOrAliasKeys() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/aliases.m4a"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
            file.url: ["DATE": "2004", "YEAR": "Keep", "ALBUM ARTIST": "Original"]
        ]))
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.upsertField(key: "DATE", value: "2005")
        store.upsertField(key: "ALBUM ARTIST", value: "Updated")
        store.upsertField(key: "Date", value: "2017-06-09")
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["DATE"], ["2005"])
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["YEAR"], ["Keep"])
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["ALBUM ARTIST"], ["Updated"])
        XCTAssertNil(store.draftPropertyMaps[file.id]?["ALBUMARTIST"])
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["STANDALONEDATE"], ["2017-06-09"])
    }

    func testPresentLoadsDraftMapsAndSelectsFirstField() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstFile = AudioFileTestFactory.make(
            id: firstID,
            url: URL(fileURLWithPath: "/tmp/01 - First.mp3")
        ,
            includeDefaultFileFingerprint: false
        )
        let secondFile = AudioFileTestFactory.make(
            id: secondID,
            url: URL(fileURLWithPath: "/tmp/02 - Second.mp3")
        ,
            includeDefaultFileFingerprint: false
        )
        let pipeline = MockMetadataEditorPipeline(propertyMapsByURL: [
            firstFile.url: ["TITLE": "First", "ALBUM": "Shared Album"],
            secondFile.url: ["TITLE": "Second", "ALBUM": "Shared Album"]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)

        XCTAssertEqual(store.targets.map(\.id), [firstID, secondID])
        XCTAssertEqual(store.originalPropertyMaps[firstID], ["TITLE": ["First"], "ALBUM": ["Shared Album"]])
        XCTAssertEqual(store.draftPropertyMaps[secondID], ["TITLE": ["Second"], "ALBUM": ["Shared Album"]])
        XCTAssertEqual(store.selectedFieldKey, "ALBUM")
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertNil(store.loadErrorMessage)
        XCTAssertEqual(store.selectionSummaryText, "2 selected files")
    }

    func testUpsertFieldPreservesExactValuesAndAppliesToEveryTarget() async throws {
        let firstFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let secondFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.mp3"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                firstFile.url: ["TITLE": "First"],
                secondFile.url: ["TITLE": "Second"]
            ])
        )

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)
        store.upsertField(key: " CUSTOMFIELD ", values: ["  Shared Value", ""])

        XCTAssertEqual(store.draftPropertyMaps[firstFile.id]?["CUSTOMFIELD"], ["  Shared Value", ""])
        XCTAssertEqual(store.draftPropertyMaps[secondFile.id]?["CUSTOMFIELD"], ["  Shared Value", ""])
        XCTAssertEqual(store.selectedFieldKey, "CUSTOMFIELD")
        XCTAssertTrue(store.hasUnsavedChanges)

        // A line break inside one element is data, not an element boundary.
        store.upsertField(key: "MULTILINE", values: ["line one\nline two"])
        XCTAssertEqual(store.draftPropertyMaps[firstFile.id]?["MULTILINE"], ["line one\nline two"])
    }

    func testUpsertFieldIgnoresEmptyKeysButPreservesWhitespaceAndEmptyValueBoundaries() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let initialMap = ["TITLE": "Original"]
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [file.url: initialMap])
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.upsertField(key: "   ", value: "Ignored")
        store.upsertField(key: "CUSTOMFIELD", values: [" ", " "])

        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Original"])
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["CUSTOMFIELD"], [" ", " "])
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testDeleteSelectedFieldRemovesFieldFromEveryTargetAndRealignsSelection() async throws {
        let firstFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let secondFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.mp3"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                firstFile.url: ["ALBUM": "Album", "TITLE": "First"],
                secondFile.url: ["ALBUM": "Album", "TITLE": "Second"]
            ])
        )

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)
        XCTAssertEqual(store.selectedFieldKey, "ALBUM")

        store.deleteSelectedField()

        XCTAssertNil(store.draftPropertyMaps[firstFile.id]?["ALBUM"])
        XCTAssertNil(store.draftPropertyMaps[secondFile.id]?["ALBUM"])
        XCTAssertEqual(store.selectedFieldKey, "TITLE")
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testDeleteSelectedFieldRemovesMultipleSelectedFields() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                file.url: ["ALBUM": "Album", "ARTIST": "Artist", "TITLE": "Title"]
            ])
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.selectedFieldKeys = ["ALBUM", "ARTIST"]

        store.deleteSelectedField()

        XCTAssertEqual(store.draftPropertyMaps[file.id], ["TITLE": ["Title"]])
        XCTAssertEqual(store.selectedFieldKey, "TITLE")
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testTextUtilityPreviewAndApplySupportMultipleFilesAndFields() async throws {
        let firstFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let secondFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.mp3"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                firstFile.url: ["TITLE": " first ", "ARTIST": " artist "],
                secondFile.url: ["TITLE": " second ", "ARTIST": " artist "]
            ])
        )
        let pipeline = TextEditPipeline(steps: [
            .trimEdges(.whitespacesAndNewlines),
            .transformCase(.titleCase)
        ])

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)

        let preview = try XCTUnwrap(
            store.makeTextUtilityPreview(pipeline: pipeline, fieldKeys: ["TITLE", "ARTIST"])
        )
        XCTAssertEqual(preview.rows.count, 4)
        let firstTitle = try XCTUnwrap(
            preview.rows.first { $0.targetID == firstFile.id && $0.fieldKey == "TITLE" }
        )
        XCTAssertEqual(firstTitle.beforeValues, [" first "])
        XCTAssertEqual(firstTitle.afterValues, ["First"])
        XCTAssertTrue(firstTitle.changed)

        XCTAssertEqual(store.applyTextUtilityPreview(preview), .applied(changeCount: 4))

        XCTAssertEqual(store.draftPropertyMaps[firstFile.id]?["TITLE"], ["First"])
        XCTAssertEqual(store.draftPropertyMaps[firstFile.id]?["ARTIST"], ["Artist"])
        XCTAssertEqual(store.draftPropertyMaps[secondFile.id]?["TITLE"], ["Second"])
        XCTAssertEqual(store.draftPropertyMaps[secondFile.id]?["ARTIST"], ["Artist"])
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testTextUtilityApplyPreservesInsertedLeadingAndTrailingSpaces() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                file.url: ["TITLE": "Title", "ARTIST": "Artist"]
            ])
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        let prefixPreview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.insertText("  ", position: .prefix)]),
            fieldKeys: ["TITLE"]
        ))
        XCTAssertEqual(store.applyTextUtilityPreview(prefixPreview), .applied(changeCount: 1))

        let suffixPreview = try XCTUnwrap(store.makeTextUtilityPreview(
            pipeline: TextEditPipeline(steps: [.insertText("  ", position: .suffix)]),
            fieldKeys: ["ARTIST"]
        ))
        XCTAssertEqual(store.applyTextUtilityPreview(suffixPreview), .applied(changeCount: 1))

        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["  Title"])
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["ARTIST"], ["Artist  "])
    }

    func testDiscardChangesRestoresOriginalMaps() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let originalMap = ["TITLE": "Original"]
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [file.url: originalMap])
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.upsertField(key: "CUSTOMFIELD", value: "Draft")
        XCTAssertTrue(store.hasUnsavedChanges)

        store.discardChanges()

        XCTAssertEqual(store.draftPropertyMaps[file.id], ["TITLE": ["Original"]])
        XCTAssertEqual(store.selectedFieldKey, "TITLE")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testRecordingPartialApplyLeavesOnlyFailedTargetsPending() async throws {
        let firstFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"),
            includeDefaultFileFingerprint: false
        )
        let secondFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.mp3"),
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                firstFile.url: ["TITLE": "First"],
                secondFile.url: ["TITLE": "Second"]
            ])
        )

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)
        store.upsertField(key: "ALBUM", value: "Shared Draft")
        store.recordAppliedTargets([firstFile.id])

        XCTAssertEqual(store.targets.map(\.id), [secondFile.id])
        XCTAssertEqual(store.pendingTargets.map(\.id), [secondFile.id])
        XCTAssertTrue(store.hasUnsavedChanges)

        store.upsertField(key: "GENRE", value: "Retry Edit")

        XCTAssertEqual(store.pendingTargets.map(\.id), [secondFile.id])

        store.recordAppliedTargets([secondFile.id])

        XCTAssertTrue(store.targets.isEmpty)
        XCTAssertTrue(store.pendingTargets.isEmpty)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testPartialApplyRetriesOnlyFailedTargetThroughProductionWritePath() async throws {
        let firstURL = try MetadataTestTokens.makeFixtureCopy()
        let secondURL = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock {
            MetadataTestTokens.removeFixtureCopy(at: firstURL)
            MetadataTestTokens.removeFixtureCopy(at: secondURL)
        }
        let firstTokens = try MetadataTestTokens.mintedTokens(at: firstURL)
        let secondTokens = try MetadataTestTokens.mintedTokens(at: secondURL)
        let firstID = UUID()
        let secondID = UUID()
        // Reviewed observations authorize the production raw apply route.
        let firstObserved = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            fileFingerprint: firstTokens.fingerprint,
            metadataFileVersion: firstTokens.version
        )
        let secondObserved = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            fileFingerprint: secondTokens.fingerprint,
            metadataFileVersion: secondTokens.version
        )
        // Display compatibility projections feed the store's raw-map load seam.
        let firstFile = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            includeDefaultFileFingerprint: false
        )
        let secondFile = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            includeDefaultFileFingerprint: false
        )
        let pipeline = RetryableMetadataEditorPipeline(
            propertyMapsByURL: [
                firstFile.url: firstObserved.metadataConflictBaseline?.values.compactMapValues(\.first) ?? [:],
                secondFile.url: secondObserved.metadataConflictBaseline?.values.compactMapValues(\.first) ?? [:]
            ],
            initiallyFailingURL: secondFile.url,
            fileVersionsByURL: [
                firstURL: firstTokens.version,
                secondURL: secondTokens.version
            ]
        )
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([firstFile, secondFile])

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)
        store.upsertField(key: "ALBUM", value: "Shared Draft")

        let observedTargets = [MetadataEditorTarget(file: firstObserved), MetadataEditorTarget(file: secondObserved)]
        let firstResult = await viewModel.applyRawMetadataPropertyMaps(
            store.draftPropertyMaps,
            to: observedTargets
        )
        store.recordAppliedTargets(firstResult.succeededTargetIDs)

        XCTAssertEqual(firstResult.succeededTargetIDs, [firstFile.id])
        XCTAssertEqual(firstResult.failedTargetIDs, [secondFile.id])
        XCTAssertFalse(firstResult.didApplyAllChanges)
        XCTAssertEqual(store.targets.map(\.id), [secondFile.id])
        XCTAssertEqual(store.pendingTargets.map(\.id), [secondFile.id])
        XCTAssertEqual(store.draftPropertyMaps[secondFile.id]?["ALBUM"], ["Shared Draft"])
        XCTAssertEqual(pipeline.writeAttemptCount(for: firstFile.url), 1)
        XCTAssertEqual(pipeline.writeAttemptCount(for: secondFile.url), 1)

        pipeline.allowWrites(to: secondFile.url)
        let retryTargets = observedTargets.filter { target in
            store.pendingTargets.contains { $0.id == target.id }
        }
        let retryResult = await viewModel.applyRawMetadataPropertyMaps(
            store.draftPropertyMaps,
            to: retryTargets
        )
        store.recordAppliedTargets(retryResult.succeededTargetIDs)

        XCTAssertTrue(retryResult.didApplyAllChanges)
        XCTAssertEqual(retryResult.succeededTargetIDs, [secondFile.id])
        XCTAssertTrue(store.targets.isEmpty)
        XCTAssertTrue(store.pendingTargets.isEmpty)
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertEqual(pipeline.writeAttemptCount(for: firstFile.url), 1)
        XCTAssertEqual(pipeline.writeAttemptCount(for: secondFile.url), 2)
        let retryPatch = try XCTUnwrap(pipeline.lastPatch(for: secondFile.url))
        XCTAssertEqual(retryPatch.valuesToSet, ["ALBUM": ["Shared Draft"]])
        XCTAssertTrue(retryPatch.removingKeys.isEmpty)
    }

    func testPresentFailsClosedWhenAnySelectedFileCannotBeRead() async throws {
        let readableFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/readable.mp3")
        ,
            includeDefaultFileFingerprint: false
        )
        let unreadableFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/unreadable.mp3")
        ,
            includeDefaultFileFingerprint: false
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(
                propertyMapsByURL: [readableFile.url: ["TITLE": "Keep Me"]],
                failuresByURL: [unreadableFile.url: MockMetadataEditorPipeline.MockError.unreadable]
            )
        )

        store.present(targetFiles: [readableFile, unreadableFile])
        try await waitUntilLoaded(store)
        store.upsertField(key: "ALBUM", value: "Must Not Apply")

        XCTAssertEqual(store.originalPropertyMaps[readableFile.id], ["TITLE": ["Keep Me"]])
        XCTAssertNil(store.originalPropertyMaps[unreadableFile.id])
        XCTAssertEqual(store.targets.map(\.id), [readableFile.id, unreadableFile.id])
        XCTAssertEqual(store.draftPropertyMaps, store.originalPropertyMaps)
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertEqual(
            store.loadErrorMessage,
            "Metadata couldn’t be read from “unreadable.mp3”.\nDetails: The metadata could not be read."
        )
    }

    private func waitUntilLoaded(
        _ store: MetadataEditorStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)

        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(store.isLoading, "Timed out waiting for metadata editor store to load", file: file, line: line)
    }
}

private final class MockMetadataEditorPipeline: AudioMetadataPipeline, @unchecked Sendable {
    enum MockError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The metadata could not be read."
            }
        }
    }

    private let propertyMapsByURL: [URL: [String: String]]
    private let failuresByURL: [URL: Error]

    init(
        propertyMapsByURL: [URL: [String: String]],
        failuresByURL: [URL: Error] = [:]
    ) {
        self.propertyMapsByURL = propertyMapsByURL
        self.failuresByURL = failuresByURL
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url,
            includeDefaultFileFingerprint: false
        )
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        if let failure = failuresByURL[url] {
            throw failure
        }

        return (propertyMapsByURL[url] ?? [:]).mapValues { [$0] }
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
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}

private final class RetryableMetadataEditorPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private enum WriteError: LocalizedError {
        case injectedFailure

        var errorDescription: String? { "Injected raw metadata write failure" }
    }

    private let lock = NSLock()
    private let propertyMapsByURL: [URL: [String: String]]
    private var failingURLs: Set<URL>
    private var writeAttemptsByURL: [URL: Int] = [:]
    private var recordedPatchesByURL: [URL: [RawMetadataPatch]] = [:]

    private let fileVersionsByURL: [URL: MetadataFileVersion]

    init(
        propertyMapsByURL: [URL: [String: String]],
        initiallyFailingURL: URL,
        fileVersionsByURL: [URL: MetadataFileVersion] = [:]
    ) {
        self.propertyMapsByURL = propertyMapsByURL
        self.failingURLs = [initiallyFailingURL]
        self.fileVersionsByURL = fileVersionsByURL
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        guard let version = lock.withLock({ fileVersionsByURL[url] }) else {
            throw CocoaError(.featureUnsupported)
        }
        return version
    }

    func allowWrites(to url: URL) {
        lock.withLock { _ = failingURLs.remove(url) }
    }

    func writeAttemptCount(for url: URL) -> Int {
        lock.withLock { writeAttemptsByURL[url, default: 0] }
    }

    func lastPatch(for url: URL) -> RawMetadataPatch? {
        lock.withLock { recordedPatchesByURL[url]?.last }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        (propertyMapsByURL[url] ?? [:]).mapValues { [$0] }
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
        let shouldFail = lock.withLock {
            writeAttemptsByURL[url, default: 0] += 1
            recordedPatchesByURL[url, default: []].append(patch)
            return failingURLs.contains(url)
        }
        if shouldFail {
            throw WriteError.injectedFailure
        }
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
