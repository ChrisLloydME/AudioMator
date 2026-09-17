import Foundation
import XCTest
@testable import AudioMator

@MainActor
final class FileAccessGrantStoreTests: XCTestCase {
    func testCorruptGrantCollectionIsQuarantinedAndCannotBeSilentlyOverwritten() throws {
        let suiteName = "FileAccessGrantStoreCorruptionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: "fileAccessGrantRecords")

        let store = FileAccessGrantStore(userDefaults: defaults)
        XCTAssertTrue(store.loadGrants().isEmpty)
        XCTAssertEqual(store.loadState, .corrupt)
        XCTAssertEqual(defaults.data(forKey: "fileAccessGrantRecords.corruptBackup"), corruptData)

        XCTAssertFalse(store.saveGrants([]))
        XCTAssertEqual(defaults.data(forKey: "fileAccessGrantRecords"), corruptData)
    }

    func testSaveWithoutPriorLoadStillProtectsCorruptGrantCollection() throws {
        let suiteName = "FileAccessGrantStorePreflightCorruptionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptData = Data([0xFF, 0x00, 0x7F])
        defaults.set(corruptData, forKey: "fileAccessGrantRecords")

        let store = FileAccessGrantStore(userDefaults: defaults)
        XCTAssertFalse(store.saveGrants([]))
        XCTAssertEqual(store.loadState, .corrupt)
        XCTAssertEqual(defaults.data(forKey: "fileAccessGrantRecords"), corruptData)
        XCTAssertEqual(defaults.data(forKey: "fileAccessGrantRecords.corruptBackup"), corruptData)
    }

    func testViewModelSurfacesCorruptBookmarkCollections() throws {
        let suiteName = "BookmarkCollectionWarningTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("bad grants".utf8), forKey: "fileAccessGrantRecords")
        defaults.set(Data("bad folders".utf8), forKey: "watchedFolderRecords")

        let viewModel = makeViewModel(defaults: defaults)

        XCTAssertEqual(viewModel.bookmarkPersistenceWarnings.count, 2)
        XCTAssertTrue(viewModel.fileAccessGrants.isEmpty)
        XCTAssertTrue(viewModel.watchedFolders.isEmpty)
    }

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

    func testViewModelRemovalUpdatesPublishedAndPersistedGrants() throws {
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

        let fileAccessGrantStore = FileAccessGrantStore(userDefaults: defaults)
        let firstGrant = try fileAccessGrantStore.makeGrant(from: firstFolderURL)
        let secondGrant = try fileAccessGrantStore.makeGrant(from: secondFolderURL)
        fileAccessGrantStore.saveGrants([firstGrant, secondGrant])
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.removeFileAccessGrant(id: firstGrant.id)

        XCTAssertEqual(viewModel.fileAccessGrants.map(\.id), [secondGrant.id])
        XCTAssertEqual(
            FileAccessGrantStore(userDefaults: defaults).loadGrants().map(\.id),
            [secondGrant.id]
        )
    }

    func testViewModelRemovesMultipleSelectedGrantsTogether() throws {
        let suiteName = "FileAccessGrantStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderURLs = (0..<3).map { index in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorFileAccessGrant-\(index)-\(UUID().uuidString)", isDirectory: true)
        }
        for folderURL in folderURLs {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        defer {
            for folderURL in folderURLs {
                try? FileManager.default.removeItem(at: folderURL)
            }
        }

        let fileAccessGrantStore = FileAccessGrantStore(userDefaults: defaults)
        let grants = try folderURLs.map(fileAccessGrantStore.makeGrant)
        fileAccessGrantStore.saveGrants(grants)
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.removeFileAccessGrants(ids: [grants[0].id, grants[2].id])

        XCTAssertEqual(viewModel.fileAccessGrants.map(\.id), [grants[1].id])
        XCTAssertEqual(
            FileAccessGrantStore(userDefaults: defaults).loadGrants().map(\.id),
            [grants[1].id]
        )
    }

    func testViewModelIgnoresRemovalOfUnknownGrant() throws {
        let suiteName = "FileAccessGrantStoreTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults.")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFileAccessGrant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let fileAccessGrantStore = FileAccessGrantStore(userDefaults: defaults)
        let grant = try fileAccessGrantStore.makeGrant(from: folderURL)
        fileAccessGrantStore.saveGrants([grant])
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.removeFileAccessGrant(id: UUID())

        XCTAssertEqual(viewModel.fileAccessGrants.map(\.id), [grant.id])
        XCTAssertEqual(
            FileAccessGrantStore(userDefaults: defaults).loadGrants().map(\.id),
            [grant.id]
        )
    }

    private func makeViewModel(defaults: UserDefaults) -> AudioViewModel {
        AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: TagLibAudioMetadataPipeline(),
            saveIssueLogStore: SaveIssueLogStore()
        )
    }
}
