import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
@MainActor
final class TrackRenumberExecutionTests: XCTestCase {
    func testRefreshRequiredTargetsDoNotConsumeNumbersAtFirstOrMiddlePosition() async {
        for blockedIndex in [0, 1] {
            let files = (0..<3).map { index in
                AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/eligible-\(index).flac"),
                                          includeDefaultFileFingerprint: false)
            }
            let pipeline = RenumberRecordingMetadataPipeline(diskReadback: files[0])
            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
            viewModel.mergeQuickImportFiles(files)
            viewModel.markFileRequiresRefresh(id: files[blockedIndex].id)
            let result = await viewModel.renumberTrackNumbers(orderedIDs: files.map(\.id), selectedIDs: [],
                options: TrackRenumberOptions(startNumber: 1, padWithZeros: true))
            XCTAssertEqual(result.totalTargets, 3)
            XCTAssertEqual(result.succeeded, 2)
            XCTAssertEqual(result.failed, 1)
            XCTAssertEqual(result.skippedUnsupported, 0)
            XCTAssertEqual(pipeline.trackNumberTextValues, ["01", "02"])
        }
    }

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
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
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
        XCTAssertEqual(pipeline.trackNumberTextValues, ["07"])
        XCTAssertEqual(viewModel.files.first?.trackNumberText, "7")
        XCTAssertEqual(result.warnings.first?.messages, ["Synthetic verification warning"])
    }

    func testRenumberReportsCommittedDurabilityUncertaintyWithoutRetrying() async {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/renumber-durability.mp3"),
            includeDefaultFileFingerprint: false)
        let pipeline = RenumberRecordingMetadataPipeline(diskReadback: file,
            commitStatus: .durabilityUncertain("Injected directory sync failure"))
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        let result = await viewModel.renumberTrackNumbers(orderedIDs: [file.id], selectedIDs: [],
            options: TrackRenumberOptions(startNumber: 7, padWithZeros: false))
        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(pipeline.trackNumberTextValues, ["7"])
        XCTAssertTrue(result.warnings.flatMap(\.messages).contains {
            $0.contains("Do not retry") && $0.contains("Injected directory sync failure")
        })
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
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
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

    func testRenumberSkipsWritableFormatWithoutTrackCapability() async {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/restricted-track.xm"),
            track: 1,
            trackNumberText: "01",
            includeDefaultFileFingerprint: false
        )
        let pipeline = RenumberRecordingMetadataPipeline(diskReadback: file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        let result = await viewModel.renumberTrackNumbers(
            orderedIDs: [file.id],
            selectedIDs: [],
            options: TrackRenumberOptions(startNumber: 7)
        )

        XCTAssertEqual(result.skippedUnsupported, 1)
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertTrue(pipeline.verifyAfterWriteValues.isEmpty)
    }

    func testRenumberDoesNotConsumeNumbersForSkippedTargets() async {
        let first = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/renumber-first.mp3"),
            track: 1,
            trackNumberText: "01",
            includeDefaultFileFingerprint: false
        )
        let skipped = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/renumber-skipped.xm"),
            track: 2,
            trackNumberText: "02",
            includeDefaultFileFingerprint: false
        )
        let last = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/renumber-last.flac"),
            track: 3,
            trackNumberText: "03",
            includeDefaultFileFingerprint: false
        )
        let pipeline = RenumberRecordingMetadataPipeline(diskReadback: first)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, skipped, last])

        let result = await viewModel.renumberTrackNumbers(
            orderedIDs: [first.id, skipped.id, last.id],
            selectedIDs: [],
            options: TrackRenumberOptions(startNumber: 1, padWithZeros: true)
        )

        XCTAssertEqual(result.totalTargets, 3)
        XCTAssertEqual(result.skippedUnsupported, 1)
        XCTAssertEqual(result.succeeded, 2)
        XCTAssertEqual(pipeline.trackNumberTextValues, ["01", "02"])
    }
}

private final class RenumberRecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private let diskReadback: AudioFile
    private let commitStatus: AudioMetadataCommitStatus
    private var recordedVerifyAfterWriteValues: [Bool] = []
    private var recordedTrackNumberTexts: [String] = []

    init(diskReadback: AudioFile, commitStatus: AudioMetadataCommitStatus = .durable) {
        self.diskReadback = diskReadback
        self.commitStatus = commitStatus
    }

    var verifyAfterWriteValues: [Bool] {
        lock.withLock { recordedVerifyAfterWriteValues }
    }

    var trackNumberTextValues: [String] {
        lock.withLock { recordedTrackNumberTexts }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        diskReadback
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }
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
    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            recordedVerifyAfterWriteValues.append(verifyAfterWrite)
            recordedTrackNumberTexts.append(trackNumberText)
        }
        return AudioMetadataWriteResult(warnings: ["Synthetic verification warning"], commitStatus: commitStatus)
    }
}
#endif
