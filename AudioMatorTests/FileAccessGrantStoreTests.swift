import Foundation
import XCTest
@testable import AudioMator

@MainActor
final class FileAccessGrantStoreTests: XCTestCase {
    func testGrantRoundTripsAsPersistentFolderBookmark() throws {
        let suiteName = "FileAccessGrantStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFileAccessGrant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let store = FileAccessGrantStore(userDefaults: defaults)
        let grant = try store.makeGrant(from: folderURL)
        store.saveGrants([grant])

        let restoredGrants = FileAccessGrantStore(userDefaults: defaults).loadGrants()

        XCTAssertEqual(restoredGrants.count, 1)
        XCTAssertEqual(restoredGrants.first?.id, grant.id)
        XCTAssertEqual(restoredGrants.first?.url.standardizedFileURL, folderURL.standardizedFileURL)
    }
}
