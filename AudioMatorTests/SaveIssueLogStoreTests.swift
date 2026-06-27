import Foundation
import XCTest
@testable import AudioMator

@MainActor
final class SaveIssueLogStoreTests: XCTestCase {
    func testSuccessSummaryDoesNotCreateLogEntry() {
        let store = SaveIssueLogStore(fileURL: temporaryLogURL(), limit: 10)
        var summary = BatchMetadataOperationSummary(totalTargets: 1)
        summary.succeeded = 1

        store.record(summary: summary)

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testWarningSummaryCreatesPersistentLogEntry() {
        let url = temporaryLogURL()
        let store = SaveIssueLogStore(fileURL: url, limit: 10)
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        var summary = BatchMetadataOperationSummary(totalTargets: 2)
        summary.succeeded = 2
        summary.warningIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Reload failed."])
        ]

        store.record(summary: summary, date: date)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].title, "Saved with Issues")
        XCTAssertEqual(store.entries[0].operation, .write)
        XCTAssertEqual(store.entries[0].severity, .warning)
        XCTAssertEqual(store.entries[0].issues[0].fileName, "one.flac")
        XCTAssertEqual(store.entries[0].issues[0].messages, ["Reload failed."])

        let reloadedStore = SaveIssueLogStore(fileURL: url, limit: 10)
        XCTAssertEqual(reloadedStore.entries, store.entries)
    }

    func testFailureSummaryCreatesFailureLogEntry() {
        let store = SaveIssueLogStore(fileURL: temporaryLogURL(), limit: 10)
        var summary = BatchMetadataOperationSummary(totalTargets: 2)
        summary.failureIssues = [
            BatchMetadataWriteIssue(fileName: "bad.flac", messages: ["Permission denied."])
        ]

        store.record(summary: summary)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].title, "Save Failed")
        XCTAssertEqual(store.entries[0].severity, .failure)
        XCTAssertEqual(store.entries[0].issues[0].messages, ["Permission denied."])
    }

    func testLogLimitKeepsNewestEntries() {
        let store = SaveIssueLogStore(fileURL: temporaryLogURL(), limit: 2)

        for index in 1...3 {
            store.recordSingleIssue(
                title: "Save Failed",
                subtitle: "file-\(index).flac\nDenied.",
                fileName: "file-\(index).flac",
                messages: ["Denied."],
                severity: .failure,
                date: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        XCTAssertEqual(store.entries.map { $0.issues[0].fileName }, ["file-3.flac", "file-2.flac"])
    }

    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("SaveIssueLog.json")
    }
}
