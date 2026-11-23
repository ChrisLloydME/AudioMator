import XCTest
import TagLibAudioMetadata
@testable import AudioMator

nonisolated final class AutomaticNumberRecoveryTests: XCTestCase {
    private func fixture() throws -> URL {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "testAudioFile", withExtension: "m4a", subdirectory: "Fixtures/Audio")
            ?? Bundle(for: Self.self).url(forResource: "testAudioFile", withExtension: "m4a"))
        let name = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name).appendingPathExtension("m4a")
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    @MainActor
    func testPrivateOnlyValuesAreRecoveredWithoutWritingTheFile() async throws {
        for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"] {
            let url = try fixture()
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                .init(key: "trkn", type: "intPair", remove: true),
                .init(key: "disk", type: "intPair", remove: true),
                .init(key: "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"]),
                .init(key: "----:com.apple.iTunes:\(prefix)_DISCNUMBER_TEXT", type: "stringList", values: ["01/02"])
            ]), to: url)
            let before = try Data(contentsOf: url)
            let pipeline = TagLibAudioMetadataPipeline()
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(file.track, 3)
            XCTAssertEqual(file.trackTotal, 12)
            XCTAssertEqual(file.disc, 1)
            XCTAssertEqual(file.discTotal, 2)
            XCTAssertEqual(file.trackNumberText, "3/12")
            XCTAssertEqual(try Data(contentsOf: url), before)
            var edit = SingleFileEditModel(from: file)
            edit.title = "Title-only compatibility"
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            let after = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(after.trackTotal, 12)
            XCTAssertEqual(after.discTotal, 2)
            let atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertEqual(atoms.first { $0.key == "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT" }?.values, ["03/12"])
            XCTAssertFalse(atoms.contains { $0.key == "trkn" })
        }
    }

    @MainActor
    func testUnresolvedCandidatesAreNotDisplayedAsAChosenValue() {
        let group = MetadataNumberGroupInventory(
            number: .init(state: .native, nativeValue: 3),
            total: .init(state: .ambiguous, candidates: ["12", "14"]))
        let result = TagLibNumberingProjection.pair(number: 3, total: 12, text: "3/12", inventory: group)
        XCTAssertEqual(result.number, 3)
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.text, "3")
    }
    @MainActor
    func testOrdinarySaveMigratesEditedPairWithTitleAndClearDoesNotResurrectIt() async throws {
        for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"] {
            let url = try fixture()
            let identity = "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT"
            let other = "----:com.apple.iTunes:\(prefix)_DISCNUMBER_TEXT"
            let foreign = "----:org.example:\(prefix)_TRACKNUMBER_TEXT"
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                .init(key: "trkn", type: "intPair", remove: true),
                .init(key: identity, type: "stringList", values: ["03/12"]),
                .init(key: other, type: "stringList", values: ["01/02"]),
                .init(key: foreign, type: "stringList", values: ["99/99"])
            ]), to: url)
            let pipeline = TagLibAudioMetadataPipeline()
            var file = try await pipeline.loadAudioFile(at: url, id: UUID())
            var edit = SingleFileEditModel(from: file)
            edit.setTrackNumberFieldText("5")
            edit.title = "Normal save"
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            file = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(file.track, 5); XCTAssertEqual(file.trackTotal, 12)
            XCTAssertEqual(file.title, "Normal save")
            var atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertFalse(atoms.contains { $0.key == identity })
            XCTAssertEqual(atoms.first { $0.key == other }?.values, ["01/02"])
            XCTAssertEqual(atoms.first { $0.key == foreign }?.values, ["99/99"])
            edit = SingleFileEditModel(from: file)
            edit.setTrackNumberFieldText(""); edit.setTrackTotalFieldText("")
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            file = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(file.track, 0); XCTAssertEqual(file.trackTotal, 0)
            atoms = try TagLibMetadataManager.readSnapshot(from: url).structured.mp4Atoms
            XCTAssertFalse(atoms.contains { $0.key == identity || $0.key == "trkn" })
        }
    }

    @MainActor
    func testCanonicalValuesAreUsedWithoutAskingForAStoragePolicy() async throws {
        let url = try fixture()
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "trkn", type: "intPair", first: 3, second: 6),
            .init(key: "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"])
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let before = try Data(contentsOf: url)
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.track, 3); XCTAssertEqual(file.trackTotal, 6)
        XCTAssertEqual(try Data(contentsOf: url), before)
        var edit = SingleFileEditModel(from: file); edit.setTrackNumberFieldText("4")
        _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
        let after = try await pipeline.loadAudioFile(at: url, id: file.id)
        XCTAssertEqual(after.track, 4); XCTAssertEqual(after.trackTotal, 6)
    }

    @MainActor
    func testAmbiguityRequestsOrdinaryTotalAndAcceptsItsReplacement() async throws {
        let url = try fixture()
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "trkn", type: "intPair", remove: true),
            .init(key: "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"]),
            .init(key: "----:com.apple.iTunes:TAGLIBAUDIOMETADATA_TRACKNUMBER_TEXT", type: "stringList", values: ["04/14"])
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        XCTAssertEqual(file.track, 0); XCTAssertEqual(file.trackTotal, 0)
        var edit = SingleFileEditModel(from: file); edit.setTrackNumberFieldText("5")
        let before = try Data(contentsOf: url)
        do {
            _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
            XCTFail("An unknown untouched total must not be guessed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Total Tracks"))
            XCTAssertFalse(error.localizedDescription.contains("AUDIOMATOR"))
            XCTAssertFalse(error.localizedDescription.contains("legacy"))
        }
        XCTAssertEqual(try Data(contentsOf: url), before)
        edit.setTrackTotalFieldText("16")
        _ = try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
        let after = try await pipeline.loadAudioFile(at: url, id: file.id)
        XCTAssertEqual(after.track, 5); XCTAssertEqual(after.trackTotal, 16)
    }

    @MainActor
    func testStalePrivateRecoveryCannotBeCommittedAgainstAnotherRevision() async throws {
        let url = try fixture()
        let identity = "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT"
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: "trkn", type: "intPair", remove: true),
            .init(key: identity, type: "stringList", values: ["03/12"])
        ]), to: url)
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
            .init(key: identity, type: "stringList", values: ["04/14"])
        ]), to: url)
        let before = try Data(contentsOf: url)
        var edit = SingleFileEditModel(from: file); edit.setTrackNumberFieldText("5")
        XCTAssertThrowsError(try pipeline.writeMetadata(.init(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    // 2.6 (V2.6B2691) pinned package cafcf403 / 0.5.1. Its MP4 writer
    // retained both private namespaces and native pairs independently.
    // Reconstruct those layouts without running old code against user files.
    @MainActor
    func testHistoricalNumberLayoutsRemainCleanAcrossInspectorLifecycle() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"] {
            for layout in 0..<8 {
                let url = try fixture()
                let native: (Int, Int)? = switch layout {
                case 0, 4, 5: nil
                case 1: (3, 12) // Matching native / zero-padded private text.
                case 2: (3, 6) // Stale private total must not win.
                case 3: (3, 0) // Recover only the missing component.
                case 6: (0, 12) // Total-only native pair.
                default: (0, 0)
                }
                let text = layout == 4 ? "side A" : "03 / 12"
                var atoms: [StructuredMP4Atom] = [
                    .init(key: "trkn", type: "intPair", first: native?.0, second: native?.1, remove: native == nil),
                    .init(key: "disk", type: "intPair", remove: true),
                    .init(key: "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT", type: "stringList", values: [text]),
                    .init(key: "----:com.apple.iTunes:\(prefix)_DISCNUMBER_TEXT", type: "stringList", values: ["01/02"])
                ]
                if layout == 5 {
                    let other = prefix == "AUDIOMATOR" ? "TAGLIBAUDIOMETADATA" : "AUDIOMATOR"
                    atoms.append(.init(key: "----:com.apple.iTunes:\(other)_TRACKNUMBER_TEXT", type: "stringList", values: ["04/14"]))
                }
                try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: atoms), to: url)
                let before = try Data(contentsOf: url)
                let file = try await pipeline.loadAudioFile(at: url, id: UUID())
                let vm = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
                vm.mergeQuickImportFiles([file])
                vm.setSelectedAudioIDs([file.id])
                let context = "\(prefix) layout \(layout)"
                XCTAssertFalse(vm.hasUnsavedInspectorChanges, context)
                XCTAssertTrue(MetadataEditPayload(try XCTUnwrap(vm.edit), comparedTo: file).requestedFields.isEmpty, context)
                // Exercise the component bindings, including their formatting guards.
                let displayed = try XCTUnwrap(vm.edit)
                vm.edit?.setTrackNumberFieldText(displayed.trackNumberFieldText)
                vm.edit?.setTrackTotalFieldText(displayed.trackTotalFieldText)
                vm.edit?.setDiscNumberFieldText(displayed.discNumberFieldText)
                vm.edit?.setDiscTotalFieldText(displayed.discTotalFieldText)
                XCTAssertFalse(vm.hasUnsavedInspectorChanges, context)
                vm.saveInspectorEdits()
                XCTAssertNil(vm.metadataSaveProgress, "No-op Save must not start a transaction: \(context)")
                await vm.refreshSelectedFilesAfterActivation()
                await vm.reloadSelectedFilesFromDisk()
                XCTAssertFalse(vm.hasUnsavedInspectorChanges, context)
                var confirmations = 0
                ContentView.confirmInspectorDiscard(
                    using: vm,
                    suppressesDiscardWarning: false,
                    requestDiscardConfirmation: { _ in confirmations += 1 },
                    action: { vm.setSelectedAudioIDs([]) }
                )
                XCTAssertEqual(confirmations, 0, context)
                vm.setSelectedAudioIDs([file.id])
                XCTAssertFalse(vm.hasUnsavedInspectorChanges, context)
                XCTAssertEqual(try pipeline.metadataFileVersion(at: url), file.metadataFileVersion, context)
                XCTAssertEqual(try Data(contentsOf: url), before, context)
            }
        }
    }

    @MainActor
    func testRecoveredBatchReloadAndRealDraftHaveDistinctDirtyState() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        var files: [AudioFile] = []
        var originals: [URL: Data] = [:]
        for (index, prefix) in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"].enumerated() {
            let url = try fixture()
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                .init(key: "trkn", type: "intPair", remove: true),
                .init(key: "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT", type: "stringList", values: ["0\(index + 1)/12"])
            ]), to: url)
            originals[url] = try Data(contentsOf: url)
            files.append(try await pipeline.loadAudioFile(at: url, id: UUID()))
        }
        let vm = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        vm.mergeQuickImportFiles(files)
        vm.setSelectedAudioIDs(Set(files.map(\.id)))
        XCTAssertFalse(vm.hasUnsavedInspectorChanges, "Mixed recovered numbers are placeholders, not edits")
        vm.saveInspectorEdits()
        XCTAssertNil(vm.metadataSaveProgress)
        await vm.reloadSelectedFilesFromDisk()
        await vm.refreshSelectedFilesAfterActivation()
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setText("Real draft", for: .title)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        await vm.refreshSelectedFilesAfterActivation()
        XCTAssertTrue(vm.hasUnsavedInspectorChanges, "Recovery must not discard a real user draft")
        vm.cancelEditing()
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.setSelectedAudioIDs([files[0].id])
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.edit?.setTrackNumberFieldText("9")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        await vm.refreshSelectedFilesAfterActivation()
        XCTAssertEqual(vm.edit?.trackNumberFieldText, "9")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        vm.cancelEditing()
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        for file in files { XCTAssertEqual(try Data(contentsOf: file.url), originals[file.url]) }
    }

    @MainActor
    func testSingleAndBatchNumberMigrationFinishWithCleanInspector() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        for count in [1, 2] {
            var files: [AudioFile] = []
            for prefix in ["AUDIOMATOR", "TAGLIBAUDIOMETADATA"].prefix(count) {
                let url = try fixture()
                try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                    .init(key: "trkn", type: "intPair", remove: true),
                    .init(key: "----:com.apple.iTunes:\(prefix)_TRACKNUMBER_TEXT", type: "stringList", values: ["03/12"])
                ]), to: url)
                files.append(try await pipeline.loadAudioFile(at: url, id: UUID()))
            }
            let vm = AudioViewModelTestFactory.make(metadataPipeline: pipeline, writableFixtures: files)
            vm.mergeQuickImportFiles(files)
            vm.setSelectedAudioIDs(Set(files.map(\.id)))
            if count == 1 { vm.edit?.setTrackNumberFieldText("5") }
            else { vm.multiEdit?.setText("5", for: .trackNumber) }
            XCTAssertTrue(vm.hasUnsavedInspectorChanges)
            vm.saveInspectorEdits()
            XCTAssertNotNil(vm.metadataSaveProgress)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while vm.metadataSaveProgress != nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNil(vm.metadataSaveProgress, "Save must finish")
            XCTAssertFalse(vm.hasUnsavedInspectorChanges, "Committed recovery must become the new clean baseline")
            for file in vm.files {
                XCTAssertEqual(file.track, 5)
                XCTAssertEqual(file.trackTotal, 12)
                let atoms = try TagLibMetadataManager.readSnapshot(from: file.url).structured.mp4Atoms
                XCTAssertFalse(atoms.contains { $0.key.hasSuffix("_TRACKNUMBER_TEXT") })
            }
            let savedBytes = try Dictionary(uniqueKeysWithValues: files.map { ($0.url, try Data(contentsOf: $0.url)) })
            vm.saveInspectorEdits()
            XCTAssertNil(vm.metadataSaveProgress, "A second unchanged Save is a no-op")
            await vm.reloadSelectedFilesFromDisk()
            XCTAssertFalse(vm.hasUnsavedInspectorChanges)
            for file in files { XCTAssertEqual(try Data(contentsOf: file.url), savedBytes[file.url]) }
        }
    }

}
