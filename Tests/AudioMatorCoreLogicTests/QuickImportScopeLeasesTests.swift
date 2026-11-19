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
