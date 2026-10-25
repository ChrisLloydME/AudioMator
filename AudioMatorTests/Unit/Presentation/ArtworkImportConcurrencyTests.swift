import Foundation
import XCTest
@testable import AudioMator

nonisolated final class ArtworkImportConcurrencyTests: XCTestCase {
    @MainActor
    func testGatedNormalizationLeavesMainActorResponsive() async throws {
        let entered = expectation(description: "Background decoder entered")
        let gate = DispatchSemaphore(value: 0)
        let work = Task { @MainActor in
            try await ArtworkImageNormalizer.normalizedPNGDataInBackground(from: Data([1])) { data in
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                guard gate.wait(timeout: .now() + 5) == .success else {
                    throw CocoaError(.userCancelled)
                }
                return data
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        // This main-actor continuation must run while the decoder is gated.
        gate.signal()
        let result = try await work.value
        XCTAssertEqual(result, Data([1]))
    }
}
