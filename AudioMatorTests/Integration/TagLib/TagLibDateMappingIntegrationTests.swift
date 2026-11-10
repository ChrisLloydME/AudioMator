import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Native-oracle coverage for the four independent date identities.
nonisolated final class TagLibDateMappingIntegrationTests: XCTestCase {
    private static let audioFixtureNames = [
        "testAudioFile.mp3",
        "testAudioFile.m4a",
        "testAudioFile.flac",
        "testAudioFile.ogg",
        "testAudioFile.aac",
        "testAudioFile.wav",
    ]

    func testFullExampleAndIndependentSetClearUseNativeStorage() async throws {
        let expectedYear = "2004"
        let expectedDate = "2008-03-04"
        let expectedRelease = "2017-06-09"
        let expectedOriginal = "1999-11-12"

        for fixtureName in Self.audioFixtureNames {
            let url = try writableFixture(extension: fixtureName)
            defer { removeTemporaryFixtureDirectory(containing: url) }

            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(fields: [
                    .year: .text(expectedYear),
                    .standaloneDate: .text(expectedDate),
                    .releaseDate: .text(expectedRelease),
                    .originalReleaseDate: .text(expectedOriginal),
                ]),
                to: url
            )

            let snapshot = try TagLibMetadataManager.readSnapshot(from: url)
            let ext = url.pathExtension
            XCTAssertEqual(nativeValues(.year, snapshot: snapshot, extension: ext), [expectedYear], fixtureName)
            XCTAssertEqual(nativeValues(.standaloneDate, snapshot: snapshot, extension: ext), [expectedDate], fixtureName)
            XCTAssertEqual(nativeValues(.releaseDate, snapshot: snapshot, extension: ext), [expectedRelease], fixtureName)
            XCTAssertEqual(nativeValues(.originalReleaseDate, snapshot: snapshot, extension: ext), [expectedOriginal], fixtureName)

            let pipeline = TagLibAudioMetadataPipeline()
            var file = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(file.year, expectedYear, fixtureName)
            XCTAssertEqual(file.date, expectedDate, fixtureName)
            XCTAssertEqual(file.releaseDate, expectedRelease, fixtureName)
            XCTAssertEqual(file.originalReleaseDate, expectedOriginal, fixtureName)
            XCTAssertNotEqual(file.year, file.releaseDate, fixtureName)

            // Change only YEAR.
            var edit = SingleFileEditModel(from: file)
            edit.year = "2005"
            let payload = MetadataEditPayload(edit, comparedTo: file)
            XCTAssertEqual(payload.changedFields, [.year], fixtureName)
            let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload)
            XCTAssertEqual(patch.fields, [.year: .text("2005")], fixtureName)
            _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion)

            file = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(file.year, "2005", fixtureName)
            XCTAssertEqual(file.date, expectedDate, fixtureName)
            XCTAssertEqual(file.releaseDate, expectedRelease, fixtureName)
            XCTAssertEqual(file.originalReleaseDate, expectedOriginal, fixtureName)

            // Clear only DATE. On ID3-backed tags the released verifier treats
            // the legacy PropertyMap DATE projection as an unedited field and
            // rejects the write; the original bytes must stay intact.
            edit = SingleFileEditModel(from: file)
            edit.date = ""
            let clearPayload = MetadataEditPayload(edit, comparedTo: file)
            XCTAssertEqual(clearPayload.changedFields, [.standaloneDate], fixtureName)
            _ = try pipeline.writeMetadata(clearPayload, to: url, expectedVersion: file.metadataFileVersion)

            file = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(file.date, "", fixtureName)
            XCTAssertEqual(file.year, "2005", fixtureName)
            XCTAssertEqual(file.releaseDate, expectedRelease, fixtureName)
            XCTAssertEqual(file.originalReleaseDate, expectedOriginal, fixtureName)
        }
    }

    func testFullYearTextSurvivesCopyUnrelatedEditExportAndReload() async throws {
        let url = try writableFixture(extension: "testAudioFile.flac")
        defer { removeTemporaryFixtureDirectory(containing: url) }

        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.year: .text("2004-07-15")]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.year, "2004-07-15")
        XCTAssertEqual(file.date, "")
        XCTAssertEqual(MetadataExchangeField.year.value(from: file, index: 0, relativeBasePath: nil), "2004-07-15")

        var edit = SingleFileEditModel(from: file)
        XCTAssertEqual(edit.year, "2004-07-15")
        edit.title = "Unrelated Title Edit"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )

        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.year, "2004-07-15")
        XCTAssertEqual(file.title, "Unrelated Title Edit")
        XCTAssertEqual(
            try TagLibMetadataManager.readSnapshot(from: url).raw
                .properties.first { $0.key == "YEAR" }?.values,
            ["2004-07-15"]
        )

        // A no-op payload must not mutate the file.
        let bytes = try Data(contentsOf: url)
        let payload = MetadataEditPayload(SingleFileEditModel(from: file), comparedTo: file)
        XCTAssertTrue(TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).isEmpty)
        let result = try MetadataConflictResolver.writeMetadata(
            payload,
            original: try XCTUnwrap(file.metadataConflictBaseline),
            originalFingerprint: try XCTUnwrap(file.fileFingerprint),
            originalVersion: try XCTUnwrap(file.metadataFileVersion),
            policy: .requireReload,
            pipeline: pipeline,
            url: url
        )
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testMP4YearIsEditableAndDoesNotTouchReleaseDate() async throws {
        let url = try writableFixture(extension: "testAudioFile.m4a")
        defer { removeTemporaryFixtureDirectory(containing: url) }

        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [
                .year: .text("1990"),
                .standaloneDate: .text("2008-03-04"),
                .releaseDate: .text("2017-06-09"),
                .originalReleaseDate: .text("1999-11-12"),
            ]),
            to: url
        )
        let pipeline = TagLibAudioMetadataPipeline()
        var file = try await pipeline.loadAudioFile(at: url, id: UUID())

        var edit = SingleFileEditModel(from: file)
        edit.year = "2004"
        let payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.year])
        _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion)

        file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.year, "2004")
        XCTAssertEqual(file.date, "2008-03-04")
        XCTAssertEqual(file.releaseDate, "2017-06-09")
        XCTAssertEqual(file.originalReleaseDate, "1999-11-12")

        let snapshot = try TagLibMetadataManager.readSnapshot(from: url)
        XCTAssertEqual(nativeValues(.year, snapshot: snapshot, extension: "m4a"), ["2004"])
        XCTAssertEqual(nativeValues(.standaloneDate, snapshot: snapshot, extension: "m4a"), ["2008-03-04"])
        XCTAssertEqual(nativeValues(.releaseDate, snapshot: snapshot, extension: "m4a"), ["2017-06-09"])

        edit = SingleFileEditModel(from: file)
        edit.year = ""
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        let cleared = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(cleared.year, "")
        XCTAssertEqual(cleared.releaseDate, "2017-06-09")
        XCTAssertEqual(cleared.date, "2008-03-04")
    }

    @MainActor
    func testID3v23DateWriteFailsSafelyWithoutChangingBytes() async throws {
        let source = try bundledAudioFixtureURL(named: "testAudioFile.mp3")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("v23.mp3")
        let v23 = try ID3v23FixtureBuilder.makeID3v23Copy(of: source)
        try v23.write(to: url)

        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        // Observed 0.7.0 behavior: TagLib normalizes ID3v2.3 TYER+TDAT into a
        // single TDRC text projection, so TDAT is not exposed as DATE. The
        // package's TDAT registration is therefore not independently writable
        // and readable; the app must not invent or coerce a value.
        XCTAssertEqual(file.year, "2004-04-03")
        XCTAssertEqual(file.date, "")

        for candidate in ["2008-03-04", "0403"] {
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(
                try TagLibMetadataManager.applyMetadataPatch(
                    MetadataPatch(fields: [.standaloneDate: .text(candidate)]),
                    to: url
                ),
                "ID3v2.3 DATE must fail safely until the package verifies TDAT independently"
            )
            XCTAssertEqual(try Data(contentsOf: url), before)
        }

        // The old successful YEAR assertion lost independent v2.3 DATE.
        // The concrete layout is now honestly read-only, not silently coerced.
        XCTAssertEqual(file.metadataConflictBaseline?.structured.id3v2MajorVersion, 3)
        XCTAssertNotNil(MetadataExchangePlanner.makeCSVExportPlan(template: "{{year}}", includeHeaderRow: true, targetFiles: [file]).validationMessage)
        XCTAssertNotNil(MetadataExchangePlanner.makeTextExportPlan(template: "{{year}}", targetFiles: [file]).validationMessage)
        XCTAssertFalse(MetadataFieldTransferPlanner.makePlan(source: .year, destination: .title, operation: .copy, targetFiles: [file]).canApply)
        XCTAssertFalse(makeFileRenamePlan(template: "{{year}}", targetFiles: [file]).canApply)
        XCTAssertFalse(AudioViewModel.canWrite(.year, to: file))
        let before = try Data(contentsOf: url)
        var edit = SingleFileEditModel(from: file)
        edit.year = "2005"
        XCTAssertThrowsError(try pipeline.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion
        ))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    // MARK: - Helpers

    private func nativeValues(
        _ field: MetadataFieldKey,
        snapshot: MetadataSnapshot,
        extension ext: String
    ) -> [String] {
        switch ext.lowercased() {
        case "mp3", "aac", "wav":
            let frames = snapshot.structured.id3v2Frames
            let values: [String]
            switch field {
            case .year:
                values = frameValues(frames, identifiers: ["TDRC", "TYER"])
            case .standaloneDate:
                values = frameValues(frames, identifiers: ["TDAT"])
                    + frameValues(frames, identifiers: ["TXXX"], descriptions: ["DATE"])
            case .releaseDate:
                values = frameValues(frames, identifiers: ["TDRL"])
            case .originalReleaseDate:
                values = frameValues(frames, identifiers: ["TDOR", "TORY"])
            default:
                values = []
            }
            if !values.isEmpty { return values }
            return propertyValues(snapshot, keys: propertyKeys(for: field))
        case "m4a", "mp4", "m4b":
            let atoms = snapshot.structured.mp4Atoms.filter { !$0.remove }
            switch field {
            case .year:
                return atomValues(atoms, key: "©day")
            case .standaloneDate:
                return atomValues(atoms, freeformDescription: "DATE")
            case .releaseDate:
                return atomValues(atoms, freeformDescription: "RELEASEDATE")
            case .originalReleaseDate:
                return atomValues(atoms, freeformDescription: "ORIGINALDATE")
            default:
                return []
            }
        default:
            return propertyValues(snapshot, keys: propertyKeys(for: field))
        }
    }

    private func propertyKeys(for field: MetadataFieldKey) -> [String] {
        switch field {
        case .year:
            return ["YEAR"]
        case .standaloneDate:
            return ["DATE"]
        case .releaseDate:
            return ["RELEASEDATE"]
        case .originalReleaseDate:
            return ["ORIGINALDATE", "ORIGINAL YEAR"]
        default:
            return []
        }
    }

    private func propertyValues(_ snapshot: MetadataSnapshot, keys: [String]) -> [String] {
        keys.compactMap { key in
            snapshot.structured.properties.first { $0.key == key }?.values
        }.flatMap { $0 }
    }

    private func frameValues(
        _ frames: [StructuredID3v2Frame],
        identifiers: [String],
        descriptions: [String] = []
    ) -> [String] {
        frames.filter { frame in
            guard identifiers.contains(frame.frameID) else { return false }
            if descriptions.isEmpty { return true }
            guard let description = frame.description?.uppercased() else { return false }
            return descriptions.contains(description)
        }.flatMap { frame in
            frame.values.isEmpty ? [frame.value] : frame.values
        }
    }

    private func atomValues(_ atoms: [StructuredMP4Atom], key: String) -> [String] {
        atoms.filter { $0.key == key }.flatMap { $0.values.isEmpty ? [$0.value] : $0.values }
    }

    private func atomValues(_ atoms: [StructuredMP4Atom], freeformDescription: String) -> [String] {
        atoms.filter {
            $0.freeformDescription?.uppercased() == freeformDescription.uppercased()
        }.flatMap { $0.values.isEmpty ? [$0.value] : $0.values }
    }

    private func writableFixture(extension fixtureName: String) throws -> URL {
        let source = try bundledAudioFixtureURL(named: fixtureName)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(fixtureName)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private func bundledAudioFixtureURL(named name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: name, withExtension: nil)
        )
    }

    private func removeTemporaryFixtureDirectory(containing url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
