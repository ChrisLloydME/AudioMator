import Foundation
import XCTest
@testable import AudioMator

final class DirectoryMonitoringPlanTests: XCTestCase {
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

    func testDegradedStatusIsObservableAndExplainsBothFailureModes() {
        let status = DirectoryMonitoringStatus(
            totalDirectoryCount: 301,
            monitoredDirectoryCount: 126,
            omittedByLimitCount: 173,
            failedToOpenCount: 2,
            metadataReadFailureCount: 1
        )

        XCTAssertTrue(status.isDegraded)
        XCTAssertTrue(status.message.contains("126 of 301"))
        XCTAssertTrue(status.message.contains("173 omitted"))
        XCTAssertTrue(status.message.contains("2 could not be opened"))
        XCTAssertTrue(status.message.contains("1 audio file could not be read"))
        XCTAssertTrue(status.message.contains("Last known metadata is retained"))
    }
}
