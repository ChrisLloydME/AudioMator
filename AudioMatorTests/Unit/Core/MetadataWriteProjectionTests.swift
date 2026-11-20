import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class MetadataWriteProjectionTests: XCTestCase {
    // MARK: - Deterministic plan-time projection

    @MainActor
    func testSemanticProjectionMatchesDeterministicEncoderForComponentOperation() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/projection-components.mp3"),
            track: 3,
            trackTotal: 12,
            trackNumberText: "3/12"
        )
        var edit = SingleFileEditModel(from: file)
        edit.setTrackNumberText("7/12")
        let payload = MetadataEditPayload(edit, comparedTo: file)

        let patch = try TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload)
        let projection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .semantic(payload),
            fileExtension: "mp3"
        )

        XCTAssertEqual(projection.validation, .executable)
        XCTAssertEqual(projection.requestedFields, payload.requestedFields)
        XCTAssertEqual(projection.unsupportedFields, [])
        XCTAssertEqual(
            projection.componentOperations,
            [MetadataNumberComponentOperation(field: .track, value: 7)]
        )
        // Projection and commit share one encoder; the effective set must equal
        // exactly what the commit patch will submit.
        XCTAssertEqual(projection.effectiveFields, Set(patch.fields.keys))
        XCTAssertEqual(projection.effectiveFields, [.track])
        XCTAssertFalse(projection.isNoOp)
    }

    @MainActor
    func testSemanticProjectionReportsEncoderDerivedNoOp() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/projection-noop.mp3"),
            title: "Same",
            track: 3,
            trackTotal: 12,
            trackNumberText: "3/12"
        )
        let edit = SingleFileEditModel(from: file)
        let payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertTrue(payload.requestedFields.isEmpty)

        let projection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .semantic(payload),
            fileExtension: "mp3"
        )

        XCTAssertEqual(projection.validation, .executable)
        XCTAssertTrue(projection.isNoOp)
        XCTAssertTrue(projection.effectiveFields.isEmpty)
        XCTAssertTrue(projection.componentOperations.isEmpty)
        XCTAssertTrue(try TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields.isEmpty)
    }

    @MainActor
    func testSemanticProjectionRejectsInvalidNumberText() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/projection-invalid.mp3"),
            track: 3,
            trackTotal: 12,
            trackNumberText: "3/12"
        )
        var edit = SingleFileEditModel(from: file)
        edit.setTrackNumberText("A1/12")
        let payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertNotNil(payload.numberPairValidationMessage)

        let projection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .semantic(payload),
            fileExtension: "mp3"
        )

        guard case .rejected(let message) = projection.validation else {
            return XCTFail("Invalid number text must be rejected by the projection")
        }
        XCTAssertEqual(message, payload.numberPairValidationMessage)
        XCTAssertFalse(projection.isExecutable)
        XCTAssertFalse(projection.isNoOp)
    }

    // MARK: - Fail-closed capability classification

    @MainActor
    func testProjectionFailsClosedWhenCapabilityInformationIsMissing() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/projection-unknown.dat"),
            title: "Original"
        )
        var edit = SingleFileEditModel(from: file)
        edit.title = "Changed"
        let payload = MetadataEditPayload(edit, comparedTo: file)
        let requested = payload.requestedFields
        XCTAssertEqual(requested, [.title])

        let projection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .semantic(payload),
            fileExtension: "no-such-audio-format"
        )

        XCTAssertEqual(projection.validation, .unsupported(requested))
        XCTAssertEqual(projection.unsupportedFields, requested)
        XCTAssertFalse(projection.isExecutable)
        XCTAssertTrue(projection.effectiveFields.isEmpty)
    }

    @MainActor
    func testProjectionReportsUnsupportedFieldOnKnownRestrictedFormat() throws {
        let file = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/projection-restricted.xm"),
            title: "Allowed title",
            artist: "Original artist"
        )
        var edit = SingleFileEditModel(from: file)
        edit.artist = "Unsupported artist change"
        let payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.requestedFields, [.artist])

        let projection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .semantic(payload),
            fileExtension: "xm"
        )

        XCTAssertEqual(projection.validation, .unsupported([.artist]))
        XCTAssertEqual(projection.unsupportedFields, [.artist])
        XCTAssertTrue(projection.effectiveFields.isEmpty)
    }

    @MainActor
    func testWritePreflightTreatsMissingCapabilityAsAllRequestedUnsupported() {
        let requested: Set<MetadataFieldKey> = [.title, .artist]
        XCTAssertEqual(
            unsupportedMetadataWriteFields(requested, forFileExtension: "no-such-audio-format"),
            requested
        )
        // An empty request is a no-op regardless of capability information.
        XCTAssertEqual(
            unsupportedMetadataWriteFields([], forFileExtension: "no-such-audio-format"),
            []
        )

        guard let writableFields = AudioFormatSupport.writableMetadataFields(for: "mp3"),
              let supportedField = writableFields.first else {
            return XCTFail("Expected concrete MP3 capability information")
        }
        XCTAssertTrue(unsupportedMetadataWriteFields([supportedField], forFileExtension: "mp3").isEmpty)
    }

    @MainActor
    func testRawAndEraseProjectionClassification() throws {
        let rawPatch = RawMetadataPatch(valuesToSet: ["TITLE": ["Raw title"]])
        let rawProjection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .raw(rawPatch),
            fileExtension: "mp3"
        )
        XCTAssertEqual(rawProjection.validation, .executable)
        XCTAssertFalse(rawProjection.isNoOp)

        let emptyRawProjection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .raw(RawMetadataPatch()),
            fileExtension: "mp3"
        )
        XCTAssertEqual(emptyRawProjection.validation, .executable)
        XCTAssertTrue(emptyRawProjection.isNoOp)

        let unknownRawProjection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .raw(rawPatch),
            fileExtension: "no-such-audio-format"
        )
        XCTAssertFalse(unknownRawProjection.isExecutable)

        let eraseProjection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .eraseAll,
            fileExtension: "mp3"
        )
        XCTAssertEqual(eraseProjection.validation, .executable)

        let unknownEraseProjection = try TagLibAudioMetadataPipeline().projectMetadataWrite(
            .eraseAll,
            fileExtension: "no-such-audio-format"
        )
        XCTAssertFalse(unknownEraseProjection.isExecutable)
    }

    // MARK: - Strict adapter writes forward the captured revision

    @MainActor
    func testStrictReviewedSemanticWriteForwardsCapturedRevisionAndRejectsStaleToken() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy()
        defer { MetadataTestTokens.removeFixtureCopy(at: url) }

        let (file, target) = try await MetadataTestTokens.makeReviewedTarget(at: url)
        var edit = SingleFileEditModel(from: file)
        edit.title = "Reviewed title"
        let payload = MetadataEditPayload(edit, comparedTo: file)

        let adapter = TagLibAudioMetadataPipeline()
        let projection = try adapter.projectMetadataWrite(.semantic(payload), fileExtension: "flac")
        XCTAssertEqual(projection.validation, .executable)
        XCTAssertEqual(projection.effectiveFields, [.title])

        _ = try adapter.writeReviewedMetadata(
            payload,
            to: target.url,
            expectedVersion: target.version
        )

        let reloaded = try await MetadataTestTokens.makeVerifiedAudioFile(at: url, id: file.id)
        XCTAssertEqual(reloaded.title, "Reviewed title")

        // The captured token no longer matches disk; the strict write must be
        // rejected and must leave the committed bytes unchanged.
        let committedBytes = try Data(contentsOf: url)
        XCTAssertThrowsError(
            try adapter.writeReviewedMetadata(
                payload,
                to: target.url,
                expectedVersion: target.version
            )
        )
        XCTAssertEqual(try Data(contentsOf: url), committedBytes)
    }

    @MainActor
    func testStrictReviewedRawWriteForwardsCapturedRevision() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy()
        defer { MetadataTestTokens.removeFixtureCopy(at: url) }

        let (_, target) = try await MetadataTestTokens.makeReviewedTarget(at: url)
        let adapter = TagLibAudioMetadataPipeline()
        let patch = RawMetadataPatch(valuesToSet: ["TITLE": ["Raw reviewed title"]])

        _ = try adapter.writeReviewedRawPatch(
            patch,
            to: target.url,
            expectedVersion: target.version
        )

        let values = try adapter.rawMetadataValueMap(for: url)
        XCTAssertEqual(values["TITLE"], ["Raw reviewed title"])

        XCTAssertThrowsError(
            try adapter.writeReviewedRawPatch(
                RawMetadataPatch(valuesToSet: ["TITLE": ["Stale write"]]),
                to: target.url,
                expectedVersion: target.version
            )
        )
        XCTAssertEqual(try adapter.rawMetadataValueMap(for: url)["TITLE"], ["Raw reviewed title"])
    }

    @MainActor
    func testStrictReviewedEraseForwardsCapturedRevision() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy()
        defer { MetadataTestTokens.removeFixtureCopy(at: url) }

        let (file, initialTarget) = try await MetadataTestTokens.makeReviewedTarget(at: url)
        let adapter = TagLibAudioMetadataPipeline()

        // Seed known tags through the strict raw path so the erase assertion is
        // meaningful for the committed fixture.
        _ = try adapter.writeReviewedRawPatch(
            RawMetadataPatch(valuesToSet: ["TITLE": ["Erase me"], "ARTIST": ["Erase me too"]]),
            to: initialTarget.url,
            expectedVersion: initialTarget.version
        )
        let (seededFile, seededTarget) = try await MetadataTestTokens.makeReviewedTarget(at: url)
        XCTAssertEqual(seededFile.title, "Erase me")

        _ = try adapter.eraseAllMetadataReviewed(at: seededTarget.url, expectedVersion: seededTarget.version)

        let cleared = try await MetadataTestTokens.makeVerifiedAudioFile(at: url, id: file.id)
        XCTAssertTrue(cleared.title.isEmpty)
        XCTAssertTrue(cleared.artist.isEmpty)

        XCTAssertThrowsError(
            try adapter.eraseAllMetadataReviewed(at: seededTarget.url, expectedVersion: seededTarget.version)
        )
    }
}
