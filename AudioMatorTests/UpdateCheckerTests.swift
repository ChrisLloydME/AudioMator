import Foundation
import XCTest
@testable import AudioMator

final class UpdateCheckerTests: XCTestCase {
    override func tearDown() {
        UpdateMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSemanticVersionComparisonHandlesAudioMatorVersions() throws {
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("2.4")), try XCTUnwrap(SemanticVersion("2.3")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("2.3.1")), try XCTUnwrap(SemanticVersion("2.3")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("2.10")), try XCTUnwrap(SemanticVersion("2.9")))
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion("2.2")), try XCTUnwrap(SemanticVersion("2.1.20")))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("V2.3B26512"))
    }

    func testReleaseVersionComparisonIncludesBuildNumber() throws {
        let installed = try XCTUnwrap(ReleaseVersion(marketingVersion: "2.6", buildNumber: "2691"))
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion(releaseTag: "V2.6B2692")), installed)
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion(releaseTag: "V2.6B2690")), installed)
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion(releaseTag: "V2.7B1")), installed)
        XCTAssertEqual(try XCTUnwrap(ReleaseVersion(releaseTag: "V2.6B2691")), installed)
        XCTAssertNil(ReleaseVersion(releaseTag: "v2.6B2692"))
        XCTAssertNil(ReleaseVersion(releaseTag: "V2.6"))
        XCTAssertNil(ReleaseVersion(releaseTag: "V2.6B"))
        XCTAssertNil(ReleaseVersion(releaseTag: "V2.6b2692"))
    }

    func testUpdateCheckerDetectsNewerRelease() async throws {
        let release = try makeRelease(tagName: "V2.4B26001")
        let checker = UpdateChecker(
            releaseProvider: MockUpdateReleaseProvider(release: release),
            currentVersionProvider: { ReleaseVersion(marketingVersion: "2.3", buildNumber: "26512") }
        )

        let result = try await checker.checkForUpdates()

        XCTAssertEqual(result, .updateAvailable(release, currentVersion: "2.3 (26512)"))
    }

    func testUpdateCheckerDetectsNewerBuildOfSameMarketingVersion() async throws {
        let release = try makeRelease(tagName: "V2.6B2692")
        let checker = UpdateChecker(
            releaseProvider: MockUpdateReleaseProvider(release: release),
            currentVersionProvider: { ReleaseVersion(marketingVersion: "2.6", buildNumber: "2691") }
        )

        let result = try await checker.checkForUpdates()
        XCTAssertEqual(result, .updateAvailable(release, currentVersion: "2.6 (2691)"))
    }

    func testUpdateCheckerReportsUpToDateWhenVersionsMatch() async throws {
        let checker = UpdateChecker(
            releaseProvider: MockUpdateReleaseProvider(release: try makeRelease(tagName: "V2.3B26512")),
            currentVersionProvider: { ReleaseVersion(marketingVersion: "2.3", buildNumber: "26512") }
        )

        let result = try await checker.checkForUpdates()

        XCTAssertEqual(result, .upToDate(currentVersion: "2.3 (26512)", latestVersion: "V2.3B26512"))
    }

    func testUpdateCheckerThrowsForMissingCurrentVersion() async throws {
        let checker = UpdateChecker(
            releaseProvider: MockUpdateReleaseProvider(release: try makeRelease(tagName: "V2.4B26001")),
            currentVersionProvider: { nil }
        )

        do {
            _ = try await checker.checkForUpdates()
            XCTFail("Expected missing current version error")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .missingCurrentVersion)
        }
    }

    func testGitHubClientBuildsReleaseMetadata() async throws {
        let payload = """
        {
          "name": "AudioMator 2.4",
          "tag_name": "V2.4B26001",
          "html_url": "https://github.com/ChrisLloydME/AudioMator/releases/tag/V2.4B26001"
        }
        """.data(using: .utf8)!

        UpdateMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "AudioMator")

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                payload
            )
        }

        let client = GitHubUpdateReleaseClient(session: makeMockSession())
        let release = try await client.fetchLatestRelease()

        XCTAssertEqual(release.tagName, "V2.4B26001")
        XCTAssertEqual(release.displayName, "AudioMator 2.4")
        XCTAssertEqual(release.releaseURL.absoluteString, "https://github.com/ChrisLloydME/AudioMator/releases/tag/V2.4B26001")
    }

    func testGitHubClientMapsRateLimitAndMissingVersionResponses() async throws {
        UpdateMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        do {
            _ = try await GitHubUpdateReleaseClient(session: makeMockSession()).fetchLatestRelease()
            XCTFail("Expected rate limit error")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .rateLimited)
        }

        UpdateMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                #"{"name":"AudioMator 2.4","tag_name":"v2.4","html_url":"https://github.com/ChrisLloydME/AudioMator/releases/tag/v2.4"}"#.data(using: .utf8)!
            )
        }

        do {
            _ = try await GitHubUpdateReleaseClient(session: makeMockSession()).fetchLatestRelease()
            XCTFail("Expected missing release version error")
        } catch let error as UpdateCheckError {
            XCTAssertEqual(error, .missingReleaseVersion)
        }
    }

    private func makeRelease(tagName: String) throws -> UpdateReleaseMetadata {
        UpdateReleaseMetadata(
            version: try XCTUnwrap(ReleaseVersion(releaseTag: tagName)),
            tagName: tagName,
            displayName: tagName,
            releaseURL: try XCTUnwrap(URL(string: "https://github.com/ChrisLloydME/AudioMator/releases/tag/\(tagName)"))
        )
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct MockUpdateReleaseProvider: UpdateReleaseProviding {
    let release: UpdateReleaseMetadata

    func fetchLatestRelease() async throws -> UpdateReleaseMetadata {
        release
    }
}

private final class UpdateMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: UpdateCheckError.malformedReleaseResponse)
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
