import XCTest
@testable import AudioMator

@MainActor
final class ErrorPresentationRepairTests: XCTestCase {
    func testMalformedTotalsAreRejectedForBothNumberPairs() {
        let file = AudioFileTestFactory.make(track: 3, trackTotal: 12, disc: 3, discTotal: 12,
                                            trackNumberText: "3/12", discNumberText: "3/12")
        for disc in [false, true] {
            for value in ["A", "/A", "3/4/5", "-1", "2147483648"] {
                var edit = SingleFileEditModel(from: file)
                if disc { edit.setDiscTotalFieldText(value) }
                else { edit.setTrackTotalFieldText(value) }
                let message = MetadataEditPayload(edit, comparedTo: file).numberPairValidationMessage
                XCTAssertNotNil(message, value)
                XCTAssertTrue(message?.contains(disc ? "Total Discs" : "Total Tracks") == true, value)
            }
            for value in ["3/A", "/A", "3/4/5"] {
                var edit = SingleFileEditModel(from: file)
                if disc { edit.setDiscNumberText(value) } else { edit.setTrackNumberText(value) }
                XCTAssertNotNil(MetadataEditPayload(edit, comparedTo: file).numberPairValidationMessage, value)
            }
        }
    }

    func testValidTotalsAndExplicitRemovalRemainAllowed() {
        let file = AudioFileTestFactory.make(track: 3, trackTotal: 12, trackNumberText: "3/12")
        for value in ["", "0", "13", "0013"] {
            var edit = SingleFileEditModel(from: file)
            edit.setTrackTotalFieldText(value)
            XCTAssertNil(MetadataEditPayload(edit, comparedTo: file).numberPairValidationMessage, value)
        }
    }

    func testUnrelatedEditPreservesExistingTextNumbering() {
        let file = AudioFileTestFactory.make(trackNumberText: "A1/12", discNumberText: "B2/3")
        var edit = SingleFileEditModel(from: file)
        edit.title = "New title"
        XCTAssertNil(MetadataEditPayload(edit, comparedTo: file).numberPairValidationMessage)
    }

    func testExplicitHUDContentKeepsNewlinesInFilenames() {
        let hud = MetadataWriteHUD(style: .failure, title: "Failed", subtitle: "legacy",
                                   summary: "one\ntwo.flac", details: "Reason")
        XCTAssertEqual(hud.summary, "one\ntwo.flac")
        XCTAssertEqual(hud.details, "Reason")
    }

    func testHUDExplainsDetailOmissionWithoutALogLink() {
        let details = Array(repeating: String(repeating: "x", count: 100), count: 12).joined(separator: "\n")
        let hud = MetadataWriteHUD(style: .warning, title: "Warning", subtitle: "",
                                   summary: "Saved", details: details)
        XCTAssertTrue(hud.hasOmittedDetails)
        XCTAssertLessThanOrEqual(hud.detailPreview.count, 1000)
        XCTAssertEqual(hud.details, details)
        XCTAssertFalse(hud.detailPreview.contains("Settings"))
    }

    func testCancelledBatchAndSkippedBatchDoNotClaimSaveFailureOrSuccess() {
        var cancelled = BatchMetadataOperationSummary(totalTargets: 2)
        cancelled.recordCancelledFiles(["one.flac", "two.flac"])
        XCTAssertEqual(cancelled.failureIssues.count, 2) // Preserve per-file accounting.
        XCTAssertEqual(cancelled.hudStyle, .warning)
        XCTAssertEqual(cancelled.hudTitle, "Operation Cancelled")
        XCTAssertFalse(cancelled.hudSubtitle.contains("couldn’t be saved"))
        var skipped = BatchMetadataOperationSummary(totalTargets: 1)
        skipped.skippedIssues = [.init(fileName: "one.flac", messages: ["Unsupported"])]
        XCTAssertEqual(skipped.hudTitle, "No Files Changed")
    }

    func testClearFailureNamesTheActualOperation() {
        var summary = BatchMetadataOperationSummary(totalTargets: 1, operation: .clear)
        summary.failureIssues = [.init(fileName: "one.flac", messages: ["Denied"])]
        XCTAssertTrue(summary.hudSubtitle.contains("Metadata couldn’t be cleared from 1 file."))
        XCTAssertFalse(summary.hudSubtitle.contains("updated"))
        XCTAssertFalse(summary.hudSubtitle.contains("Settings"))
    }
    func testOutOfRangeNumbersIdentifyTrackAndDiscFields() {
        let file = AudioFileTestFactory.make(track: 3, trackTotal: 12, disc: 3, discTotal: 12,
                                            trackNumberText: "3/12", discNumberText: "3/12")
        for disc in [false, true] {
            for value in ["-1", "2147483648", "9999999999999999999999999999"] {
                var edit = SingleFileEditModel(from: file)
                if disc { edit.setDiscNumberFieldText(value) }
                else { edit.setTrackNumberFieldText(value) }
                let reason = MetadataEditPayload(edit, comparedTo: file).numberPairValidationMessage
                XCTAssertTrue(reason?.contains(disc ? "Disc Number" : "Track Number") == true, value)
                XCTAssertTrue(reason?.contains("0 to 2147483647") == true, value)
                XCTAssertFalse(reason?.contains("contains text") == true, value)
            }
        }
    }

    func testRealBatchWarningFixtureKeepsEveryShownFileReasonTogether() {
        var result = BatchMetadataOperationSummary(totalTargets: 3)
        result.succeeded = 3
        result.warningIssues = [
            .init(fileName: "one.flac", messages: ["Artwork could not be refreshed."]),
            .init(fileName: "two.flac", messages: ["Tags saved.", "Reload failed."]),
            .init(fileName: "three.flac", messages: ["Late warning."])
        ]
        let hud = MetadataWriteHUD(style: result.hudStyle, title: result.hudTitle, subtitle: result.hudSubtitle)
        XCTAssertTrue(hud.detailPreview.contains("two.flac\nTags saved.\nReload failed."))
        XCTAssertTrue(hud.detailPreview.contains("Additional files with issues: 1."))
        XCTAssertFalse(hud.hasOmittedDetails)
        XCTAssertFalse(hud.details.contains("Settings"))
    }

    func testRenameCancellationAndNumberingCancellationHaveDistinctOutcomes() {
        let cancelled = FileRenameTransactionFailure(message: "Cancelled", recoveryItems: [], wasCancelled: true)
        XCTAssertTrue(cancelled.wasCancelled)
        var numbered = TrackRenumberResult.empty
        numbered.cancelled = [.init(fileName: "one.flac", reason: "Cancelled")]
        XCTAssertEqual(numbered.failed, 0)
        XCTAssertTrue(numbered.failures.isEmpty)
        XCTAssertEqual(numbered.cancelled.count, 1)
    }

    func testGroupBudgetNeverShowsHalfOfTheNextFile() {
        let first = "one.flac\n" + String(repeating: "x", count: 600)
        let second = "two.flac\n" + String(repeating: "y", count: 600)
        let hud = MetadataWriteHUD(style: .warning, title: "Warning", subtitle: "",
                                   summary: "Saved", details: first + "\n\n" + second)
        XCTAssertEqual(hud.detailPreview, first)
        XCTAssertTrue(hud.hasOmittedDetails)
        XCTAssertTrue(hud.omissionNotice.contains("two.flac"))
        XCTAssertTrue(hud.omissionNotice.contains("1"))
    }

    func testSingleOperationCancellationPresenterUsesWarningWithoutSaveFailureLog() {
        let vm = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
        vm.presentMetadataWriteFailure(for: "one.flac", reason: MetadataCancellation.message,
                                      title: "Metadata Couldn’t Be Cleared", operation: .clear)
        XCTAssertEqual(vm.metadataWriteHUD?.style, .warning)
        XCTAssertEqual(vm.metadataWriteHUD?.title, "Operation Cancelled")
        XCTAssertTrue(vm.saveIssueLogStore.entries.isEmpty)
    }

    func testWarningPresenterPreservesMultilineFilenameInHUDAndLog() {
        let vm = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
        vm.presentMetadataWriteWarning(title: "Saved with Warnings", fileName: "one\ntwo.flac", warnings: ["Reload failed."])
        XCTAssertEqual(vm.metadataWriteHUD?.summary, "one\ntwo.flac")
        XCTAssertEqual(vm.metadataWriteHUD?.details, "Reload failed.")
        XCTAssertEqual(vm.saveIssueLogStore.entries.first?.issues.first?.fileName, "one\ntwo.flac")
    }

    func testSingleDetailGroupStillHonorsLineBudget() {
        let detail = (1...30).map { "Line \($0)" }.joined(separator: "\n")
        let hud = MetadataWriteHUD(style: .failure, title: "Failed", subtitle: "",
                                   summary: "File", details: detail)
        XCTAssertEqual(hud.detailPreview.components(separatedBy: .newlines).count, 14)
        XCTAssertTrue(hud.detailPreview.hasSuffix("Line 14"))
        XCTAssertFalse(hud.detailPreview.contains("Line 15"))
        XCTAssertTrue(hud.hasOmittedDetails)
        XCTAssertFalse(hud.omissionNotice.isEmpty)
    }

    func testOmittedHeadingListIsBoundedForLargeReloadFailures() {
        let first = "Shown file\n" + String(repeating: "x", count: 900)
        let rest = (1...500).map {
            "file-\($0)-" + String(repeating: "y", count: 200) + "\nReason"
        }
        let hud = MetadataWriteHUD(style: .failure, title: "Reload Failed", subtitle: "",
                                   summary: "500 files", details: ([first] + rest).joined(separator: "\n\n"))
        XCTAssertEqual(hud.detailPreview, first)
        XCTAssertTrue(hud.hasOmittedDetails)
        XCTAssertTrue(hud.omissionNotice.contains("500"))
        XCTAssertTrue(hud.omissionNotice.contains("And 497 more groups."))
        XCTAssertFalse(hud.omissionNotice.contains("file-4-"))
        XCTAssertLessThanOrEqual(hud.omissionNotice.count, 250)
    }

    func testRecoveryInstructionDoesNotAssumeInspectorEdits() {
        let message = AudioFileFingerprintValidationError.recoveryRequired(fileName: "song.flac").errorDescription ?? ""
        XCTAssertFalse(message.contains("Inspector"))
        XCTAssertTrue(message.contains("Close any open metadata tool"))
        XCTAssertTrue(message.contains("If there are unsaved edits"))
    }

}
