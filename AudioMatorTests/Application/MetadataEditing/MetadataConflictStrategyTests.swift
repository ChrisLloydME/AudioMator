import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

@MainActor
final class MetadataConflictStrategyTests: XCTestCase {
    func testDefaultAndUnknownPreferenceUseSafeMerge() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(MetadataConflictPolicy.load(from: defaults), .mergeNonConflicting)
        defaults.set("obsolete", forKey: MetadataConflictPolicy.defaultsKey)
        XCTAssertEqual(MetadataConflictPolicy.load(from: defaults), .mergeNonConflicting)
        for policy in MetadataConflictPolicy.allCases {
            defaults.set(policy.rawValue, forKey: MetadataConflictPolicy.defaultsKey)
            XCTAssertEqual(MetadataConflictPolicy.load(from: defaults), policy)
        }
    }

    func testPermissionOnlyChangeAutomaticallySavesInspectorDraft() async throws {
        let file = try await loadedFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        let viewModel = selectedViewModel(file)
        var draft = SingleFileEditModel(from: file)
        draft.title = "My title"
        let result = await viewModel.persistMetadataEdit(
            draft, to: file, comparedTo: file,
            expectedFileFingerprint: file.fileFingerprint, expectedMetadataVersion: file.metadataFileVersion
        )
        guard case .success = result else { return XCTFail("Expected a safe rebase: \(result)") }
        XCTAssertEqual(viewModel.files.first?.title, "My title")
    }

    func testDisjointInspectorChangesKeepExternalMultiValues() async throws {
        let file = try await loadedFixture()
        try externalChange(["ARTIST": ["External A", "External B"]], at: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.title = "My title"
        _ = try save(draft, original: file, policy: .mergeNonConflicting)
        let values = try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: file.url)
        XCTAssertEqual(values["TITLE"], ["My title"])
        XCTAssertEqual(values["ARTIST"], ["External A", "External B"])
    }

    func testOverlapStopsWriteAndRetainsInspectorDraft() async throws {
        let file = try await loadedFixture()
        let viewModel = selectedViewModel(file)
        viewModel.edit?.title = "My title"
        try externalChange(["TITLE": ["Disk title"]], at: file.url)
        let bytes = try Data(contentsOf: file.url)
        let result = await viewModel.persistMetadataEdit(
            try XCTUnwrap(viewModel.edit), to: file, comparedTo: file,
            expectedFileFingerprint: file.fileFingerprint, expectedMetadataVersion: file.metadataFileVersion
        )
        guard case .failure(let reason) = result else { return XCTFail("Expected a field conflict") }
        XCTAssertTrue(reason.contains("Title"))
        XCTAssertEqual(viewModel.edit?.title, "My title")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    }

    func testSelectedPriorityPoliciesApplyToConflictingFieldsOnly() async throws {
        for policy in [MetadataConflictPolicy.preferUserChanges, .preferDiskChanges] {
            let file = try await loadedFixture()
            let defaults = isolatedDefaults()
            defaults.set(policy.rawValue, forKey: MetadataConflictPolicy.defaultsKey)
            let viewModel = selectedViewModel(file, defaults: defaults)
            try externalChange(["TITLE": ["Disk title"], "ARTIST": ["Disk artist"]], at: file.url)
            var draft = SingleFileEditModel(from: file)
            draft.title = "My title"
            draft.album = "My album"
            let result = await viewModel.persistMetadataEdit(
                draft, to: file, comparedTo: file,
                expectedFileFingerprint: file.fileFingerprint, expectedMetadataVersion: file.metadataFileVersion
            )
            guard case .success(let outcome) = result else { return XCTFail("Expected priority resolution") }
            let saved = try TagLibMetadataManager.readMetadataResult(from: file.url)
            XCTAssertEqual(saved.title, policy == .preferUserChanges ? "My title" : "Disk title")
            XCTAssertEqual(saved.artist, "Disk artist")
            XCTAssertEqual(saved.album, "My album")
            if policy == .preferDiskChanges { XCTAssertTrue(outcome.warnings.contains { $0.contains("Title") }) }
        }
    }

    func testSameFinalTitleDoesNotConflict() async throws {
        let file = try await loadedFixture()
        try externalChange(["TITLE": ["Same title"]], at: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.title = "Same title"
        draft.album = "My album"
        _ = try save(draft, original: file, policy: .mergeNonConflicting)
        let saved = try TagLibMetadataManager.readMetadataResult(from: file.url)
        XCTAssertEqual(saved.title, "Same title")
        XCTAssertEqual(saved.album, "My album")
    }

    func testConvergedDraftAvoidsRedundantWrite() async throws {
        let file = try await loadedFixture()
        try externalChange(["TITLE": ["Same title"]], at: file.url)
        let before = try TagLibMetadataManager.fileVersion(at: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.title = "Same title"
        _ = try save(draft, original: file, policy: .mergeNonConflicting)
        XCTAssertEqual(try TagLibMetadataManager.fileVersion(at: file.url), before)
    }

    func testBasicProjectionDoesNotHideExternalExtraArtistValue() async throws {
        let file = try await loadedFixture()
        try externalChange(["ARTIST": ["My artist", "External second artist"]], at: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.artist = "My artist"
        XCTAssertThrowsError(try save(draft, original: file, policy: .mergeNonConflicting))
        XCTAssertEqual(try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: file.url)["ARTIST"], ["My artist", "External second artist"])
    }

    func testManualReloadRejectsPermissionOnlyRevisionChange() async throws {
        let file = try await loadedFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        var draft = SingleFileEditModel(from: file)
        draft.title = "My title"
        XCTAssertThrowsError(try save(draft, original: file, policy: .requireReload))
    }

    func testEveryPolicyRejectsFileReplacement() async throws {
        for policy in MetadataConflictPolicy.allCases {
            let file = try await loadedFixture()
            let replacement = file.url.deletingLastPathComponent().appendingPathComponent("replacement.flac")
            try FileManager.default.copyItem(at: file.url, to: replacement)
            try FileManager.default.removeItem(at: file.url)
            try FileManager.default.moveItem(at: replacement, to: file.url)
            var draft = SingleFileEditModel(from: file)
            draft.title = "Must not save"
            XCTAssertThrowsError(try save(draft, original: file, policy: policy))
        }
    }

    func testRawDeltaKeepsExternalAddedKeysAndExactValueArrays() async throws {
        let file = try await loadedFixture()
        var draft = try XCTUnwrap(file.metadataConflictBaseline).values
        draft["TITLE"] = ["My title"]
        draft.removeValue(forKey: "ALBUM")
        try externalChange(["CUSTOM-EXTERNAL": ["A; B", "Second", "Second"], "ARTIST": ["A", "B"]], at: file.url)
        let viewModel = selectedViewModel(file)
        let result = await viewModel.applyRawMetadataPropertyMaps(
            [file.id: draft], to: [MetadataEditorTarget(file: file)]
        )
        XCTAssertTrue(result.didApplyAllChanges)
        let saved = try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: file.url)
        XCTAssertEqual(saved["TITLE"], ["My title"])
        XCTAssertNil(saved["ALBUM"])
        XCTAssertEqual(saved["CUSTOM-EXTERNAL"], ["A; B", "Second", "Second"])
        XCTAssertEqual(saved["ARTIST"], ["A", "B"])
    }

    func testRawNumberAndTotalAreOneConflictGroup() async throws {
        let file = try await loadedFixture(extra: ["TRACKNUMBER": ["1"], "TRACKTOTAL": ["10"]])
        var draft = try XCTUnwrap(file.metadataConflictBaseline).values
        draft["TRACKNUMBER"] = ["2"]
        try externalChange(["TRACKTOTAL": ["20"]], at: file.url)
        XCTAssertThrowsError(try saveRaw(draft, original: file, policy: .mergeNonConflicting))
        _ = try saveRaw(draft, original: file, policy: .preferDiskChanges)
        let saved = try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: file.url)
        XCTAssertEqual(saved["TRACKNUMBER"], ["1"])
        XCTAssertEqual(saved["TRACKTOTAL"], ["20"])
    }

    func testRawPriorityDeletionAndOverlap() async throws {
        for policy in [MetadataConflictPolicy.preferUserChanges, .preferDiskChanges] {
            let file = try await loadedFixture()
            var draft = try XCTUnwrap(file.metadataConflictBaseline).values
            draft.removeValue(forKey: "ARTIST")
            draft["TITLE"] = ["My title"]
            try externalChange(["ARTIST": ["Disk A", "Disk B"], "EXTERNAL": ["Keep"]], at: file.url)
            _ = try saveRaw(draft, original: file, policy: policy)
            let saved = try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: file.url)
            XCTAssertEqual(saved["ARTIST"], policy == .preferUserChanges ? nil : ["Disk A", "Disk B"])
            XCTAssertEqual(saved["TITLE"], ["My title"])
            XCTAssertEqual(saved["EXTERNAL"], ["Keep"])
        }
    }

    func testEditorOpensWithCoherentNewBaselineBeforeDrafting() async throws {
        let file = try await loadedFixture()
        try externalChange(["TITLE": ["New before opening"]], at: file.url)
        let store = MetadataEditorStore(metadataPipeline: TagLibAudioMetadataPipeline())
        store.present(targetFiles: [file])
        for _ in 0..<200 where store.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.isEditable)
        XCTAssertEqual(store.originalPropertyMaps[file.id]?["TITLE"], ["New before opening"])
        XCTAssertNotEqual(store.targets.first?.expectedMetadataVersion, file.metadataFileVersion)
        XCTAssertEqual(store.targets.first?.metadataConflictBaseline?.values, store.originalPropertyMaps[file.id])
    }

    func testDiscOnlyDraftKeepsExternallyUpdatedTrackPair() async throws {
        let file = try await loadedFixture(extra: ["TRACKNUMBER": ["1"], "TRACKTOTAL": ["10"], "DISCNUMBER": ["1"], "DISCTOTAL": ["2"]])
        try externalChange(["TRACKNUMBER": ["5"], "TRACKTOTAL": ["20"]], at: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.setDiscNumberFieldText("2")
        _ = try save(draft, original: file, policy: .mergeNonConflicting)
        let saved = try TagLibMetadataManager.readMetadataResult(from: file.url)
        XCTAssertEqual(saved.track, 5)
        XCTAssertEqual(saved.trackTotal, 20)
        XCTAssertEqual(saved.disc, 2)
        XCTAssertEqual(saved.discTotal, 2)
    }

    func testArtworkSnapshotRoleChangeWithIdenticalFirstImageConflictsAsAGroup() async throws {
        let file = try await loadedFixture()
        var original = try TagLibMetadataManager.readSnapshot(from: file.url)
        let front = StructuredArtwork(pictureTypeCode: 3, mimeType: "image/jpeg", data: Data([1]))
        let back = StructuredArtwork(pictureTypeCode: 4, mimeType: "image/jpeg", description: "Before", data: Data([2]))
        original.structured.artwork = [front, back]
        let changedBack = StructuredArtwork(pictureTypeCode: 4, mimeType: "image/jpeg", description: "After", data: Data([2]))
        let pipeline = FixtureConflictPipeline(artworkOverride: [front, changedBack])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        let current = try pipeline.conflictSnapshot(for: file.url)
        XCTAssertEqual(original.structured.artwork.first, current.structured.artwork.first)
        XCTAssertNotEqual(original.structured.artwork, current.structured.artwork)
        let bytes = try Data(contentsOf: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.artworkEditAction = .remove
        XCTAssertThrowsError(try MetadataConflictResolver.writeMetadata(
            MetadataEditPayload(draft, comparedTo: file), original: MetadataConflictBaseline(original),
            originalFingerprint: try XCTUnwrap(file.fileFingerprint),
            originalVersion: try XCTUnwrap(file.metadataFileVersion),
            policy: .mergeNonConflicting, pipeline: pipeline, url: file.url
        )) { error in
            XCTAssertTrue(error is MetadataConflictError)
        }
        XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    }

    func testFinalVersionGuardRejectsChangeAfterConflictRead() async throws {
        let file = try await loadedFixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        let bytes = try Data(contentsOf: file.url)
        var draft = SingleFileEditModel(from: file)
        draft.title = "Must not save"
        XCTAssertThrowsError(try MetadataConflictResolver.writeMetadata(
            MetadataEditPayload(draft, comparedTo: file),
            original: try XCTUnwrap(file.metadataConflictBaseline),
            originalFingerprint: try XCTUnwrap(file.fileFingerprint),
            originalVersion: try XCTUnwrap(file.metadataFileVersion),
            policy: .preferUserChanges, pipeline: FixtureConflictPipeline(raceBeforeWrite: true), url: file.url
        ))
        XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    }

    func testPartialInspectorBatchRetryDoesNotResaveCompletedFile() async throws {
        let first = try await loadedFixture()
        let second = try await loadedFixture()
        let defaults = isolatedDefaults()
        let viewModel = selectedViewModel(first, defaults: defaults)
        viewModel.mergeQuickImportFiles([second])
        viewModel.setSelectedAudioIDs([first.id, second.id])
        viewModel.multiEdit?.setText("Batch title", for: .title)
        try externalChange(["TITLE": ["Second disk title"]], at: second.url)

        viewModel.saveInspectorEdits()
        try await waitForInspectorSave(viewModel)
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: first.url).title, "Batch title")
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: second.url).title, "Second disk title")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        let firstSavedVersion = try TagLibMetadataManager.fileVersion(at: first.url)
        defaults.set(MetadataConflictPolicy.preferUserChanges.rawValue, forKey: MetadataConflictPolicy.defaultsKey)

        viewModel.saveInspectorEdits()
        try await waitForInspectorSave(viewModel)
        XCTAssertEqual(try TagLibMetadataManager.fileVersion(at: first.url), firstSavedVersion)
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: second.url).title, "Batch title")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    func testPartialDiskPriorityRetryDoesNotReapplyDiscardedField() async throws {
        let first = try await loadedFixture()
        let second = try await loadedFixture()
        let defaults = isolatedDefaults()
        defaults.set(MetadataConflictPolicy.preferDiskChanges.rawValue, forKey: MetadataConflictPolicy.defaultsKey)
        let viewModel = selectedViewModel(first, defaults: defaults)
        viewModel.mergeQuickImportFiles([second])
        viewModel.setSelectedAudioIDs([first.id, second.id])
        viewModel.multiEdit?.setText("Batch title", for: .title)
        viewModel.multiEdit?.setText("Batch album", for: .album)
        try externalChange(["TITLE": ["First disk title"]], at: first.url)
        let secondBytes = try Data(contentsOf: second.url)
        try rewriteInPlace(Data("temporarily unreadable".utf8), at: second.url)

        viewModel.saveInspectorEdits()
        try await waitForInspectorSave(viewModel)
        let firstSavedVersion = try TagLibMetadataManager.fileVersion(at: first.url)
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: first.url).title, "First disk title")
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: first.url).album, "Batch album")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        try rewriteInPlace(secondBytes, at: second.url)

        viewModel.saveInspectorEdits()
        try await waitForInspectorSave(viewModel)
        XCTAssertEqual(try TagLibMetadataManager.fileVersion(at: first.url), firstSavedVersion)
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: first.url).title, "First disk title")
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: second.url).title, "Batch title")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    func testNewFieldAfterPartialBatchUsesReadbackAndKeepsLaterExternalChanges() async throws {
        let first = try await loadedFixture()
        let second = try await loadedFixture()
        let defaults = isolatedDefaults()
        let viewModel = selectedViewModel(first, defaults: defaults)
        viewModel.mergeQuickImportFiles([second])
        viewModel.setSelectedAudioIDs([first.id, second.id])
        viewModel.multiEdit?.setText("Batch title", for: .title)
        try externalChange(["TITLE": ["Second disk title"]], at: second.url)
        viewModel.saveInspectorEdits()
        try await waitForInspectorSave(viewModel)
        try externalChange(["TITLE": ["Later external title"]], at: first.url)
        viewModel.multiEdit?.setText("New album", for: .album)
        defaults.set(MetadataConflictPolicy.preferUserChanges.rawValue, forKey: MetadataConflictPolicy.defaultsKey)

        viewModel.saveInspectorEdits()
        try await waitForInspectorSave(viewModel)
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: first.url).title, "Later external title")
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: first.url).album, "New album")
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: second.url).title, "Batch title")
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: second.url).album, "New album")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    private func waitForInspectorSave(_ viewModel: AudioViewModel) async throws {
        for _ in 0..<300 {
            if viewModel.metadataSaveProgress == nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Inspector save did not finish")
    }

    private func rewriteInPlace(_ bytes: Data, at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
    }

    private func save(_ draft: SingleFileEditModel, original file: AudioFile, policy: MetadataConflictPolicy) throws -> AudioMetadataWriteResult {
        try MetadataConflictResolver.writeMetadata(
            MetadataEditPayload(draft, comparedTo: file),
            original: try XCTUnwrap(file.metadataConflictBaseline),
            originalFingerprint: try XCTUnwrap(file.fileFingerprint),
            originalVersion: try XCTUnwrap(file.metadataFileVersion),
            policy: policy, pipeline: TagLibAudioMetadataPipeline(), url: file.url
        )
    }

    private func saveRaw(_ draft: RawMetadataValueMap, original file: AudioFile, policy: MetadataConflictPolicy) throws -> AudioMetadataWriteResult {
        try MetadataConflictResolver.writeRawMetadata(
            draft, original: try XCTUnwrap(file.metadataConflictBaseline),
            originalFingerprint: try XCTUnwrap(file.fileFingerprint),
            originalVersion: try XCTUnwrap(file.metadataFileVersion),
            policy: policy, pipeline: TagLibAudioMetadataPipeline(), url: file.url
        )
    }

    private func loadedFixture(extra: RawMetadataValueMap = [:]) async throws -> AudioFile {
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource: "testAudioFile.flac", withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AudioMatorConflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.flac")
        try FileManager.default.copyItem(at: fixture, to: url)
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["TITLE": ["Original"], "ARTIST": ["Original artist"], "ALBUM": ["Original album"]].merging(extra) { _, extra in extra }), to: url
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        return try await TagLibAudioMetadataPipeline().loadAudioFile(at: url, id: UUID())
    }

    /// Simulates an external editor writing in place, without replacing identity.
    private func externalChange(_ values: RawMetadataValueMap, at url: URL) throws {
        let copy = url.deletingLastPathComponent().appendingPathComponent("external.flac")
        try FileManager.default.copyItem(at: url, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        _ = try TagLibMetadataManager.applyRawMetadataPatch(RawMetadataPatch(valuesToSet: values), to: copy)
        let bytes = try Data(contentsOf: copy)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "AudioMatorConflictTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func selectedViewModel(_ file: AudioFile, defaults: UserDefaults? = nil) -> AudioViewModel {
        let defaults = defaults ?? isolatedDefaults()
        let logURL = file.url.deletingLastPathComponent().appendingPathComponent("issues.json")
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: FixtureConflictPipeline(), saveIssueLogStore: SaveIssueLogStore(fileURL: logURL),
            conflictPolicyDefaults: defaults
        )
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([file.id])
        return viewModel
    }
}

// Test-owned temporary files already have access. Skip only the production
// folder permission UI; all reads and commits still use the real adapter.
private struct FixtureConflictPipeline: AudioMetadataPipeline {
    let raceBeforeWrite: Bool
    let artworkOverride: [StructuredArtwork]?
    nonisolated init(raceBeforeWrite: Bool = false, artworkOverride: [StructuredArtwork]? = nil) {
        self.raceBeforeWrite = raceBeforeWrite
        self.artworkOverride = artworkOverride
    }
    private let base = TagLibAudioMetadataPipeline()
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile { try await base.loadAudioFile(at: url, id: id) }
    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion { try base.metadataFileVersion(at: url) }
    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        var snapshot = try base.conflictSnapshot(for: url)
        if let artworkOverride { snapshot.structured.artwork = artworkOverride }
        return snapshot
    }
    nonisolated func rawMetadataDumpText(for url: URL) -> String? { base.rawMetadataDumpText(for: url) }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { try base.rawMetadataValueMap(for: url) }
    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        if raceBeforeWrite { try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path) }
        return try base.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }
    nonisolated func writeRawMetadataPatch(_ patch: RawMetadataPatch, to url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }
    nonisolated func eraseAllMetadata(at url: URL, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult { try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion) }
    nonisolated func writeTrackNumberText(_ trackNumberText: String, discNumberText: String?, to url: URL, verifyAfterWrite: Bool, expectedVersion: MetadataFileVersion?) throws -> AudioMetadataWriteResult {
        try base.writeTrackNumberText(trackNumberText, discNumberText: discNumberText, to: url, verifyAfterWrite: verifyAfterWrite, expectedVersion: expectedVersion)
    }
}
