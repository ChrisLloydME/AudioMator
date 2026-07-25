import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class ProviderSearchRestartTests: XCTestCase {
    func testiTunesAlbumMatchingDoesNotBlockMainActor() async throws {
        let matchingGate = BlockingSynchronousGate()
        let detail = makeAlbumDetail()
        let store = iTunesBrowserStore(
            client: ImmediateiTunesDetailClient(detail: detail),
            albumMatcher: { selection, _ in
                matchingGate.blockUntilReleased()
                return iTunesAlbumMatchPreview(
                    totalSelectedFiles: selection.files.count,
                    matchedAssignments: [],
                    unmatchedFiles: selection.files,
                    unassignedTracks: [],
                    overallScore: 0
                )
            }
        )
        store.seed(from: [
            AudioFileTestFactory.make(title: "Track", artist: "Artist", album: "Album")
        ])

        let detailTask = Task {
            try await store.albumDetail(for: detail.album)
        }
        let matcherStarted = try await waitUntil { matchingGate.didStart }

        XCTAssertTrue(matcherStarted)
        XCTAssertTrue(
            Thread.isMainThread,
            "The test must resume on the main actor while the matcher is still blocked off-main."
        )

        matchingGate.release()
        let resolved = try await detailTask.value
        XCTAssertEqual(resolved.selectionMatchPreview?.totalSelectedFiles, 1)
    }

    func testiTunesCancelledNonCooperativeSearchReleasesStoreAndLoadingState() async {
        let gate = NonCooperativeProviderSearchGate()
        var store: iTunesBrowserStore? = iTunesBrowserStore(
            client: NonCooperativeiTunesBrowserClient(gate: gate)
        )
        weak var weakStore = store
        store?.titleQuery = "Never Finishes"

        store?.search()
        await gate.waitUntilStarted()
        store?.closeWindowSession()
        XCTAssertFalse(store?.isSearching ?? true)
        store = nil
        await drainCancelledSearchCompletion()

        XCTAssertNil(
            weakStore,
            "A non-cooperative provider request must not retain its browser store after closure."
        )
        await gate.finish()
    }

    func testMusicBrainzCancelledNonCooperativeSearchReleasesStoreAndLoadingState() async {
        let gate = NonCooperativeProviderSearchGate()
        var store: MusicBrainzBrowserStore? = MusicBrainzBrowserStore(
            client: NonCooperativeMusicBrainzBrowserClient(gate: gate)
        )
        weak var weakStore = store
        store?.titleQuery = "Never Finishes"

        store?.search()
        await gate.waitUntilStarted()
        store?.closeWindowSession()
        XCTAssertFalse(store?.isSearching ?? true)
        store = nil
        await drainCancelledSearchCompletion()

        XCTAssertNil(
            weakStore,
            "A non-cooperative provider request must not retain its browser store after closure."
        )
        await gate.finish()
    }

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

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func makeAlbumDetail() -> iTunesAlbumDetail {
        iTunesAlbumDetail(
            album: iTunesAlbumResult(
                collectionID: 42,
                artistID: nil,
                collectionArtistID: nil,
                collectionName: "Album",
                artistName: "Artist",
                collectionArtistName: "Artist",
                trackCount: 0,
                releaseDate: "",
                primaryGenreName: "",
                country: "US",
                copyright: "",
                contentAdvisoryRating: "",
                collectionExplicitness: "",
                collectionViewURL: nil,
                artistViewURL: nil,
                selectionMatchPreview: nil,
                selectionMatchScore: nil
            ),
            tracks: [],
            selectionMatchPreview: nil
        )
    }
}

private final class BlockingSynchronousGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var started = false

    var didStart: Bool {
        lock.withLock { started }
    }

    func blockUntilReleased() {
        lock.withLock { started = true }
        releaseSemaphore.wait()
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private actor NonCooperativeProviderSearchGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var started = false

    func suspendIgnoringCancellation() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private struct ImmediateiTunesDetailClient: iTunesBrowserClient {
    let detail: iTunesAlbumDetail

    func search(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        .tracks([])
    }

    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        detail
    }
}

private struct NonCooperativeiTunesBrowserClient: iTunesBrowserClient {
    let gate: NonCooperativeProviderSearchGate

    func search(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        await gate.suspendIgnoringCancellation()
        return .tracks([])
    }

    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        throw ProviderSearchTestError.unexpectedDetailRequest
    }
}

private struct NonCooperativeMusicBrainzBrowserClient: MusicBrainzBrowserClient {
    let gate: NonCooperativeProviderSearchGate

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        await gate.suspendIgnoringCancellation()
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
