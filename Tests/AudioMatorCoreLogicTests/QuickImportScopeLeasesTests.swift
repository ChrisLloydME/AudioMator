import Foundation
import XCTest
@testable import AudioMatorCoreLogic

final class QuickImportScopeLeasesTests: XCTestCase {
    func testFirstOwnerStartsAndLastOwnerStopsExactlyOnce() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let url = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let job = QuickImportScopeOwner.job(UUID())
        let membership = QuickImportScopeOwner.membership(UUID())

        access.setGranted(true, for: url)
        let firstState = leases.acquire(url: url, key: "file:01", owner: job)
        XCTAssertEqual(firstState, .granted(url: url))
        XCTAssertEqual(access.startCount(for: url), 1)

        leases.acquire(url: url, key: "file:01", owner: membership)
        XCTAssertEqual(access.startCount(for: url), 1, "A second owner must not start the scope again")

        leases.release(key: "file:01", owner: job)
        XCTAssertEqual(access.stopCount(for: url), 0, "A live membership owner keeps the scope")

        leases.release(key: "file:01", owner: membership)
        XCTAssertEqual(access.stopCount(for: url), 1, "The last owner stops the scope exactly once")
        XCTAssertEqual(access.startCount(for: url), 1)

        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 1)
        XCTAssertEqual(metrics.stopCount, 1)
        XCTAssertEqual(metrics.grantedCount, 1)
        XCTAssertEqual(metrics.liveLeaseCount, 0)
    }

    func testReleasingANonOwnerNeverStopsALiveLease() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let url = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let owner = QuickImportScopeOwner.job(UUID())
        access.setGranted(true, for: url)
        leases.acquire(url: url, key: "file:01", owner: owner)

        leases.release(key: "file:01", owner: .membership(UUID()))
        leases.release(owner: .membership(UUID()))
        XCTAssertEqual(access.stopCount(for: url), 0)

        leases.release(owner: owner)
        XCTAssertEqual(access.stopCount(for: url), 1)
        XCTAssertEqual(leases.metricsSnapshot().startCount, 1)
        XCTAssertEqual(leases.metricsSnapshot().stopCount, 1)
    }

    func testNotRequiredLeaseIsNeverStoppedAndIsNotRetriedByBatchSync() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let url = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let job = QuickImportScopeOwner.job(UUID())
        let membership = QuickImportScopeOwner.membership(UUID())

        access.setGranted(false, for: url)
        XCTAssertEqual(leases.acquire(url: url, key: "file:01", owner: job), .notRequired(url: url))
        leases.acquire(url: url, key: "file:01", owner: membership)

        XCTAssertEqual(access.startCount(for: url), 1, "Passive batch sync must not retry a failed start")
        XCTAssertEqual(leases.metricsSnapshot().suppressedStartAttempts, 1)

        leases.release(key: "file:01", owner: job)
        leases.release(key: "file:01", owner: membership)
        XCTAssertEqual(access.stopCount(for: url), 0, "A scope that never started is never stopped")
        XCTAssertEqual(leases.state(forKey: "file:01"), .notRequired(url: url))
    }

    func testPreviouslyGrantedFailureBecomesRevokedAndRetriesOnlyAtNewAuthorizationEpoch() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let url = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let firstJob = QuickImportScopeOwner.job(UUID())

        access.setGranted(true, for: url)
        leases.acquire(url: url, key: "file:01", owner: firstJob)
        leases.release(owner: firstJob)
        XCTAssertEqual(access.stopCount(for: url), 1)

        // The volume unmounted or the authorization was revoked: the next start fails.
        access.setGranted(false, for: url)
        let secondJob = QuickImportScopeOwner.job(UUID())
        XCTAssertEqual(leases.acquire(url: url, key: "file:01", owner: secondJob), .revoked(url: url))
        XCTAssertEqual(access.startCount(for: url), 2)
        XCTAssertEqual(leases.metricsSnapshot().revokedCount, 1)

        // Passive retry within the same authorization epoch must not call the adapter.
        leases.release(owner: secondJob)
        leases.acquire(url: url, key: "file:01", owner: secondJob)
        XCTAssertEqual(access.startCount(for: url), 2)
        leases.release(owner: secondJob)

        let epoch = leases.beginAuthorizationEpoch()
        access.setGranted(true, for: url)
        let thirdJob = QuickImportScopeOwner.job(UUID())
        XCTAssertEqual(
            leases.acquire(url: url, key: "file:01", owner: thirdJob, authorizationEpoch: epoch),
            .granted(url: url)
        )
        XCTAssertEqual(access.startCount(for: url), 3)
        leases.release(owner: thirdJob)
        XCTAssertEqual(access.stopCount(for: url), 2)
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 3)
        XCTAssertEqual(metrics.stopCount, 2)
    }

    func testReleaseAllBalancesEveryLiveLease() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let owner = QuickImportScopeOwner.job(UUID())
        let urls = (0..<8).map { URL(fileURLWithPath: "/tmp/import/\($0).mp3") }
        for (index, url) in urls.enumerated() {
            access.setGranted(true, for: url)
            leases.acquire(url: url, key: "file:\(index)", owner: owner)
        }
        leases.releaseAll()
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 8)
        XCTAssertEqual(metrics.stopCount, 8)
        XCTAssertEqual(metrics.liveLeaseCount, 0)
    }

    func testMigrateKeyTransfersTheGrantToTheRenamedRowWithoutRestarting() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let destinationURL = URL(fileURLWithPath: "/tmp/renamed/01 - Renamed.mp3")
        let job = QuickImportScopeOwner.job(UUID())
        let membership = QuickImportScopeOwner.membership(UUID())

        access.setGranted(true, for: sourceURL)
        leases.acquire(url: sourceURL, key: "source", owner: job)
        leases.acquire(url: sourceURL, key: "source", owner: membership)
        leases.release(key: "source", owner: job)

        leases.migrateKey(from: "source", to: "destination", url: destinationURL, owner: membership)

        XCTAssertNil(leases.state(forKey: "source"))
        XCTAssertEqual(leases.state(forKey: "destination"), .granted(url: sourceURL))
        XCTAssertEqual(leases.owners(forKey: "destination"), [membership])
        XCTAssertEqual(access.startCount(for: sourceURL), 1, "A move must not start a new scope")
        XCTAssertEqual(access.startCount(for: destinationURL), 0)

        leases.release(key: "destination", owner: membership)
        XCTAssertEqual(access.stopCount(for: sourceURL), 1)
        XCTAssertEqual(access.startCount(for: sourceURL), 1)
    }

    func testSharedParentKeySurvivesSiblingCompletion() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let parentURL = URL(fileURLWithPath: "/tmp/import")
        let firstJob = QuickImportScopeOwner.job(UUID())
        let secondJob = QuickImportScopeOwner.job(UUID())

        access.setGranted(true, for: parentURL)
        leases.acquire(url: parentURL, key: "parent", owner: firstJob)
        leases.acquire(url: parentURL, key: "parent", owner: secondJob)
        XCTAssertEqual(access.startCount(for: parentURL), 1)

        leases.release(owner: firstJob)
        XCTAssertEqual(access.stopCount(for: parentURL), 0, "The shared parent stays alive for the second job")
        leases.release(owner: secondJob)
        XCTAssertEqual(access.stopCount(for: parentURL), 1)
    }

    func testMigrateFromSharedKeyStartsDestinationAndKeepsSourceGrant() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let destinationURL = URL(fileURLWithPath: "/tmp/renamed/01.mp3")
        let movingOwner = QuickImportScopeOwner.membership(UUID())
        let siblingOwner = QuickImportScopeOwner.membership(UUID())
        access.setGranted(true, for: sourceURL)
        access.setGranted(true, for: destinationURL)

        leases.acquire(url: sourceURL, key: "shared-parent", owner: movingOwner)
        leases.acquire(url: sourceURL, key: "shared-parent", owner: siblingOwner)
        leases.migrateKey(
            from: "shared-parent",
            to: "destination-parent",
            url: destinationURL,
            owner: movingOwner
        )

        XCTAssertEqual(access.startCount(for: sourceURL), 1, "The shared source grant must not move")
        XCTAssertEqual(access.startCount(for: destinationURL), 1, "The moved owner gets its own destination start")
        XCTAssertEqual(leases.state(forKey: "shared-parent"), .granted(url: sourceURL))
        XCTAssertEqual(leases.owners(forKey: "shared-parent"), [siblingOwner])
        XCTAssertEqual(leases.owners(forKey: "destination-parent"), [movingOwner])

        leases.release(key: "destination-parent", owner: movingOwner)
        leases.release(key: "shared-parent", owner: siblingOwner)
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 2)
        XCTAssertEqual(metrics.stopCount, 2, "One start per key must produce exactly one stop")
        XCTAssertEqual(metrics.transferCount, 0, "A shared grant is never copied onto a second key")
        XCTAssertEqual(metrics.dedupedGrantTransferStopCount, 0)
    }

    func testMigrateSecondOwnerFromNowUnsharedKeyTransfersTheSingleOutstandingGrant() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import")
        let firstDestinationURL = URL(fileURLWithPath: "/tmp/disc-one")
        let secondDestinationURL = URL(fileURLWithPath: "/tmp/disc-two")
        let firstOwner = QuickImportScopeOwner.membership(UUID())
        let secondOwner = QuickImportScopeOwner.membership(UUID())
        access.setGranted(true, for: sourceURL)
        access.setGranted(true, for: firstDestinationURL)

        leases.acquire(url: sourceURL, key: "source-parent", owner: firstOwner)
        leases.acquire(url: sourceURL, key: "source-parent", owner: secondOwner)

        // First move: the old key is still shared, so the destination starts once.
        leases.migrateKey(
            from: "source-parent",
            to: "destination-one",
            url: firstDestinationURL,
            owner: firstOwner
        )
        XCTAssertEqual(access.startCount(for: sourceURL), 1)
        XCTAssertEqual(access.startCount(for: firstDestinationURL), 1)

        // Second move: the old key is now unshared, so its single outstanding
        // grant travels to the new key instead of planning a second stop.
        leases.migrateKey(
            from: "source-parent",
            to: "destination-two",
            url: secondDestinationURL,
            owner: secondOwner
        )
        XCTAssertNil(leases.state(forKey: "source-parent"))
        XCTAssertEqual(leases.state(forKey: "destination-two"), .granted(url: sourceURL))
        XCTAssertEqual(access.startCount(for: secondDestinationURL), 0, "A transferred grant is not restarted")
        XCTAssertEqual(leases.metricsSnapshot().transferCount, 1)

        leases.release(key: "destination-one", owner: firstOwner)
        leases.release(key: "destination-two", owner: secondOwner)
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 2)
        XCTAssertEqual(metrics.stopCount, 2, "Transferred grant keeps one start and one stop")
    }

    func testMigrateIntoLivGrantStopsTheRedundantSourceGrantExactlyOnce() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let destinationURL = URL(fileURLWithPath: "/tmp/renamed/01.mp3")
        let movingOwner = QuickImportScopeOwner.membership(UUID())
        let residentOwner = QuickImportScopeOwner.membership(UUID())
        access.setGranted(true, for: sourceURL)
        access.setGranted(true, for: destinationURL)

        leases.acquire(url: sourceURL, key: "source", owner: movingOwner)
        leases.acquire(url: destinationURL, key: "destination", owner: residentOwner)
        XCTAssertEqual(leases.metricsSnapshot().startCount, 2)

        leases.migrateKey(from: "source", to: "destination", url: destinationURL, owner: movingOwner)

        XCTAssertNil(leases.state(forKey: "source"))
        XCTAssertEqual(access.stopCount(for: sourceURL), 1, "The duplicated source start is stopped exactly once")
        XCTAssertEqual(leases.state(forKey: "destination"), .granted(url: destinationURL))
        XCTAssertEqual(leases.owners(forKey: "destination"), [residentOwner, movingOwner])
        XCTAssertEqual(leases.metricsSnapshot().dedupedGrantTransferStopCount, 1)

        leases.release(key: "destination", owner: movingOwner)
        XCTAssertEqual(access.stopCount(for: destinationURL), 0, "The resident owner keeps the destination live")
        leases.release(key: "destination", owner: residentOwner)
        XCTAssertEqual(access.stopCount(for: destinationURL), 1)
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 2)
        XCTAssertEqual(metrics.stopCount, 2, "De-duplication keeps starts and stops balanced")
    }

    func testOwnerAddedDuringTransferSharesTheDestinationGrant() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import")
        let destinationURL = URL(fileURLWithPath: "/tmp/disc-two")
        let firstOwner = QuickImportScopeOwner.membership(UUID())
        let secondOwner = QuickImportScopeOwner.membership(UUID())
        let addedOwner = QuickImportScopeOwner.membership(UUID())
        access.setGranted(true, for: sourceURL)
        access.setGranted(true, for: destinationURL)

        leases.acquire(url: sourceURL, key: "source-parent", owner: firstOwner)
        leases.acquire(url: sourceURL, key: "source-parent", owner: secondOwner)
        leases.migrateKey(
            from: "source-parent",
            to: "destination-parent",
            url: destinationURL,
            owner: firstOwner
        )
        // A new owner joins the destination while the second sibling is about to move.
        leases.acquire(url: destinationURL, key: "destination-parent", owner: addedOwner)
        XCTAssertEqual(access.startCount(for: destinationURL), 1)

        leases.migrateKey(
            from: "source-parent",
            to: "destination-parent",
            url: destinationURL,
            owner: secondOwner
        )
        XCTAssertEqual(access.stopCount(for: sourceURL), 1)
        XCTAssertEqual(leases.owners(forKey: "destination-parent"), [firstOwner, secondOwner, addedOwner])
        XCTAssertEqual(access.startCount(for: destinationURL), 1, "A third owner only joins the live grant")

        leases.release(key: "destination-parent", owner: firstOwner)
        leases.release(key: "destination-parent", owner: addedOwner)
        XCTAssertEqual(access.stopCount(for: destinationURL), 0)
        leases.release(key: "destination-parent", owner: secondOwner)
        XCTAssertEqual(access.stopCount(for: destinationURL), 1)
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, metrics.stopCount)
    }

    func testMigratePreservesDestinationNotRequiredAndRevokedEvidence() {
        let access = ScriptedQuickImportScopeAccess()
        let notRequiredLeases = QuickImportScopeLeases(access: access)
        let notRequiredURL = URL(fileURLWithPath: "/tmp/not-required")
        let notRequiredDestination = URL(fileURLWithPath: "/tmp/not-required-destination")
        let firstOwner = QuickImportScopeOwner.membership(UUID())
        let secondOwner = QuickImportScopeOwner.membership(UUID())
        access.setGranted(false, for: notRequiredURL)
        access.setGranted(false, for: notRequiredDestination)
        notRequiredLeases.acquire(url: notRequiredURL, key: "not-required", owner: firstOwner)
        notRequiredLeases.acquire(url: notRequiredURL, key: "not-required", owner: secondOwner)
        notRequiredLeases.migrateKey(
            from: "not-required",
            to: "not-required-destination",
            url: notRequiredDestination,
            owner: firstOwner
        )
        XCTAssertEqual(notRequiredLeases.state(forKey: "not-required-destination"), .notRequired(url: notRequiredDestination))
        XCTAssertEqual(access.startCount(for: notRequiredURL), 1, "A notRequired source state must not retry on transfer")
        XCTAssertEqual(access.startCount(for: notRequiredDestination), 0)
        notRequiredLeases.releaseAll()
        XCTAssertEqual(access.stopCount(for: notRequiredURL), 0, "A scope that never started is never stopped")

        let revokedAccess = ScriptedQuickImportScopeAccess()
        let revokedLeases = QuickImportScopeLeases(access: revokedAccess)
        let revokedURL = URL(fileURLWithPath: "/tmp/revoked")
        let revokedDestination = URL(fileURLWithPath: "/tmp/revoked-destination")
        let revokedOwner = QuickImportScopeOwner.membership(UUID())
        let joiningOwner = QuickImportScopeOwner.membership(UUID())
        revokedAccess.setGranted(true, for: revokedURL)
        revokedLeases.acquire(url: revokedURL, key: "revoked", owner: revokedOwner)
        revokedLeases.release(owner: revokedOwner)
        revokedAccess.setGranted(false, for: revokedURL)
        let epoch = revokedLeases.beginAuthorizationEpoch()
        revokedLeases.acquire(
            url: revokedURL,
            key: "revoked",
            owner: revokedOwner,
            authorizationEpoch: epoch
        )
        XCTAssertEqual(revokedLeases.state(forKey: "revoked"), .revoked(url: revokedURL))
        revokedLeases.acquire(url: revokedURL, key: "revoked", owner: joiningOwner)
        revokedLeases.migrateKey(
            from: "revoked",
            to: "revoked-destination",
            url: revokedDestination,
            owner: joiningOwner
        )
        XCTAssertEqual(revokedLeases.state(forKey: "revoked-destination"), .revoked(url: revokedDestination))
        XCTAssertEqual(revokedAccess.startCount(for: revokedURL), 2, "A revoked state is never retried during transfer")
        revokedLeases.releaseAll()
        let revokedMetrics = revokedLeases.metricsSnapshot()
        XCTAssertEqual(revokedMetrics.startCount, 2, "One initial grant plus one authorized retry")
        XCTAssertEqual(revokedMetrics.grantedCount, 1, "Only the initial start was granted")
        XCTAssertEqual(revokedMetrics.stopCount, 1, "Only the previously granted start is stopped")
        XCTAssertEqual(revokedMetrics.transferCount, 0, "A revoked state transfers evidence, not a grant")
    }

    func testMigrateWithoutTheOldOwnerIsInert() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let unknownOwner = QuickImportScopeOwner.membership(UUID())
        access.setGranted(true, for: sourceURL)
        leases.acquire(url: sourceURL, key: "source", owner: .membership(UUID()))

        leases.migrateKey(from: "source", to: "destination", url: sourceURL, owner: unknownOwner)

        XCTAssertEqual(leases.state(forKey: "source"), .granted(url: sourceURL))
        XCTAssertNil(leases.state(forKey: "destination"))
        XCTAssertEqual(leases.metricsSnapshot().startCount, 1)
    }

    func testImmediateReacquireAfterReleaseRestartsAndStopsExactlyOnce() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let url = URL(fileURLWithPath: "/tmp/import/01.mp3")
        let firstJob = QuickImportScopeOwner.job(UUID())
        let secondJob = QuickImportScopeOwner.job(UUID())
        access.setGranted(true, for: url)

        leases.acquire(url: url, key: "file", owner: firstJob)
        leases.release(owner: firstJob)
        leases.acquire(url: url, key: "file", owner: secondJob)
        leases.release(owner: secondJob)

        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 2)
        XCTAssertEqual(metrics.stopCount, 2)
    }

    func testMigrateNonGrantedLeaseIntoRetainedStoppedGrantStartsFreshAndNeverDoubleStops() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/old.mp3")
        let destinationURL = URL(fileURLWithPath: "/tmp/moved/destination.mp3")
        let destinationOwner = QuickImportScopeOwner.membership(UUID())
        let movingOwner = QuickImportScopeOwner.membership(UUID())

        // Destination is started once, then fully released: the entry is
        // retained as `.granted` but has no outstanding stop obligation.
        access.setGranted(true, for: destinationURL)
        leases.acquire(url: destinationURL, key: "destination", owner: destinationOwner)
        leases.release(key: "destination", owner: destinationOwner)
        XCTAssertEqual(access.startCount(for: destinationURL), 1)
        XCTAssertEqual(access.stopCount(for: destinationURL), 1)
        XCTAssertFalse(leases.isLiveGranted(forKey: "destination"))

        // The migrating old key never had a grant.
        access.setGranted(false, for: sourceURL)
        leases.acquire(url: sourceURL, key: "source", owner: movingOwner)
        XCTAssertEqual(leases.state(forKey: "source"), .notRequired(url: sourceURL))

        leases.migrateKey(from: "source", to: "destination", url: destinationURL, owner: movingOwner)

        // R1 regression: the retained-but-stopped destination must not be
        // resurrected as a live lease. A real fresh start is required.
        XCTAssertEqual(
            access.startCount(for: destinationURL),
            2,
            "The destination must start a fresh grant instead of fabricating a live one"
        )
        XCTAssertEqual(leases.state(forKey: "destination"), .granted(url: destinationURL))
        XCTAssertTrue(leases.isLiveGranted(forKey: "destination"))
        XCTAssertEqual(leases.metricsSnapshot().transferCount, 0, "A non-granted source is not a transfer")

        leases.release(key: "destination", owner: movingOwner)
        XCTAssertEqual(access.stopCount(for: destinationURL), 2)
        XCTAssertEqual(
            access.startCount(for: destinationURL),
            access.stopCount(for: destinationURL),
            "Each destination start must have exactly one stop (no fabricated grant, no double-stop)"
        )
        let metrics = leases.metricsSnapshot()
        XCTAssertEqual(metrics.startCount, 3)
        XCTAssertEqual(metrics.stopCount, 2)
        XCTAssertEqual(metrics.grantedCount, 2)
        XCTAssertEqual(metrics.notRequiredCount, 1)
    }

    func testMigrateIntoRetainedStoppedGrantWithRefusedRestartRecordsRevocationWithoutFabrication() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/old.mp3")
        let destinationURL = URL(fileURLWithPath: "/tmp/moved/destination.mp3")
        let destinationOwner = QuickImportScopeOwner.membership(UUID())
        let movingOwner = QuickImportScopeOwner.membership(UUID())

        access.setGranted(true, for: destinationURL)
        leases.acquire(url: destinationURL, key: "destination", owner: destinationOwner)
        leases.release(key: "destination", owner: destinationOwner)
        XCTAssertEqual(access.startCount(for: destinationURL), 1)
        XCTAssertEqual(access.stopCount(for: destinationURL), 1)

        access.setGranted(false, for: destinationURL)
        access.setGranted(false, for: sourceURL)
        leases.acquire(url: sourceURL, key: "source", owner: movingOwner)

        leases.migrateKey(from: "source", to: "destination", url: destinationURL, owner: movingOwner)

        XCTAssertEqual(access.startCount(for: destinationURL), 2, "A fresh start was attempted")
        XCTAssertEqual(
            leases.state(forKey: "destination"),
            .revoked(url: destinationURL),
            "A refused restart is recorded as revoked evidence, not a live grant"
        )
        XCTAssertFalse(leases.isLiveGranted(forKey: "destination"))
        leases.release(key: "destination", owner: movingOwner)
        XCTAssertEqual(
            access.stopCount(for: destinationURL),
            1,
            "No fabricated grant means no extra stop"
        )
    }

    func testMigrateOutstandingGrantIntoNotRequiredDestinationStopsSourceExactlyOnce() {
        let access = ScriptedQuickImportScopeAccess()
        let leases = QuickImportScopeLeases(access: access)
        let sourceURL = URL(fileURLWithPath: "/tmp/import/old.mp3")
        let destinationURL = URL(fileURLWithPath: "/tmp/moved/destination.mp3")
        let destinationOwner = QuickImportScopeOwner.membership(UUID())
        let movingOwner = QuickImportScopeOwner.membership(UUID())

        access.setGranted(false, for: destinationURL)
        leases.acquire(url: destinationURL, key: "destination", owner: destinationOwner)
        leases.release(key: "destination", owner: destinationOwner)
        XCTAssertEqual(leases.state(forKey: "destination"), .notRequired(url: destinationURL))

        access.setGranted(true, for: sourceURL)
        leases.acquire(url: sourceURL, key: "source", owner: movingOwner)

        leases.migrateKey(from: "source", to: "destination", url: destinationURL, owner: movingOwner)

        // R2: the destination's own notRequired evidence wins, and the now
        // ownerless source grant is stopped exactly once.
        XCTAssertEqual(access.stopCount(for: sourceURL), 1)
        XCTAssertEqual(leases.state(forKey: "destination"), .notRequired(url: destinationURL))
        XCTAssertEqual(leases.owners(forKey: "destination"), [movingOwner])
        XCTAssertEqual(leases.metricsSnapshot().unusedGrantStopCount, 1)
        XCTAssertEqual(leases.metricsSnapshot().transferCount, 0)
        XCTAssertEqual(leases.metricsSnapshot().startCount, 2)
        XCTAssertEqual(leases.metricsSnapshot().stopCount, 1)

        leases.release(key: "destination", owner: movingOwner)
        XCTAssertEqual(access.stopCount(for: sourceURL), 1, "A notRequired lease owns no stop")
        XCTAssertEqual(access.stopCount(for: destinationURL), 0)
    }
}

private final class ScriptedQuickImportScopeAccess: QuickImportScopeAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var grantedURLs: [URL: Bool] = [:]
    private var startCounts: [URL: Int] = [:]
    private var stopCounts: [URL: Int] = [:]

    func setGranted(_ granted: Bool, for url: URL) {
        lock.withLock { grantedURLs[url] = granted }
    }

    func startAccessingScope(for url: URL) -> Bool {
        lock.withLock {
            startCounts[url, default: 0] += 1
            return grantedURLs[url] ?? false
        }
    }

    func stopAccessingScope(for url: URL) {
        lock.withLock { stopCounts[url, default: 0] += 1 }
    }

    func startCount(for url: URL) -> Int {
        lock.withLock { startCounts[url] ?? 0 }
    }

    func stopCount(for url: URL) -> Int {
        lock.withLock { stopCounts[url] ?? 0 }
    }
}
