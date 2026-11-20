import Foundation
import XCTest
@testable import AudioMator

/// Headless coverage for the Metadata Write HUD dismissal generation barrier.
///
/// The AppKit animation and panel lifetime are not testable headlessly; the
/// decision that guards the completion hop is a pure value, and the completion
/// capture form is reproduced here so the old/current generation, replacement
/// HUD and deallocated-owner outcomes are exercised without launching UI.
nonisolated final class MetadataWriteHUDDismissalDecisionTests: XCTestCase {
    func testCurrentGenerationWithoutPresentedHUDAllowsOrderOut() {
        let generation = UUID()
        let decision = MetadataWriteHUDDismissalDecision(expectedGeneration: generation)

        XCTAssertTrue(decision.shouldOrderOut(currentGeneration: generation, presentedHUDID: nil))
    }

    func testSupersededGenerationRejectsEarlierDismissal() {
        let dismissedGeneration = UUID()
        let currentGeneration = UUID()
        let decision = MetadataWriteHUDDismissalDecision(expectedGeneration: dismissedGeneration)

        XCTAssertFalse(
            decision.shouldOrderOut(currentGeneration: currentGeneration, presentedHUDID: nil),
            "A dismissal started for HUD A must not order out a newer HUD B"
        )
    }

    func testPresentedReplacementHUDRejectsEarlierDismissalCompletion() {
        let generation = UUID()
        let decision = MetadataWriteHUDDismissalDecision(expectedGeneration: generation)

        XCTAssertFalse(
            decision.shouldOrderOut(currentGeneration: generation, presentedHUDID: UUID()),
            "A replacement HUD that reuses the presentation generation still blocks the old completion"
        )
    }

    func testDeallocatedOwnerCompletionPerformsNoAction() {
        var orderedOut = false
        var owner: HUDDismissalOwnerProbe? = HUDDismissalOwnerProbe()
        let decision = MetadataWriteHUDDismissalDecision(
            expectedGeneration: owner!.presentationGeneration
        )
        let completion = owner?.dismissalCompletion(decision: decision) {
            orderedOut = true
        }

        weak let weakOwner = owner
        owner = nil
        XCTAssertNil(weakOwner, "The probe must deallocate before the completion fires")
        completion?()

        XCTAssertFalse(orderedOut, "A completion whose owner deallocated must not order out a panel")
    }

    func testCurrentOwnerWithPresentedHUDOrdersOut() {
        let owner = HUDDismissalOwnerProbe()
        var orderedOut = false
        let decision = MetadataWriteHUDDismissalDecision(expectedGeneration: owner.presentationGeneration)
        let completion = owner.dismissalCompletion(decision: decision) {
            orderedOut = true
        }

        completion()

        XCTAssertTrue(orderedOut)
    }
}

/// Reproduces the production completion capture form: weak owner in the outer
/// AppKit completion and the nested MainActor hop, with a strong post-check load.
private nonisolated final class HUDDismissalOwnerProbe {
    var presentationGeneration = UUID()
    var presentedHUDID: UUID?

    func dismissalCompletion(
        decision: MetadataWriteHUDDismissalDecision,
        orderOut: @escaping () -> Void
    ) -> () -> Void {
        { [weak self] in
            guard let self else { return }
            guard decision.shouldOrderOut(
                currentGeneration: self.presentationGeneration,
                presentedHUDID: self.presentedHUDID
            ) else { return }
            orderOut()
        }
    }
}
