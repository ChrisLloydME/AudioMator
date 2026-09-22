import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

@MainActor
final class RenameRefreshSafetyTests: XCTestCase {
    func testFailedRenameRefreshDisablesMetadataWritesWhenRevisionCannotBeRecovered() async {
        let id = UUID()
        let original = AudioFileTestFactory.make(
            id: id,
            url: URL(fileURLWithPath: "/tmp/original.mp3")
        )
        let pipeline = RenameRefreshFailurePipeline(recoveredVersion: nil)
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let warnings = await viewModel.applyMovedFiles([
            (id: id, newURL: URL(fileURLWithPath: "/tmp/missing-renamed.mp3"))
        ])

        let moved = try! XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertTrue(warnings.first?.contains("editing is disabled") == true)

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Must not write"
        let result = await viewModel.persistMetadataEdit(edit, to: moved)

        guard case .failure(let reason) = result else {
            return XCTFail("Expected a refresh-required failure")
        }
        XCTAssertTrue(reason.contains("Reload the file"))
        XCTAssertEqual(pipeline.writeCount, 0)
    }

    func testFailedFullRefreshRetainsWriteSafetyWhenLightweightRevisionRecovers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameRefresh-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent("renamed.mp3")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("renamed payload".utf8).write(to: destination)
        defer { try? FileManager.default.removeItem(at: directory) }

        let version = try TagLibMetadataManager.fileVersion(at: destination)
        let id = UUID()
        let original = AudioFileTestFactory.make(
            id: id,
            url: directory.appendingPathComponent("original.mp3")
        )
        let pipeline = RenameRefreshFailurePipeline(recoveredVersion: version)
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let warnings = await viewModel.applyMovedFiles([(id: id, newURL: destination)])

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(moved.fileFingerprint)
        XCTAssertEqual(moved.metadataFileVersion, version)
        XCTAssertTrue(warnings.first?.contains("recovered its safety revision") == true)
    }
}

private final class RenameRefreshFailurePipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let recoveredVersion: MetadataFileVersion?
    private let lock = NSLock()
    private var recordedWriteCount = 0

    init(recoveredVersion: MetadataFileVersion?) {
        self.recoveredVersion = recoveredVersion
    }

    var writeCount: Int {
        lock.withLock { recordedWriteCount }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        throw CocoaError(.fileReadCorruptFile)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        guard let recoveredVersion else { throw CocoaError(.fileReadUnknown) }
        return recoveredVersion
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock { recordedWriteCount += 1 }
        return AudioMetadataWriteResult(warnings: [])
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
        AudioMetadataWriteResult(warnings: [])
    }
}
