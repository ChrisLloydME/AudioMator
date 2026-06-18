import Foundation
import XCTest
@testable import AudioMator

final class LRCLIBLyricsTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSearchRequestUsesExpectedQueryItemsAndHeaders() throws {
        let client = LRCLIBClient()
        let request = try client.makeSearchRequest(
            for: LRCLIBSearchQuery(
                trackName: "Sweeter Than Fiction",
                artistName: "Taylor Swift",
                albumName: "Single",
                durationSeconds: 235
            )
        )

        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "lrclib.net")
        XCTAssertEqual(components.path, "/api/search")

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(queryItems["track_name"], "Sweeter Than Fiction")
        XCTAssertEqual(queryItems["artist_name"], "Taylor Swift")
        XCTAssertEqual(queryItems["album_name"], "Single")
        XCTAssertEqual(queryItems["duration"], "235")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("AudioMator/") == true)
    }

    func testSearchDecodesSyncedPlainInstrumentalAndEmptyResults() async throws {
        let payload = """
        [
          {
            "id": 1,
            "name": "Synced",
            "trackName": "Synced Song",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 200,
            "instrumental": false,
            "plainLyrics": "plain",
            "syncedLyrics": "[00:01.00]synced"
          },
          {
            "id": 2,
            "name": "Plain",
            "trackName": "Plain Song",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 201,
            "instrumental": false,
            "plainLyrics": "plain only",
            "syncedLyrics": null
          },
          {
            "id": 3,
            "name": "Instrumental",
            "trackName": "Instrumental Song",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 202,
            "instrumental": true,
            "plainLyrics": null,
            "syncedLyrics": null
          }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, payload)
        }

        let client = LRCLIBClient(session: makeMockSession())
        let results = try await client.search(
            matching: LRCLIBSearchQuery(trackName: "Song", artistName: "Artist", albumName: "", durationSeconds: nil),
            limit: 20
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results[0].hasSyncedLyrics)
        XCTAssertTrue(results[1].hasPlainLyrics)
        XCTAssertFalse(results[1].hasSyncedLyrics)
        XCTAssertTrue(results[2].instrumental)
        XCTAssertEqual(results[2].lyricsAvailabilityLabel, "Instrumental")
    }

    func testRankingSortsExactSyncedDurationCloseCandidateFirst() {
        let query = LRCLIBSearchQuery(
            trackName: "Sweeter Than Fiction",
            artistName: "Taylor Swift",
            albumName: "Single",
            durationSeconds: 235
        )
        let candidates = [
            makeCandidate(id: 1, track: "Sweeter Than Fiction", artist: "Taylor Swift", album: "Single", duration: 235, syncedLyrics: "[00:01.00]Line"),
            makeCandidate(id: 2, track: "Sweeter Than Fiction", artist: "Taylor Swift", album: "Single", duration: 260, plainLyrics: "Line"),
            makeCandidate(id: 3, track: "Sweeter", artist: "Other Artist", album: "Other", duration: 235, syncedLyrics: "[00:01.00]Line")
        ]

        let ranked = LRCLIBCandidateRanker.rankedCandidates(candidates, for: query)

        XCTAssertEqual(ranked.map(\.id), [1, 2, 3])
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    @MainActor
    func testStoreHandlesNoResultsNoSyncedLyricsCancellationAndQueueNavigation() async throws {
        let firstFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/01 - First.m4a"),
            title: "First",
            artist: "Artist"
        )
        let secondFile = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/02 - Second.m4a"),
            title: "Second",
            artist: "Artist"
        )
        let client = MockLRCLIBSearchClient(results: [
            firstFile.id: [],
            secondFile.id: [
                makeCandidate(id: 10, track: "Second", artist: "Artist", album: "", duration: nil, plainLyrics: "Plain only")
            ]
        ])
        let store = LRCLIBLyricsBrowserStore(client: client)

        store.seed(from: [firstFile, secondFile])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)
        XCTAssertEqual(store.searchState, .loaded)
        XCTAssertTrue(store.rankedCandidates.isEmpty)

        store.moveNext()
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)
        XCTAssertEqual(store.queuePositionText, "2 of 2")
        XCTAssertFalse(store.hasSyncedCandidate)
        XCTAssertFalse(store.canApplySelectedCandidate)
        XCTAssertEqual(store.selectedCandidate?.lyricsAvailabilityLabel, "Plain only")

        store.movePrevious()
        XCTAssertEqual(store.queuePositionText, "1 of 2")

        let slowStore = LRCLIBLyricsBrowserStore(client: MockLRCLIBSearchClient(delayNanoseconds: 2_000_000_000))
        slowStore.seed(from: [firstFile])
        slowStore.searchCurrentFile()
        slowStore.cancelSearch()
        XCTAssertEqual(slowStore.searchState, .cancelled)
    }

    @MainActor
    func testApplyingSyncedLyricsWritesOnlyLyricsPropertyThroughRawMetadataPath() async throws {
        let file = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/lyrics-target.m4a"),
            title: "Title",
            artist: "Artist"
        )
        let pipeline = RecordingRawMetadataPipeline(
            file: file,
            initialPropertyMap: [
                "TITLE": "Title",
                "ARTIST": "Artist"
            ]
        )
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.files = [file]

        let didApply = await viewModel.applyLRCLIBSyncedLyrics("  [00:01.00]Synced line\n", to: file.id)

        XCTAssertTrue(didApply)
        XCTAssertEqual(pipeline.writtenPropertyMap?["TITLE"], "Title")
        XCTAssertEqual(pipeline.writtenPropertyMap?["ARTIST"], "Artist")
        XCTAssertEqual(pipeline.writtenPropertyMap?["LYRICS"], "[00:01.00]Synced line")
        XCTAssertEqual(pipeline.writtenPropertyMap?.count, 3)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func waitForSearchToFinish(
        _ store: LRCLIBLyricsBrowserStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while store.searchState == .searching && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotEqual(store.searchState, .searching, "Timed out waiting for LRCLIB search", file: file, line: line)
    }
}

private func makeCandidate(
    id: Int,
    track: String,
    artist: String,
    album: String,
    duration: Double?,
    plainLyrics: String? = nil,
    syncedLyrics: String? = nil,
    instrumental: Bool = false
) -> LRCLIBLyricsCandidate {
    LRCLIBLyricsCandidate(
        id: id,
        name: track,
        trackName: track,
        artistName: artist,
        albumName: album,
        duration: duration,
        instrumental: instrumental,
        plainLyrics: plainLyrics,
        syncedLyrics: syncedLyrics
    )
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: LRCLIBClientError.invalidResponse)
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class MockLRCLIBSearchClient: LRCLIBLyricsSearching, @unchecked Sendable {
    private let results: [AudioFile.ID: [LRCLIBLyricsCandidate]]
    private let delayNanoseconds: UInt64

    init(
        results: [AudioFile.ID: [LRCLIBLyricsCandidate]] = [:],
        delayNanoseconds: UInt64 = 0
    ) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func search(matching query: LRCLIBSearchQuery, limit: Int) async throws -> [LRCLIBLyricsCandidate] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let queryTrackName = await MainActor.run { query.trackName }
        for (_, candidates) in results {
            for candidate in candidates {
                let candidateTrackName = await MainActor.run { candidate.trackName }
                if candidateTrackName == queryTrackName {
                    return candidates
                }
            }
        }

        return []
    }
}

private final class RecordingRawMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let file: AudioFile
    private let initialPropertyMap: [String: String]
    private let lock = NSLock()
    private var _writtenPropertyMap: [String: String]?

    init(file: AudioFile, initialPropertyMap: [String: String]) {
        self.file = file
        self.initialPropertyMap = initialPropertyMap
    }

    var writtenPropertyMap: [String: String]? {
        lock.withLock { _writtenPropertyMap }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        file
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        initialPropertyMap
    }

    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        lock.withLock {
            _writtenPropertyMap = propertyMap
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
