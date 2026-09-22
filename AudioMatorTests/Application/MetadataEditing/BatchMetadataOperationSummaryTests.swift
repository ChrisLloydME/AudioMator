import XCTest
@testable import AudioMator

final class BatchMetadataOperationSummaryTests: XCTestCase {
    func testWriteSuccessUsesExistingSavedToDiskMessage() {
        var summary = BatchMetadataOperationSummary(totalTargets: 2)
        summary.succeeded = 2

        XCTAssertEqual(summary.hudStyle, .success)
        XCTAssertEqual(summary.hudTitle, "Saved to Disk")
        XCTAssertEqual(summary.hudSubtitle, "2 files")
    }

    func testWriteWarningsUseExistingSavedWithIssuesMessageAndDetails() {
        var summary = BatchMetadataOperationSummary(totalTargets: 3)
        summary.succeeded = 3
        summary.warningIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Artwork could not be refreshed."]),
            BatchMetadataWriteIssue(fileName: "two.flac", messages: ["Tags saved.", "Reload failed."]),
            BatchMetadataWriteIssue(fileName: "three.flac", messages: ["Late warning."])
        ]

        XCTAssertEqual(summary.hudStyle, .warning)
        XCTAssertEqual(summary.hudTitle, "Saved with Issues")
        XCTAssertEqual(
            summary.hudSubtitle,
            """
            3 of 3 files saved
            3 file(s) saved with issues
            one.flac: Artwork could not be refreshed.
            two.flac: Tags saved. Reload failed.
            ...and 1 more
            """
        )
    }

    func testWriteFailuresUseExistingPartialAndFullFailureMessages() {
        var partial = BatchMetadataOperationSummary(totalTargets: 3)
        partial.succeeded = 1
        partial.failureIssues = [
            BatchMetadataWriteIssue(fileName: "bad.flac", messages: ["Unsupported format."])
        ]

        XCTAssertEqual(partial.hudStyle, .warning)
        XCTAssertEqual(partial.hudTitle, "Partially Saved")
        XCTAssertEqual(
            partial.hudSubtitle,
            """
            1 of 3 files saved
            1 file(s) failed
            bad.flac: Unsupported format.
            """
        )

        var failed = BatchMetadataOperationSummary(totalTargets: 2)
        failed.failureIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Denied."])
        ]

        XCTAssertEqual(failed.hudStyle, .failure)
        XCTAssertEqual(failed.hudTitle, "Save Failed")
        XCTAssertEqual(
            failed.hudSubtitle,
            """
            No files were saved
            1 file(s) failed
            one.flac: Denied.
            """
        )
    }

    func testClearSummaryUsesExistingClearVocabulary() {
        var summary = BatchMetadataOperationSummary(totalTargets: 2, operation: .clear)
        summary.succeeded = 2
        summary.warningIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Reload failed."])
        ]

        XCTAssertEqual(summary.hudStyle, .warning)
        XCTAssertEqual(summary.hudTitle, "Cleared with Issues")
        XCTAssertEqual(
            summary.hudSubtitle,
            """
            2 of 2 files cleared
            1 file(s) cleared with issues
            one.flac: Reload failed.
            """
        )

        var failed = BatchMetadataOperationSummary(totalTargets: 1, operation: .clear)
        failed.failureIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Permission denied."])
        ]

        XCTAssertEqual(failed.hudStyle, .failure)
        XCTAssertEqual(failed.hudTitle, "Clear Failed")
        XCTAssertEqual(
            failed.hudSubtitle,
            """
            No files were cleared
            1 file(s) failed
            one.flac: Permission denied.
            """
        )
    }
}
