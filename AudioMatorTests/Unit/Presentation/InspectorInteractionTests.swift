import AppKit
import SwiftUI
import XCTest
@testable import AudioMator

nonisolated final class InspectorInteractionTests: XCTestCase {
    @MainActor
    func testTrackpadVerticalAndMostlyVerticalScrollForwardsToParentOverOverflowingValue() {
        var router = InspectorValueScrollRouter()

        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .began, momentumPhase: [], currentOffsetX: 120, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0.4, deltaY: -12, hasPreciseScrollingDeltas: true,
                phase: .changed, momentumPhase: [], currentOffsetX: 120, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(router.axisLatch, .vertical)

        // Once latched vertical, even a horizontal-leaning jitter tick stays forwarded to parent.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 4, deltaY: -1, hasPreciseScrollingDeltas: true,
                phase: .changed, momentumPhase: [], currentOffsetX: 120, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .ended, momentumPhase: [], currentOffsetX: 120, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0.2, deltaY: -8, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: .changed, currentOffsetX: 120, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: .ended, currentOffsetX: 120, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(router.axisLatch, .undecided)
    }

    @MainActor
    func testTrackpadHorizontalScrollLatchesThroughEdgesAndMomentumAndBalancesParentBegin() {
        var router = InspectorValueScrollRouter()

        // Zero-delta .began is forwarded to parent so vertical gestures stay native.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .began, momentumPhase: [], currentOffsetX: 20, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertTrue(router.didForwardPreciseBeginToParent)

        // Mostly horizontal swipe latches .horizontal and pans by deltaX only.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 15, deltaY: 3, hasPreciseScrollingDeltas: true,
                phase: .changed, momentumPhase: [], currentOffsetX: 20, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 5)
        )
        XCTAssertEqual(router.axisLatch, .horizontal)

        // Reaching left edge clamps cleanly to 0; further ticks at edge are consumed (no vertical spill).
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 15, deltaY: 2, hasPreciseScrollingDeltas: true,
                phase: .changed, momentumPhase: [], currentOffsetX: 5, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 0)
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 10, deltaY: 4, hasPreciseScrollingDeltas: true,
                phase: .changed, momentumPhase: [], currentOffsetX: 0, maxOffsetX: 200
            )),
            .consume
        )

        // Zero-delta .ended closes the earlier forwarded .began while keeping horizontal latch for momentum.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .ended, momentumPhase: [], currentOffsetX: 0, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertFalse(router.didForwardPreciseBeginToParent)
        XCTAssertEqual(router.axisLatch, .horizontal)

        // Momentum at the edge stays consumed until momentum ends.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 8, deltaY: 2, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: .changed, currentOffsetX: 0, maxOffsetX: 200
            )),
            .consume
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: .ended, currentOffsetX: 0, maxOffsetX: 200
            )),
            .consume
        )
        XCTAssertEqual(router.axisLatch, .undecided)
    }

    @MainActor
    func testMouseWheelPreservesHorizontalLongValueAccessAndHandsOffAtEdges() {
        var router = InspectorValueScrollRouter()

        // Short value always hands off immediately.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 1, hasPreciseScrollingDeltas: false,
                phase: [], momentumPhase: [], currentOffsetX: 0, maxOffsetX: 0
            )),
            .forwardToParent
        )

        // Overflowing value: vertical mouse wheel pans horizontally by deltaY * 12.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 1, hasPreciseScrollingDeltas: false,
                phase: [], momentumPhase: [], currentOffsetX: 200, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 188)
        )

        // At trailing edge scrolling further past edge hands off directly to outer vertical ScrollView.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: -1, hasPreciseScrollingDeltas: false,
                phase: [], momentumPhase: [], currentOffsetX: 200, maxOffsetX: 200
            )),
            .forwardToParent
        )

        // At leading edge scrolling further past edge hands off directly to outer vertical ScrollView.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 1, hasPreciseScrollingDeltas: false,
                phase: [], momentumPhase: [], currentOffsetX: 0, maxOffsetX: 200
            )),
            .forwardToParent
        )

        // Pure horizontal/Shift+wheel pans horizontally and consumes at edge without leaking vertically.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 1, deltaY: 0, hasPreciseScrollingDeltas: false,
                phase: [], momentumPhase: [], currentOffsetX: 100, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 88)
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 1, deltaY: 0, hasPreciseScrollingDeltas: false,
                phase: [], momentumPhase: [], currentOffsetX: 0, maxOffsetX: 200
            )),
            .consume
        )
    }

    @MainActor
    func testPhaselessPreciseScrollDoesNotStickInStaleLatch() {
        var router = InspectorValueScrollRouter()

        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 10, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: [], currentOffsetX: 100, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 90)
        )
        // Smaller vertical scroll after larger horizontal scroll must still forward cleanly.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: -5, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: [], currentOffsetX: 90, maxOffsetX: 200
            )),
            .forwardToParent
        )
        // Sub-2pt phaseless vertical delta still uses deltaThreshold and forwards.
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: -0.5, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: [], currentOffsetX: 90, maxOffsetX: 200
            )),
            .forwardToParent
        )
    }

    @MainActor
    func testTrackpadMayBeginBalancingMicroJitterAndNoStaleLeak() {
        // Case 1: .mayBegin followed directly by non-zero horizontal .began balances .ended to parent.
        var router = InspectorValueScrollRouter()
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .mayBegin, momentumPhase: [], currentOffsetX: 50, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 12, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .began, momentumPhase: [], currentOffsetX: 50, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 38)
        )
        XCTAssertEqual(router.axisLatch, .horizontal)
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .ended, momentumPhase: [], currentOffsetX: 38, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertFalse(router.didForwardPreciseBeginToParent)

        // Case 2: .mayBegin -> tiny horizontal jitter on .began -> real vertical swipe latches vertical.
        var jitterRouter = InspectorValueScrollRouter()
        XCTAssertEqual(
            jitterRouter.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .mayBegin, momentumPhase: [], currentOffsetX: 50, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(
            jitterRouter.handle(InspectorValueScrollInput(
                deltaX: 0.02, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .began, momentumPhase: [], currentOffsetX: 50, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(jitterRouter.axisLatch, .undecided)
        XCTAssertEqual(
            jitterRouter.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: -12, hasPreciseScrollingDeltas: true,
                phase: .changed, momentumPhase: [], currentOffsetX: 50, maxOffsetX: 200
            )),
            .forwardToParent
        )
        XCTAssertEqual(jitterRouter.axisLatch, .vertical)

        // Case 3: Previous gesture scrolled away without .ended; a later gesture starting directly
        // with .began(non-zero) must NOT inherit stale didForwardPreciseBeginToParent.
        XCTAssertEqual(
            jitterRouter.handle(InspectorValueScrollInput(
                deltaX: 12, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .began, momentumPhase: [], currentOffsetX: 50, maxOffsetX: 200
            )),
            .scrollHorizontal(to: 38)
        )
        XCTAssertFalse(jitterRouter.didForwardPreciseBeginToParent)
        XCTAssertEqual(
            jitterRouter.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: 0, hasPreciseScrollingDeltas: true,
                phase: .ended, momentumPhase: [], currentOffsetX: 38, maxOffsetX: 200
            )),
            .consume
        )
    }

    @MainActor
    func testInlineDoubleClickHandoffPromotesOnlyRapidUntouchedSameSpotClick() {
        var handoff = InspectorInlineDoubleClickHandoff()
        handoff.begin(at: 10.0, windowNumber: 7, locationInWindow: CGPoint(x: 120, y: 40))

        XCTAssertTrue(
            handoff.consumeLeftMouseDown(
                clickCount: 2,
                timestamp: 10.18,
                windowNumber: 7,
                locationInWindow: CGPoint(x: 122, y: 41),
                doubleClickInterval: 0.5,
                hasMutated: false
            )
        )
        // Disarmed after first evaluation.
        XCTAssertFalse(
            handoff.consumeLeftMouseDown(
                clickCount: 2,
                timestamp: 10.20,
                windowNumber: 7,
                locationInWindow: CGPoint(x: 122, y: 41),
                doubleClickInterval: 0.5,
                hasMutated: false
            )
        )

        // Rejects after typing, timeout, single click, distant click, or another window.
        for (clickCount, timestamp, windowNumber, point, hasMutated) in [
            (2, 10.15, 7, CGPoint(x: 120, y: 40), true),
            (2, 10.75, 7, CGPoint(x: 120, y: 40), false),
            (1, 10.15, 7, CGPoint(x: 120, y: 40), false),
            (2, 10.15, 7, CGPoint(x: 140, y: 40), false),
            (2, 10.15, 8, CGPoint(x: 120, y: 40), false)
        ] {
            handoff.begin(at: 10.0, windowNumber: 7, locationInWindow: CGPoint(x: 120, y: 40))
            XCTAssertFalse(
                handoff.consumeLeftMouseDown(
                    clickCount: clickCount,
                    timestamp: timestamp,
                    windowNumber: windowNumber,
                    locationInWindow: point,
                    doubleClickInterval: 0.5,
                    hasMutated: hasMutated
                )
            )
        }
    }

    @MainActor
    func testQuickEditCommitDecisionProtectsUntouchedMixedAndRejectsStaleScope() {
        let scopeA = InspectorActiveDraftScope(sessionID: InspectorDraftSessionID(), selectedIDs: [UUID()])
        let scopeB = InspectorActiveDraftScope(sessionID: InspectorDraftSessionID(), selectedIDs: scopeA.selectedIDs)

        XCTAssertEqual(
            InspectorPane.quickEditCommitDecision(
                startedMixed: true,
                text: "",
                allowClearingUntouchedMixed: false,
                expectedScope: scopeA,
                currentScope: scopeA
            ),
            .skipUntouchedMixedClear
        )
        XCTAssertEqual(
            InspectorPane.quickEditCommitDecision(
                startedMixed: true,
                text: "",
                allowClearingUntouchedMixed: true,
                expectedScope: scopeA,
                currentScope: scopeA
            ),
            .apply("")
        )
        XCTAssertEqual(
            InspectorPane.quickEditCommitDecision(
                startedMixed: true,
                text: "Unified Value",
                allowClearingUntouchedMixed: false,
                expectedScope: scopeA,
                currentScope: scopeA
            ),
            .apply("Unified Value")
        )
        XCTAssertEqual(
            InspectorPane.quickEditCommitDecision(
                startedMixed: false,
                text: "Draft",
                allowClearingUntouchedMixed: false,
                expectedScope: scopeA,
                currentScope: scopeB
            ),
            .discardStaleScope
        )
    }

    @MainActor
    func testActiveInspectorDraftScopeSurvivesCleanRefreshAndInvalidatesOnCancelSelectionOrPendingReview() {
        let fileA = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/scope-a.mp3"), title: "A")
        let fileB = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/scope-b.mp3"), title: "B")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
        viewModel.mergeQuickImportFiles([fileA, fileB])
        viewModel.setSelectedAudioIDs([fileA.id])

        guard let initialScope = viewModel.activeInspectorDraftScope else {
            return XCTFail("Expected active Inspector draft scope for selected file")
        }

        // Benign clean refresh bumps editGeneration while keeping sessionID and selectedIDs.
        let beforeIdentity = viewModel.inspectorDraftIdentity
        viewModel.refreshInspectorDraftAfterAcceptedPublication()
        XCTAssertNotEqual(viewModel.inspectorDraftIdentity, beforeIdentity)
        XCTAssertEqual(viewModel.activeInspectorDraftScope, initialScope)

        // Explicit Cancel creates a new draft session and invalidates open editors.
        viewModel.cancelEditing()
        let postCancelScope = viewModel.activeInspectorDraftScope
        XCTAssertNotNil(postCancelScope)
        XCTAssertNotEqual(postCancelScope, initialScope)

        // Switching selection invalidates the previous scope.
        viewModel.setSelectedAudioIDs([fileB.id])
        let selectionBScope = viewModel.activeInspectorDraftScope
        XCTAssertNotNil(selectionBScope)
        XCTAssertNotEqual(selectionBScope, postCancelScope)

        // Dirty draft moving to pending review clears the active editor scope.
        viewModel.edit?.title = "Dirty B"
        viewModel.quickImportFiles = [fileA]
        viewModel.quickImportFilesByID = [fileA.id: fileA]
        viewModel.rebuildVisibleFiles(preservingOutOfScopeDraft: true)
        XCTAssertTrue(viewModel.hasInspectorPendingReview)
        XCTAssertNil(viewModel.activeInspectorDraftScope)
    }

    @MainActor
    func testEscapeRevertRestoresPairedNumbersAndUntouchedMixedWithoutLosingUnrelatedDraftEdits() {
        // Single-file: paired track paste ("7/12") reverted restores track, total, and raw text,
        // while keeping an unrelated earlier title edit intact.
        let singleFile = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/revert-single.mp3"),
            title: "Original Title",
            track: 1,
            trackTotal: 10,
            trackNumberText: "01/10"
        )
        var singleEdit = SingleFileEditModel(from: singleFile)
        singleEdit.title = "Edited Title"

        let trackSnapshot = singleEdit.trackPairSnapshot
        singleEdit.setTrackNumberFieldText("7/12")
        XCTAssertEqual(singleEdit.track, 7)
        XCTAssertEqual(singleEdit.trackTotal, 12)
        XCTAssertEqual(singleEdit.trackNumberText, "7/12")

        singleEdit.restoreTrackPair(trackSnapshot)
        XCTAssertEqual(singleEdit.track, 1)
        XCTAssertEqual(singleEdit.trackTotal, 10)
        XCTAssertEqual(singleEdit.trackNumberText, "01/10")
        XCTAssertEqual(singleEdit.title, "Edited Title")

        // Multi-file: reverting paired track paste restores trackTotal and untouched-mixed state
        // while keeping unrelated album edits intact.
        let fileA = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/revert-multi-a.mp3"),
            title: "Track A",
            album: "Old Album",
            track: 1,
            trackTotal: 10,
            trackNumberText: "1/10"
        )
        let fileB = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/revert-multi-b.mp3"),
            title: "Track B",
            album: "Old Album",
            track: 2,
            trackTotal: 10,
            trackNumberText: "2/10"
        )
        var multiEdit = MultiFileEditModel(files: [fileA, fileB])
        multiEdit.setText("New Album", for: .album)

        let multiTrackSnapshot = multiEdit.textFieldRevertSnapshot(for: .trackNumber)
        multiEdit.setText("7/12", for: .trackNumber)
        XCTAssertEqual(multiEdit.values.track, 7)
        XCTAssertEqual(multiEdit.values.trackTotal, 12)
        XCTAssertTrue(multiEdit.modifiedTextFields.contains(.trackNumber))

        multiEdit.restoreTextField(multiTrackSnapshot)
        XCTAssertEqual(multiEdit.values.trackTotal, 10)
        XCTAssertTrue(multiEdit.isUntouchedMixedTextField(.trackNumber))
        XCTAssertEqual(multiEdit.modifiedTextFields, [.album])
        let appliedA = multiEdit.applyingChanges(to: fileA)
        XCTAssertEqual(appliedA.album, "New Album")
        XCTAssertEqual(appliedA.track, 1)
        XCTAssertEqual(appliedA.trackTotal, 10)

        // Multi-file untouched mixed text field edited and escaped stays untouched mixed (never clears).
        let multiTitleSnapshot = multiEdit.textFieldRevertSnapshot(for: .title)
        multiEdit.setText("Temporary", for: .title)
        XCTAssertFalse(multiEdit.isUntouchedMixedTextField(.title))
        multiEdit.restoreTextField(multiTitleSnapshot)
        XCTAssertTrue(multiEdit.isUntouchedMixedTextField(.title))
        XCTAssertEqual(multiEdit.applyingChanges(to: fileA).title, "Track A")
        XCTAssertEqual(multiEdit.applyingChanges(to: fileB).title, "Track B")
    }

    @MainActor
    func testScrollViewPreservesOffsetAndSkipsRemeasurementOnUnchangedUpdate() {
        let scrollView = InspectorValueScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: inspectorRowContentHeight))
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color = NSColor.secondaryLabelColor
        let longText = String(repeating: "Symphony No. 9 in D Minor ", count: 6)

        scrollView.update(text: longText, font: font, textColor: color)
        scrollView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(scrollView.maximumHorizontalOffset, 0)
        XCTAssertEqual(scrollView.currentHorizontalOffset, scrollView.maximumHorizontalOffset, accuracy: 0.5)
        XCTAssertEqual(scrollView.textMeasurementCount, 1)

        // User scrolls to the leading edge of the long value.
        scrollView.scrollHorizontal(to: 0)
        XCTAssertEqual(scrollView.currentHorizontalOffset, 0, accuracy: 0.5)

        // Unchanged update (e.g., focus return without text edits) skips remeasurement and preserves offset.
        scrollView.update(text: longText, font: font, textColor: color)
        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrollView.textMeasurementCount, 1)
        XCTAssertEqual(scrollView.currentHorizontalOffset, 0, accuracy: 0.5)

        // Resizing does not remeasure text and keeps offset valid.
        scrollView.setFrameSize(NSSize(width: 160, height: inspectorRowContentHeight))
        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrollView.textMeasurementCount, 1)
        XCTAssertEqual(scrollView.currentHorizontalOffset, 0, accuracy: 0.5)

        // Changing text remeasures once and scrolls to the new trailing edge.
        let updatedText = longText + "(Remastered)"
        scrollView.update(text: updatedText, font: font, textColor: color)
        scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrollView.textMeasurementCount, 2)
        XCTAssertEqual(scrollView.currentHorizontalOffset, scrollView.maximumHorizontalOffset, accuracy: 0.5)
    }

    @MainActor
    func testFlexibleScrollableInspectorValueTextSizesToProposedWidthInHostingView() {
        let host = NSHostingView(
            rootView: HStack(spacing: 12) {
                Text("Title")
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                FlexibleScrollableInspectorValueText(text: String(repeating: "Long Title ", count: 8))
            }
            .frame(width: 320)
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 32)
        host.layoutSubtreeIfNeeded()

        let scrollView = findSubview(ofType: InspectorValueScrollView.self, in: host)
        XCTAssertNotNil(scrollView)
        if let scrollView {
            XCTAssertGreaterThan(scrollView.bounds.width, 150)
            XCTAssertEqual(scrollView.bounds.height, inspectorRowContentHeight, accuracy: 0.5)
            XCTAssertGreaterThan(scrollView.maximumHorizontalOffset, 0)
            XCTAssertEqual(scrollView.currentHorizontalOffset, scrollView.maximumHorizontalOffset, accuracy: 0.5)
        }
    }

    @MainActor
    func testFindAndReplacePreviewFitsFullWidthAndHeightInHostingView() async throws {
        let layout = MetadataTextUtilityPreviewLayout.self
        XCTAssertEqual(layout.availableContentWidth, 780)
        XCTAssertEqual(layout.totalRowWidth, layout.availableContentWidth)

        let url = try MetadataTestTokens.makeFixtureCopy()
        defer { MetadataTestTokens.removeFixtureCopy(at: url) }
        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        let deadline = ContinuousClock.now + .seconds(5)
        while store.isLoading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.isEditable, store.loadErrorMessage ?? "Metadata Editor did not finish loading")
        store.upsertField(key: "TITLE", values: [String(repeating: "Original value ", count: 64)])

        let host = NSHostingView(rootView: MetadataTextUtilitiesSheet(
            store: store,
            fieldKeys: ["TITLE"],
            initialOperation: .findAndReplace,
            initialFindText: "Original",
            initialReplacementText: "Replacement",
            onClose: {}
        ))
        let frame = NSRect(x: 0, y: 0, width: 820, height: 540)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = host
        defer { window.contentView = nil }
        host.frame = frame
        host.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findSubview(ofType: NSScrollView.self, in: host))
        let viewport = scrollView.contentView
        XCTAssertGreaterThanOrEqual(viewport.bounds.height, 120)
        XCTAssertEqual(viewport.bounds.width, layout.availableContentWidth, accuracy: 0.5)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        let visibleFrame = host.convert(viewport.bounds, from: viewport)
        XCTAssertTrue(host.bounds.contains(visibleFrame))
    }

    @MainActor
    func testMultiEditBindingGuardPreservesUntouchedMixedClearWhileSkippingNoOpSharedWrites() {
        let mixedFiles = [
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/mixed-guard-a.m4a"), title: "Track A", album: "Shared Album"),
            AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/mixed-guard-b.m4a"), title: "Track B", album: "Shared Album")
        ]
        var multiEdit = MultiFileEditModel(files: mixedFiles)

        // Shared field with identical value is a no-op write.
        XCTAssertFalse(InspectorPane.shouldApplyMultiEditText("Shared Album", for: .album, in: multiEdit))
        // Shared field with a new value applies.
        XCTAssertTrue(InspectorPane.shouldApplyMultiEditText("Updated Album", for: .album, in: multiEdit))
        // Untouched mixed field allows explicit "" write (e.g., Quick Edit Save intentional clear).
        XCTAssertTrue(InspectorPane.shouldApplyMultiEditText("", for: .title, in: multiEdit))

        // After an intentional clear, writing "" again is a no-op.
        multiEdit.setText("", for: .title)
        XCTAssertFalse(InspectorPane.shouldApplyMultiEditText("", for: .title, in: multiEdit))
        XCTAssertTrue(InspectorPane.shouldApplyMultiEditText("Unified Title", for: .title, in: multiEdit))
    }

    @MainActor
    private func findSubview<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = findSubview(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
