import Foundation

actor MusicBrainzRateLimiter {
    nonisolated static let shared = MusicBrainzRateLimiter()

    private struct Waiter {
        let id: UInt64
        var continuation: CheckedContinuation<Void, Error>?
    }

    private let minimumIntervalNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void
    private var waiters: [Waiter] = []
    private var drainTask: Task<Void, Never>?
    private var lastGrantUptimeNanoseconds: UInt64?
    private var reservationCount: UInt64 = 0

    init(
        minimumIntervalNanoseconds: UInt64 = 1_100_000_000,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
        self.sleep = sleep
    }

    func waitIfNeeded() async throws {
        try Task.checkCancellation()

        let waiterID = reservationCount
        reservationCount &+= 1

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: waiterID, continuation: continuation))
                startDrainingIfNeeded()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    private func startDrainingIfNeeded() {
        guard drainTask == nil else { return }
        drainTask = Task { await self.drainWaiters() }
    }

    private func drainWaiters() async {
        while !waiters.isEmpty {
            await waitUntilNextGrant()
            lastGrantUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

            let waiter = waiters.removeFirst()
            waiter.continuation?.resume()
        }

        drainTask = nil
    }

    private func waitUntilNextGrant() async {
        guard let lastGrantUptimeNanoseconds else { return }

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            let (earliestGrant, overflowed) = lastGrantUptimeNanoseconds
                .addingReportingOverflow(minimumIntervalNanoseconds)
            let deadline = overflowed ? UInt64.max : earliestGrant
            guard now < deadline else { return }
            await sleep(deadline - now)
        }
    }

    private func cancelWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }),
              let continuation = waiters[index].continuation else {
            return
        }

        // The queue entry remains as a tombstone. Removing it would collapse an
        // already-reserved slot and pull later callers forward.
        waiters[index].continuation = nil
        continuation.resume(throwing: CancellationError())
    }

    func scheduledTurnCount() -> UInt64 {
        reservationCount
    }
}

nonisolated struct MusicBrainzRetryPolicy: Sendable {
    static let production = MusicBrainzRetryPolicy(maximumRetryCount: 2, baseDelaySeconds: 2)
    static let disabled = MusicBrainzRetryPolicy(maximumRetryCount: 0, baseDelaySeconds: 0)

    let maximumRetryCount: Int
    let baseDelaySeconds: Int

    func delay(forRetry retry: Int) -> Duration {
        let exponent = min(max(0, retry), 8)
        let multiplier = 1 << exponent
        let deterministicJitterMilliseconds = 150 * (retry + 1)
        return .milliseconds(
            (max(0, baseDelaySeconds) * multiplier * 1_000) + deterministicJitterMilliseconds
        )
    }
}

actor MusicBrainzResponseCache {
    private struct Entry {
        let data: Data
        let expiresAt: Date
        var lastAccess: UInt64
    }

    private let maximumEntryCount: Int
    private let maximumTotalBytes: Int
    private var entriesByURL: [URL: Entry] = [:]
    private var inFlightTasksByURL: [URL: Task<Data, Error>] = [:]
    private var totalBytes = 0
    private var accessSequence: UInt64 = 0

    init(
        maximumEntryCount: Int = 128,
        maximumTotalBytes: Int = 16 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = max(0, maximumEntryCount)
        self.maximumTotalBytes = max(0, maximumTotalBytes)
    }

    func data(
        for url: URL,
        timeToLive: TimeInterval,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let now = Date()
        removeExpiredEntries(at: now)
        if var entry = entriesByURL[url], entry.expiresAt > now {
            entry.lastAccess = nextAccessSequence()
            entriesByURL[url] = entry
            return entry.data
        }

        if let inFlightTask = inFlightTasksByURL[url] {
            return try await inFlightTask.value
        }

        let task = Task { try await loader() }
        inFlightTasksByURL[url] = task
        do {
            let data = try await task.value
            insert(data, for: url, expiresAt: Date().addingTimeInterval(max(0, timeToLive)))
            inFlightTasksByURL[url] = nil
            return data
        } catch {
            inFlightTasksByURL[url] = nil
            throw error
        }
    }

    func statistics() -> (entryCount: Int, totalBytes: Int) {
        (entriesByURL.count, totalBytes)
    }

    private func insert(_ data: Data, for url: URL, expiresAt: Date) {
        if let replaced = entriesByURL.removeValue(forKey: url) {
            totalBytes -= replaced.data.count
        }

        guard maximumEntryCount > 0,
              maximumTotalBytes > 0,
              data.count <= maximumTotalBytes else {
            return
        }

        entriesByURL[url] = Entry(
            data: data,
            expiresAt: expiresAt,
            lastAccess: nextAccessSequence()
        )
        totalBytes += data.count
        evictToCapacity()
    }

    private func removeExpiredEntries(at now: Date) {
        let expiredURLs = entriesByURL.compactMap { url, entry in
            entry.expiresAt <= now ? url : nil
        }
        for url in expiredURLs {
            removeEntry(for: url)
        }
    }

    private func evictToCapacity() {
        while entriesByURL.count > maximumEntryCount || totalBytes > maximumTotalBytes {
            guard let leastRecentlyUsedURL = entriesByURL.min(by: {
                $0.value.lastAccess < $1.value.lastAccess
            })?.key else {
                return
            }
            removeEntry(for: leastRecentlyUsedURL)
        }
    }

    private func removeEntry(for url: URL) {
        guard let removed = entriesByURL.removeValue(forKey: url) else { return }
        totalBytes -= removed.data.count
    }

    private func nextAccessSequence() -> UInt64 {
        accessSequence &+= 1
        return accessSequence
    }
}
