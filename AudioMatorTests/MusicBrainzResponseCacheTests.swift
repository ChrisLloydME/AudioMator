import Foundation
import XCTest
@testable import AudioMator

final class MusicBrainzResponseCacheTests: XCTestCase {
    func testCacheCoalescesConcurrentLoadsForTheSameURL() async throws {
        let cache = MusicBrainzResponseCache(maximumEntryCount: 10, maximumTotalBytes: 1_024)
        let loader = SuspendedLoader()
        let url = URL(string: "https://musicbrainz.org/coalesced")!
        let tasks = (0..<10).map { _ in
            Task {
                try await cache.data(for: url, timeToLive: 60) {
                    await loader.load()
                }
            }
        }

        while await loader.callCount == 0 {
            await Task.yield()
        }
        await loader.release(with: Data([1, 2, 3]))
        for task in tasks {
            let value = try await task.value
            XCTAssertEqual(value, Data([1, 2, 3]))
        }
        let callCount = await loader.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testCacheEvictsLeastRecentlyUsedEntryAtCountLimit() async throws {
        let cache = MusicBrainzResponseCache(maximumEntryCount: 2, maximumTotalBytes: 1_024)
        let loads = LoadCounter()
        let firstURL = URL(string: "https://musicbrainz.org/first")!
        let secondURL = URL(string: "https://musicbrainz.org/second")!
        let thirdURL = URL(string: "https://musicbrainz.org/third")!

        _ = try await load(firstURL, cache: cache, counter: loads)
        _ = try await load(secondURL, cache: cache, counter: loads)
        _ = try await load(firstURL, cache: cache, counter: loads)
        _ = try await load(thirdURL, cache: cache, counter: loads)
        _ = try await load(secondURL, cache: cache, counter: loads)

        let counts = await loads.counts
        XCTAssertEqual(counts[firstURL], 1)
        XCTAssertEqual(counts[secondURL], 2)
        XCTAssertEqual(counts[thirdURL], 1)
        let statistics = await cache.statistics()
        XCTAssertEqual(statistics.entryCount, 2)
    }

    func testCacheEnforcesByteLimitAndSkipsOversizedResponses() async throws {
        let cache = MusicBrainzResponseCache(maximumEntryCount: 10, maximumTotalBytes: 3)
        let firstURL = URL(string: "https://musicbrainz.org/two-bytes")!
        let secondURL = URL(string: "https://musicbrainz.org/oversized")!

        _ = try await cache.data(for: firstURL, timeToLive: 60) { Data([1, 2]) }
        _ = try await cache.data(for: secondURL, timeToLive: 60) { Data([1, 2, 3, 4]) }

        let statistics = await cache.statistics()
        XCTAssertEqual(statistics.entryCount, 1)
        XCTAssertEqual(statistics.totalBytes, 2)
    }

    private func load(
        _ url: URL,
        cache: MusicBrainzResponseCache,
        counter: LoadCounter
    ) async throws -> Data {
        try await cache.data(for: url, timeToLive: 60) {
            await counter.record(url)
            return Data(url.absoluteString.utf8)
        }
    }
}

private actor LoadCounter {
    private(set) var counts: [URL: Int] = [:]

    func record(_ url: URL) {
        counts[url, default: 0] += 1
    }
}

private actor SuspendedLoader {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Data, Never>?

    func load() async -> Data {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release(with data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}
