import Foundation
import XCTest
@testable import AudioMator

final class SecurityScopedResourceAccessTests: XCTestCase {
    func testGrantedAccessIsStoppedAfterSuccessfulRead() {
        let url = URL(fileURLWithPath: "/tmp/security-scoped-artwork.png")
        var events: [String] = []

        let value = SecurityScopedResourceAccess.withAccess(
            to: url,
            startAccessing: { accessedURL in
                events.append("start:\(accessedURL.path)")
                return true
            },
            stopAccessing: { accessedURL in
                events.append("stop:\(accessedURL.path)")
            },
            perform: {
                events.append("read")
                return 42
            }
        )

        XCTAssertEqual(value, 42)
        XCTAssertEqual(events, ["start:\(url.path)", "read", "stop:\(url.path)"])
    }

    func testOrdinaryLocalURLDoesNotReceiveUnbalancedStop() {
        let url = URL(fileURLWithPath: "/tmp/local-artwork.png")
        var stopCount = 0

        let value = SecurityScopedResourceAccess.withAccess(
            to: url,
            startAccessing: { _ in false },
            stopAccessing: { _ in stopCount += 1 },
            perform: { "read" }
        )

        XCTAssertEqual(value, "read")
        XCTAssertEqual(stopCount, 0)
    }
}
