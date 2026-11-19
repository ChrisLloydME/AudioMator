import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
/// F3 ContentView raw-editor open routing tests.
///
/// The window side effects live in `MetadataEditorOpener`, which ContentView's
/// `openMetadataEditor` funnels every programmatic open through. These tests
/// exercise the decision matrix against a real `MetadataEditorStore` without
/// AppKit window presentation.
@MainActor
final class MetadataEditorOpenDecisionTests: XCTestCase {
    func testFocusExistingRaisesWindowWithoutResettingLiveDraft() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-focus.mp3"), title: "Original")
        let store = MetadataEditorStore(metadataPipeline: OpenDecisionTestPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Live Draft")
        let presentationID = try requiredPresentationID(of: store)

        var didRequestDiscardConfirmation = false
        let outcome = await MetadataEditorOpener.open(
            store: store,
            targetFiles: [file],
            decision: store.openDecision(for: [file.id]),
            confirmDiscard: { _ in
                didRequestDiscardConfirmation = true
                return true
            }
        )

        XCTAssertEqual(outcome, .focusExisting)
        XCTAssertFalse(didRequestDiscardConfirmation, "Focusing must not ask to discard anything")
        XCTAssertEqual(try requiredPresentationID(of: store), presentationID)
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Live Draft"])
        XCTAssertEqual(store.targets.map(\.id), [file.id])
    }

    func testPresentNewForCleanDifferentTargetsStartsNewSession() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-first.mp3"))
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-second.mp3"))
        let store = MetadataEditorStore(metadataPipeline: OpenDecisionTestPipeline())
        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        let originalPresentationID = try requiredPresentationID(of: store)

        var didRequestDiscardConfirmation = false
        let outcome = await MetadataEditorOpener.open(
            store: store,
            targetFiles: [second],
            decision: store.openDecision(for: [second.id]),
            confirmDiscard: { _ in
                didRequestDiscardConfirmation = true
                return true
            }
        )
        try await waitUntilLoaded(store)

        XCTAssertEqual(outcome, .presentedNew)
        XCTAssertFalse(didRequestDiscardConfirmation)
        XCTAssertNotEqual(try requiredPresentationID(of: store), originalPresentationID)
        XCTAssertEqual(store.targets.map(\.id), [second.id])
    }

    func testDiscardDeclinedLeavesCurrentDraftAndTargetsUntouched() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-decline-01.mp3"))
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-decline-02.mp3"))
        let store = MetadataEditorStore(metadataPipeline: OpenDecisionTestPipeline())
        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Keep This Draft")
        let presentationID = try requiredPresentationID(of: store)

        var confirmedPresentationID: MetadataEditorPresentationID?
        let outcome = await MetadataEditorOpener.open(
            store: store,
            targetFiles: [second],
            decision: store.openDecision(for: [second.id]),
            confirmDiscard: { sessionID in
                confirmedPresentationID = sessionID
                return false
            }
        )

        XCTAssertEqual(outcome, .discardDeclined)
        XCTAssertEqual(confirmedPresentationID, presentationID)
        XCTAssertEqual(try requiredPresentationID(of: store), presentationID)
        XCTAssertEqual(store.targets.map(\.id), [first.id])
        XCTAssertEqual(store.draftPropertyMaps[first.id]?["TITLE"], ["Keep This Draft"])
    }

    func testDiscardConfirmedStartsNewSessionForRequestedTargets() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-confirm-01.mp3"))
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-confirm-02.mp3"))
        let store = MetadataEditorStore(metadataPipeline: OpenDecisionTestPipeline())
        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Discard Me")
        let originalPresentationID = try requiredPresentationID(of: store)

        let outcome = await MetadataEditorOpener.open(
            store: store,
            targetFiles: [second],
            decision: store.openDecision(for: [second.id]),
            confirmDiscard: { sessionID in
                sessionID == originalPresentationID
            }
        )
        try await waitUntilLoaded(store)

        XCTAssertEqual(outcome, .presentedNew)
        XCTAssertNotEqual(try requiredPresentationID(of: store), originalPresentationID)
        XCTAssertEqual(store.targets.map(\.id), [second.id])
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testSessionChangeWhileConfirmingIsStaleAndNeverDiscardsNewerDraft() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-stale-01.mp3"))
        let requested = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-stale-02.mp3"))
        let newer = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-stale-03.mp3"))
        let store = MetadataEditorStore(metadataPipeline: OpenDecisionTestPipeline())
        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Original Session Draft")
        let originalPresentationID = try requiredPresentationID(of: store)
        let decision = store.openDecision(for: [requested.id])
        XCTAssertEqual(decision, .confirmDiscardAndOpen(presentationID: originalPresentationID))

        let outcome = await MetadataEditorOpener.open(
            store: store,
            targetFiles: [requested],
            decision: decision,
            confirmDiscard: { _ in
                // A newer session replaces the draft while the alert is pending.
                store.presentNew(targetFiles: [newer])
                return true
            }
        )
        try await waitUntilLoaded(store)

        XCTAssertEqual(outcome, .staleConfirmation)
        XCTAssertEqual(store.targets.map(\.id), [newer.id])
        XCTAssertNotEqual(try requiredPresentationID(of: store), originalPresentationID)
        XCTAssertNil(store.draftPropertyMaps[first.id])
    }

    func testPresentWhileDrainingLoadsForInspectionButCannotApply() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-draining.mp3"))
        let store = MetadataEditorStore(metadataPipeline: OpenDecisionTestPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Closed By Apply")
        let closedRequest = try XCTUnwrap(store.startApply())
        store.windowWillClose(presentationID: closedRequest.presentationID)
        XCTAssertTrue(store.isDrainingApply)

        let decision = store.openDecision(for: [file.id])
        guard case .presentWhileDraining = decision else {
            return XCTFail("Expected presentWhileDraining, got \(decision)")
        }

        let outcome = await MetadataEditorOpener.open(
            store: store,
            targetFiles: [file],
            decision: decision,
            confirmDiscard: { _ in
                XCTFail("A draining presentation must not ask to discard a draft")
                return false
            }
        )
        try await waitUntilLoaded(store)

        XCTAssertEqual(outcome, .presentedWhileDraining)
        XCTAssertTrue(store.isDrainingApply)
        XCTAssertFalse(store.canStartApply)
        XCTAssertNil(store.startApply())
        XCTAssertEqual(store.targets.map(\.id), [file.id])

        let drainedOutcome = store.makeApplyOutcome(
            from: RawMetadataApplyResult(succeededTargetIDs: [file.id], failedTargetIDs: []),
            for: closedRequest
        )
        XCTAssertEqual(store.completeApply(drainedOutcome), .sessionClosed)
        XCTAssertFalse(store.isDrainingApply)
        XCTAssertTrue(store.canStartApply)
    }

    private func requiredPresentationID(
        of store: MetadataEditorStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> MetadataEditorPresentationID {
        try XCTUnwrap(store.currentPresentationID, "Expected an active presentation", file: file, line: line)
    }

    private func waitUntilLoaded(
        _ store: MetadataEditorStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.isLoading, "Timed out waiting for metadata editor load", file: file, line: line)
    }
}

private final class OpenDecisionTestPipeline: AudioMetadataPipeline, @unchecked Sendable {
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
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
}
#endif
