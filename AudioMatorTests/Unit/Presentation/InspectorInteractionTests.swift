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
        XCTAssertEqual(
            router.handle(InspectorValueScrollInput(
                deltaX: 0, deltaY: -10, hasPreciseScrollingDeltas: true,
                phase: [], momentumPhase: [], currentOffsetX: 90, maxOffsetX: 200
            )),
            .forwardToParent
        )
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
