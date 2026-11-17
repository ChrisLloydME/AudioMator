import XCTest
@testable import AudioMator

final class BatchMetadataOperationSummaryTests: XCTestCase {
    func testWriteSuccessUsesExistingSavedToDiskMessage() {
        var summary = BatchMetadataOperationSummary(totalTargets: 2)
        summary.succeeded = 2

        XCTAssertEqual(summary.hudStyle, .success)
        XCTAssertEqual(summary.hudTitle, "Saved to Disk")
        XCTAssertEqual(summary.hudSubtitle, "Changes were saved to 2 of 2 files.")
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
        XCTAssertEqual(summary.hudTitle, "Changes Saved with Warnings")
        XCTAssertEqual(
            summary.hudSubtitle,
            """
            Changes were saved to 3 of 3 files.
            3 files have warnings.

            one.flac
            Artwork could not be refreshed.

            two.flac
            Tags saved.
            Reload failed.

            More file details are available in Settings → Save Logs.
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
        XCTAssertEqual(partial.hudTitle, "Changes Saved to Some Files")
        XCTAssertEqual(
            partial.hudSubtitle,
            """
            Changes were saved to 1 of 3 files. 1 file couldn’t be updated.

            bad.flac
            Unsupported format.
            """
        )

        var failed = BatchMetadataOperationSummary(totalTargets: 2)
        failed.failureIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Denied."])
        ]

        XCTAssertEqual(failed.hudStyle, .failure)
        XCTAssertEqual(failed.hudTitle, "Changes Couldn’t Be Saved")
        XCTAssertEqual(
            failed.hudSubtitle,
            """
            No changes were saved to any files. 1 file couldn’t be updated.

            one.flac
            Denied.
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
        XCTAssertEqual(summary.hudTitle, "Metadata Cleared with Warnings")
        XCTAssertEqual(
            summary.hudSubtitle,
            """
            Metadata was cleared from 2 of 2 files.
            1 file has warnings.

            one.flac
            Reload failed.
            """
        )

        var failed = BatchMetadataOperationSummary(totalTargets: 1, operation: .clear)
        failed.failureIssues = [
            BatchMetadataWriteIssue(fileName: "one.flac", messages: ["Permission denied."])
        ]

        XCTAssertEqual(failed.hudStyle, .failure)
        XCTAssertEqual(failed.hudTitle, "Metadata Couldn’t Be Cleared")
        XCTAssertEqual(
            failed.hudSubtitle,
            """
            Metadata wasn't cleared from any files. 1 file couldn’t be updated.

            one.flac
            Permission denied.
            """
        )
    }
}
