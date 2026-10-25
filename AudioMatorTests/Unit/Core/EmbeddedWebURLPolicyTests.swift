import Foundation
import XCTest
@testable import AudioMator

final class EmbeddedWebURLPolicyTests: XCTestCase {
    func testAllowsHTTPSProviderHosts() throws {
        XCTAssertNotNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "https://music.apple.com/us/album/name/1"))))
        XCTAssertNotNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "https://musicbrainz.org/release/abc"))))
        XCTAssertNotNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "https://www.musicbrainz.org/release/abc"))))
    }

    func testRejectsCleartextAndUnrelatedHosts() throws {
        XCTAssertNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "http://music.apple.com/us/album/name/1"))))
        XCTAssertNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "https://example.com/"))))
        XCTAssertNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "file:///etc/passwd"))))
        XCTAssertNil(EmbeddedWebURLPolicy.validatedURL(try XCTUnwrap(URL(string: "https://apple.com.evil.example/"))))
    }
}
