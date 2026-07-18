import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class TrackRenumberExecutionTests: XCTestCase {
    func testRenumberVerifiesWriteAndRefreshesModelFromDiskReadback() async throws {
        let fileID = UUID()
        let fileURL = URL(fileURLWithPath: "/tmp/AudioMatorRenumberExecution.mp3")
        let original = AudioFileTestFactory.make(
            id: fileID,
            url: fileURL,
            track: 1,
            trackNumberText: "01",
            includeDefaultFileFingerprint: false
        )
        let diskReadback = AudioFileTestFactory.make(
            id: fileID,
            url: fileURL,
            track: 7,
            trackNumberText: "7"
        )
        let pipeline = RenumberRecordingMetadataPipeline(diskReadback: diskReadback)
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let result = await viewModel.renumberTrackNumbers(
            orderedIDs: [fileID],
            selectedIDs: [],
            options: TrackRenumberOptions(
                direction: .ascending,
                startNumber: 7,
                padWithZeros: true
            )
        )

        XCTAssertEqual(pipeline.verifyAfterWriteValues, [true])
        XCTAssertEqual(viewModel.files.first?.trackNumberText, "7")
        XCTAssertEqual(result.warnings.first?.messages, ["Synthetic verification warning"])
    }

    func testRenumberRejectsFileChangedSinceSelection() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenumberFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("changed.mp3")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try Data(repeating: 0x41, count: 16).write(to: fileURL)
        let file = AudioFileTestFactory.make(
            url: fileURL,
            track: 1,
            trackNumberText: "01",
            fileFingerprint: try AudioFileFingerprint.capture(at: fileURL)
        )
        let pipeline = RenumberRecordingMetadataPipeline(diskReadback: file)
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        let result = await viewModel.renumberTrackNumbers(
            orderedIDs: [file.id],
            selectedIDs: [],
            options: TrackRenumberOptions(startNumber: 7)
        )

        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertTrue(result.failures.first?.reason.contains("changed after the preview") == true)
        XCTAssertTrue(
            pipeline.verifyAfterWriteValues.isEmpty,
            "Track renumbering must not write when its loaded file fingerprint is stale."
        )
    }
}

private final class RenumberRecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private let diskReadback: AudioFile
    private var recordedVerifyAfterWriteValues: [Bool] = []

    init(diskReadback: AudioFile) {
        self.diskReadback = diskReadback
    }

    var verifyAfterWriteValues: [Bool] {
        lock.withLock { recordedVerifyAfterWriteValues }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        diskReadback
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }
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
        lock.withLock { recordedVerifyAfterWriteValues.append(verifyAfterWrite) }
        return AudioMetadataWriteResult(warnings: ["Synthetic verification warning"])
    }
}
#endif
