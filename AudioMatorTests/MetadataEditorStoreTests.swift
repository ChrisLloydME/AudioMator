import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class MetadataEditorStoreTests: XCTestCase {
    func testPresentLoadsDraftMapsAndSelectsFirstField() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstFile = AudioFileTestFactory.make(
            id: firstID,
            url: URL(fileURLWithPath: "/tmp/01 - First.mp3")
        )
        let secondFile = AudioFileTestFactory.make(
            id: secondID,
            url: URL(fileURLWithPath: "/tmp/02 - Second.mp3")
        )
        let pipeline = MockMetadataEditorPipeline(propertyMapsByURL: [
            firstFile.url: ["TITLE": "First", "ALBUM": "Shared Album"],
            secondFile.url: ["TITLE": "Second", "ALBUM": "Shared Album"]
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)

        XCTAssertEqual(store.targets.map(\.id), [firstID, secondID])
        XCTAssertEqual(store.originalPropertyMaps[firstID], ["TITLE": "First", "ALBUM": "Shared Album"])
        XCTAssertEqual(store.draftPropertyMaps[secondID], ["TITLE": "Second", "ALBUM": "Shared Album"])
        XCTAssertEqual(store.selectedFieldKey, "ALBUM")
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertNil(store.loadErrorMessage)
        XCTAssertEqual(store.selectionSummaryText, "2 selected files")
    }

    func testUpsertFieldTrimsValueAndAppliesToEveryTarget() async throws {
        let firstFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"))
        let secondFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.mp3"))
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [
                firstFile.url: ["TITLE": "First"],
                secondFile.url: ["TITLE": "Second"]
            ])
        )

        store.present(targetFiles: [firstFile, secondFile])
        try await waitUntilLoaded(store)
        store.upsertField(key: " CUSTOMFIELD ", value: "  Shared Value\n")

        XCTAssertEqual(store.draftPropertyMaps[firstFile.id]?["CUSTOMFIELD"], "Shared Value")
        XCTAssertEqual(store.draftPropertyMaps[secondFile.id]?["CUSTOMFIELD"], "Shared Value")
        XCTAssertEqual(store.selectedFieldKey, "CUSTOMFIELD")
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testUpsertFieldIgnoresEmptyKeysAndValues() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"))
        let initialMap = ["TITLE": "Original"]
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [file.url: initialMap])
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.upsertField(key: "   ", value: "Ignored")
        store.upsertField(key: "CUSTOMFIELD", value: " \n ")

        XCTAssertEqual(store.draftPropertyMaps[file.id], initialMap)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testDeleteSelectedFieldRemovesFieldFromEveryTargetAndRealignsSelection() async throws {
        let firstFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"))
        let secondFile = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/02.mp3"))
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

    func testDiscardChangesRestoresOriginalMaps() async throws {
        let file = AudioFileTestFactory.make(id: UUID(), url: URL(fileURLWithPath: "/tmp/01.mp3"))
        let originalMap = ["TITLE": "Original"]
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(propertyMapsByURL: [file.url: originalMap])
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.upsertField(key: "CUSTOMFIELD", value: "Draft")
        XCTAssertTrue(store.hasUnsavedChanges)

        store.discardChanges()

        XCTAssertEqual(store.draftPropertyMaps[file.id], originalMap)
        XCTAssertEqual(store.selectedFieldKey, "TITLE")
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testPresentKeepsEmptyMapAndReportsLoadFailure() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/unreadable.mp3")
        )
        let store = MetadataEditorStore(
            metadataPipeline: MockMetadataEditorPipeline(
                propertyMapsByURL: [:],
                failuresByURL: [file.url: MockMetadataEditorPipeline.MockError.unreadable]
            )
        )

        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)

        XCTAssertEqual(store.originalPropertyMaps[file.id], [:])
        XCTAssertEqual(store.draftPropertyMaps[file.id], [:])
        XCTAssertNil(store.selectedFieldKey)
        XCTAssertNotNil(store.loadErrorMessage)
        XCTAssertTrue(store.loadErrorMessage?.contains("unreadable.mp3") == true)
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
        AudioFileTestFactory.make(id: id, url: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        if let failure = failuresByURL[url] {
            throw failure
        }

        return propertyMapsByURL[url] ?? [:]
    }

    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
#endif
