import Foundation
import XCTest
@testable import AudioMator

nonisolated final class DirectoryMonitoringPlanTests: XCTestCase {
    @MainActor
    func testCorruptWatchedFolderCollectionIsQuarantinedAndCannotBeSilentlyOverwritten() throws {
        let suiteName = "AudioMator.WatchedFolderCorruptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let corruptData = Data("invalid-records".utf8)
        defaults.set(corruptData, forKey: "watchedFolderRecords")

        let store = WatchedFolderStore(userDefaults: defaults)
        XCTAssertTrue(store.loadFolders().isEmpty)
        XCTAssertEqual(store.loadState, .corrupt)
        XCTAssertEqual(defaults.data(forKey: "watchedFolderRecords.corruptBackup"), corruptData)

        XCTAssertFalse(store.saveFolders([]))
        XCTAssertEqual(defaults.data(forKey: "watchedFolderRecords"), corruptData)
    }

    @MainActor
    func testWatchedFolderAccessFailureMessagesAvoidFullPaths() {
        let single = AudioViewModel.watchedFolderAccessFailureMessage(for: ["Music"])
        let multiple = AudioViewModel.watchedFolderAccessFailureMessage(for: ["Music", "Archive"])

        XCTAssertEqual(single, "Access to “Music” couldn’t be saved for future use.")
        XCTAssertEqual(multiple, "Access to 2 selected folders couldn’t be saved for future use.")
        XCTAssertFalse(single.contains("/Users/"))
        XCTAssertFalse(multiple.contains("Music"))
    }

    @MainActor
    func testWatchedFolderRestoreKeepsValidRecordsWhenOneBookmarkIsInvalid() throws {
        let suiteName = "AudioMator.WatchedFolderStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let validFolder = try store.makeFolder(from: directoryURL)
        let records = [
            WatchedFolderRecord(
                id: UUID(),
                displayName: "Unavailable",
                bookmarkData: Data([0x00, 0x01, 0x02])
            ),
            WatchedFolderRecord(
                id: validFolder.id,
                displayName: validFolder.displayName,
                bookmarkData: validFolder.bookmarkData
            )
        ]
        userDefaults.set(try JSONEncoder().encode(records), forKey: "watchedFolderRecords")

        let restoredFolders = store.loadFolders()

        XCTAssertEqual(restoredFolders.map(\.id), [validFolder.id])
        XCTAssertEqual(restoredFolders.first?.url.standardizedFileURL, directoryURL.standardizedFileURL)
    }

    @MainActor
    func testWatchedFolderSavePreservesUnresolvedRecordsForRecovery() throws {
        let suiteName = "AudioMator.WatchedFolderSaveRecoveryTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolder-Save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let validFolder = try store.makeFolder(from: directoryURL)
        let unresolvedID = UUID()
        let records = [
            WatchedFolderRecord(
                id: unresolvedID,
                displayName: "Offline Library",
                bookmarkData: Data([0x00, 0x01, 0x02])
            ),
            WatchedFolderRecord(
                id: validFolder.id,
                displayName: validFolder.displayName,
                bookmarkData: validFolder.bookmarkData
            )
        ]
        userDefaults.set(try JSONEncoder().encode(records), forKey: "watchedFolderRecords")

        let restoredFolders = store.loadFolders()
        store.saveFolders(restoredFolders)

        let persistedData = try XCTUnwrap(userDefaults.data(forKey: "watchedFolderRecords"))
        let persistedRecords = try JSONDecoder().decode([WatchedFolderRecord].self, from: persistedData)
        XCTAssertEqual(Set(persistedRecords.map(\.id)), Set([unresolvedID, validFolder.id]))
    }

    @MainActor
    func testStaleWatchedFolderBookmarkIsRefreshedAndPersisted() throws {
        let suiteName = "AudioMator.WatchedFolderStaleBookmarkTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-WatchedFolder-Stale-\(UUID().uuidString)", isDirectory: true)
        let originalURL = rootURL.appendingPathComponent("Original", isDirectory: true)
        try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        // Moving the folder makes its bookmark stale. Loading must resolve the
        // new location and rewrite the stored bookmark, not just refresh the
        // in-memory value.
        let staleBookmarkData = try originalURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let record = WatchedFolderRecord(
            id: UUID(),
            displayName: "Original",
            bookmarkData: staleBookmarkData
        )
        userDefaults.set(try JSONEncoder().encode([record]), forKey: "watchedFolderRecords")
        let movedURL = rootURL.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: originalURL, to: movedURL)

        // Confirm the scenario really produced a stale bookmark before relying on it.
        let staleResolution = try resolveBookmark(staleBookmarkData)
        XCTAssertTrue(staleResolution.isStale)
        XCTAssertEqual(staleResolution.url.standardizedFileURL, movedURL.standardizedFileURL)

        let store = WatchedFolderStore(userDefaults: userDefaults)
        let restoredFolders = store.loadFolders()

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(restoredFolders.map(\.id), [record.id])
        XCTAssertEqual(restoredFolders.first?.url.standardizedFileURL, movedURL.standardizedFileURL)
        XCTAssertEqual(restoredFolders.first?.displayName, "Original")

        let persistedData = try XCTUnwrap(userDefaults.data(forKey: "watchedFolderRecords"))
        let persistedRecords = try JSONDecoder().decode([WatchedFolderRecord].self, from: persistedData)
        let persistedRecord = try XCTUnwrap(persistedRecords.first)
        XCTAssertEqual(persistedRecord.id, record.id)
        XCTAssertNotEqual(persistedRecord.bookmarkData, staleBookmarkData)
        let refreshedBookmark = try resolveBookmark(persistedRecord.bookmarkData)
        XCTAssertFalse(refreshedBookmark.isStale)
        XCTAssertEqual(refreshedBookmark.url.standardizedFileURL, movedURL.standardizedFileURL)

        // The persisted bookmark is current, so reloading must not rewrite it again.
        let reloadedStore = WatchedFolderStore(userDefaults: userDefaults)
        XCTAssertEqual(reloadedStore.loadFolders().map(\.id), [record.id])
        XCTAssertEqual(userDefaults.data(forKey: "watchedFolderRecords"), persistedData)
    }

    @MainActor
    func testViewModelRemovesMultipleWatchedFoldersTogether() throws {
        let suiteName = "AudioMator.WatchedFolderMultipleRemovalTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let folderURLs = (0..<3).map { index in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMator-WatchedFolder-\(index)-\(UUID().uuidString)", isDirectory: true)
        }
        for folderURL in folderURLs {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        defer {
            for folderURL in folderURLs {
                try? FileManager.default.removeItem(at: folderURL)
            }
        }

        let watchedFolderStore = WatchedFolderStore(userDefaults: userDefaults)
        let folders = try folderURLs.map(watchedFolderStore.makeFolder)
        watchedFolderStore.saveFolders(folders)
        let viewModel = AudioViewModel(
            watchedFolderStore: watchedFolderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: userDefaults),
            metadataPipeline: TagLibAudioMetadataPipeline(),
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: userDefaults
        )
        defer {
            viewModel.removeWatchedFolders(ids: Set(viewModel.watchedFolders.map(\.id)))
        }

        viewModel.removeWatchedFolders(ids: [folders[0].id, folders[2].id])

        XCTAssertEqual(viewModel.watchedFolders.map(\.id), [folders[1].id])
        XCTAssertEqual(
            WatchedFolderStore(userDefaults: userDefaults).loadFolders().map(\.id),
            [folders[1].id]
        )
    }

    @MainActor
    func testPlanIsBoundedAndAlwaysPrioritizesRootDirectory() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMonitorRoot", isDirectory: true)
        let directories = (0..<300).map { index in
            rootURL.appendingPathComponent("nested-\(index)", isDirectory: true)
        }

        let plan = DirectoryMonitoringPlan.make(
            directories: directories,
            rootURL: rootURL,
            limit: 128
        )

        XCTAssertEqual(plan.monitoredURLs.count, 128)
        XCTAssertEqual(plan.monitoredURLs.first, rootURL.standardizedFileURL)
        XCTAssertEqual(plan.totalDirectoryCount, 301)
        XCTAssertEqual(plan.omittedByLimitCount, 173)
    }

    @MainActor
    func testDegradedStatusIsObservableAndExplainsBothFailureModes() {
        let status = DirectoryMonitoringStatus(
            totalDirectoryCount: 301,
            monitoredDirectoryCount: 126,
            omittedByLimitCount: 173,
            failedToOpenCount: 2,
            scanFailureCount: 1,
            metadataReadFailureCount: 1
        )

        XCTAssertTrue(status.isDegraded)
        XCTAssertTrue(status.message.contains("126 of 301"))
        XCTAssertTrue(status.message.contains("173 folders exceed"))
        XCTAssertTrue(status.message.contains("2 folders couldn't be opened"))
        XCTAssertTrue(status.message.contains("1 folder scan couldn’t be completed"))
        XCTAssertTrue(status.message.contains("1 audio file couldn’t be read"))
        XCTAssertTrue(status.message.contains("Previously loaded metadata is still shown"))
        XCTAssertTrue(status.message.contains("previous file list will stay visible"))
        // The status explains the directory-entry/in-place distinction.
        XCTAssertTrue(status.message.contains("edits inside an already loaded file may need Refresh"))
    }

    @MainActor
    func testStatusDistinguishesIdentityMismatchFromFailedOpenAndExplainsEventCoverage() {
        let status = DirectoryMonitoringStatus(
            totalDirectoryCount: 2,
            monitoredDirectoryCount: 1,
            omittedByLimitCount: 0,
            failedToOpenCount: 0,
            identityMismatchCount: 1,
            scanFailureCount: 0,
            metadataReadFailureCount: 0
        )

        XCTAssertTrue(status.isDegraded)
        XCTAssertTrue(status.message.contains("1 of 2"))
        XCTAssertTrue(status.message.contains("1 folder now refers to a different directory"))
        XCTAssertFalse(status.message.contains("couldn’t be opened"))
        XCTAssertTrue(status.message.contains("edits inside an already loaded file may need Refresh"))

        let healthy = DirectoryMonitoringStatus(
            totalDirectoryCount: 2,
            monitoredDirectoryCount: 2,
            omittedByLimitCount: 0,
            failedToOpenCount: 0,
            scanFailureCount: 0,
            metadataReadFailureCount: 0
        )
        XCTAssertFalse(healthy.isDegraded)
        XCTAssertTrue(healthy.message.contains("monitoring all 2 folders"))
        XCTAssertTrue(healthy.message.contains("added, removed and renamed entries"))
    }

    @MainActor
    func testStatusReportsUnaccountedPlannedDirectoriesAsDegraded() {
        let status = DirectoryMonitoringStatus(
            totalDirectoryCount: 3,
            monitoredDirectoryCount: 1,
            omittedByLimitCount: 0,
            failedToOpenCount: 0,
            scanFailureCount: 0,
            metadataReadFailureCount: 0
        )

        XCTAssertEqual(status.plannedDirectoryCount, 3)
        XCTAssertEqual(status.unaccountedDirectoryCount, 2)
        XCTAssertTrue(status.isDegraded)
        XCTAssertTrue(status.message.contains("2 folders are not actively monitored"))
        XCTAssertTrue(status.message.contains("Changes in unmonitored subfolders"))
    }

    private func resolveBookmark(_ bookmarkData: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            var fallbackIsStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &fallbackIsStale
            )
            return (url, fallbackIsStale)
        }
    }
}
