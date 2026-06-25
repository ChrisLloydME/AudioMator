import Foundation
import XCTest
@testable import AudioMator

final class DirectoryMonitoringPlanTests: XCTestCase {
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
            failedToOpenCount: 2
        )

        XCTAssertTrue(status.isDegraded)
        XCTAssertTrue(status.message.contains("126 of 301"))
        XCTAssertTrue(status.message.contains("173 omitted"))
        XCTAssertTrue(status.message.contains("2 could not be opened"))
    }
}
