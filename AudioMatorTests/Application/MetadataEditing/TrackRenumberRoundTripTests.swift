import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

#if os(macOS)
/// Real TagLib round trips through the reviewed renumber route.
///
/// The wrapper forwards every read and write to `TagLibAudioMetadataPipeline`;
/// it only declines the interactive folder grant so an app-hosted test never
/// presents a modal panel. All persistence assertions read back independently
/// through the unwrapped pipeline.
nonisolated final class TrackRenumberRoundTripTests: XCTestCase {
    private struct RoundTripFixture {
        let file: AudioFile
        let url: URL
    }

    @MainActor
    private func temporaryAudioCopy(_ fileExtension: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(
            bundle.url(forResource: "testAudioFile", withExtension: fileExtension, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: "testAudioFile", withExtension: fileExtension)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackRenumberRoundTrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("round-trip.\(fileExtension)")
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    /// Baseline: positive track 3/12, disc pair 2/3, unrelated tags present.
    @MainActor
    private func makeRoundTripFixture(_ fileExtension: String) async throws -> RoundTripFixture {
        let url = try temporaryAudioCopy(fileExtension)
        let pipeline = TagLibAudioMetadataPipeline()
        _ = try pipeline.eraseAllMetadata(at: url, expectedVersion: nil)
        let loaded = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: loaded)
        edit.title = "Keep Title"
        edit.artist = "Keep Artist"
        edit.album = "Keep Album"
        edit.setTrackNumberText("3/12")
        edit.setDiscNumberText("2/3")
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: loaded),
            to: url,
            expectedVersion: loaded.metadataFileVersion
        )
        let reviewed = try await pipeline.loadAudioFile(at: url, id: UUID())
        return RoundTripFixture(file: reviewed, url: url)
    }

    @MainActor
    func testRealFLACMP3M4ARoundTripsPreservePairAndUnrelatedTags() async throws {
        for fileExtension in ["flac", "mp3", "m4a"] {
            let fixture = try await makeRoundTripFixture(fileExtension)
            let pipeline = RoundTripRenumberPipeline()
            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
            viewModel.mergeQuickImportFiles([fixture.file])
            let plan = viewModel.makeTrackRenumberPlan(
                orderedFiles: [fixture.file],
                selectedIDs: [],
                direction: .ascending,
                startNumberText: "7"
            )

            XCTAssertEqual(plan.executableCount, 1, fileExtension)
            XCTAssertEqual(plan.rows.first?.assignedNumber, 7, fileExtension)

            let result = await viewModel.renumberTrackNumbers(using: plan)

            XCTAssertEqual(result.succeeded, 1, fileExtension)
            XCTAssertEqual(result.failed, 0, fileExtension)
            XCTAssertEqual(pipeline.reviewedWriteCount, 1, fileExtension)

            let readback = try await TagLibAudioMetadataPipeline().loadAudioFile(
                at: fixture.url,
                id: fixture.file.id
            )
            XCTAssertEqual(readback.track, 7, fileExtension)
            XCTAssertEqual(readback.trackTotal, 12, fileExtension)
            XCTAssertEqual(readback.disc, 2, fileExtension)
            XCTAssertEqual(readback.discTotal, 3, fileExtension)
            XCTAssertEqual(readback.title, "Keep Title", fileExtension)
            XCTAssertEqual(readback.artist, "Keep Artist", fileExtension)
            XCTAssertEqual(readback.album, "Keep Album", fileExtension)
        }
    }

    @MainActor
    func testPaddedRawTextIsPreservedWhenNumericValueIsAlreadyDesired() async throws {
        let url = try temporaryAudioCopy("flac")
        let pipeline = TagLibAudioMetadataPipeline()
        _ = try pipeline.eraseAllMetadata(at: url, expectedVersion: nil)
        _ = try pipeline.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: [
                "TRACKNUMBER": ["007"],
                "TRACKTOTAL": ["12"],
                "TITLE": ["Keep Title"],
            ]),
            to: url,
            expectedVersion: nil
        )
        let reviewed = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(reviewed.track, 7, "The padded raw text must project to the numeric value 7.")
        XCTAssertEqual(reviewed.trackTotal, 12)

        let beforeBytes = try Data(contentsOf: url)
        let beforeRawMap = try pipeline.rawMetadataValueMap(for: url)
        let wrapper = RoundTripRenumberPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: wrapper)
        viewModel.mergeQuickImportFiles([reviewed])
        let plan = viewModel.makeTrackRenumberPlan(
            orderedFiles: [reviewed],
            selectedIDs: [],
            direction: .ascending,
            startNumberText: "7"
        )

        XCTAssertEqual(plan.unchangedCount, 1)
        XCTAssertEqual(plan.executableCount, 0)
        XCTAssertEqual(plan.rows.first?.assignedNumber, 7)

        let result = await viewModel.renumberTrackNumbers(using: plan)

        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(result.unchanged, 1)
        XCTAssertEqual(wrapper.reviewedWriteCount, 0, "No operation reaches the writer for an already desired number.")
        XCTAssertEqual(try Data(contentsOf: url), beforeBytes)
        XCTAssertEqual(try pipeline.rawMetadataValueMap(for: url), beforeRawMap)
        XCTAssertEqual(try pipeline.rawMetadataValueMap(for: url)["TRACKNUMBER"], ["007"])
    }

    @MainActor
    func testZeroAndBlankStartLeavePositiveTagUnchanged() async throws {
        let fixture = try await makeRoundTripFixture("flac")
        let beforeBytes = try Data(contentsOf: fixture.url)
        let wrapper = RoundTripRenumberPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: wrapper)
        viewModel.mergeQuickImportFiles([fixture.file])

        for startText in ["0", "", "10000"] {
            let plan = viewModel.makeTrackRenumberPlan(
                orderedFiles: [fixture.file],
                selectedIDs: [],
                direction: .ascending,
                startNumberText: startText
            )
            XCTAssertFalse(plan.isStartValid, startText)
            _ = await viewModel.renumberTrackNumbers(using: plan)
        }

        XCTAssertEqual(wrapper.reviewedWriteCount, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.url), beforeBytes)
        let readback = try await TagLibAudioMetadataPipeline().loadAudioFile(
            at: fixture.url,
            id: fixture.file.id
        )
        XCTAssertEqual(readback.track, 3, "An existing positive tag must remain unchanged.")
    }
}

/// Forwards every operation to the real pipeline; only the interactive folder
/// grant is declined so the test never presents a modal panel.
private nonisolated struct RoundTripRenumberPipeline: AudioMetadataPipeline, Sendable {
    private let base = TagLibAudioMetadataPipeline()
    private let counter = RoundTripWriteCounter()

    nonisolated var reviewedWriteCount: Int { counter.value }

    nonisolated var requiresTransactionalDirectoryAccess: Bool { false }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        try await base.loadAudioFile(at: url, id: id)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        base.rawMetadataDumpText(for: url)
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try base.rawMetadataValueMap(for: url)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try base.projectMetadataWrite(intent, fileExtension: fileExtension)
    }

    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        counter.increment()
        return try base.writeReviewedMetadata(edit, to: url, expectedVersion: expectedVersion)
    }
}

private nonisolated final class RoundTripWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
#endif
