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

        XCTAssertEqual(staleReceipt.identity.sessionID,
                       staleReceipt.identity.sessionID)
        XCTAssertEqual(vm.inspectorDraftIdentity?.sessionID, newSessionID)
        XCTAssertEqual(vm.inspectorDraft?.baselinesByID[other.id]?.snapshotID, newBaseline)
        XCTAssertNil(vm.inspectorDraft?.baselinesByID[id])
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

private final class InspectorSessionTestPipeline: AudioMetadataPipeline, @unchecked Sendable {
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
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
