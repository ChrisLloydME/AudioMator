import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
/// F3-b Inspector draft session lifecycle, passive prune pending review,
/// save-delta completion and artwork generation tests.
nonisolated final class InspectorDraftSessionTests: XCTestCase {
    @MainActor
    private func makeViewModel() -> AudioViewModel {
        AudioViewModelTestFactory.make(metadataPipeline: InspectorSessionTestPipeline())
    }

    @MainActor
    private func file(
        id: UUID = UUID(),
        name: String = "track.mp3",
        title: String = "Original",
        album: String = "",
        artist: String = ""
    ) -> AudioFile {
        AudioFileTestFactory.makeDisplayOnly(
            id: id,
            url: URL(fileURLWithPath: "/tmp/f3b/\(id.uuidString)-\(name)"),
            title: title
        )
    }

    @MainActor
    private func fullFile(
        id: UUID,
        name: String = "track.mp3",
        title: String = "Original",
        album: String = "",
        artist: String = ""
    ) -> AudioFile {
        AudioFileTestFactory.make(
            id: id,
            url: URL(fileURLWithPath: "/tmp/f3b/\(id.uuidString)-\(name)"),
            title: title,
            artist: artist,
            album: album,
            includeDefaultFileFingerprint: false
        )
    }

    // MARK: - Identity and generations

    @MainActor
    func testSelectionCreatesIdentityAndMutationsAdvanceEditGeneration() {
        let track = file()
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([track.id])

        guard let identity = vm.inspectorDraftIdentity else {
            return XCTFail("Expected a draft session identity")
        }
        XCTAssertEqual(identity.targetIDs, [track.id])
        XCTAssertNil(vm.inspectorPendingReview)

        vm.edit?.title = "Draft"
        let afterEdit = vm.inspectorDraftIdentity
        XCTAssertGreaterThan(afterEdit?.editGeneration ?? 0, identity.editGeneration)
        XCTAssertEqual(afterEdit?.artworkGeneration, identity.artworkGeneration)
    }

    @MainActor
    func testDirtyDraftAndOriginalBaselineSurvivePassiveRefresh() {
        let track = file()
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([track.id])
        vm.edit?.title = "Dirty"
        let originalBaseline = vm.inspectorDraft?.baselinesByID[track.id]?.snapshotID

        let refreshed = file(id: track.id, title: "Disk")
        vm.mergeQuickImportFiles([refreshed])

        XCTAssertEqual(vm.edit?.title, "Dirty")
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[track.id]?.snapshotID, originalBaseline)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testCleanDraftFollowsNewObservationOnPassiveRefresh() {
        let track = file()
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([track.id])

        vm.mergeQuickImportFiles([file(id: track.id, title: "Disk")])

        XCTAssertEqual(vm.edit?.title, "Disk")
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    // MARK: - Passive prune and pending review

    @MainActor
    func testDirtySingleSelectionPruneBecomesDetachedPendingReview() {
        let track = file()
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([track.id])
        vm.edit?.title = "Keep Me"

        vm.removeQuickImportFile(id: track.id)

        XCTAssertTrue(vm.selectedAudioIDs.isEmpty)
        XCTAssertNotNil(vm.inspectorPendingReview)
        XCTAssertEqual(vm.inspectorPendingReview?.unavailableTargetIDs, [track.id])
        XCTAssertEqual(vm.edit?.title, "Keep Me")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        XCTAssertTrue(vm.isInspectorSaveSuspended)
        XCTAssertFalse(vm.isInspectorPendingReviewResumable)
        XCTAssertEqual(vm.inspectorPendingReviewCapturedSummaries().first?.fileName,
                       track.url.lastPathComponent)
    }

    @MainActor
    func testPendingReviewResumesWhenCapturedTargetReturns() {
        let track = file()
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([track.id])
        vm.edit?.title = "Captured Draft"
        vm.removeQuickImportFile(id: track.id)
        XCTAssertNotNil(vm.inspectorPendingReview)

        vm.mergeQuickImportFiles([file(id: track.id)])
        XCTAssertTrue(vm.isInspectorPendingReviewResumable)
        XCTAssertTrue(vm.resumeInspectorPendingReview())

        XCTAssertNil(vm.inspectorPendingReview)
        XCTAssertEqual(vm.selectedAudioIDs, [track.id])
        XCTAssertEqual(vm.edit?.title, "Captured Draft")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testMultiPruneRetainsCapturedValuesWithoutTransferringToSurvivors() {
        let first = file(name: "first.mp3")
        let second = file(name: "second.mp3")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([first, second])
        vm.setSelectedAudioIDs([first.id, second.id])
        vm.multiEdit?.setText("Batch Album", for: .album)

        vm.removeQuickImportFile(id: first.id)

        XCTAssertEqual(vm.selectedAudioIDs, [second.id])
        XCTAssertEqual(vm.inspectorPendingReview?.capturedTargetIDs, [first.id, second.id])
        XCTAssertEqual(vm.inspectorPendingReview?.unavailableTargetIDs, [first.id])
        XCTAssertEqual(vm.multiEdit?.text(for: .album), "Batch Album")
        XCTAssertTrue(vm.isInspectorSaveSuspended)
        XCTAssertFalse(vm.isInspectorPendingReviewResumable)

        vm.discardInspectorPendingReview()
        XCTAssertNil(vm.inspectorPendingReview)
        XCTAssertNil(vm.multiEdit)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testExplicitSelectionTransitionReplacesSession() {
        let first = file(name: "first.mp3")
        let second = file(name: "second.mp3")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([first, second])
        vm.setSelectedAudioIDs([first.id])
        vm.edit?.title = "First Draft"
        let firstIdentity = vm.inspectorDraftIdentity

        vm.setSelectedAudioIDs([second.id])

        XCTAssertNotEqual(vm.inspectorDraftIdentity?.sessionID, firstIdentity?.sessionID)
        XCTAssertEqual(vm.edit?.title, "Original")
        XCTAssertNil(vm.inspectorPendingReview)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    // MARK: - Own-save capture and per-field delta baseline

    @MainActor
    func testCaptureFreezesIntentAndCompletionInheritsReadbackForUnchangedFields() {
        let id = UUID()
        let track = fullFile(id: id, title: "Original", artist: "Original Artist")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([id])
        vm.edit?.title = "Saved"

        guard let receipt = vm.captureInspectorSaveReceipt() else {
            return XCTFail("Expected a captured save receipt")
        }
        vm.edit?.title = "Newer"
        let readback = fullFile(id: id, title: "Saved", artist: "Disk Artist")
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(
                targetID: id,
                didRefreshFileModel: true,
                readback: readback
            )
        )
        vm.finishInspectorSave()

        XCTAssertEqual(receipt.submittedSingleEdit?.title, "Saved")
        XCTAssertEqual(vm.edit?.title, "Newer", "Newer typed intent must be reapplied")
        XCTAssertEqual(vm.edit?.artist, "Disk Artist", "Unchanged fields inherit the readback")
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[id]?.snapshotID, readback.snapshotID)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        XCTAssertNil(vm.inspectorDraft?.saveReceipt)
    }

    @MainActor
    func testCompletionKeepsIntentionalRevertToPreSaveValueDirty() {
        let id = UUID()
        let track = fullFile(id: id, title: "Original")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([id])
        vm.edit?.title = "Saved"
        _ = vm.captureInspectorSaveReceipt()
        // Deliberately revert to the pre-save value while the save is in flight.
        vm.edit?.title = "Original"

        let readback = fullFile(id: id, title: "Saved")
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: id, didRefreshFileModel: true, readback: readback)
        )
        vm.finishInspectorSave()

        XCTAssertEqual(vm.edit?.title, "Original")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[id]?.title, "Saved")
    }

    @MainActor
    func testSaveReceiptIsRejectedAfterSessionReplacement() {
        let id = UUID()
        let track = fullFile(id: id, title: "Original")
        let other = fullFile(id: UUID(), name: "other.mp3", title: "Other")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track, other])
        vm.setSelectedAudioIDs([id])
        vm.edit?.title = "Save Me"
        guard let staleReceipt = vm.captureInspectorSaveReceipt() else {
            return XCTFail("Expected a captured receipt")
        }

        vm.setSelectedAudioIDs([other.id])
        let newSessionID = vm.inspectorDraftIdentity?.sessionID
        let newBaseline = vm.inspectorDraft?.baselinesByID[other.id]?.snapshotID
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(
                targetID: id,
                didRefreshFileModel: true,
                readback: fullFile(id: id, title: "Save Me")
            )
        )
        vm.finishInspectorSave()

        XCTAssertNotEqual(staleReceipt.identity.sessionID, newSessionID)
        XCTAssertEqual(vm.inspectorDraftIdentity?.sessionID, newSessionID)
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[other.id]?.snapshotID, newBaseline)
        XCTAssertNil(vm.inspectorDraft?.baselinesByID[id])
    }

    @MainActor
    func testResumePendingReviewPreservesOriginalConflictBaselineAcrossSamePathReplacement() throws {
        let v1 = try XCTUnwrap(AudioFileTestFactory.fixtureFileVersion)
        let v2 = try XCTUnwrap(AudioFileTestFactory.secondaryFixtureFileVersion)
        XCTAssertNotEqual(v1, v2)

        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/f3-replacement.mp3")
        let original = AudioFileTestFactory.makeObserved(
            id: id,
            url: url,
            title: "Original V1",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: url, fileSize: 100),
            metadataFileVersion: v1
        )
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([original])
        vm.setSelectedAudioIDs([id])
        vm.edit?.title = "User Edit"
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[id]?.metadataFileVersion, v1)

        // Passive prune moves the dirty draft into pending review.
        vm.removeQuickImportFile(id: id)
        XCTAssertTrue(vm.hasInspectorPendingReview)

        // A different replacement file appears at the same path with the same
        // logical ID and a newer disk version V2.
        let replacement = AudioFileTestFactory.makeObserved(
            id: id,
            url: url,
            title: "Replacement V2",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: url, fileSize: 200),
            metadataFileVersion: v2
        )
        vm.mergeQuickImportFiles([replacement])
        XCTAssertTrue(vm.isInspectorPendingReviewResumable)
        XCTAssertTrue(vm.resumeInspectorPendingReview())

        // Original V1 conflict baseline MUST remain intact so Save routes
        // through MetadataConflictResolver rather than silently overwriting V2.
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[id]?.metadataFileVersion, v1)
        XCTAssertEqual(vm.inspectorEditSourceFilesByID[id]?.metadataFileVersion, v1)
        XCTAssertEqual(vm.edit?.title, "User Edit")
    }

    @MainActor
    func testSingleFileSavePreservesIntentionalRevertAcrossImmediateReload() {
        let id = UUID()
        let original = fullFile(id: id, title: "Original")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([original])
        vm.setSelectedAudioIDs([id])
        vm.edit?.title = "Submitted"
        guard vm.captureInspectorSaveReceipt() != nil else {
            return XCTFail("Expected a captured single-file save receipt")
        }

        // User intentionally reverts to the pre-save value while save is in flight.
        vm.edit?.title = "Original"

        // Immediate reload publication runs rebuildVisibleFiles() BEFORE
        // recordInspectorSaveTargetCompletion; it must NOT wipe the revert.
        let reloaded = fullFile(id: id, title: "Submitted")
        _ = vm.replaceLoadedFile(
            reloaded,
            refreshGeneration: vm.makeFileModelRefreshGeneration(),
            deferVisibleRefresh: false
        )
        XCTAssertEqual(vm.edit?.title, "Original", "Immediate reload during in-flight save must not overwrite a post-submit revert")

        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: id, didRefreshFileModel: true, readback: reloaded)
        )
        vm.finishInspectorSave()

        XCTAssertEqual(vm.edit?.title, "Original")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[id]?.title, "Submitted")
    }

    @MainActor
    func testMultiFileSaveCancelledDirectoryPromptReleasesSaveReceipt() throws {
        let version = try XCTUnwrap(AudioFileTestFactory.fixtureFileVersion)
        let firstURL = URL(fileURLWithPath: "/tmp/f3-cancel-prompt/m1.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/f3-cancel-prompt/m2.mp3")
        let first = AudioFileTestFactory.makeObserved(
            id: UUID(),
            url: firstURL,
            title: "First",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: firstURL, fileSize: 100),
            metadataFileVersion: version
        )
        let second = AudioFileTestFactory.makeObserved(
            id: UUID(),
            url: secondURL,
            title: "Second",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: secondURL, fileSize: 100),
            metadataFileVersion: version
        )
        let suiteName = "AudioMatorTests.CancelPrompt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InspectorDraftJournal-\(UUID().uuidString)", isDirectory: true)
        let vm = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: InspectorSessionTestPipeline(requiresTransactionalDirectoryAccess: true),
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: defaults,
            renameJournalStore: LocalRenameJournalStore(directoryURL: journalDirectory),
            renameJournalAutoClassification: false,
            quickImportEnvironment: QuickImportEnvironment(
                identityProvider: FileSystemQuickImportPathIdentityProvider(),
                scopeAccess: DeniedQuickImportScopeAccess(),
                loadPolicy: .production
            )
        )
        vm.mergeQuickImportFiles([first, second])
        vm.setSelectedAudioIDs([first.id, second.id])
        vm.multiEdit?.setText("Updated Album", for: .album)
        var promptCount = 0
        vm.mutationDirectoryAccessRequester = { _ in
            promptCount += 1
            return "Access denied."
        }

        vm.saveMultiFileEdits()

        XCTAssertEqual(promptCount, 1, "Multi-file save should have reached the directory access prompt")
        XCTAssertEqual(vm.inspectorDraft?.isSaveInFlight, false, "Cancelled folder prompt must clear saveReceipt via finishInspectorSave")
        XCTAssertFalse(vm.isInspectorSaveSuspended)
        XCTAssertNotNil(vm.beginArtworkCommand(for: [first.id, second.id]))
    }

    @MainActor
    func testMultiFileSaveFullCompletionReappliesReadbackAndResetsArtworkAction() {
        let firstID = UUID()
        let secondID = UUID()
        let first = fullFile(id: firstID, name: "b1.mp3", title: "First")
        let second = fullFile(id: secondID, name: "b2.mp3", title: "Second")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([first, second])
        vm.setSelectedAudioIDs([firstID, secondID])
        vm.multiEdit?.setText("Saved Album", for: .album)
        vm.multiEdit?.artworkEditAction = .remove
        guard vm.captureInspectorSaveReceipt() != nil else {
            return XCTFail("Expected a captured multi receipt")
        }

        let firstReadback = fullFile(id: firstID, name: "b1.mp3", title: "First", album: "Saved Album")
        let secondReadback = fullFile(id: secondID, name: "b2.mp3", title: "Second", album: "Saved Album")
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: firstID, didRefreshFileModel: true, readback: firstReadback)
        )
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: secondID, didRefreshFileModel: true, readback: secondReadback)
        )
        vm.finishInspectorSave(didCompleteAllMultiTargets: true)

        XCTAssertEqual(vm.multiEdit?.artworkEditAction, .unchanged, "Completed multi-file save must reset staged artwork action")
        XCTAssertTrue(vm.completedInspectorEditsByID.isEmpty)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testPassiveCleanRefreshPreservesInFlightArtworkCommandGeneration() {
        let id = UUID()
        let original = fullFile(id: id, title: "Original")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([original])
        vm.setSelectedAudioIDs([id])

        guard let artworkToken = vm.beginArtworkCommand(for: [id]) else {
            return XCTFail("Expected an artwork command token")
        }
        // A clean passive refresh (e.g., watched-folder reload) updates display
        // baselines without invalidating an in-flight artwork handoff.
        vm.refreshInspectorDraftAfterAcceptedPublication()
        XCTAssertTrue(
            vm.isCurrentArtworkCommand(artworkToken),
            "Passive clean refresh must not bump artworkGeneration and kill an in-flight artwork handoff"
        )
    }

    @MainActor
    func testPartialBatchLedgerOnlyExcludesCompletedTargets() {
        let firstID = UUID()
        let secondID = UUID()
        let first = fullFile(id: firstID, name: "first.mp3", title: "First")
        let second = fullFile(id: secondID, name: "second.mp3", title: "Second")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([first, second])
        vm.setSelectedAudioIDs([firstID, secondID])
        vm.multiEdit?.setText("Batch Album", for: .album)
        guard vm.captureInspectorSaveReceipt() != nil else {
            return XCTFail("Expected a captured multi receipt")
        }

        let firstReadback = fullFile(id: firstID, name: "first.mp3", title: "First", album: "Batch Album")
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: firstID, didRefreshFileModel: true, readback: firstReadback)
        )
        XCTAssertNotNil(vm.completedInspectorEditsByID[firstID])
        XCTAssertNil(vm.completedInspectorEditsByID[secondID])
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)

        let secondReadback = fullFile(id: secondID, name: "second.mp3", title: "Second", album: "Batch Album")
        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: secondID, didRefreshFileModel: true, readback: secondReadback)
        )
        vm.finishInspectorSave()

        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testUnverifiedReadbackDoesNotFabricateBaseline() {
        let id = UUID()
        let track = fullFile(id: id, title: "Original")
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([id])
        vm.edit?.title = "Save Me"
        _ = vm.captureInspectorSaveReceipt()
        let baselineBefore = vm.inspectorDraft?.baselinesByID[id]?.snapshotID

        vm.recordInspectorSaveTargetCompletion(
            InspectorSavedTargetOutcome(targetID: id, didRefreshFileModel: false, readback: nil)
        )
        vm.finishInspectorSave()

        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[id]?.snapshotID, baselineBefore)
        XCTAssertEqual(vm.edit?.title, "Save Me")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
    }

    // MARK: - Artwork command generation

    @MainActor
    func testArtworkCommandGenerationIsIndependentOfEditGeneration() {
        let track = file()
        let vm = makeViewModel()
        vm.mergeQuickImportFiles([track])
        vm.setSelectedAudioIDs([track.id])

        guard let firstToken = vm.beginArtworkCommand() else {
            return XCTFail("Expected an artwork command token")
        }
        vm.edit?.title = "Text edit"
        XCTAssertTrue(vm.isCurrentArtworkCommand(firstToken))

        guard let secondToken = vm.beginArtworkCommand() else {
            return XCTFail("Expected a second artwork command token")
        }
        XCTAssertFalse(vm.isCurrentArtworkCommand(firstToken))
        XCTAssertTrue(vm.isCurrentArtworkCommand(secondToken))
        XCTAssertTrue(vm.completeArtworkHandoff(secondToken, action: .remove))
        XCTAssertEqual(vm.edit?.artworkEditAction, .remove)
    }
}

private nonisolated struct DeniedQuickImportScopeAccess: QuickImportScopeAccessing {
    nonisolated func startAccessingScope(for url: URL) -> Bool { false }
    nonisolated func stopAccessingScope(for url: URL) {}
}

private final class InspectorSessionTestPipeline: AudioMetadataPipeline, @unchecked Sendable {
    nonisolated let requiresTransactionalDirectoryAccess: Bool

    nonisolated init(requiresTransactionalDirectoryAccess: Bool = false) {
        self.requiresTransactionalDirectoryAccess = requiresTransactionalDirectoryAccess
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try TagLibAudioMetadataPipeline().projectMetadataWrite(intent, fileExtension: fileExtension)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult { AudioMetadataWriteResult(warnings: []) }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult { AudioMetadataWriteResult(warnings: []) }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult { AudioMetadataWriteResult(warnings: []) }
}
#endif
