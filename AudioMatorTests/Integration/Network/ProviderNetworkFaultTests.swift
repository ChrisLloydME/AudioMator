import Foundation
import ImageIO
import XCTest
@testable import AudioMator

nonisolated final class ProviderNetworkFaultTests: XCTestCase {
    override func tearDown() {
        ProviderFaultURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testMusicBrainzMapsHTTPAndInvalidPayloadFailures() async throws {
        ProviderFaultURLProtocol.requestHandler = response(statusCode: 503, data: Data())
        let client = MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0),
            retryPolicy: .disabled
        )

        do {
            _ = try await client.search(matching: MusicBrainzSearchQuery(title: "Fault"), limit: 1)
            XCTFail("Expected MusicBrainz HTTP failure")
        } catch let error as MusicBrainzClientError {
            guard case .requestFailed(statusCode: 503) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        ProviderFaultURLProtocol.requestHandler = response(
            statusCode: 200,
            data: Data(#"{"unexpected":true}"#.utf8)
        )

        do {
            _ = try await client.search(matching: MusicBrainzSearchQuery(title: "Fault"), limit: 1)
            XCTFail("Expected MusicBrainz decoding failure")
        } catch let error as MusicBrainzClientError {
            guard case .decodingFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testITunesMapsHTTPAndInvalidPayloadFailures() async throws {
        ProviderFaultURLProtocol.requestHandler = response(statusCode: 429, data: Data())
        let client = iTunesClient(session: makeSession())
        let query = iTunesSearchQuery(mode: .track, title: "Fault")

        do {
            _ = try await client.search(matching: query, limit: 1)
            XCTFail("Expected iTunes HTTP failure")
        } catch let error as iTunesClientError {
            guard case .requestFailed(429) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        ProviderFaultURLProtocol.requestHandler = response(
            statusCode: 200,
            data: Data(#"{"results":"not-an-array"}"#.utf8)
        )

        do {
            _ = try await client.search(matching: query, limit: 1)
            XCTFail("Expected iTunes invalid response failure")
        } catch let error as iTunesClientError {
            guard case .invalidResponseBody = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testLRCLIBMapsHTTPAndInvalidPayloadFailures() async throws {
        ProviderFaultURLProtocol.requestHandler = response(statusCode: 502, data: Data())
        let client = LRCLIBClient(session: makeSession())
        let query = LRCLIBSearchQuery(
            trackName: "Fault",
            artistName: "Artist",
            albumName: "",
            durationSeconds: nil
        )

        do {
            _ = try await client.search(matching: query, limit: 1)
            XCTFail("Expected LRCLIB HTTP failure")
        } catch let error as LRCLIBClientError {
            XCTAssertEqual(error, .requestFailed(statusCode: 502))
        }

        ProviderFaultURLProtocol.requestHandler = response(
            statusCode: 200,
            data: Data(#"{"not":"an-array"}"#.utf8)
        )

        do {
            _ = try await client.search(matching: query, limit: 1)
            XCTFail("Expected LRCLIB decoding failure")
        } catch is DecodingError {
            // Expected: the caller receives the concrete invalid-payload failure.
        }
    }

    @MainActor
    func testProviderTimeoutsRemainDistinguishableFromHTTPAndDecodeFailures() async throws {
        ProviderFaultURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let operations: [() async throws -> Void] = [
            {
                _ = try await MusicBrainzClient(
                    session: self.makeSession(),
                    rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
                ).search(matching: MusicBrainzSearchQuery(title: "Timeout"), limit: 1)
            },
            {
                _ = try await iTunesClient(session: self.makeSession()).search(
                    matching: iTunesSearchQuery(mode: .track, title: "Timeout"),
                    limit: 1
                )
            },
            {
                _ = try await LRCLIBClient(session: self.makeSession()).search(
                    matching: LRCLIBSearchQuery(
                        trackName: "Timeout",
                        artistName: "Artist",
                        albumName: "",
                        durationSeconds: nil
                    ),
                    limit: 1
                )
            }
        ]

        for operation in operations {
            do {
                try await operation()
                XCTFail("Expected timeout")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .timedOut)
            }
        }
    }

    @MainActor
    func testMusicBrainzITunesAndArtworkRequestsUseFiniteExplicitTimeouts() async throws {
        let requestRecorder = ProviderRequestRecorder()
        ProviderFaultURLProtocol.requestHandler = { request in
            requestRecorder.record(request)
            let data: Data
            if request.url?.host == "musicbrainz.org" {
                data = Data(#"{"created":"","count":0,"offset":0,"recordings":[]}"#.utf8)
            } else {
                data = Data(#"{"results":[]}"#.utf8)
            }
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, data)
        }

        _ = try await MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
        ).search(matching: MusicBrainzSearchQuery(title: "Timeout"), limit: 1)
        _ = try await iTunesClient(session: makeSession()).search(
            matching: iTunesSearchQuery(mode: .track, title: "Timeout"),
            limit: 1
        )
        _ = try await iTunesArtworkService(session: makeSession()).search(
            iTunesArtworkSearchRequest(query: "Timeout", entity: .album, limit: 1)
        )

        XCTAssertTrue(requestRecorder.hosts.contains("musicbrainz.org"))
        XCTAssertTrue(requestRecorder.hosts.contains("itunes.apple.com"))
        XCTAssertGreaterThanOrEqual(
            requestRecorder.hosts.filter { $0 == "itunes.apple.com" }.count,
            2
        )
        XCTAssertTrue(requestRecorder.timeoutIntervals.allSatisfy { $0 == 15 })
    }

    @MainActor
    func testMusicBrainzStaleStoredReleaseFallsBackAndReturnsCandidatesBeyondDetailCap() async throws {
        let staleID = "00000000-0000-0000-0000-000000000099"
        let ids = (1...5).map { String(format: "00000000-0000-0000-0000-%012d", $0) }
        let requests = ProviderRequestRecorder()
        ProviderFaultURLProtocol.requestHandler = { request in
            requests.record(request)
            let url = try XCTUnwrap(request.url)
            let status: Int
            let payload: [String: Any]
            if url.lastPathComponent == staleID {
                status = 404
                payload = [:]
            } else if url.path == "/ws/2/release" {
                status = 200
                payload = ["releases": ids.map { [
                    "id": $0, "title": "Album", "score": 100,
                    "artist-credit": [["name": "Artist", "artist": ["id": "artist", "name": "Artist"]]]
                ] as [String: Any] }]
            } else {
                status = 200
                payload = ["id": url.lastPathComponent, "title": "Album"]
            }
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)),
                try JSONSerialization.data(withJSONObject: payload))
        }
        let files = (1...2).map { number in
            MusicBrainzFileSearchInput(id: "file-\(number)", displayTitle: "Track \(number)",
                title: "Track \(number)", artist: "Artist", albumArtist: "Artist", album: "Album",
                trackNumber: String(number), trackTotal: 2, musicBrainzAlbumID: staleID)
        }
        let client = MusicBrainzClient(session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0), retryPolicy: .disabled)
        let results = try await client.searchFileSelections(matching: MusicBrainzSearchQuery(mode: .file, fileInputs: files), limit: 5)
        XCTAssertEqual(Set(results.map(\.id)), Set(ids))
        XCTAssertGreaterThan(requests.requestCount, 1, "Both stored-ID and text search paths must execute")
        XCTAssertLessThanOrEqual(results.filter { $0.selectionMatchScore != nil }.count, 3)
    }

    @MainActor
    func testITunesSearchAndLookupEncodeTheCatalogLanguage() async throws {
        ProviderFaultURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let locale = items.filter { $0.name == "lang" || $0.name == "l" }
            let country = items.first { $0.name == "country" }?.value
            if country == "us" {
                XCTAssertEqual(url.path, "/search")
                let entity = items.first { $0.name == "entity" }?.value
                XCTAssertEqual(locale, entity == "album" ? [URLQueryItem(name: "l", value: "es-MX")] : [])
            } else {
                XCTAssertEqual(country, "hk")
                XCTAssertEqual(url.path, "/lookup")
                XCTAssertEqual(locale, [URLQueryItem(name: "lang", value: "zh_tw")])
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            let data = Data(#"{"results":[{"wrapperType":"collection","collectionId":456,"collectionName":"Album"}]}"#.utf8)
            return (response, data)
        }
        let client = iTunesClient(session: makeSession())
        let queries: [iTunesSearchQuery] = [
            .init(mode: .track, title: "Track"),
            .init(mode: .album, album: "Album", language: .spanishMexico),
            .init(mode: .link, link: "https://music.apple.com/us/album/album/456?i=123",
                  country: "hk", language: .traditionalChineseTaiwan),
            .init(mode: .link, link: "https://music.apple.com/us/album/album/456",
                  country: "hk", language: .traditionalChineseTaiwan),
            .init(mode: .upc, upc: "043396499461", country: "hk", language: .traditionalChineseTaiwan)
        ]
        for query in queries {
            _ = try await client.search(matching: query, limit: 5)
        }
        _ = try await client.albumDetail(collectionID: 456, country: "hk", language: .traditionalChineseTaiwan)
    }

    @MainActor
    func testITunesStaleStoredAlbumFallsBackToTextSearch() async throws {
        let requests = ProviderRequestRecorder()
        ProviderFaultURLProtocol.requestHandler = { request in
            requests.record(request)
            let url = try XCTUnwrap(request.url)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertTrue(items.contains(URLQueryItem(name: "country", value: "hk")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "lang", value: "zh_tw")))
            let payload: [String: Any] = url.path == "/lookup"
                ? ["resultCount": 0, "results": []]
                : ["resultCount": 1, "results": [["wrapperType": "track", "kind": "song", "trackId": 123,
                    "collectionId": 456, "trackName": "Track", "artistName": "Artist", "collectionName": "Album"]]]
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                try JSONSerialization.data(withJSONObject: payload))
        }
        let file = iTunesFileSearchInput(id: "file", displayTitle: "Track", title: "Track", artist: "Artist",
            albumArtist: "Artist", album: "Album", trackNumber: "1", discNumber: "1", trackTotal: 1,
            durationMilliseconds: nil, releaseDate: "", barcode: "", itunesAlbumID: "999",
            itunesArtistID: "", itunesCatalogID: "")
        let results = try await iTunesClient(session: makeSession()).search(
            matching: iTunesSearchQuery(mode: .file, country: "hk", language: .traditionalChineseTaiwan, fileInputs: [file]),
            limit: 5
        )
        guard case .tracks(let tracks) = results else { return XCTFail("Expected text-search track results") }
        XCTAssertEqual(tracks.map(\.trackID), [123])
        XCTAssertEqual(requests.requestCount, 2)
    }

    @MainActor
    func testMusicBrainzMultiFileNoResultSearchHasBoundedFallbackRequests() async throws {
        let requestRecorder = ProviderRequestRecorder()
        ProviderFaultURLProtocol.requestHandler = { request in
            requestRecorder.record(request)
            let data = request.url?.path.contains("/release") == true
                ? Data(#"{"releases":[]}"#.utf8)
                : Data(#"{"recordings":[]}"#.utf8)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, data)
        }
        let files = (1...3).map { trackNumber in
            MusicBrainzFileSearchInput(
                id: "file-\(trackNumber)",
                displayTitle: "Track \(trackNumber)",
                title: "Track \(trackNumber)",
                artist: "Artist",
                albumArtist: "Artist",
                album: "Album",
                trackNumber: String(trackNumber),
                trackTotal: 3,
                durationMilliseconds: 180_000
            )
        }
        let query = MusicBrainzSearchQuery(mode: .file, fileInputs: files)
        let client = MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
        )

        let results = try await client.search(matching: query, limit: 25)

        XCTAssertEqual(results, .releases([]))
        XCTAssertGreaterThanOrEqual(
            requestRecorder.requestCount,
            1,
            "The multi-file fallback must actually issue requests."
        )
        XCTAssertTrue(requestRecorder.hosts.allSatisfy { $0 == "musicbrainz.org" })
        XCTAssertLessThanOrEqual(
            requestRecorder.requestCount,
            3,
            "Each multi-file fallback stage should be represented by at most one request."
        )
    }

    @MainActor
    func testMusicBrainzReusesSuccessfulIdenticalSearchResponse() async throws {
        let requestRecorder = ProviderRequestRecorder()
        ProviderFaultURLProtocol.requestHandler = { request in
            requestRecorder.record(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (
                response,
                Data(#"{"created":"","count":0,"offset":0,"recordings":[]}"#.utf8)
            )
        }
        let client = MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
        )
        let query = MusicBrainzSearchQuery(title: "Cached Search")

        _ = try await client.search(matching: query, limit: 25)
        let firstSearchRequestCount = requestRecorder.requestCount
        _ = try await client.search(matching: query, limit: 25)

        XCTAssertGreaterThan(firstSearchRequestCount, 0)
        XCTAssertEqual(requestRecorder.requestCount, firstSearchRequestCount)
    }

    @MainActor
    func testMusicBrainzRetriesServiceUnavailableOnce() async throws {
        let requestRecorder = ProviderRequestRecorder()
        ProviderFaultURLProtocol.requestHandler = { request in
            requestRecorder.record(request)
            let statusCode = requestRecorder.requestCount == 1 ? 503 : 200
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            let data = statusCode == 503
                ? Data()
                : Data(
                    #"{"created":"","count":1,"offset":0,"recordings":[{"id":"00000000-0000-0000-0000-000000000001","title":"Retry Result","score":100}]}"#.utf8
                )
            return (response, data)
        }
        let client = MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0),
            retryPolicy: MusicBrainzRetryPolicy(maximumRetryCount: 1, baseDelaySeconds: 0)
        )

        let results = try await client.search(
            matching: MusicBrainzSearchQuery(title: "Retry Result"),
            limit: 1
        )

        XCTAssertEqual(requestRecorder.requestCount, 2)
        guard case let .recordings(recordings) = results else {
            return XCTFail("Expected recording results after retrying the request.")
        }
        XCTAssertEqual(recordings.map(\.title), ["Retry Result"])
    }

    // MARK: - AM-10 · Validate MusicBrainz responses before cache admission

    @MainActor
    func testMusicBrainzInvalidJSONThenValidResponseRecoversForEveryRequestShape() async throws {
        for shape in ProviderMusicBrainzRequestShape.allCases {
            let script = ProviderScriptedTransport()
            script.setMode(.invalidJSON)
            ProviderFaultURLProtocol.requestHandler = { request in try script.response(for: request) }
            let client = makeScriptedMusicBrainzClient()

            do {
                try await shape.perform(on: client)
                XCTFail("Expected a decoding failure for \(shape).")
            } catch let error as MusicBrainzClientError {
                guard case .decodingFailed = error else {
                    return XCTFail("Unexpected error for \(shape): \(error)")
                }
            }

            let failedRequestCount = script.requestCount
            XCTAssertEqual(failedRequestCount, 1, "\(shape) must attempt exactly one transport request before failing")

            script.setMode(.success(shape.validBody))
            try await shape.perform(on: client)
            let recoveredRequestCount = script.requestCount
            XCTAssertEqual(recoveredRequestCount, 2, "\(shape) must retry the same URL once and decode successfully")

            try await shape.perform(on: client)
            XCTAssertEqual(
                script.requestCount,
                recoveredRequestCount,
                "\(shape) must reuse the validated cache entry instead of refetching."
            )
        }
    }

    @MainActor
    func testMusicBrainzWrongSchemaJSONIsNotAdmittedForEveryRequestShape() async throws {
        for shape in ProviderMusicBrainzRequestShape.allCases {
            let script = ProviderScriptedTransport()
            script.setMode(.wrongSchema)
            ProviderFaultURLProtocol.requestHandler = { request in try script.response(for: request) }
            let client = makeScriptedMusicBrainzClient()

            do {
                try await shape.perform(on: client)
                XCTFail("Expected a decoding failure for \(shape).")
            } catch let error as MusicBrainzClientError {
                guard case .decodingFailed = error else {
                    return XCTFail("Unexpected error for \(shape): \(error)")
                }
            }
            XCTAssertEqual(script.requestCount, 1, "\(shape) must attempt exactly one transport request before failing")

            script.setMode(.success(shape.validBody))
            try await shape.perform(on: client)
            XCTAssertEqual(
                script.requestCount,
                2,
                "\(shape) must refetch after a wrong-schema response instead of using a poisoned cache entry."
            )
        }
    }

    @MainActor
    func testMusicBrainzUnsuccessfulSharedLoadsLeaveNoCachedEntry() async throws {
        let failureModes: [(name: String, mode: ProviderScriptedTransportMode)] = [
            ("http 503", .httpStatus(503)),
            ("timeout", .transportError(.timedOut)),
            ("transport cancellation", .transportError(.cancelled))
        ]
        let shape = ProviderMusicBrainzRequestShape.recordingLookup

        for failure in failureModes {
            let script = ProviderScriptedTransport()
            script.setMode(failure.mode)
            ProviderFaultURLProtocol.requestHandler = { request in try script.response(for: request) }
            let client = makeScriptedMusicBrainzClient()

            do {
                try await shape.perform(on: client)
                XCTFail("Expected \(failure.name) to fail.")
            } catch is MusicBrainzClientError {
                // Expected mapping for non-2xx status.
            } catch let error as URLError {
                XCTAssertTrue(
                    [.timedOut, .cancelled].contains(error.code),
                    "Unexpected transport error for \(failure.name): \(error)"
                )
            } catch is CancellationError {
                // Expected when Foundation maps a cancelled URLProtocol load to task cancellation.
            }
            let failedRequestCount = script.requestCount
            XCTAssertGreaterThan(failedRequestCount, 0)

            script.setMode(.success(shape.validBody))
            try await shape.perform(on: client)
            let recoveredRequestCount = script.requestCount
            XCTAssertGreaterThan(recoveredRequestCount, failedRequestCount)

            try await shape.perform(on: client)
            XCTAssertEqual(
                script.requestCount,
                recoveredRequestCount,
                "\(failure.name) must not have poisoned the cache."
            )
        }
    }

    @MainActor
    func testMusicBrainzCoalescedWaitersShareOneInvalidFetchThenRecover() async throws {
        let script = ProviderScriptedTransport()
        let gate = ProviderResponseGate()
        script.setMode(.invalidJSON)
        script.blockFirstRequest(on: gate)
        ProviderFaultURLProtocol.requestHandler = { request in try script.response(for: request) }
        let client = makeScriptedMusicBrainzClient()
        let recordingID = ProviderMusicBrainzFixture.recordingID

        let first = Task { try await client.recordingDetail(id: recordingID) }
        let second = Task { try await client.recordingDetail(id: recordingID) }
        let started = try await waitUntil { gate.didStart }
        XCTAssertTrue(started, "The shared fetch must start before both waiters continue.")
        for _ in 0..<20 {
            await Task.yield()
        }
        gate.release()

        var decodingFailures = 0
        for task in [first, second] {
            do {
                _ = try await task.value
                XCTFail("Expected the shared invalid response to fail both waiters.")
            } catch let error as MusicBrainzClientError {
                if case .decodingFailed = error {
                    decodingFailures += 1
                }
            }
        }
        XCTAssertEqual(decodingFailures, 2)
        XCTAssertEqual(script.requestCount, 1, "Both waiters must share one transport request.")

        script.setMode(.success(ProviderMusicBrainzRequestShape.recordingLookup.validBody))
        _ = try await client.recordingDetail(id: recordingID)
        XCTAssertEqual(script.requestCount, 2, "A retry after an invalid shared response must fetch again.")

        _ = try await client.recordingDetail(id: recordingID)
        XCTAssertEqual(script.requestCount, 2, "The recovered response must be cached.")
    }

    @MainActor
    func testMusicBrainzCancelledCoalescedWaiterDoesNotPoisonSharedSuccess() async throws {
        let script = ProviderScriptedTransport()
        let gate = ProviderResponseGate()
        script.setMode(.success(ProviderMusicBrainzRequestShape.recordingLookup.validBody))
        script.blockFirstRequest(on: gate)
        ProviderFaultURLProtocol.requestHandler = { request in try script.response(for: request) }
        let client = makeScriptedMusicBrainzClient()
        let recordingID = ProviderMusicBrainzFixture.recordingID

        let cancelledWaiter = Task { try await client.recordingDetail(id: recordingID) }
        let survivingWaiter = Task { try await client.recordingDetail(id: recordingID) }
        let started = try await waitUntil { gate.didStart }
        XCTAssertTrue(started)
        for _ in 0..<20 {
            await Task.yield()
        }
        cancelledWaiter.cancel()
        gate.release()

        let survived = try await survivingWaiter.value
        XCTAssertEqual(survived.id, recordingID)
        _ = try? await cancelledWaiter.value
        XCTAssertEqual(
            script.requestCount,
            1,
            "A cancelled waiter must not invalidate the shared response or start a second fetch."
        )

        _ = try await client.recordingDetail(id: recordingID)
        XCTAssertEqual(script.requestCount, 1, "The shared successful response must have been cached.")
    }

    @MainActor
    func testMusicBrainzRecordingSearchScoreAcceptsIntegerStringAndDefaults() async throws {
        let validCases: [(name: String, field: String, expected: Int)] = [
            ("integer", #""score":100"#, 100),
            ("numeric string", #""score":"100""#, 100),
            ("absent", "", 0),
            ("null", #""score":null"#, 0)
        ]

        for testCase in validCases {
            let client = makeSingleResponseClient(
                ProviderMusicBrainzFixture.recordingSearch(scoreField: testCase.field)
            )
            let results = try await client.searchRecordings(
                matching: MusicBrainzSearchQuery(title: "Numeric"),
                limit: 1
            )
            XCTAssertEqual(results.first?.score, testCase.expected, testCase.name)
        }
    }

    @MainActor
    func testMusicBrainzReleaseSearchScoreAcceptsIntegerStringAndDefaults() async throws {
        let validCases: [(name: String, field: String, expected: Int)] = [
            ("integer", #""score":75"#, 75),
            ("numeric string", #""score":"75""#, 75),
            ("absent", "", 0),
            ("null", #""score":null"#, 0)
        ]

        for testCase in validCases {
            let client = makeSingleResponseClient(
                ProviderMusicBrainzFixture.releaseSearch(scoreField: testCase.field)
            )
            let results = try await client.searchReleases(
                matching: MusicBrainzSearchQuery(mode: .album, album: "Numeric"),
                limit: 1
            )
            XCTAssertEqual(results.first?.score, testCase.expected, testCase.name)
        }
    }

    @MainActor
    func testMusicBrainzSearchScoresRejectMalformedOverflowAndNonIntegerValues() async throws {
        let invalidFields: [(name: String, field: String)] = [
            ("malformed string", #""score":"abc""#),
            ("decimal string", #""score":"1.5""#),
            ("overflow string", #""score":"99999999999999999999""#),
            ("overflow number", #""score":99999999999999999999"#),
            ("decimal number", #""score":1.5"#)
        ]

        for testCase in invalidFields {
            let recordingClient = makeSingleResponseClient(
                ProviderMusicBrainzFixture.recordingSearch(scoreField: testCase.field)
            )
            do {
                _ = try await recordingClient.searchRecordings(
                    matching: MusicBrainzSearchQuery(title: "Numeric"),
                    limit: 1
                )
                XCTFail("Expected recording \(testCase.name) score to fail decoding.")
            } catch let error as MusicBrainzClientError {
                guard case .decodingFailed(let detail) = error else {
                    return XCTFail("Unexpected recording error for \(testCase.name): \(error)")
                }
                XCTAssertTrue(
                    detail.lowercased().contains("score"),
                    "Expected a field-level score error, got: \(detail)"
                )
            }

            let releaseClient = makeSingleResponseClient(
                ProviderMusicBrainzFixture.releaseSearch(scoreField: testCase.field)
            )
            do {
                _ = try await releaseClient.searchReleases(
                    matching: MusicBrainzSearchQuery(mode: .album, album: "Numeric"),
                    limit: 1
                )
                XCTFail("Expected release \(testCase.name) score to fail decoding.")
            } catch let error as MusicBrainzClientError {
                guard case .decodingFailed = error else {
                    return XCTFail("Unexpected release error for \(testCase.name): \(error)")
                }
            }
        }
    }

    @MainActor
    func testMusicBrainzMalformedNumericResponseIsNotCached() async throws {
        let script = ProviderScriptedTransport()
        script.setMode(.success(ProviderMusicBrainzFixture.recordingSearch(scoreField: #""score":"abc""#)))
        ProviderFaultURLProtocol.requestHandler = { request in try script.response(for: request) }
        let client = makeScriptedMusicBrainzClient()

        do {
            _ = try await client.searchRecordings(
                matching: MusicBrainzSearchQuery(title: "Numeric"),
                limit: 1
            )
            XCTFail("Expected the malformed score to fail decoding.")
        } catch let error as MusicBrainzClientError {
            guard case .decodingFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let failedRequestCount = script.requestCount

        script.setMode(.success(ProviderMusicBrainzFixture.recordingSearch(scoreField: #""score":100"#)))
        let results = try await client.searchRecordings(
            matching: MusicBrainzSearchQuery(title: "Numeric"),
            limit: 1
        )
        XCTAssertEqual(results.first?.score, 100)
        XCTAssertGreaterThan(
            script.requestCount,
            failedRequestCount,
            "A malformed numeric field must not leave a cached entry."
        )
    }

    @MainActor
    func testMusicBrainzTermCountVotesAndRatingValueAcceptAlternateFormsAndDefaults() async throws {
        let cases: [(name: String, body: Data, expectedCount: Int?, expectedValue: Double?, expectedVotes: Int?)] = [
            (
                "integer forms",
                ProviderMusicBrainzFixture.recordingLookup(
                    countField: #""count":7"#,
                    ratingValueField: #""value":4.5"#,
                    votesField: #""votes-count":9"#
                ),
                7,
                4.5,
                9
            ),
            (
                "numeric string forms",
                ProviderMusicBrainzFixture.recordingLookup(
                    countField: #""count":"7""#,
                    ratingValueField: #""value":"4.5""#,
                    votesField: #""votes-count":"9""#
                ),
                7,
                4.5,
                9
            ),
            ("absent", ProviderMusicBrainzFixture.recordingLookup(), nil, nil, nil),
            (
                "null",
                ProviderMusicBrainzFixture.recordingLookup(
                    countField: #""count":null"#,
                    ratingValueField: #""value":null"#,
                    votesField: #""votes-count":null"#
                ),
                nil,
                nil,
                0
            )
        ]

        for testCase in cases {
            let client = makeSingleResponseClient(testCase.body)
            let detail = try await client.recordingDetail(id: ProviderMusicBrainzFixture.recordingID)
            XCTAssertEqual(detail.genres.first?.count, testCase.expectedCount, testCase.name)
            XCTAssertEqual(detail.rating?.value, testCase.expectedValue, testCase.name)
            XCTAssertEqual(detail.rating?.voteCount, testCase.expectedVotes, testCase.name)
        }
    }

    @MainActor
    func testMusicBrainzTermCountVotesAndRatingValueRejectMalformedOverflowAndNonfinite() async throws {
        let invalidBodies: [(name: String, body: Data)] = [
            ("malformed count", ProviderMusicBrainzFixture.recordingLookup(countField: #""count":"abc""#)),
            ("decimal count", ProviderMusicBrainzFixture.recordingLookup(countField: #""count":1.5"#)),
            ("overflow count", ProviderMusicBrainzFixture.recordingLookup(countField: #""count":99999999999999999999"#)),
            ("malformed votes", ProviderMusicBrainzFixture.recordingLookup(votesField: #""votes-count":"abc""#)),
            ("overflow votes", ProviderMusicBrainzFixture.recordingLookup(votesField: #""votes-count":99999999999999999999"#)),
            ("malformed rating value", ProviderMusicBrainzFixture.recordingLookup(ratingValueField: #""value":"abc""#)),
            ("nonfinite rating NaN", ProviderMusicBrainzFixture.recordingLookup(ratingValueField: #""value":"NaN""#)),
            ("nonfinite rating infinity", ProviderMusicBrainzFixture.recordingLookup(ratingValueField: #""value":"inf""#)),
            ("nonfinite rating string overflow", ProviderMusicBrainzFixture.recordingLookup(ratingValueField: #""value":"1e400""#)),
            ("nonfinite rating number overflow", ProviderMusicBrainzFixture.recordingLookup(ratingValueField: #""value":1e400"#))
        ]

        for testCase in invalidBodies {
            let client = makeSingleResponseClient(testCase.body)
            do {
                _ = try await client.recordingDetail(id: ProviderMusicBrainzFixture.recordingID)
                XCTFail("Expected \(testCase.name) to fail decoding.")
            } catch let error as MusicBrainzClientError {
                guard case .decodingFailed = error else {
                    return XCTFail("Unexpected error for \(testCase.name): \(error)")
                }
            }
        }
    }

    func testMusicBrainzScoreGapDecisionHandlesIntMinWithoutOverflowAndPreservesThresholds() {
        let preview = ProviderMusicBrainzFixture.matchPreview()

        func shouldStop(candidate: Int, next: Int?, evidence: Double = 0) -> Bool {
            MusicBrainzClient.shouldStopReleaseDetailVerification(
                candidate: ProviderMusicBrainzFixture.releaseResult(score: candidate),
                nextCandidate: next.map(ProviderMusicBrainzFixture.releaseResult(score:)),
                preview: preview,
                evidence: evidence
            )
        }

        XCTAssertTrue(shouldStop(candidate: 100, next: Int.min), "Int.min must not overflow the gap check")
        XCTAssertTrue(shouldStop(candidate: 100, next: 92), "An 8-point gap stops")
        XCTAssertFalse(shouldStop(candidate: 100, next: 93), "A 7-point gap continues")
        XCTAssertFalse(shouldStop(candidate: 89, next: Int.min), "Evidence below 90 continues")
        XCTAssertTrue(shouldStop(candidate: 50, next: Int.min, evidence: 1), "Evidence of one stops")
    }

    @MainActor
    func testArtworkNormalizerDownsamplesBeforePNGEncoding() throws {
        let sourceData = try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQAQMAAABNzu8aAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExURTNmmf////ENxh0AAAABYktHRAH/Ai3eAAAAB3RJTUUH6gccCAUaXeL69AAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0wNy0yOFQwODowNToyNiswMDowMA6jkt8AAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMDctMjhUMDg6MDU6MjYrMDA6MDB//ipjAAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTA3LTI4VDA4OjA1OjI2KzAwOjAwKOsLvAAAAAxJREFUCNdjYKAuAAAAUAABIhPodQAAAABJRU5ErkJggg=="
            )
        )

        let normalizedData = try ArtworkImageNormalizer.normalizedPNGData(
            from: sourceData,
            maximumPixelDimension: 8,
            maximumSourcePixelCount: 1_024
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(normalizedData as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 8)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 4)
    }

    func testArtworkNormalizerRejectsOversizedEncodedInputBeforeDecode() throws {
        let sourceData = Data(repeating: 0, count: 32)

        XCTAssertThrowsError(
            try ArtworkImageNormalizer.normalizedPNGData(
                from: sourceData,
                maximumInputByteCount: 31
            )
        ) { error in
            XCTAssertEqual(error as? ArtworkImageNormalizerError, .inputTooLarge)
        }
    }

    func testArtworkNormalizerRejectsUnsafePixelCountBeforeDecode() throws {
        let sourceData = try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQAQMAAABNzu8aAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExURTNmmf////ENxh0AAAABYktHRAH/Ai3eAAAAB3RJTUUH6gccCAUaXeL69AAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0wNy0yOFQwODowNToyNiswMDowMA6jkt8AAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMDctMjhUMDg6MDU6MjYrMDA6MDB//ipjAAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTA3LTI4VDA4OjA1OjI2KzAwOjAwKOsLvAAAAAxJREFUCNdjYKAuAAAAUAABIhPodQAAAABJRU5ErkJggg=="
            )
        )

        XCTAssertThrowsError(
            try ArtworkImageNormalizer.normalizedPNGData(
                from: sourceData,
                maximumSourcePixelCount: 511
            )
        ) { error in
            XCTAssertEqual(error as? ArtworkImageNormalizerError, .unsafeDimensions)
        }
    }

    @MainActor
    func testITunesArtworkDownloadNormalizesAValidResponseFromTemporaryStorage() async throws {
        let sourceData = try XCTUnwrap(
            Data(
                base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAQAQMAAABNzu8aAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExURTNmmf////ENxh0AAAABYktHRAH/Ai3eAAAAB3RJTUUH6gccCAUaXeL69AAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0wNy0yOFQwODowNToyNiswMDowMA6jkt8AAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMDctMjhUMDg6MDU6MjYrMDA6MDB//ipjAAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTA3LTI4VDA4OjA1OjI2KzAwOjAwKOsLvAAAAAxJREFUCNdjYKAuAAAAUAABIhPodQAAAABJRU5ErkJggg=="
            )
        )
        ProviderFaultURLProtocol.requestHandler = response(statusCode: 200, data: sourceData)
        let artworkURL = try XCTUnwrap(URL(string: "https://example.test/artwork.png"))
        let result = iTunesArtworkSearchResult(
            id: "fixture",
            title: "Fixture",
            subtitle: nil,
            thumbnailURL: nil,
            standardURL: artworkURL,
            hiresURL: nil,
            uncompressedURL: nil,
            pixelWidth: 32,
            pixelHeight: 16
        )

        let artwork = try await iTunesArtworkService(session: makeSession())
            .downloadArtworkData(for: result)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(artwork.pngData as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 32)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 16)
    }

    @MainActor
    func testLargeMusicBrainzPayloadLeavesMainActorSchedulableAndDecodesWithinDeadline() async throws {
        let responseGate = ProviderResponseGate()
        let recordings: [[String: Any]] = (0..<10_000).map { index in
            [
                "id": "00000000-0000-0000-0000-\(String(format: "%012d", index))",
                "title": "Synthetic Track \(index)",
                "score": 100,
                "artist-credit": [["name": "Synthetic Artist", "joinphrase": ""]],
                "releases": [[
                    "id": "10000000-0000-0000-0000-\(String(format: "%012d", index))",
                    "title": "Synthetic Album"
                ]]
            ]
        }
        let payload = try JSONSerialization.data(withJSONObject: ["recordings": recordings])
        ProviderFaultURLProtocol.requestHandler = { request in
            responseGate.blockUntilReleased()
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, payload)
        }
        let client = MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
        )

        let searchTask = Task {
            try await withAsyncTimeout(.seconds(5), operationName: "MusicBrainz stress decode") {
                try await client.search(
                    matching: MusicBrainzSearchQuery(title: "Synthetic Track"),
                    limit: 25
                )
            }
        }
        let requestStarted = try await waitUntil { responseGate.didStart }

        XCTAssertTrue(requestStarted)
        XCTAssertTrue(
            Thread.isMainThread,
            "The main actor must remain schedulable while the MusicBrainz response is pending."
        )

        responseGate.release()
        let results = try await searchTask.value
        guard case .recordings(let decodedRecordings) = results else {
            return XCTFail("Expected recording results")
        }
        XCTAssertEqual(decodedRecordings.count, 25)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderFaultURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    @MainActor
    private func makeScriptedMusicBrainzClient() -> MusicBrainzClient {
        MusicBrainzClient(
            session: makeSession(),
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0),
            retryPolicy: .disabled
        )
    }

    @MainActor
    private func makeSingleResponseClient(_ body: Data) -> MusicBrainzClient {
        ProviderFaultURLProtocol.requestHandler = response(statusCode: 200, data: body)
        return makeScriptedMusicBrainzClient()
    }

    @MainActor
    private func response(
        statusCode: Int,
        data: Data
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (response, data)
        }
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private nonisolated final class ProviderResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var started = false

    var didStart: Bool {
        lock.withLock { started }
    }

    func blockUntilReleased() {
        lock.withLock { started = true }
        semaphore.wait()
    }

    func release() {
        semaphore.signal()
    }
}

private final class ProviderRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [RecordedRequest] = []

    var timeoutIntervals: [TimeInterval] {
        lock.withLock { recordedRequests.map(\.timeoutInterval) }
    }

    var hosts: [String] {
        lock.withLock { recordedRequests.compactMap(\.host) }
    }

    var requestCount: Int {
        lock.withLock { recordedRequests.count }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            recordedRequests.append(
                RecordedRequest(host: request.url?.host, timeoutInterval: request.timeoutInterval)
            )
        }
    }

    private struct RecordedRequest {
        let host: String?
        let timeoutInterval: TimeInterval
    }
}

private nonisolated final class ProviderFaultURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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

private nonisolated enum ProviderScriptedTransportMode {
    case success(Data)
    case invalidJSON
    case wrongSchema
    case httpStatus(Int)
    case transportError(URLError.Code)
}

private nonisolated final class ProviderScriptedTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var mode: ProviderScriptedTransportMode = .invalidJSON
    private var requestCountValue = 0
    private var firstRequestGate: ProviderResponseGate?

    var requestCount: Int {
        lock.withLock { requestCountValue }
    }

    func setMode(_ mode: ProviderScriptedTransportMode) {
        lock.withLock { self.mode = mode }
    }

    func blockFirstRequest(on gate: ProviderResponseGate) {
        lock.withLock { firstRequestGate = gate }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let (mode, gate) = lock.withLock { () -> (ProviderScriptedTransportMode, ProviderResponseGate?) in
            requestCountValue += 1
            let gate = requestCountValue == 1 ? firstRequestGate : nil
            if requestCountValue == 1 {
                firstRequestGate = nil
            }
            return (mode, gate)
        }

        gate?.blockUntilReleased()

        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw URLError(.badServerResponse)
        }

        switch mode {
        case .success(let data):
            return (response, data)
        case .invalidJSON:
            return (response, Data("this is not JSON".utf8))
        case .wrongSchema:
            return (response, Data(#"{"unexpected":true}"#.utf8))
        case .httpStatus(let statusCode):
            guard let statusResponse = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ) else {
                throw URLError(.badServerResponse)
            }
            return (statusResponse, Data())
        case .transportError(let code):
            throw URLError(code)
        }
    }
}

private nonisolated enum ProviderMusicBrainzRequestShape: CaseIterable {
    case recordingSearch
    case releaseSearch
    case recordingLookup
    case releaseLookup

    var validBody: Data {
        switch self {
        case .recordingSearch:
            return ProviderMusicBrainzFixture.recordingSearch(scoreField: #""score":100"#)
        case .releaseSearch:
            return ProviderMusicBrainzFixture.releaseSearch(scoreField: #""score":100"#)
        case .recordingLookup:
            return ProviderMusicBrainzFixture.recordingLookup(
                countField: #""count":7"#,
                ratingValueField: #""value":4.5"#,
                votesField: #""votes-count":9"#
            )
        case .releaseLookup:
            return Data(
                #"{"id":"22222222-2222-2222-2222-222222222222","title":"Recovered"}"#.utf8
            )
        }
    }

    func perform(on client: MusicBrainzClient) async throws {
        switch self {
        case .recordingSearch:
            _ = try await client.searchRecordings(
                matching: MusicBrainzSearchQuery(title: "Recovery"),
                limit: 1
            )
        case .releaseSearch:
            _ = try await client.searchReleases(
                matching: MusicBrainzSearchQuery(mode: .album, album: "Recovery"),
                limit: 1
            )
        case .recordingLookup:
            _ = try await client.recordingDetail(id: ProviderMusicBrainzFixture.recordingID)
        case .releaseLookup:
            _ = try await client.releaseDetail(id: ProviderMusicBrainzFixture.releaseID)
        }
    }
}

private nonisolated enum ProviderMusicBrainzFixture {
    static let recordingID = "11111111-1111-1111-1111-111111111111"
    static let releaseID = "22222222-2222-2222-2222-222222222222"

    static func recordingSearch(scoreField: String) -> Data {
        let suffix = scoreField.isEmpty ? "" : ",\(scoreField)"
        return Data(
            "{\"recordings\":[{\"id\":\"\(recordingID)\",\"title\":\"Numeric\"\(suffix)}]}".utf8
        )
    }

    static func releaseSearch(scoreField: String) -> Data {
        let suffix = scoreField.isEmpty ? "" : ",\(scoreField)"
        return Data(
            "{\"releases\":[{\"id\":\"\(releaseID)\",\"title\":\"Numeric\"\(suffix)}]}".utf8
        )
    }

    static func recordingLookup(
        countField: String = "",
        ratingValueField: String = "",
        votesField: String = ""
    ) -> Data {
        let genreSuffix = countField.isEmpty ? "" : ",\(countField)"
        let ratingParts = [ratingValueField, votesField].filter { !$0.isEmpty }.joined(separator: ",")
        let ratingJSON = ratingParts.isEmpty ? "null" : "{\(ratingParts)}"
        let json = """
        {"id":"\(recordingID)","title":"Numeric","genres":[{"name":"rock"\(genreSuffix)}],"rating":\(ratingJSON)}
        """
        return Data(json.utf8)
    }

    static func releaseResult(score: Int) -> MusicBrainzReleaseSearchResult {
        MusicBrainzReleaseSearchResult(
            id: releaseID,
            title: "Numeric",
            artistCredit: "Artist",
            score: score,
            date: "",
            country: "",
            status: "",
            mediaFormats: [],
            releaseGroup: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }

    static func matchPreview() -> MusicBrainzReleaseMatchPreview {
        let file = MusicBrainzFileSearchInput(
            id: "file",
            displayTitle: "Track",
            title: "Track",
            artist: "Artist",
            albumArtist: "Artist",
            album: "Album",
            trackNumber: "1"
        )
        let track = MusicBrainzReleaseMatchTrack(
            id: "track",
            mediumTitle: "CD 1",
            mediumFormat: "CD",
            mediumPosition: 1,
            mediumTrackCount: 1,
            releaseMediumCount: 1,
            number: "1",
            title: "Track",
            artistCredit: "Artist",
            durationMilliseconds: nil,
            recordingID: "recording",
            isrcs: []
        )
        return MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [
                MusicBrainzReleaseMatchAssignment(
                    id: "file:track",
                    file: file,
                    track: track,
                    score: 1,
                    reason: "fixture"
                )
            ],
            unmatchedFiles: [],
            unassignedTracks: [],
            averageTrackScore: 0.95,
            overallScore: 0.95,
            selectionLooksMixed: false
        )
    }
}
