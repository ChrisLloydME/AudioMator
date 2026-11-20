import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
nonisolated final class OnlineMetadataRoutingTests: XCTestCase {
    @MainActor
    func testGenericOpenSeedsLocallyPresentsPickerAndContactsNoProvider() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let windowRequests = LockedCounter()

        fixture.router.openGeneric(
            selectedFiles: [fixture.file],
            openWindow: { windowRequests.increment() }
        )

        XCTAssertEqual(windowRequests.value, 1)
        XCTAssertEqual(musicBrainzClient.searchCount, 0)
        XCTAssertEqual(lrclibClient.searchCount, 0)
        XCTAssertNotNil(fixture.activationStore.pendingIntentID)
        XCTAssertNotNil(fixture.musicBrainzStore.fileSelectionSummary)
        XCTAssertTrue(fixture.lrclibStore.hasFiles)

        let session = fixture.makeSession()
        session.consumePendingIntent()
        XCTAssertNil(session.selectedSource)
        XCTAssertNil(fixture.activationStore.pendingIntentID)
        session.select(.musicBrainz)
        session.select(.lrclib)
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(musicBrainzClient.searchCount, 0, "Selecting the MusicBrainz tile after a generic open must not reconstruct a request")
        XCTAssertEqual(lrclibClient.searchCount, 0)
    }

    @MainActor
    func testExplicitFindSubmitsCapturedQueryExactlyOnceInNewWindow() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let windowRequests = LockedCounter()

        let opened = fixture.router.findInMusicBrainz(
            selectedFiles: [fixture.file],
            openWindow: { windowRequests.increment() }
        )
        XCTAssertTrue(opened)
        XCTAssertEqual(windowRequests.value, 1)
        XCTAssertEqual(musicBrainzClient.searchCount, 0, "Find must not contact MusicBrainz before the window consumes the intent")
        XCTAssertNotNil(fixture.activationStore.pendingIntentID)

        let session = fixture.makeSession()
        session.consumePendingIntent()
        XCTAssertEqual(session.selectedSource, .musicBrainz)
        try await waitUntil { musicBrainzClient.searchCount == 1 }

        let submitted = try XCTUnwrap(musicBrainzClient.searches.first)
        XCTAssertEqual(submitted.title, "Routing Title")
        XCTAssertEqual(submitted.artist, "Routing Artist")
        XCTAssertEqual(submitted.fileInputs.map(\.id), [fixture.file.id.uuidString])
        XCTAssertNil(fixture.activationStore.pendingIntentID)

        // Reappearance/onChange replays cannot resubmit the consumed intent.
        session.consumePendingIntent()
        session.consumePendingIntent()
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(musicBrainzClient.searchCount, 1)
    }

    @MainActor
    func testExplicitFindRetargetsAnAlreadyOpenWindowFromAnotherProviderOnce() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let session = fixture.makeSession()
        session.select(.iTunes)
        XCTAssertEqual(session.selectedSource, .iTunes)
        XCTAssertEqual(musicBrainzClient.searchCount, 0)

        let windowRequests = LockedCounter()
        _ = fixture.router.findInMusicBrainz(
            selectedFiles: [fixture.file],
            openWindow: { windowRequests.increment() }
        )
        session.consumePendingIntent()

        XCTAssertEqual(session.selectedSource, .musicBrainz)
        try await waitUntil { musicBrainzClient.searchCount == 1 }
        XCTAssertEqual(windowRequests.value, 1)
        session.consumePendingIntent()
        XCTAssertEqual(musicBrainzClient.searchCount, 1)
    }

    @MainActor
    func testGenericOpenAfterFindReturnsToPickerWithoutResending() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let session = fixture.makeSession()
        let windowRequests = LockedCounter()

        _ = fixture.router.findInMusicBrainz(
            selectedFiles: [fixture.file],
            openWindow: { windowRequests.increment() }
        )
        session.consumePendingIntent()
        try await waitUntil { musicBrainzClient.searchCount == 1 }

        fixture.router.openGeneric(
            selectedFiles: [fixture.file],
            openWindow: { windowRequests.increment() }
        )
        session.consumePendingIntent()
        XCTAssertNil(session.selectedSource)
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(musicBrainzClient.searchCount, 1)
        XCTAssertEqual(windowRequests.value, 2)
    }

    @MainActor
    func testSourceTileSelectionNeverCrossDispatches() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let session = fixture.makeSession()

        session.select(.iTunes)
        session.select(.lrclib)
        session.select(.musicBrainz)
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(session.selectedSource, .musicBrainz)
        XCTAssertEqual(musicBrainzClient.searchCount, 0)
        XCTAssertEqual(lrclibClient.searchCount, 0)
    }

    @MainActor
    func testEmptySelectionFindIsInertAndGenericOpenStillPresentsPicker() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let windowRequests = LockedCounter()

        let opened = fixture.router.findInMusicBrainz(
            selectedFiles: [],
            openWindow: { windowRequests.increment() }
        )
        XCTAssertFalse(opened)
        XCTAssertEqual(windowRequests.value, 0)
        XCTAssertNil(fixture.activationStore.pendingIntentID)
        XCTAssertEqual(musicBrainzClient.searchCount, 0)
        XCTAssertEqual(lrclibClient.searchCount, 0)

        fixture.router.openGeneric(selectedFiles: [], openWindow: { windowRequests.increment() })
        XCTAssertEqual(windowRequests.value, 1)
        let session = fixture.makeSession()
        session.consumePendingIntent()
        XCTAssertNil(session.selectedSource)
        XCTAssertEqual(musicBrainzClient.searchCount, 0)
        XCTAssertEqual(lrclibClient.searchCount, 0)
    }

    @MainActor
    func testConsumedIntentCannotBeReplayedAfterWindowRecreation() async throws {
        let musicBrainzClient = RoutingMusicBrainzClient()
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let firstSession = fixture.makeSession()
        _ = fixture.router.findInMusicBrainz(selectedFiles: [fixture.file], openWindow: {})
        firstSession.consumePendingIntent()
        try await waitUntil { musicBrainzClient.searchCount == 1 }
        firstSession.closeWindowSession()

        let reopenedSession = fixture.makeSession()
        reopenedSession.consumePendingIntent()
        XCTAssertNil(reopenedSession.selectedSource)
        XCTAssertEqual(musicBrainzClient.searchCount, 1, "A reopened window must not resend a consumed intent")
    }

    @MainActor
    func testReplacementFindCancelsPreviousSearchAndSubmitsLatestOnce() async throws {
        let gate = RoutingProviderGate()
        let musicBrainzClient = RoutingMusicBrainzClient(suspendFirstCallOn: gate)
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let session = fixture.makeSession()
        let secondFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/02 - Second Title.mp3"),
            title: "Second Title",
            artist: "Second Artist",
            album: "Second Album"
        )

        _ = fixture.router.findInMusicBrainz(selectedFiles: [fixture.file], openWindow: {})
        session.consumePendingIntent()
        await gate.waitUntilStarted()

        _ = fixture.router.findInMusicBrainz(selectedFiles: [secondFile], openWindow: {})
        session.consumePendingIntent()
        try await waitUntil { musicBrainzClient.searchCount == 2 }

        XCTAssertEqual(fixture.musicBrainzStore.lastSubmittedQuery?.title, "Second Title")
        gate.release()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(musicBrainzClient.searchCount, 2)
    }

    @MainActor
    func testBackToSourcesCancelsTrackedSearchAndRetainsSeed() async throws {
        let gate = RoutingProviderGate()
        let musicBrainzClient = RoutingMusicBrainzClient(suspendFirstCallOn: gate)
        let lrclibClient = RoutingLRCLIBClient()
        let fixture = makeFixture(musicBrainzClient: musicBrainzClient, lrclibClient: lrclibClient)
        let session = fixture.makeSession()

        session.select(.musicBrainz)
        fixture.musicBrainzStore.search()
        await gate.waitUntilStarted()
        XCTAssertTrue(fixture.musicBrainzStore.isSearching)

        session.backToSources()
        XCTAssertNil(session.selectedSource)
        XCTAssertFalse(fixture.musicBrainzStore.isSearching)
        XCTAssertNotNil(fixture.musicBrainzStore.fileSelectionSummary, "Back to Sources retains the seeded inputs")
        gate.release()
    }

    @MainActor
    func testLRCLIBNavigationCancelsDepartingRowWithoutStartingSearch() async throws {
        let gate = RoutingProviderGate()
        let lrclibClient = RoutingLRCLIBClient(suspendFirstCallOn: gate)
        let fixture = makeFixture(
            musicBrainzClient: RoutingMusicBrainzClient(),
            lrclibClient: lrclibClient
        )
        let secondFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/02 - Second Lyrics.mp3"),
            title: "Second Lyrics",
            artist: "Artist",
            album: "Album"
        )
        fixture.lrclibStore.seed(from: [fixture.file, secondFile])

        fixture.lrclibStore.searchCurrentFile()
        await gate.waitUntilStarted()
        XCTAssertEqual(lrclibClient.searchCount, 1)

        fixture.lrclibStore.moveNext()
        XCTAssertEqual(fixture.lrclibStore.searchState, .idle)
        XCTAssertEqual(lrclibClient.searchCount, 1, "Moving rows must not start a search")

        fixture.lrclibStore.movePrevious()
        XCTAssertEqual(fixture.lrclibStore.searchState, .cancelled)
        XCTAssertEqual(lrclibClient.searchCount, 1)

        gate.release()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(lrclibClient.searchCount, 1)

        fixture.lrclibStore.searchCurrentFile()
        try await waitUntil { lrclibClient.searchCount == 2 }
    }

    @MainActor
    func testLRCLIBQueryValuesComeFromParentAndGrandparentFoldersAndTags() throws {
        let syntheticFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/Music/Artist Name/Album (2020)/CD1/01 - Track One.mp3"),
            title: "",
            artist: "",
            album: ""
        )
        let syntheticInput = LRCLIBFileSearchInput(file: syntheticFile)
        XCTAssertEqual(syntheticInput.title, "Track One")
        XCTAssertEqual(syntheticInput.artist, "Artist Name")
        XCTAssertEqual(syntheticInput.album, "Album (2020)")

        let request = try LRCLIBRequestBuilder.makeSearchRequest(
            for: syntheticInput.query,
            userAgent: "AudioMator/test"
        )
        let queryItems = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["track_name"], "Track One")
        XCTAssertEqual(values["artist_name"], "Artist Name")
        XCTAssertEqual(values["album_name"], "Album (2020)")
        XCTAssertFalse(values.values.contains { $0.contains("/tmp") || $0.contains("Music/") })
        XCTAssertFalse((request.url?.absoluteString ?? "").contains("Artist%20Name%2FAlbum"))

        let taggedFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/Other/Second Artist/Second Album/02 - Wrong Name.mp3"),
            title: "Tagged Title",
            artist: "Tagged Artist",
            album: "Tagged Album"
        )
        let taggedInput = LRCLIBFileSearchInput(file: taggedFile)
        XCTAssertEqual(taggedInput.title, "Tagged Title")
        XCTAssertEqual(taggedInput.artist, "Tagged Artist")
        XCTAssertEqual(taggedInput.album, "Tagged Album")
    }

    @MainActor
    func testDisclosureStatesActualLRCLIBFieldsAndFolderDerivation() {
        let summary = NetworkServiceDisclosure.LRCLIB.sentDataSummary
        XCTAssertTrue(summary.contains("track_name"))
        XCTAssertTrue(summary.contains("artist_name"))
        XCTAssertTrue(summary.contains("album_name"))
        XCTAssertTrue(summary.contains("duration"))
        XCTAssertTrue(summary.contains("parent or grandparent"))
        XCTAssertTrue(summary.contains("No full file path"))
        XCTAssertTrue(summary.contains("audio bytes"))

        let registryEntry = NetworkServiceDisclosure.allDisclosures.first { $0.id == .lrclib }
        XCTAssertEqual(registryEntry?.sentDataSummary, summary)

        XCTAssertTrue(NetworkServiceDisclosure.MusicBrainz.sentDataSummary.contains("release filters"))
        XCTAssertTrue(NetworkServiceDisclosure.MusicBrainz.sentDataSummary.contains("No full file path"))
        XCTAssertTrue(NetworkServiceDisclosure.iTunesArtwork.sentDataSummary.contains("media, entity, and limit"))
        XCTAssertTrue(NetworkServiceDisclosure.iTunesArtwork.sentDataSummary.contains("No full file path"))
    }

    // MARK: - Helpers

    private struct Fixture {
        let file: AudioFile
        let musicBrainzStore: MusicBrainzBrowserStore
        let lrclibStore: LRCLIBLyricsBrowserStore
        let activationStore: OnlineMetadataActivationStore
        let router: OnlineMetadataRoutingController

        @MainActor
        func makeSession() -> OnlineMetadataBrowserSessionModel {
            OnlineMetadataBrowserSessionModel(
                initialSource: nil,
                activationStore: activationStore,
                musicBrainzStore: musicBrainzStore,
                lrclibStore: lrclibStore,
                selectedFilesProvider: { [file] in [file] }
            )
        }
    }

    @MainActor
    private func makeFixture(
        musicBrainzClient: RoutingMusicBrainzClient,
        lrclibClient: RoutingLRCLIBClient
    ) -> Fixture {
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/01 - Routing Title.mp3"),
            title: "Routing Title",
            artist: "Routing Artist",
            album: "Routing Album"
        )
        let musicBrainzStore = MusicBrainzBrowserStore(
            client: musicBrainzClient,
            operationTimeout: .seconds(3)
        )
        let lrclibStore = LRCLIBLyricsBrowserStore(
            client: lrclibClient,
            providerCallTimeout: .seconds(3)
        )
        let activationStore = OnlineMetadataActivationStore()
        let router = OnlineMetadataRoutingController(
            musicBrainzStore: musicBrainzStore,
            lrclibStore: lrclibStore,
            activationStore: activationStore
        )
        return Fixture(
            file: file,
            musicBrainzStore: musicBrainzStore,
            lrclibStore: lrclibStore,
            activationStore: activationStore,
            router: router
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for routing condition")
    }
}

// MARK: - Fake providers

private enum RoutingProviderTestError: Error {
    case unexpectedDetailRequest
}

private nonisolated final class RoutingProviderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    var didStart: Bool {
        lock.withLock { started }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}

private nonisolated final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private nonisolated final class RoutingMusicBrainzClient: MusicBrainzBrowserClient, @unchecked Sendable {
    private let lock = NSLock()
    private var searchesValue: [MusicBrainzSearchQuery] = []
    private let gate: RoutingProviderGate?

    init(suspendFirstCallOn gate: RoutingProviderGate? = nil) {
        self.gate = gate
    }

    var searches: [MusicBrainzSearchQuery] {
        lock.withLock { searchesValue }
    }

    var searchCount: Int {
        lock.withLock { searchesValue.count }
    }

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        let callIndex = lock.withLock { () -> Int in
            searchesValue.append(query)
            return searchesValue.count
        }
        if callIndex == 1, let gate {
            await gate.wait()
        }
        return .recordings([])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        throw RoutingProviderTestError.unexpectedDetailRequest
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        throw RoutingProviderTestError.unexpectedDetailRequest
    }
}

private nonisolated final class RoutingLRCLIBClient: LRCLIBLyricsSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var searchesValue: [LRCLIBSearchQuery] = []
    private let gate: RoutingProviderGate?

    init(suspendFirstCallOn gate: RoutingProviderGate? = nil) {
        self.gate = gate
    }

    var searches: [LRCLIBSearchQuery] {
        lock.withLock { searchesValue }
    }

    var searchCount: Int {
        lock.withLock { searchesValue.count }
    }

    nonisolated func search(matching query: LRCLIBSearchQuery, limit: Int) async throws -> [LRCLIBLyricsCandidate] {
        let callIndex = lock.withLock { () -> Int in
            searchesValue.append(query)
            return searchesValue.count
        }
        if callIndex == 1, let gate {
            await gate.wait()
        }
        return []
    }
}
#endif
