import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
nonisolated final class iTunesStorefrontScopingTests: XCTestCase {
    private static let collectionID = 77
    private static let trackID = 7_701

    @MainActor
    func testStorefrontChangeCancelsDelayedSearchAndNeverPublishesStaleResults() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.setSearchResults(.albums([StorefrontFixture.album(country: "us")]), for: "us")
        catalog.setSearchResults(.albums([StorefrontFixture.album(country: "jp")]), for: "jp")
        let gate = catalog.gateNextSearch(country: "us")
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
        let searchRequests = catalog.searchRequests
        XCTAssertEqual(searchRequests.map(\.country), ["us", "jp"])
    }

    @MainActor
    func testLanguageChangeCancelsSearchAndScopesDetailsWithinOneStorefront() async throws {
        let catalog = RegionaliTunesCatalog()
        let album = StorefrontFixture.album(country: "hk")
        let track = StorefrontFixture.track(country: "hk", index: 1)
        catalog.upsert(album: album, tracks: [track])
        catalog.setSearchResults(.albums([album]), for: "hk")
        let store = makeStore(catalog: catalog)
        store.selectStorefront(.hk)
        store.mode = .album
        store.albumQuery = "Album"
        let gate = catalog.gateNextSearch(country: "hk")
        store.search()
        await gate.waitUntilStarted()

        let priorNavigation = store.navigationResetToken
        store.selectStorefrontLanguage(.traditionalChineseTaiwan)
        XCTAssertFalse(store.isSearching)
        XCTAssertNil(store.lastSubmittedQuery)
        XCTAssertNotEqual(store.navigationResetToken, priorNavigation)
        XCTAssertEqual(store.albumQuery, "Album")
        await gate.release()
        try await waitUntil { catalog.completedSearchCount == 1 }
        for _ in 0..<40 {
            await Task.yield()
        }
        XCTAssertNil(store.publication, "A delayed response must not publish under a new storefront language")
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.isSearching)

        store.search()
        try await waitUntil { store.publication != nil }
        let taiwanContext = try XCTUnwrap(store.submittedContext)
        XCTAssertEqual(taiwanContext.language, .traditionalChineseTaiwan)

        store.selectStorefrontLanguage(.traditionalChineseHongKong)
        XCTAssertNil(store.publication)
        store.search()
        try await waitUntil { store.publication != nil }
        let defaultContext = try XCTUnwrap(store.submittedContext)
        XCTAssertNil(defaultContext.language)
        XCTAssertEqual(catalog.searchRequests.map(\.language), [nil, .traditionalChineseTaiwan, nil])

        let taiwanDetail = try await store.albumDetail(for: track, context: taiwanContext)
        let hongKongDetail = try await store.albumDetail(for: album, context: defaultContext)
        let cachedDetail = try await store.albumDetail(for: album, context: taiwanContext)
        XCTAssertEqual(taiwanDetail.album.primaryGenreName, "華語流行樂")
        XCTAssertEqual(hongKongDetail.album.primaryGenreName, album.primaryGenreName)
        XCTAssertEqual(cachedDetail.album, taiwanDetail.album)
        XCTAssertEqual(catalog.detailRequests.map(\.language), [.traditionalChineseTaiwan, nil])

        store.selectStorefrontLanguage(.english)
        store.selectStorefront(.jp)
        XCTAssertEqual(store.storefrontLanguage, .japanese)
        XCTAssertNil(store.currentQuery.language)
    }

    @MainActor
    func testSuccessfulSearchPublishesResultsStorefrontSelectionAndGenerationTogether() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.setSearchResults(.albums([StorefrontFixture.album(country: "us")]), for: "us")
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

    @MainActor
    func testSameCollectionIDRegionalAlbumsDriveAlbumAndTrackEntryPaths() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        catalog.upsert(album: StorefrontFixture.album(country: "jp"), tracks: [
            StorefrontFixture.track(country: "jp", index: 1)
        ])
        catalog.setSearchResults(.albums([StorefrontFixture.album(country: "us")]), for: "us")
        catalog.setSearchResults(.albums([StorefrontFixture.album(country: "jp")]), for: "jp")

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

        let detailRequests = catalog.detailRequests
        let requestedCountries = detailRequests.map(\.country)
        XCTAssertEqual(requestedCountries.sorted(), ["jp", "us"])
        XCTAssertEqual(requestedCountries.filter { $0 == "us" }.count, 1)
        XCTAssertEqual(requestedCountries.filter { $0 == "jp" }.count, 1)
    }

    @MainActor
    func testAlbumDetailCacheIsKeyedByStorefrontWithAToBToACounts() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        catalog.upsert(album: StorefrontFixture.album(country: "jp"), tracks: [
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
        let requests = catalog.detailRequests
        XCTAssertEqual(requests, [
            .init(collectionID: Self.collectionID, country: "us"),
            .init(collectionID: Self.collectionID, country: "jp")
        ])
    }

    @MainActor
    func testTwoLocalSelectionsShareCachedRemoteDetailWithoutLeakingPreview() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
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

        let detailRequestCount = catalog.detailRequests.count
        XCTAssertEqual(detailRequestCount, 1, "Both selections must share the raw remote detail")
    }

    @MainActor
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
        catalog.setSearchResults(.albums([resultWithFallback]), for: "us")
        catalog.upsert(album: resultWithFallback, tracks: usDetail.tracks)

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

    @MainActor
    func testDelayedDetailAcrossCloseReopenDoesNotRepopulateCache() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        let gate = catalog.gateNextDetail(country: "us", collectionID: Self.collectionID)
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
        let requestCount = catalog.detailRequests.count
        XCTAssertEqual(requestCount, 2, "A stale completion must not repopulate the closed session's cache")
    }

    @MainActor
    func testRegionalLookupFailureDoesNotPoisonCacheAndRecovers() async throws {
        let catalog = RegionaliTunesCatalog()
        catalog.upsert(album: StorefrontFixture.album(country: "us"), tracks: [
            StorefrontFixture.track(country: "us", index: 1)
        ])
        catalog.failDetail(for: "us")
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
        let failureCount = catalog.detailRequests.count
        XCTAssertEqual(failureCount, 1)

        catalog.clearDetailFailure(for: "us")
        let recovered = try await store.albumDetail(for: album, context: context)
        XCTAssertEqual(recovered.album.collectionName, "US Album")
        let recoveredCount = catalog.detailRequests.count
        XCTAssertEqual(recoveredCount, 2, "A failed detail must not be cached")
    }

    // MARK: - Helpers

    @MainActor
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
        XCTFail("Timed out waiting for storefront-scoping condition")
    }
}

// MARK: - Fake regional catalog

@MainActor private final class RegionaliTunesCatalog: iTunesBrowserClient {
    struct DetailRequest: Equatable, Sendable {
        let collectionID: Int
        let country: String
        var language: iTunesCatalogLanguage? = nil
    }

    struct SearchRequest: Equatable, Sendable {
        let term: String
        let country: String
        let language: iTunesCatalogLanguage?
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
    private(set) var completedSearchCount = 0

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
        defer { completedSearchCount += 1 }
        searchRequests.append(SearchRequest(term: query.searchTerm, country: query.country, language: query.language))
        if query.country == searchGateCountry, let gate = searchGate {
            searchGateCountry = nil
            searchGate = nil
            await gate.wait()
        }
        return searchResultsByCountry[query.country] ?? .tracks([])
    }

    func albumDetail(collectionID: Int, country: String, language: iTunesCatalogLanguage?) async throws -> iTunesAlbumDetail {
        detailRequests.append(DetailRequest(collectionID: collectionID, country: country, language: language))
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
            album: language == .traditionalChineseTaiwan
                ? StorefrontFixture.album(country: country, genre: "華語流行樂")
                : fixture.album,
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
    static func album(country: String, preview: iTunesAlbumMatchPreview? = nil, genre: String = "Pop") -> iTunesAlbumResult {
        iTunesAlbumResult(
            collectionID: 77,
            artistID: 1,
            collectionArtistID: 1,
            collectionName: "\(country.uppercased()) Album",
            artistName: "Artist",
            collectionArtistName: "Artist",
            trackCount: 2,
            releaseDate: "2020-01-01T08:00:00Z",
            primaryGenreName: genre,
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
