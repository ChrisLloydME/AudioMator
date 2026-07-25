import Foundation
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
            rateLimiter: MusicBrainzRateLimiter(minimumIntervalNanoseconds: 0)
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
