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

    func testSavingRemainingGrantsRemovesDeletedGrant() throws {
        let suiteName = "FileAccessGrantStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFileAccessGrant-\(UUID().uuidString)", isDirectory: true)
        let secondFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFileAccessGrant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolderURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstFolderURL)
            try? FileManager.default.removeItem(at: secondFolderURL)
        }

        let store = FileAccessGrantStore(userDefaults: defaults)
        let firstGrant = try store.makeGrant(from: firstFolderURL)
        let secondGrant = try store.makeGrant(from: secondFolderURL)
        store.saveGrants([firstGrant, secondGrant])

        store.saveGrants([secondGrant])

        let restoredGrants = FileAccessGrantStore(userDefaults: defaults).loadGrants()
        XCTAssertEqual(restoredGrants.map(\.id), [secondGrant.id])
    }
}
