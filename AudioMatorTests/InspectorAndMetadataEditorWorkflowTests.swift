import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class InspectorAndMetadataEditorWorkflowTests: XCTestCase {
    func testInspectorSelectionSyncCreatesSingleAndMultiEditModels() {
        let firstID = UUID()
        let secondID = UUID()
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: URL(fileURLWithPath: "/tmp/01.mp3"),
            title: "First",
            album: "Shared Album"
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: URL(fileURLWithPath: "/tmp/02.mp3"),
            title: "Second",
            album: "Shared Album"
        )
        let viewModel = AudioViewModel(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles([first, second])

        viewModel.selectedAudioIDs = [firstID]
        viewModel.updateEditForSelection()

        XCTAssertEqual(viewModel.edit?.title, "First")
        XCTAssertNil(viewModel.multiEdit)
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)

        viewModel.edit?.title = "First Draft"
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        viewModel.selectedAudioIDs = [firstID, secondID]
        viewModel.updateEditForSelection()

        XCTAssertNil(viewModel.edit)
        XCTAssertEqual(viewModel.multiEdit?.text(for: .album), "Shared Album")
        XCTAssertEqual(viewModel.multiEdit?.text(for: .title), "")
        XCTAssertEqual(viewModel.multiEdit?.placeholder(for: .title), "Multiple Values")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)

        viewModel.multiEdit?.setText("Batch Album", for: .album)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        viewModel.cancelEditing()
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(viewModel.multiEdit?.text(for: .album), "Shared Album")
    }

    func testSaveInspectorEditsWritesSingleSelectionAndRefreshesEditModel() async throws {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/01.mp3")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let reloaded = AudioFileTestFactory.make(id: id, url: url, title: "Reloaded")
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
        viewModel.updateEditForSelection()
        viewModel.edit?.title = "Draft Title"

        viewModel.saveInspectorEdits()

        try await pipeline.waitForMetadataWriteCount(1)
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(pipeline.metadataWrites.first?.payload.title, "Draft Title")
        XCTAssertEqual(viewModel.files.first?.title, "Reloaded")
        XCTAssertEqual(viewModel.edit?.title, "Reloaded")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    func testSaveInspectorEditsAppliesOnlyModifiedMultiFileFieldsToEachFile() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First", album: "Old One")
        let second = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second", album: "Old Two")
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First", album: "Batch Album")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second", album: "Batch Album")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ]
        )
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.selectedAudioIDs = [firstID, secondID]
        viewModel.updateEditForSelection()
        viewModel.multiEdit?.setText("Batch Album", for: .album)

        viewModel.saveInspectorEdits()

        try await pipeline.waitForMetadataWriteCount(2)
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        let writesByURL = Dictionary(uniqueKeysWithValues: pipeline.metadataWrites.map { ($0.url, $0.payload) })
        XCTAssertEqual(writesByURL[firstURL]?.title, "First")
        XCTAssertEqual(writesByURL[firstURL]?.album, "Batch Album")
        XCTAssertEqual(writesByURL[secondURL]?.title, "Second")
        XCTAssertEqual(writesByURL[secondURL]?.album, "Batch Album")
        XCTAssertEqual(viewModel.files.map(\.album), ["Batch Album", "Batch Album"])
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    func testMetadataEditorRawMapApplyWritesEachTargetAndRefreshesLoadedFiles() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First")
        let second = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second")
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "Raw First")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Raw Second")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ]
        )
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.selectedAudioIDs = [firstID]
        viewModel.updateEditForSelection()

        await viewModel.applyRawMetadataPropertyMaps(
            [
                firstID: ["TITLE": "Raw First", "CUSTOM": "One"],
                secondID: ["TITLE": "Raw Second"]
            ],
            to: [
                MetadataEditorTarget(file: first),
                MetadataEditorTarget(file: second)
            ]
        )

        XCTAssertEqual(pipeline.rawMapWrites[firstURL], ["TITLE": "Raw First", "CUSTOM": "One"])
        XCTAssertEqual(pipeline.rawMapWrites[secondURL], ["TITLE": "Raw Second"])
        XCTAssertEqual(viewModel.files.map(\.title), ["Raw First", "Raw Second"])
        XCTAssertEqual(viewModel.edit?.title, "Raw First")
    }

    private func waitUntil(
        _ condition: @autoclosure @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }
}

private final class RecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct MetadataWrite: Sendable {
        let payload: MetadataEditPayload
        let url: URL
    }

    private let lock = NSLock()
    private let reloadedFilesByURL: [URL: AudioFile]
    private(set) var metadataWrites: [MetadataWrite] = []
    private(set) var rawMapWrites: [URL: [String: String]] = [:]

    init(reloadedFilesByURL: [URL: AudioFile] = [:]) {
        self.reloadedFilesByURL = reloadedFilesByURL
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let file = reloadedFilesByURL[url] {
            return file
        }

        return await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        [:]
    }

    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        lock.withLock {
            metadataWrites.append(MetadataWrite(payload: edit, url: url))
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        lock.withLock {
            rawMapWrites[url] = propertyMap
        }
        return AudioMetadataWriteResult(warnings: [])
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

    func waitForMetadataWriteCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)

        while Date() < deadline {
            if lock.withLock({ metadataWrites.count >= expectedCount }) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for \(expectedCount) metadata writes", file: file, line: line)
    }
}
#endif
