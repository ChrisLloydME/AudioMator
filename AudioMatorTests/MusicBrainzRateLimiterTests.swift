import XCTest
@testable import AudioMator

final class MusicBrainzRateLimiterTests: XCTestCase {
    func testConcurrentCallersReceiveGloballySpacedTurns() async throws {
        let interval: UInt64 = 35_000_000
        let limiter = MusicBrainzRateLimiter(minimumIntervalNanoseconds: interval)

        let releaseTimes = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await limiter.waitIfNeeded()
                    return DispatchTime.now().uptimeNanoseconds
                }
            }

            return try await group.reduce(into: []) { $0.append($1) }.sorted()
        }

        XCTAssertEqual(releaseTimes.count, 6)
        for (earlier, later) in zip(releaseTimes, releaseTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                later - earlier,
                25_000_000,
                "Concurrent callers were released too close together"
            )
        }
    }

    func testCancellationDoesNotCollapseAlreadyReservedSchedule() async throws {
        let interval: UInt64 = 300_000_000
        let limiter = MusicBrainzRateLimiter(minimumIntervalNanoseconds: interval)

        try await limiter.waitIfNeeded()
        let cancelledWaiter = Task {
            try await limiter.waitIfNeeded()
        }
        while await limiter.scheduledTurnCount() < 2 {
            await Task.yield()
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let followingWaiter = Task {
            try await limiter.waitIfNeeded()
            return DispatchTime.now().uptimeNanoseconds
        }
        cancelledWaiter.cancel()

        do {
            try await cancelledWaiter.value
            XCTFail("Expected the reserved waiter to observe cancellation")
        } catch is CancellationError {
            // Expected. Its slot deliberately remains reserved.
        }

        let followingRelease = try await followingWaiter.value
        XCTAssertGreaterThanOrEqual(followingRelease - start, 500_000_000)
    }
}
