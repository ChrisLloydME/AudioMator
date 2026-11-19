import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class iTunesStorefrontScopingTests: XCTestCase {
    private static let collectionID = 77
    private static let trackID = 7_701

    func testStorefrontChangeCancelsDelayedSearchAndNeverPublishesStaleResults() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.setSearchResults(.albums([StorefrontFixture.album(country: "us")]), for: "us")
        await catalog.setSearchResults(.albums([StorefrontFixture.album(country: "jp")]), for: "jp")
        let gate = await catalog.gateNextSearch(country: "us")
        let store = makeStore(catalog: catalog)

        store.mode = .album
        store.albumQuery = "Album"
        store.search()
        await gate.waitUntilStarted()

        store.selectStorefront(.jp)
        XCTAssertNil(store.publication)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.isSearching)
        XCTAssertNil(store.lastSubmittedQuery)

        await gate.release()
        for _ in 0..<40 {
            await Task.yield()
        }
        XCTAssertNil(store.publication, "A delayed response must not publish under a new storefront")

        store.search()
        try await waitUntil { store.publication != nil }
        XCTAssertEqual(store.publication?.storefront, .jp)
        XCTAssertEqual(store.publication?.results, .albums([StorefrontFixture.album(country: "jp")]))
        let searchRequests = await catalog.searchRequests
        XCTAssertEqual(searchRequests.map(\.country), ["us", "jp"])
    }

    func testSuccessfulSearchPublishesResultsStorefrontSelectionAndGenerationTogether() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.setSearchResults(.albums([StorefrontFixture.album(country: "us")]), for: "us")
        let store = makeStore(catalog: catalog)
        store.mode = .album
        store.albumQuery = "Album"

        store.search()
        try await waitUntil { store.publication != nil }

        let publication = try XCTUnwrap(store.publication)
        XCTAssertEqual(publication.storefront, .us)
        XCTAssertEqual(publication.query.country, "us")
        XCTAssertNil(publication.submittedSelection)
        XCTAssertEqual(publication.results, .albums([StorefrontFixture.album(country: "us")]))
        XCTAssertEqual(store.resultContext.generation, publication.generation)
        XCTAssertEqual(store.resultContext.storefront, .us)
        XCTAssertNil(store.submittedContext?.submittedSelection)

        let destination = store.detailDestination(for: StorefrontFixture.album(country: "us"))
        guard case .album(let album, let context) = destination else {
            return XCTFail("Expected an album destination")
        }
        XCTAssertEqual(album.collectionID, Self.collectionID)
        XCTAssertEqual(context.storefront, .us)
        XCTAssertEqual(context.generation, publication.generation)
    }

    func testSameCollectionIDRegionalAlbumsDriveAlbumAndTrackEntryPaths() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        await catalog.upsert(album: StorefrontFixture.album(country: "jp"), tracks: [
            StorefrontFixture.track(country: "jp", index: 1)
        ])
        await catalog.setSearchResults(.albums([StorefrontFixture.album(country: "us")]), for: "us")
        await catalog.setSearchResults(.albums([StorefrontFixture.album(country: "jp")]), for: "jp")

        let store = makeStore(catalog: catalog)
        store.mode = .album
        store.albumQuery = "Album"

        store.search()
        try await waitUntil { store.publication != nil }
        let usResult = try XCTUnwrap(firstAlbum(in: store.results))
        let usContext = store.resultContext

        store.selectStorefront(.jp)
        store.search()
        try await waitUntil { store.publication != nil }
        let jpResult = try XCTUnwrap(firstAlbum(in: store.results))
        let jpContext = store.resultContext
        XCTAssertEqual(usContext.storefront, .us)
        XCTAssertEqual(jpContext.storefront, .jp)

        let usAlbumDetail = try await store.albumDetail(for: usResult, context: usContext)
        XCTAssertEqual(usAlbumDetail.album.collectionName, "US Album")
        let usTrack = try XCTUnwrap(usAlbumDetail.tracks.first)
        let usTrackDetail = try await store.albumDetail(for: usTrack, context: usContext)
        XCTAssertEqual(usTrackDetail.album.collectionName, "US Album")

        let jpAlbumDetail = try await store.albumDetail(for: jpResult, context: jpContext)
        XCTAssertEqual(jpAlbumDetail.album.collectionName, "JP Album")
        let jpTrack = try XCTUnwrap(jpAlbumDetail.tracks.first)
        let jpTrackDetail = try await store.albumDetail(for: jpTrack, context: jpContext)
        XCTAssertEqual(jpTrackDetail.album.collectionName, "JP Album")

        // The originating context wins over whatever storefront the UI currently shows.
        let usViaJpScreen = try await store.albumDetail(for: usTrack, context: usContext)
        XCTAssertEqual(usViaJpScreen.album.collectionName, "US Album")

        let detailRequests = await catalog.detailRequests
        let requestedCountries = detailRequests.map(\.country)
        XCTAssertEqual(requestedCountries.sorted(), ["jp", "us"])
        XCTAssertEqual(requestedCountries.filter { $0 == "us" }.count, 1)
        XCTAssertEqual(requestedCountries.filter { $0 == "jp" }.count, 1)
    }

    func testAlbumDetailCacheIsKeyedByStorefrontWithAToBToACounts() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        await catalog.upsert(album: StorefrontFixture.album(country: "jp"), tracks: [
            StorefrontFixture.track(country: "jp", index: 1)
        ])
        let store = makeStore(catalog: catalog)
        let generation = UUID()
        let usContext = iTunesSearchContext(storefront: .us, generation: generation, submittedSelection: nil)
        let jpContext = iTunesSearchContext(storefront: .jp, generation: generation, submittedSelection: nil)
        let album = StorefrontFixture.album(country: "us")

        let firstUS = try await store.albumDetail(for: album, context: usContext)
        let jp = try await store.albumDetail(for: album, context: jpContext)
        let secondUS = try await store.albumDetail(for: album, context: usContext)

        XCTAssertEqual(firstUS.album.collectionName, "US Album")
        XCTAssertEqual(jp.album.collectionName, "JP Album")
        XCTAssertEqual(secondUS.album.collectionName, "US Album")
        let requests = await catalog.detailRequests
        XCTAssertEqual(requests, [
            .init(collectionID: Self.collectionID, country: "us"),
            .init(collectionID: Self.collectionID, country: "jp")
        ])
    }

    func testTwoLocalSelectionsShareCachedRemoteDetailWithoutLeakingPreview() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1),
            StorefrontFixture.track(country: "us", index: 2)
        ])
        let store = makeStore(catalog: catalog)
        let firstFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/01 - US Track 1.mp3"),
            title: "US Track 1",
            artist: "Artist",
            album: "US Album"
        )
        let secondFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/02 - US Track 2.mp3"),
            title: "US Track 2",
            artist: "Artist",
            album: "US Album"
        )
        let album = StorefrontFixture.album(country: "us")

        store.seed(from: [firstFile])
        let firstSelection = try XCTUnwrap(store.fileSelectionSummary)
        let firstContext = iTunesSearchContext(storefront: .us, generation: UUID(), submittedSelection: firstSelection)
        let firstDetail = try await store.albumDetail(for: album, context: firstContext)
        let firstFileIDs = try XCTUnwrap(firstDetail.selectionMatchPreview)
            .matchedAssignments.map(\.file.id)
        XCTAssertEqual(firstFileIDs, [firstFile.id.uuidString])

        store.seed(from: [secondFile])
        let secondSelection = try XCTUnwrap(store.fileSelectionSummary)
        let secondContext = iTunesSearchContext(storefront: .us, generation: UUID(), submittedSelection: secondSelection)
        let secondDetail = try await store.albumDetail(for: album, context: secondContext)
        let secondFileIDs = try XCTUnwrap(secondDetail.selectionMatchPreview)
            .matchedAssignments.map(\.file.id)
        XCTAssertEqual(secondFileIDs, [secondFile.id.uuidString])

        let detailRequestCount = await catalog.detailRequests.count
        XCTAssertEqual(detailRequestCount, 1, "Both selections must share the raw remote detail")
    }

    func testFallbackPreviewIsReusedOnlyForMatchingLineage() async throws {
        let catalog = RegionaliTunesCatalog()
        let firstFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/01 - US Track 1.mp3"),
            title: "US Track 1",
            artist: "Artist",
            album: "US Album"
        )
        let secondFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/02 - US Track 2.mp3"),
            title: "US Track 2",
            artist: "Artist",
            album: "US Album"
        )
        let counter = MatcherCallCounter()
        let store = makeStore(catalog: catalog) { selection, detail in
            counter.increment()
            return iTunesAlbumMatcher.match(selection: selection, detail: detail)
        }

        store.seed(from: [firstFile])
        let firstSelection = try XCTUnwrap(store.fileSelectionSummary)
        let usTrackOne = StorefrontFixture.track(country: "us", index: 1)
        let usTrackTwo = StorefrontFixture.track(country: "us", index: 2)
        let usDetail = iTunesAlbumDetail(
            album: StorefrontFixture.album(country: "us"),
            tracks: [usTrackOne, usTrackTwo],
            selectionMatchPreview: nil
        )
        let fallback = iTunesAlbumMatcher.match(selection: firstSelection, detail: usDetail)
        let resultWithFallback = StorefrontFixture.album(country: "us", preview: fallback)
        await catalog.setSearchResults(.albums([resultWithFallback]), for: "us")
        await catalog.upsert(album: resultWithFallback, tracks: usDetail.tracks)

        store.mode = .album
        store.albumQuery = "US Album"
        store.search()
        try await waitUntil { store.publication != nil }
        let matchingContext = store.resultContext
        XCTAssertEqual(matchingContext.submittedSelection, firstSelection)
        _ = try await store.albumDetail(for: resultWithFallback, context: matchingContext)
        XCTAssertEqual(counter.value, 0, "A fallback preview for the same lineage is reused without the matcher")

        store.seed(from: [secondFile])
        let secondSelection = try XCTUnwrap(store.fileSelectionSummary)
        let differentSelectionContext = iTunesSearchContext(
            storefront: matchingContext.storefront,
            generation: matchingContext.generation,
            submittedSelection: secondSelection
        )
        _ = try await store.albumDetail(for: resultWithFallback, context: differentSelectionContext)
        XCTAssertEqual(counter.value, 1, "A different local selection must be matched against its own inputs")
    }

    func testDelayedDetailAcrossCloseReopenDoesNotRepopulateCache() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        let gate = await catalog.gateNextDetail(country: "us", collectionID: Self.collectionID)
        let store = makeStore(catalog: catalog)
        let album = StorefrontFixture.album(country: "us")
        let context = iTunesSearchContext(storefront: .us, generation: UUID(), submittedSelection: nil)

        let delayed = Task {
            try await store.albumDetail(for: album, context: context)
        }
        await gate.waitUntilStarted()

        store.closeWindowSession()
        await gate.release()

        do {
            _ = try await delayed.value
            XCTFail("A detail completing after close/reopen must not publish")
        } catch is CancellationError {
            // Expected: the session that requested it is gone.
        }

        let reopened = try await store.albumDetail(for: album, context: context)
        XCTAssertEqual(reopened.album.collectionName, "US Album")
        let requestCount = await catalog.detailRequests.count
        XCTAssertEqual(requestCount, 2, "A stale completion must not repopulate the closed session's cache")
    }

    func testRegionalLookupFailureDoesNotPoisonCacheAndRecovers() async throws {
        let catalog = RegionaliTunesCatalog()
        await catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        await catalog.failDetail(for: "us")
        let store = makeStore(catalog: catalog)
        let album = StorefrontFixture.album(country: "us")
        let context = iTunesSearchContext(storefront: .us, generation: UUID(), submittedSelection: nil)

        do {
            _ = try await store.albumDetail(for: album, context: context)
            XCTFail("Expected the regional lookup to fail")
        } catch let error as iTunesClientError {
            guard case .invalidResponseBody = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let failureCount = await catalog.detailRequests.count
        XCTAssertEqual(failureCount, 1)

        await catalog.clearDetailFailure(for: "us")
        let recovered = try await store.albumDetail(for: album, context: context)
        XCTAssertEqual(recovered.album.collectionName, "US Album")
        let recoveredCount = await catalog.detailRequests.count
        XCTAssertEqual(recoveredCount, 2, "A failed detail must not be cached")
    }

    // MARK: - Helpers

    private func makeStore(
        catalog: RegionaliTunesCatalog,
        albumMatcher: @escaping @Sendable (iTunesFileSelectionSummary, iTunesAlbumDetail) -> iTunesAlbumMatchPreview = iTunesAlbumMatcher.match
    ) -> iTunesBrowserStore {
        iTunesBrowserStore(
            client: catalog,
            albumMatcher: albumMatcher,
            operationTimeout: .seconds(3)
        )
    }

    private func firstAlbum(in results: iTunesSearchResults) -> iTunesAlbumResult? {
        guard case .albums(let albums) = results else { return nil }
        return albums.first
    }

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
        XCTFail("Timed out waiting for storefront-scoping condition")
    }
}

// MARK: - Fake regional catalog

@MainActor private final class RegionaliTunesCatalog: iTunesBrowserClient, @unchecked Sendable {
    struct DetailRequest: Equatable, Sendable {
        let collectionID: Int
        let country: String
    }

    struct SearchRequest: Equatable, Sendable {
        let term: String
        let country: String
    }

    private struct AlbumFixture: Sendable {
        let album: iTunesAlbumResult
        let tracks: [iTunesTrackResult]
    }

    private var albumsByCountryAndID: [String: AlbumFixture] = [:]
    private var searchResultsByCountry: [String: iTunesSearchResults] = [:]
    private var searchGateCountry: String?
    private var searchGate: StorefrontGate?
    private var detailGateKey: String?
    private var detailGate: StorefrontGate?
    private var failingDetailCountries: Set<String> = []
    private(set) var detailRequests: [DetailRequest] = []
    private(set) var searchRequests: [SearchRequest] = []

    func setSearchResults(_ results: iTunesSearchResults, for country: String) {
        searchResultsByCountry[country] = results
    }

    func upsert(album: iTunesAlbumResult, tracks: [iTunesTrackResult]) {
        albumsByCountryAndID["\(album.country):\(album.collectionID)"] = AlbumFixture(album: album, tracks: tracks)
    }

    func gateNextSearch(country: String) -> StorefrontGate {
        let gate = StorefrontGate()
        searchGateCountry = country
        searchGate = gate
        return gate
    }

    func gateNextDetail(country: String, collectionID: Int) -> StorefrontGate {
        let gate = StorefrontGate()
        detailGateKey = "\(country):\(collectionID)"
        detailGate = gate
        return gate
    }

    func failDetail(for country: String) {
        failingDetailCountries.insert(country)
    }

    func clearDetailFailure(for country: String) {
        failingDetailCountries.remove(country)
    }

    func search(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        searchRequests.append(SearchRequest(term: query.searchTerm, country: query.country))
        if query.country == searchGateCountry, let gate = searchGate {
            searchGateCountry = nil
            searchGate = nil
            await gate.wait()
        }
        return searchResultsByCountry[query.country] ?? .tracks([])
    }

    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        detailRequests.append(DetailRequest(collectionID: collectionID, country: country))
        if "\(country):\(collectionID)" == detailGateKey, let gate = detailGate {
            detailGateKey = nil
            detailGate = nil
            await gate.wait()
        }
        guard !failingDetailCountries.contains(country) else {
            throw iTunesClientError.invalidResponseBody
        }
        guard let fixture = albumsByCountryAndID["\(country):\(collectionID)"] else {
            throw iTunesClientError.invalidResponseBody
        }
        return iTunesAlbumDetail(
            album: fixture.album,
            tracks: fixture.tracks,
            selectionMatchPreview: nil
        )
    }
}

private actor StorefrontGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func wait() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private nonisolated final class MatcherCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private enum StorefrontFixture {
    static func album(country: String, preview: iTunesAlbumMatchPreview? = nil) -> iTunesAlbumResult {
        iTunesAlbumResult(
            collectionID: 77,
            artistID: 1,
            collectionArtistID: 1,
            collectionName: "\(country.uppercased()) Album",
            artistName: "Artist",
            collectionArtistName: "Artist",
            trackCount: 2,
            releaseDate: "2020-01-01T08:00:00Z",
            primaryGenreName: "Pop",
            country: country,
            copyright: "© Fixture",
            contentAdvisoryRating: "",
            collectionExplicitness: "notExplicit",
            collectionViewURL: nil,
            artistViewURL: nil,
            selectionMatchPreview: preview,
            selectionMatchScore: preview.map { _ in 1.0 }
        )
    }

    static func track(country: String, index: Int) -> iTunesTrackResult {
        iTunesTrackResult(
            trackID: 7_700 + index,
            collectionID: 77,
            artistID: 1,
            collectionArtistID: 1,
            trackName: "\(country.uppercased()) Track \(index)",
            artistName: "Artist",
            collectionArtistName: "Artist",
            collectionName: "\(country.uppercased()) Album",
            trackNumber: index,
            trackCount: 2,
            discNumber: 1,
            discCount: 1,
            durationMilliseconds: 180_000,
            releaseDate: "2020-01-01T08:00:00Z",
            primaryGenreName: "Pop",
            country: country,
            copyright: "© Fixture",
            contentAdvisoryRating: "",
            kind: "song",
            wrapperType: "track",
            trackExplicitness: "notExplicit",
            collectionExplicitness: "notExplicit",
            trackViewURL: nil,
            collectionViewURL: nil,
            artistViewURL: nil
        )
    }
}
#endif
