import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
/// F3 raw Metadata Editor session/apply ownership tests.
///
/// These cover store-owned presentation/apply/load identity, repeated-open
/// decisions, explicit close/cancel ownership, applying-close cancellation with
/// a preserved app-owned outcome, partial-success application scoped to the
/// captured session targets, and stale same-ID completion suppression.
@MainActor
final class MetadataEditorSessionTests: XCTestCase {
    // MARK: - Repeated open decision matrix

    func testOpenDecisionFocusesLivePresentationAndOnlyConfirmsBeforeDiscard() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-01.mp3"), title: "First")
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-open-02.mp3"), title: "Second")
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())

        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()

        let presentationID = try requiredPresentationID(of: store)
        XCTAssertEqual(store.openDecision(for: [first.id]), .focusExisting(presentationID: presentationID))
        XCTAssertEqual(
            store.openDecision(for: [second.id]),
            .presentNew,
            "A clean live session can be replaced without a discard decision"
        )

        store.upsertField(key: "TITLE", value: "Dirty Draft")

        XCTAssertEqual(
            store.openDecision(for: [first.id]),
            .focusExisting(presentationID: presentationID),
            "A repeated open for the same targets must focus, never reset"
        )
        XCTAssertEqual(
            store.openDecision(for: [second.id]),
            .confirmDiscardAndOpen(presentationID: presentationID),
            "A different target selection needs a deliberate discard decision"
        )
        XCTAssertEqual(store.targets.map(\.id), [first.id])
        XCTAssertEqual(store.draftPropertyMaps[first.id]?["TITLE"], ["Dirty Draft"])
        XCTAssertEqual(try requiredPresentationID(of: store), presentationID)
    }

    func testRepeatedOpenDoesNotResetDirtyDraftEvenThoughPresentWould() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-reopen.mp3"), title: "Original")
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Keep Me")
        let presentationID = try requiredPresentationID(of: store)
        let draftGeneration = store.draftGeneration

        // The repeated open path is only a decision; the window raises itself.
        XCTAssertEqual(store.openDecision(for: [file.id]), .focusExisting(presentationID: presentationID))
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Keep Me"])
        XCTAssertEqual(store.draftGeneration, draftGeneration)
        XCTAssertEqual(store.targets.map(\.id), [file.id])
    }

    func testDiscardAndOpenRejectsStaleConfirmationAndStartsFreshSession() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-discard-01.mp3"))
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-discard-02.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Pending")
        let originalPresentationID = try requiredPresentationID(of: store)

        XCTAssertFalse(
            store.discardAndOpen(targetFiles: [second], sessionID: MetadataEditorPresentationID()),
            "A stale confirmation must not discard a newer/current draft"
        )
        XCTAssertEqual(store.draftPropertyMaps[first.id]?["TITLE"], ["Pending"])
        XCTAssertEqual(try requiredPresentationID(of: store), originalPresentationID)

        XCTAssertTrue(store.discardAndOpen(targetFiles: [second], sessionID: originalPresentationID))
        XCTAssertNotEqual(try requiredPresentationID(of: store), originalPresentationID)
        try await waitUntilLoaded(store)
        XCTAssertEqual(store.targets.map(\.id), [second.id])
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    // MARK: - Apply capture and partial success

    func testApplyCapturesFrozenMapsAndRemovesOnlyCapturedSuccessfulTargets() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/f3-apply-01.mp3"), title: "First"
        )
        let second = AudioFileTestFactory.makeDisplayOnly(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/f3-apply-02.mp3"), title: "Second"
        )
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [first, second])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "ALBUM", value: "Draft Album")

        let request = try XCTUnwrap(store.startApply())
        XCTAssertEqual(request.pendingTargets.map(\.id), [first.id, second.id])
        XCTAssertEqual(request.submittedPropertyMaps[first.id]?["ALBUM"], ["Draft Album"])
        XCTAssertEqual(store.draftGeneration, request.draftGeneration)

        let firstResult = store.makeApplyOutcome(
            from: RawMetadataApplyResult(
                succeededTargetIDs: [first.id],
                failedTargetIDs: [second.id]
            ),
            for: request
        )
        XCTAssertEqual(store.completeApply(firstResult), .remainReady)

        XCTAssertEqual(store.targets.map(\.id), [second.id], "Only the captured successful target is removed")
        XCTAssertEqual(store.pendingTargets.map(\.id), [second.id])
        XCTAssertEqual(store.draftPropertyMaps[second.id]?["ALBUM"], ["Draft Album"])
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertTrue(store.canStartApply)

        let retryRequest = try XCTUnwrap(store.startApply())
        XCTAssertEqual(retryRequest.pendingTargets.map(\.id), [second.id])
        let retryResult = store.makeApplyOutcome(
            from: RawMetadataApplyResult(succeededTargetIDs: [second.id], failedTargetIDs: []),
            for: retryRequest
        )
        XCTAssertEqual(store.completeApply(retryResult), .dismiss)
        XCTAssertTrue(store.targets.isEmpty)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testNewerDraftEditDuringApplyIsPreservedAndSuppressesAutoDismiss() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-newer.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Submitted")

        let request = try XCTUnwrap(store.startApply())
        let capturedGeneration = store.draftGeneration
        store.upsertField(key: "COMMENT", value: "Newer edit")
        XCTAssertGreaterThan(store.draftGeneration, capturedGeneration)

        let outcome = store.makeApplyOutcome(
            from: RawMetadataApplyResult(succeededTargetIDs: [file.id], failedTargetIDs: []),
            for: request
        )
        XCTAssertEqual(
            store.completeApply(outcome),
            .remainReady,
            "A completion must not dismiss when the live draft changed after capture"
        )
        XCTAssertEqual(store.lastApplyOutcome?.presentationID, request.presentationID)
        XCTAssertEqual(store.suppressedStaleCompletionCount, 0)
    }

    // MARK: - Stale same-ID completion suppression

    func testStaleCompletionForSameIDsCannotMutateNewerPresentation() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-stale-01.mp3"), title: "First")
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-stale-02.mp3"), title: "Second")
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [first, second])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Session One Draft")

        let staleRequest = try XCTUnwrap(store.startApply())
        store.windowWillClose(presentationID: staleRequest.presentationID)
        XCTAssertTrue(store.isDrainingApply)

        // Reopen for the same IDs while the cancelled apply drains.
        store.presentNew(targetFiles: [first, second])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        let currentPresentationID = try requiredPresentationID(of: store)
        store.upsertField(key: "TITLE", value: "Session Two Draft")
        XCTAssertFalse(store.canStartApply)

        let staleOutcome = store.makeApplyOutcome(
            from: RawMetadataApplyResult(
                succeededTargetIDs: [first.id, second.id],
                failedTargetIDs: []
            ),
            for: staleRequest
        )
        XCTAssertEqual(store.completeApply(staleOutcome), .sessionClosed)
        XCTAssertFalse(store.isDrainingApply)
        XCTAssertEqual(try requiredPresentationID(of: store), currentPresentationID)
        XCTAssertEqual(store.targets.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.draftPropertyMaps[first.id]?["TITLE"], ["Session Two Draft"])
        XCTAssertEqual(store.lastApplyOutcome?.applyID, staleRequest.applyID)
        XCTAssertTrue(store.canStartApply)
    }

    func testCompletionFromSupersededPresentationIsCountedAndIgnored() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-superseded.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Draft")
        let request = try XCTUnwrap(store.startApply())

        store.presentNew(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        let currentPresentationID = try requiredPresentationID(of: store)

        let outcome = store.makeApplyOutcome(
            from: RawMetadataApplyResult(succeededTargetIDs: [file.id], failedTargetIDs: []),
            for: request
        )
        XCTAssertEqual(store.completeApply(outcome), .sessionClosed)
        XCTAssertEqual(store.suppressedStaleCompletionCount, 1)
        XCTAssertEqual(try requiredPresentationID(of: store), currentPresentationID)
        XCTAssertEqual(store.targets.map(\.id), [file.id])
    }

    // MARK: - Explicit close/cancel ownership

    func testCloseDuringApplyCancelsTaskAndPreservesAppOwnedOutcome() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-apply-close.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Draft")
        let request = try XCTUnwrap(store.startApply())
        let presentationID = request.presentationID

        let taskWasCancelled = expectation(description: "apply task cancelled")
        let applyTask = Task { @MainActor in
            while !Task.isCancelled {
                await Task.yield()
            }
            taskWasCancelled.fulfill()
        }
        store.attachApplyTask(applyTask)

        store.windowWillClose(presentationID: presentationID)
        await fulfillment(of: [taskWasCancelled], timeout: 2)
        XCTAssertNil(store.currentPresentationID)
        XCTAssertTrue(store.isDrainingApply)
        XCTAssertFalse(store.isApplying)

        // The cancelled apply's real outcome is still recorded as app-owned state.
        let outcome = store.makeApplyOutcome(
            from: RawMetadataApplyResult(succeededTargetIDs: [file.id], failedTargetIDs: []),
            for: request
        )
        XCTAssertEqual(store.completeApply(outcome), .sessionClosed)
        XCTAssertFalse(store.isDrainingApply)
        XCTAssertEqual(store.lastApplyOutcome?.succeededTargetIDs, [file.id])
        XCTAssertNil(store.currentPresentationID)
    }

    func testReopenWhileDrainingCanPrepareDataButCannotApplyUntilDrainCompletes() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-drain.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Closed Draft")
        let oldRequest = try XCTUnwrap(store.startApply())
        store.windowWillClose(presentationID: oldRequest.presentationID)
        XCTAssertTrue(store.isDrainingApply)

        store.presentNew(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        XCTAssertTrue(store.targets.map(\.id) == [file.id])
        store.upsertField(key: "TITLE", value: "Prepared While Draining")
        XCTAssertFalse(store.canStartApply)
        XCTAssertNil(store.startApply(), "A reopened window cannot admit a second raw write while draining")

        let oldOutcome = store.makeApplyOutcome(
            from: RawMetadataApplyResult(succeededTargetIDs: [file.id], failedTargetIDs: []),
            for: oldRequest
        )
        XCTAssertEqual(store.completeApply(oldOutcome), .sessionClosed)
        XCTAssertFalse(store.isDrainingApply)
        XCTAssertEqual(store.targets.map(\.id), [file.id])
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["TITLE"], ["Prepared While Draining"])
        XCTAssertTrue(store.canStartApply)
    }

    func testIdleCloseDiscardsDraftAndSupersededCloseCannotClearNewerSession() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-idle-01.mp3"))
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-idle-02.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Discarded By Close")
        let closedPresentationID = try requiredPresentationID(of: store)

        store.windowWillClose(presentationID: closedPresentationID)
        XCTAssertNil(store.currentPresentationID)
        XCTAssertTrue(store.targets.isEmpty)
        XCTAssertFalse(store.hasUnsavedChanges)

        store.presentNew(targetFiles: [second])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        let newerPresentationID = try requiredPresentationID(of: store)
        store.upsertField(key: "TITLE", value: "Newer Session")

        // A delayed close notification carrying the old identity must be ignored.
        store.windowWillClose(presentationID: closedPresentationID)
        XCTAssertEqual(try requiredPresentationID(of: store), newerPresentationID)
        XCTAssertEqual(store.targets.map(\.id), [second.id])
        XCTAssertEqual(store.draftPropertyMaps[second.id]?["TITLE"], ["Newer Session"])

        store.windowWillClose(presentationID: newerPresentationID)
        XCTAssertNil(store.currentPresentationID)
        XCTAssertTrue(store.targets.isEmpty)
    }

    func testCancelAndCloseIsExplicitDiscardAndIsRefusedWhileApplying() async throws {
        let file = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-cancel.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())
        store.present(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Cancel Me")

        store.cancelAndClose()
        XCTAssertNil(store.currentPresentationID)
        XCTAssertTrue(store.targets.isEmpty)
        XCTAssertFalse(store.hasUnsavedChanges)

        store.presentNew(targetFiles: [file])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        store.upsertField(key: "TITLE", value: "Applying")
        _ = store.startApply()
        let presentationID = try requiredPresentationID(of: store)
        store.cancelAndClose()
        XCTAssertTrue(
            store.isApplying,
            "The store must keep the presenting session while an apply is in flight"
        )
        XCTAssertEqual(try requiredPresentationID(of: store), presentationID)
    }

    // MARK: - Load identity and generations

    func testStaleDetachedLoadCannotPublishAfterNewPresentation() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-load-01.mp3"), title: "First")
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-load-02.mp3"), title: "Second")
        let firstGate = SessionLoadGate()
        let secondGate = SessionLoadGate()
        let pipeline = SessionMockPipeline(loadGates: [
            first.url: firstGate,
            second.url: secondGate
        ])
        let store = MetadataEditorStore(metadataPipeline: pipeline)

        store.present(targetFiles: [first])
        XCTAssertTrue(firstGate.waitUntilStarted())
        store.presentNew(targetFiles: [second])
        XCTAssertTrue(secondGate.waitUntilStarted())

        firstGate.open()
        secondGate.open()
        try await waitUntilLoaded(store)

        XCTAssertEqual(store.targets.map(\.id), [second.id])
        XCTAssertEqual(store.originalPropertyMaps.keys.sorted(by: { $0.uuidString < $1.uuidString }),
                       [second.id].sorted(by: { $0.uuidString < $1.uuidString }))
        XCTAssertTrue(store.originalPropertyMaps[first.id] == nil)
    }

    func testLoadAndDraftGenerationsAreMonotonic() async throws {
        let first = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-gen-01.mp3"))
        let second = AudioFileTestFactory.makeDisplayOnly(url: URL(fileURLWithPath: "/tmp/f3-gen-02.mp3"))
        let store = MetadataEditorStore(metadataPipeline: SessionMockPipeline())

        store.present(targetFiles: [first])
        try await waitUntilLoaded(store)
        store.windowDidAppear()
        let generationAfterFirstLoad = store.draftGeneration

        store.upsertField(key: "TITLE", value: "One")
        let afterUpsert = store.draftGeneration
        XCTAssertGreaterThan(afterUpsert, generationAfterFirstLoad)

        store.deleteField(named: "TITLE")
        let afterDelete = store.draftGeneration
        XCTAssertGreaterThan(afterDelete, afterUpsert)

        store.discardChanges()
        XCTAssertGreaterThan(store.draftGeneration, afterDelete)

        let firstPresentationID = try requiredPresentationID(of: store)
        store.presentNew(targetFiles: [second])
        XCTAssertNotEqual(try requiredPresentationID(of: store), firstPresentationID)
        XCTAssertGreaterThan(store.draftGeneration, afterDelete)
        try await waitUntilLoaded(store)
    }

    // MARK: - Helpers

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

// MARK: - Fixtures

private final class SessionMockPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let propertyMapsByURL: [URL: [String: String]]
    private let loadGates: [URL: SessionLoadGate]

    init(
        propertyMapsByURL: [URL: [String: String]] = [:],
        loadGates: [URL: SessionLoadGate] = [:]
    ) {
        self.propertyMapsByURL = propertyMapsByURL
        self.loadGates = loadGates
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await AudioFileTestFactory.make(id: id, url: url, includeDefaultFileFingerprint: false)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        loadGates[url]?.blockLoadUntilOpened()
        return (propertyMapsByURL[url] ?? [:]).mapValues { [$0] }
    }

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

/// A synchronous load gate used to hold the store's detached metadata read.
///
/// The store loads display-only targets through `rawMetadataValueMap` on a
/// detached worker, so the gate blocks that worker (never the main actor) and
/// signals the test when the read has started.
private final class SessionLoadGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let opened = DispatchSemaphore(value: 0)

    func blockLoadUntilOpened() {
        started.signal()
        _ = opened.wait(timeout: .now() + 10)
    }

    @discardableResult
    func waitUntilStarted(timeout: TimeInterval = 3) -> Bool {
        started.wait(timeout: .now() + timeout) == .success
    }

    func open() {
        opened.signal()
    }
}
#endif
