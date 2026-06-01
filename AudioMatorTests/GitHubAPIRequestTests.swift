import XCTest
@testable import AudioMator

final class GitHubAPIRequestTests: XCTestCase {
    func testMakeAppliesSharedGitHubHeadersWithoutChangingURL() throws {
        let url = try XCTUnwrap(URL(string: "https://api.github.com/repos/ChrisLloydME/AudioMator/releases"))

        let request = GitHubAPIRequest.make(url: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "AudioMator")
    }
}
