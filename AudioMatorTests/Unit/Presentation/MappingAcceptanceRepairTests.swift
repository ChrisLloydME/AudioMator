import XCTest
import TagLibAudioMetadata
@testable import AudioMator

@MainActor
final class MappingAcceptanceRepairTests: XCTestCase {
    func testPurchaseDateAndRateHaveRealVisibleRoutes() {
        XCTAssertTrue(ContainerMetadataFieldCatalog.editableKeys.contains(.itunesPurchaseDate))
        XCTAssertTrue(ContainerMetadataFieldCatalog.readKeys.contains(.itunesPurchaseDate))
        XCTAssertTrue(ContainerMetadataFieldCatalog.visibleKeys.contains(.rate))
        XCTAssertFalse(ContainerMetadataFieldCatalog.editableKeys.contains(.rate))
    }

    func testUnknownAdvisoryImportIsNotConvertedToUnset() throws {
        XCTAssertNil(MetadataExchangeField.contentAdvisory.importedValueValidationMessage("4"))
        var edit = SingleFileEditModel()
        edit.contentAdvisory = .explicit
        MetadataExchangeField.contentAdvisory.applyImportedValue("4", to: &edit)
        XCTAssertEqual(edit.contentAdvisory, .explicit)
        XCTAssertEqual(edit.unsupportedAdvisoryImport, "4")
        let payload = MetadataEditPayload(edit)
        XCTAssertThrowsError(try TagLibAudioMetadataPipeline.metadataPatchForWrite(
            from: payload, at: URL(fileURLWithPath: "/tmp/unused.m4a"), expectedVersion: nil
        ))
    }

    func testUnknownAdvisoryRoundTripsOnOriginalFileAndRejectsUnsupportedAssignment() async throws {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile", withExtension: "m4a", subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile", withExtension: "m4a"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try FileManager.default.copyItem(at: source, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "rtng", type: "uint", value: "4")
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let csv = MetadataExchangePlanner.makeCSVExportPlan(template: "{{contentAdvisory}}", includeHeaderRow: true, targetFiles: [file])
        let original = MetadataExchangePlanner.makeCSVImportPlan(template: "{{contentAdvisory}}", sourceText: csv.outputText,
            firstRowIsHeader: true, targetFiles: [file], clearBlankImportedValues: false)
        XCTAssertNil(original.rows.first?.issueMessage)
        XCTAssertTrue(original.writeEntries.isEmpty)
        let other = MetadataExchangePlanner.makeCSVImportPlan(template: "{{contentAdvisory}}", sourceText: csv.outputText,
            firstRowIsHeader: true, targetFiles: [AudioFileTestFactory.make()], clearBlankImportedValues: false)
        XCTAssertNotNil(other.rows.first?.issueMessage)
        XCTAssertTrue(other.writeEntries.isEmpty)

        var edit = SingleFileEditModel(from: file)
        edit.containerValues[.itunesPurchaseDate] = .text("2017-06-09T10:00:00Z")
        let payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.itunesPurchaseDate])
        _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion)
        let after = try await pipeline.loadAudioFile(at: url, id: file.id)
        XCTAssertEqual(after.advisoryRawValue, "4")
        XCTAssertEqual(after.containerValues[.itunesPurchaseDate], .text("2017-06-09T10:00:00Z"))
    }

    func testInvalidReplacementMustNotBecomeRemoval() throws {
        XCTAssertNil(try NumberNormalizationChoice.replacementComponent("  "))
        XCTAssertEqual(try NumberNormalizationChoice.replacementComponent("03"), 3)
        for text in ["abc", "3/12", "-1", "0", "+1", "999999999999999999999999"] {
            XCTAssertThrowsError(try NumberNormalizationChoice.replacementComponent(text), text)
        }
    }

    func testExportedRemovalTokenIsLiteralOnReimport() throws {
        let original = AudioFileTestFactory.make(title: "<remove>")
        let target = AudioFileTestFactory.make(title: "Keep me")
        let exported = MetadataExchangePlanner.makeCSVExportPlan(
            template: "{{title}}", includeHeaderRow: true, targetFiles: [original]
        )
        XCTAssertTrue(exported.outputText.contains("\"<remove>\""))
        let imported = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}", sourceText: exported.outputText, firstRowIsHeader: true,
            targetFiles: [target], clearBlankImportedValues: false
        )
        let entry = try XCTUnwrap(imported.writeEntries.first)
        XCTAssertEqual(entry.values[.title], "<remove>")
        var edit = SingleFileEditModel(from: target)
        MetadataExchangeField.title.applyImportedValue(entry.values[.title]!, to: &edit, preservingNumberPairComponents: true)
        XCTAssertEqual(edit.title, "<remove>")
    }

    func testLegacyRemovalTextStaysLiteralAndVersionedTextEscapesRoundTrip() throws {
        let target = AudioFileTestFactory.make(title: "Keep me")
        let legacy = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{title}}", sourceText: "Title\n<remove>", firstRowIsHeader: true,
            targetFiles: [target], clearBlankImportedValues: false
        )
        XCTAssertEqual(try XCTUnwrap(legacy.writeEntries.first).values[.title], "<remove>")
        for literal in ["<remove>", "\\<remove>", "\\\\<remove>"] {
            let original = AudioFileTestFactory.make(title: literal)
            let exported = MetadataExchangePlanner.makeTextExportPlan(template: "{{title}}", targetFiles: [original])
            let imported = MetadataExchangePlanner.makeTextImportPlan(
                template: "{{title}}", sourceText: exported.outputText,
                targetFiles: [target], clearBlankImportedValues: false
            )
            XCTAssertEqual(try XCTUnwrap(imported.writeEntries.first).values[.title], literal)
        }
    }

    func testForeignFreeformDateIsNotAnIndependentSemanticDate() {
        let structured = StructuredMetadata(mp4Atoms: [
            .init(key: "----:org.example:DATE", type: "stringList", values: ["1999"]),
            .init(key: "----:com.apple.iTunes:DATE", type: "stringList", values: ["2008-03-04"])
        ])
        XCTAssertEqual(TagLibDateNativeProjection.values(
            for: .standaloneDate, structured: structured, basicYear: "2004", fileExtension: "m4a"
        ), ["2008-03-04"])
    }

    func testPrivatePairsCanBeSeededAndCleanedThroughCapturedAppPlan() throws {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile.m4a", withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.m4a", withExtension: nil, subdirectory: "Audio")
            ?? bundle.url(forResource: "testAudioFile.m4a", withExtension: nil))
        for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
            try FileManager.default.copyItem(at: source, to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let track = "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT"
            let disc = "----:com.apple.iTunes:\(prefix)_DISCNUMBER_TEXT"
            let foreign = "----:org.example:\(prefix)_TRACKNUMBER_TEXT"
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(StructuredMetadata(mp4Atoms: [
                .init(key: "trkn", type: "intPair", remove: true),
                .init(key: track, type: "stringList", values: ["03/12"]),
                .init(key: disc, type: "stringList", values: ["01/02"]),
                .init(key: foreign, type: "stringList", values: ["99/99"])
            ]), to: url)
            let pipeline = TagLibAudioMetadataPipeline()
            let preview = try pipeline.planNumberNormalization(at: url, policy: .useLegacy, groups: [.track])
            XCTAssertEqual(preview.plan.trackNumber, 3)
            XCTAssertEqual(preview.plan.trackTotal, 12)
            _ = try pipeline.applyNumberNormalization(preview, to: url, expectedVersion: preview.fileVersion)
            let atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertFalse(atoms.contains { $0.key == track })
            XCTAssertEqual(atoms.first { $0.key == disc }?.values, ["01/02"])
            XCTAssertEqual(atoms.first { $0.key == foreign }?.values, ["99/99"])
            XCTAssertEqual(atoms.first { $0.key == "trkn" }?.first, 3)
            XCTAssertEqual(atoms.first { $0.key == "trkn" }?.second, 12)
        }
    }

    func testReplacementEditsInvalidateCapturedPreview() throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "testAudioFile", withExtension: "m4a", subdirectory: "Fixtures/Audio")
            ?? Bundle(for: Self.self).url(forResource: "testAudioFile", withExtension: "m4a"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try FileManager.default.copyItem(at: source, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let pipeline = TagLibAudioMetadataPipeline()
        let preview = try pipeline.planNumberNormalization(at: url, policy: .useNative, groups: [.track])
        let model = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        model.numberNormalizationPreview = preview
        model.numberNormalizationReplaceNumber = "5"
        XCTAssertNil(model.numberNormalizationPreview)
        model.numberNormalizationPreview = preview
        model.numberNormalizationReplaceTotal = "12"
        XCTAssertNil(model.numberNormalizationPreview)
    }
}
