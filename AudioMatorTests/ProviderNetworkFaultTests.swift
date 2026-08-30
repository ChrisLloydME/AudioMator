import Foundation
import ImageIO
import XCTest
@testable import AudioMator

final class ProviderNetworkFaultTests: XCTestCase {
    override func tearDown() {
        ProviderFaultURLProtocol.requestHandler = nil
        super.tearDown()
    }

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
        XCTAssertLessThanOrEqual(
            requestRecorder.requestCount,
            3,
            "Each multi-file fallback stage should be represented by at most one request."
        )
    }

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
        return URLSession(configuration: configuration)
    }

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

private final class ProviderFaultURLProtocol: URLProtocol {
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
