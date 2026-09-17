import Foundation

actor MusicBrainzRateLimiter {
    nonisolated static let shared = MusicBrainzRateLimiter()

    private let minimumIntervalNanoseconds: UInt64
    private var nextAvailableUptimeNanoseconds: UInt64 = 0
    private var reservationCount: UInt64 = 0

    init(minimumIntervalNanoseconds: UInt64 = 1_100_000_000) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
    }

    func waitIfNeeded() async throws {
        try Task.checkCancellation()

        let now = DispatchTime.now().uptimeNanoseconds
        let reservedUptimeNanoseconds = max(now, nextAvailableUptimeNanoseconds)
        let (nextAvailable, overflowed) = reservedUptimeNanoseconds.addingReportingOverflow(minimumIntervalNanoseconds)
        nextAvailableUptimeNanoseconds = overflowed ? UInt64.max : nextAvailable
        reservationCount &+= 1

        guard reservedUptimeNanoseconds > now else { return }

        // A cancelled caller keeps its reservation. Collapsing it could move a later
        // already-reserved caller forward and violate the global spacing guarantee.
        try await Task.sleep(nanoseconds: reservedUptimeNanoseconds - now)
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
