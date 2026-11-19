import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class TrackRenumberTests: XCTestCase {
    // MARK: - Plan construction

    @MainActor
    private func makeFile(
        _ name: String,
        extension fileExtension: String = "mp3",
        track: Int = 0,
        trackTotal: Int = 0,
        trackNumberText: String = "",
        includeReviewedRevision: Bool = true
    ) -> AudioFile {
        AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/renumber-tests/\(name).\(fileExtension)"),
            track: track,
            trackTotal: trackTotal,
            trackNumberText: trackNumberText,
            includeDefaultFileFingerprint: includeReviewedRevision
        )
    }

    @MainActor
    private func makePlan(
        files: [AudioFile],
        selectedIDs: Set<AudioFile.ID> = [],
        direction: TrackRenumberDirection = .ascending,
        startNumberText: String = "1",
        recoveryBlockedIDs: Set<AudioFile.ID> = []
    ) -> TrackRenumberPlan {
        TrackRenumberPlanner.makePlan(
            orderedFiles: files,
            selectedIDs: selectedIDs,
            direction: direction,
            startNumberText: startNumberText,
            recoveryBlockedIDs: recoveryBlockedIDs
        )
    }

    @MainActor
    private func assignedNumbers(_ plan: TrackRenumberPlan) -> [Int?] {
        plan.rows.map(\.assignedNumber)
    }

    @MainActor
    func testAscendingPlanPreviewsNumericStoredValuesWithoutPadding() {
        let files = (0..<3).map { makeFile("ascending-\($0)") }

        let plan = makePlan(files: files, startNumberText: "007")

        XCTAssertEqual(plan.startInput, .valid(7))
        XCTAssertEqual(assignedNumbers(plan), [7, 8, 9])
        XCTAssertEqual(plan.previewNumbers, [7, 8, 9])
        XCTAssertEqual(plan.executableCount, 3)
        XCTAssertEqual(plan.unchangedCount, 0)
        for (index, row) in plan.rows.enumerated() {
            let write = try? XCTUnwrap(row.executableWrite)
            XCTAssertEqual(write?.payload.trackNumberText, String(7 + index))
            XCTAssertEqual(write?.payload.trackNumber, 7 + index)
        }
    }

    @MainActor
    func testDescendingPlanAssignsHighestNumberToFirstRow() {
        let files = (0..<3).map { makeFile("descending-\($0)") }

        let plan = makePlan(files: files, direction: .descending, startNumberText: "1")

        XCTAssertEqual(assignedNumbers(plan), [3, 2, 1])
        XCTAssertEqual(
            plan.executableRows.compactMap { $0.executableWrite?.payload.trackNumber },
            [3, 2, 1]
        )
    }

    @MainActor
    func testUnsupportedFormatSkipsWithoutConsumingNumbers() {
        let first = makeFile("mixed-first", extension: "mp3")
        let unsupported = makeFile("mixed-unsupported", extension: "mod")
        let last = makeFile("mixed-last", extension: "flac")

        let plan = makePlan(files: [first, unsupported, last])

        XCTAssertEqual(plan.orderedTargetIDs, [first.id, unsupported.id, last.id])
        XCTAssertEqual(plan.rows.map(\.id), [first.id, unsupported.id, last.id])
        XCTAssertEqual(plan.rows[0].assignedNumber, 1)
        XCTAssertTrue(plan.rows[0].isExecutable)
        XCTAssertEqual(plan.rows[1].skipReason, .unsupportedFormat)
        XCTAssertNil(plan.rows[1].assignedNumber)
        XCTAssertEqual(plan.rows[2].assignedNumber, 2)
        XCTAssertTrue(plan.rows[2].isExecutable)
        XCTAssertEqual(plan.executableCount, 2)
        XCTAssertEqual(plan.skippedUnsupportedCount, 1)
        XCTAssertEqual(plan.resultBaseline().skippedUnsupported, 1)
    }

    @MainActor
    func testRefreshRequiredTargetsDoNotConsumeNumbersAtFirstOrMiddlePosition() {
        for blockedIndex in [0, 1] {
            let files = (0..<3).map { index -> AudioFile in
                let file = makeFile("refresh-\(blockedIndex)-\(index)")
                return index == blockedIndex ? file.projectingRecoveryState() : file
            }

            let plan = makePlan(files: files)

            XCTAssertEqual(plan.rows[blockedIndex].skipReason, .requiresMetadataRefresh)
            XCTAssertNil(plan.rows[blockedIndex].assignedNumber)
            let assigned = plan.executableRows.compactMap(\.assignedNumber)
            XCTAssertEqual(assigned, [1, 2])
            XCTAssertEqual(plan.resultBaseline().failed, 1)
            XCTAssertEqual(
                plan.resultBaseline().failures.map(\.fileName),
                [files[blockedIndex].url.lastPathComponent]
            )
        }
    }

    @MainActor
    func testRecoveryBlockedAndUnreviewedTargetsAreClassifiedBeforeNumbering() {
        let reviewable = makeFile("reviewable")
        let unreviewed = makeFile("unreviewed", includeReviewedRevision: false)
        let recoveryBlocked = makeFile("recovery-blocked")

        let plan = makePlan(
            files: [reviewable, unreviewed, recoveryBlocked],
            recoveryBlockedIDs: [recoveryBlocked.id]
        )

        XCTAssertEqual(plan.rows[0].assignedNumber, 1)
        XCTAssertEqual(plan.rows[1].skipReason, .missingReviewedRevision)
        XCTAssertEqual(plan.rows[2].skipReason, .recoveryBlocked)
        XCTAssertEqual(plan.executableCount, 1)
        XCTAssertEqual(plan.failedRowCount, 2)
    }

    @MainActor
    func testSubsetCustomOrderAndWholeListSelectionPreserveResolvedOrder() {
        let first = makeFile("order-first")
        let second = makeFile("order-second")
        let third = makeFile("order-third")
        let resolvedOrder = [third, first, second]

        let allPlan = makePlan(files: resolvedOrder)
        XCTAssertEqual(allPlan.orderedTargetIDs, [third.id, first.id, second.id])
        XCTAssertEqual(assignedNumbers(allPlan), [1, 2, 3])

        let subsetPlan = makePlan(
            files: resolvedOrder,
            selectedIDs: [first.id, second.id]
        )
        XCTAssertEqual(subsetPlan.orderedTargetIDs, [first.id, second.id])
        XCTAssertEqual(assignedNumbers(subsetPlan), [1, 2])
    }

    @MainActor
    func testDuplicateIdentitiesAreClassifiedBeforeNumbering() {
        let first = makeFile("duplicate-first")
        let second = makeFile("duplicate-second")
        // The same reviewed file can only be numbered once even if it appears
        // twice in the resolved order.
        let duplicated = [first, second, first]
        // A second logical identity for the same physical URL is also a duplicate
        // target for write authority.
        let sameURLDifferentID = AudioFileTestFactory.make(
            id: UUID(),
            url: second.url,
            metadataFileVersion: second.metadataFileVersion
        )

        let plan = makePlan(files: duplicated + [sameURLDifferentID])

        XCTAssertEqual(plan.executableCount, 2)
        XCTAssertEqual(assignedNumbers(plan), [1, 2, nil, nil])
        XCTAssertEqual(plan.rows[2].skipReason, .duplicateTarget)
        XCTAssertEqual(plan.rows[3].skipReason, .duplicateTarget)
        XCTAssertEqual(plan.skippedDuplicateCount, 2)
    }

    @MainActor
    func testAllSkippedPlanHasNoExecutableRows() {
        let unsupported = makeFile("all-skipped-unsupported", extension: "xm")
        let unreviewed = makeFile("all-skipped-unreviewed", includeReviewedRevision: false)

        let plan = makePlan(files: [unsupported, unreviewed])

        XCTAssertEqual(plan.totalTargets, 2)
        XCTAssertTrue(plan.executableRows.isEmpty)
        XCTAssertEqual(plan.skippedUnsupportedCount, 1)
        XCTAssertEqual(plan.failedRowCount, 1)
        XCTAssertTrue(plan.previewNumbers.isEmpty)
    }

    @MainActor
    func testAlreadyDesiredNumbersAreUnchangedRowsThatKeepTheirSlot() {
        let alreadyDesired = makeFile("unchanged", track: 7, trackTotal: 12, trackNumberText: "007/12")
        let changed = makeFile("changed", track: 1, trackNumberText: "1/12")

        let plan = makePlan(files: [alreadyDesired, changed], startNumberText: "7")

        XCTAssertEqual(plan.rows[0].assignedNumber, 7)
        XCTAssertTrue(plan.rows[0].isUnchanged)
        XCTAssertNil(plan.rows[0].executableWrite, "A numeric match must not reach a writer.")
        XCTAssertEqual(plan.rows[1].assignedNumber, 8)
        XCTAssertTrue(plan.rows[1].isExecutable)
        XCTAssertEqual(plan.executableCount, 1)
        XCTAssertEqual(plan.unchangedCount, 1)
        XCTAssertEqual(plan.previewNumbers, [7, 8])
        XCTAssertEqual(plan.resultBaseline().unchanged, 1)
    }

    @MainActor
    func testFrozenPayloadRequestsOnlyTrackAndPreservesReviewedPairComponents() {
        let file = makeFile(
            "frozen",
            extension: "flac",
            track: 3,
            trackTotal: 12,
            trackNumberText: "3/12"
        )
        let plan = makePlan(files: [file], startNumberText: "7")
        guard let row = plan.rows.first, let write = row.executableWrite else {
            return XCTFail("Expected one executable row")
        }

        XCTAssertEqual(row.assignedNumber, 7)
        XCTAssertEqual(write.target.id, file.id)
        XCTAssertEqual(write.target.url, file.url)
        XCTAssertEqual(write.target.version, file.metadataFileVersion)
        XCTAssertEqual(write.payload.requestedFields, Set([MetadataFieldKey.track]))
        XCTAssertEqual(write.payload.trackNumber, 7)
        XCTAssertEqual(write.payload.trackTotal, 12)
        XCTAssertEqual(write.payload.discNumber, file.disc)
        XCTAssertEqual(write.payload.discTotal, file.discTotal)
        XCTAssertEqual(
            write.projection.componentOperations,
            [MetadataNumberComponentOperation(field: .track, value: 7)]
        )
    }

    @MainActor
    func testInvalidStartIsExplicitInvalidStateWithoutAnyAssignedNumber() {
        let files = [makeFile("invalid-first"), makeFile("invalid-second")]

        for startText in ["", "   ", "abc", "0", "10000", "-1", "+7", "1.5", "1/12", "７"] {
            let plan = makePlan(files: files, startNumberText: startText)
            XCTAssertFalse(plan.isStartValid, "\(startText) must be invalid")
            XCTAssertNotNil(plan.validationMessage, "\(startText) must explain invalid state")
            XCTAssertEqual(plan.executableCount, 0)
            XCTAssertTrue(plan.previewNumbers.isEmpty)
            XCTAssertTrue(plan.rows.allSatisfy { $0.skipReason == .invalidStartNumber })
            XCTAssertNotNil(plan.resultBaseline().validationMessage)
            XCTAssertEqual(plan.resultBaseline().failed, 0, "Invalid input is not a per-file failure.")
        }

        let trimmedPlan = makePlan(files: files, startNumberText: " 007 ")
        XCTAssertEqual(trimmedPlan.startInput, .valid(7))
        XCTAssertEqual(assignedNumbers(trimmedPlan), [7, 8])
    }

    @MainActor
    func testCheckedNumberingRejectsSharedAndContainerBoundsWithoutClamping() {
        let sharedOverflow = Int32.max
        switch TrackRenumberNumbering.plannedNumber(
            slotIndex: Int(sharedOverflow) - 1,
            slotCount: Int(sharedOverflow),
            startNumber: 9_999,
            direction: .ascending,
            fileExtension: "flac"
        ) {
        case .success:
            XCTFail("Expected the shared Int32 bound to reject the number")
        case .failure(let rejection):
            XCTAssertEqual(rejection, .exceedsSharedComponentMaximum(attempted: 2_147_493_645))
            XCTAssertEqual(rejection.attemptedNumber, 2_147_493_645)
        }

        // 9_999 + 55_537 = 65_536, one above the declared MP4 component maximum.
        for direction in [TrackRenumberDirection.ascending, .descending] {
            let slotIndex = direction == .ascending ? 55_537 : 0
            switch TrackRenumberNumbering.plannedNumber(
                slotIndex: slotIndex,
                slotCount: 55_538,
                startNumber: 9_999,
                direction: direction,
                fileExtension: "m4a"
            ) {
            case .success:
                XCTFail("Expected the MP4 component bound to reject the number")
            case .failure(let rejection):
                XCTAssertEqual(
                    rejection,
                    .exceedsContainerComponentMaximum(attempted: 65_536, maximum: 65_535)
                )
            }
        }

        // The same value is representable for an ID3/Xiph container.
        switch TrackRenumberNumbering.plannedNumber(
            slotIndex: 55_537,
            slotCount: 55_538,
            startNumber: 9_999,
            direction: .ascending,
            fileExtension: "flac"
        ) {
        case .success(let number):
            XCTAssertEqual(number, 65_536)
        case .failure(let rejection):
            XCTFail("FLAC should accept \(65_536): \(rejection)")
        }
    }

    @MainActor
    func testPlanMatchesOnlyItsCapturedOrderedTargets() {
        let first = makeFile("scope-first")
        let second = makeFile("scope-second")
        let plan = makePlan(files: [first, second])

        XCTAssertTrue(plan.matchesOrderedTargets([first.id, second.id]))
        XCTAssertFalse(plan.matchesOrderedTargets([second.id, first.id]))
        XCTAssertFalse(plan.matchesOrderedTargets([first.id]))
    }
}
