import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class ProviderSearchRestartTests: XCTestCase {
    func testiTunesRestartedSearchIgnoresCancellationCompletionFromPreviousRequest() async throws {
        let gate = RestartableProviderSearchGate()
        let store = iTunesBrowserStore(client: RestartableiTunesBrowserClient(gate: gate))
        store.titleQuery = "Restarted Search"

        store.search()
        await gate.waitUntilCallCount(1)
        store.search()
        await gate.waitUntilCallCount(2)
        await gate.waitUntilCancellationCount(1)
        await drainCancelledSearchCompletion()

        XCTAssertTrue(
            store.isSearching,
            "A cancelled iTunes request must not finish its replacement search."
        )

        await gate.releaseSecondCall()
        try await waitUntilSearchFinishes { store.isSearching }
        XCTAssertFalse(store.isSearching)
        XCTAssertNil(store.errorMessage)
    }

    func testMusicBrainzRestartedSearchIgnoresCancellationCompletionFromPreviousRequest() async throws {
        let gate = RestartableProviderSearchGate()
        let store = MusicBrainzBrowserStore(client: RestartableMusicBrainzBrowserClient(gate: gate))
        store.titleQuery = "Restarted Search"

        store.search()
        await gate.waitUntilCallCount(1)
        store.search()
        await gate.waitUntilCallCount(2)
        await gate.waitUntilCancellationCount(1)
        await drainCancelledSearchCompletion()

        XCTAssertTrue(
            store.isSearching,
            "A cancelled MusicBrainz request must not finish its replacement search."
        )

        await gate.releaseSecondCall()
        try await waitUntilSearchFinishes { store.isSearching }
        XCTAssertFalse(store.isSearching)
        XCTAssertNil(store.errorMessage)
    }

    private func waitUntilSearchFinishes(
        _ isSearching: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while isSearching(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(isSearching(), "Timed out waiting for provider search", file: file, line: line)
    }

    private func drainCancelledSearchCompletion() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

private actor RestartableProviderSearchGate {
    private var callCount = 0
    private var cancellationCount = 0
    private var callCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var secondCallContinuation: CheckedContinuation<Void, Never>?
    private var isSecondCallReleased = false

    func beginCall() -> Int {
        callCount += 1
        resumeSatisfiedWaiters(currentCount: callCount, waiters: &callCountWaiters)
        return callCount
    }

    func recordCancellation() {
        cancellationCount += 1
        resumeSatisfiedWaiters(currentCount: cancellationCount, waiters: &cancellationWaiters)
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        guard callCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append((expectedCount, continuation))
        }
    }

    func waitUntilCancellationCount(_ expectedCount: Int) async {
        guard cancellationCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append((expectedCount, continuation))
        }
    }

    func waitForSecondCallRelease() async {
        guard !isSecondCallReleased else { return }
        await withCheckedContinuation { secondCallContinuation = $0 }
    }

    func releaseSecondCall() {
        isSecondCallReleased = true
        secondCallContinuation?.resume()
        secondCallContinuation = nil
    }

    private func resumeSatisfiedWaiters(
        currentCount: Int,
        waiters: inout [(Int, CheckedContinuation<Void, Never>)]
    ) {
        let satisfied = waiters.filter { currentCount >= $0.0 }
        waiters.removeAll { currentCount >= $0.0 }
        satisfied.forEach { $0.1.resume() }
    }
}

private enum ProviderSearchTestError: Error {
    case unexpectedDetailRequest
}

private final class RestartableiTunesBrowserClient: iTunesBrowserClient, @unchecked Sendable {
    private let gate: RestartableProviderSearchGate

    init(gate: RestartableProviderSearchGate) {
        self.gate = gate
    }

    func search(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        let callIndex = await gate.beginCall()
        if callIndex == 1 {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await gate.recordCancellation()
                throw error
            }
        } else {
            await gate.waitForSecondCallRelease()
        }
        return .tracks([])
    }

    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        throw ProviderSearchTestError.unexpectedDetailRequest
    }
}

private final class RestartableMusicBrainzBrowserClient: MusicBrainzBrowserClient, @unchecked Sendable {
    private let gate: RestartableProviderSearchGate

    init(gate: RestartableProviderSearchGate) {
        self.gate = gate
    }

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        let callIndex = await gate.beginCall()
        if callIndex == 1 {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await gate.recordCancellation()
                throw error
            }
        } else {
            await gate.waitForSecondCallRelease()
        }
        return .recordings([])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        throw ProviderSearchTestError.unexpectedDetailRequest
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        throw ProviderSearchTestError.unexpectedDetailRequest
    }
}
#endif
