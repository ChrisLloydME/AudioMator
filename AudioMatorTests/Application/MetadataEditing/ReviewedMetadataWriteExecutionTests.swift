import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class ReviewedMetadataWriteExecutionTests: XCTestCase {
    // MARK: - Fixtures

    @MainActor
    private func makeObservedFixture() throws -> (file: AudioFile, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewedMetadataWrite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("observed.mp3")
        try Data(repeating: 0x41, count: 64).write(to: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        guard let version = AudioFileTestFactory.fixtureFileVersion else {
            throw XCTSkip("The committed fixture snapshot is unavailable in this test bundle.")
        }
        let file = AudioFileTestFactory.makeObserved(
            id: UUID(),
            url: url,
            title: "Original",
            fileFingerprint: fingerprint,
            metadataFileVersion: version
        )
        return (file, directory)
    }

    private func removeDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    private func makeSemanticWrite(
        for file: AudioFile,
        title: String = "Reviewed title"
    ) throws -> ReviewedMetadataWrite {
        var edit = SingleFileEditModel(from: file)
        edit.title = title
        return try XCTUnwrap(ReviewedMetadataWriteFactory.semanticWrite(edit: edit, comparedTo: file))
    }

    // MARK: - S6/S7 admission, permit and cancellation

    @MainActor
    func testStrictWriteUsesCapturedRevisionAndRejectsChangedDisk() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])

        let write = try makeSemanticWrite(for: fixture.file)
        let result = await viewModel.executeReviewedMetadataWrite(write, publication: .immediate)
        guard case .success = result else { return XCTFail("Expected strict write success: \(result)") }
        XCTAssertEqual(pipeline.semanticWrites.count, 1)
        XCTAssertEqual(pipeline.semanticWrites.first?.version, write.target.version)

        // External disk change after review: the captured fingerprint must fail
        // before any second writer call.
        try Data(repeating: 0x42, count: 128).write(to: fixture.file.url)
        let staleResult = await viewModel.executeReviewedMetadataWrite(write, publication: .immediate)
        guard case .failure(let reason) = staleResult else {
            return XCTFail("Expected stale observation rejection, got \(staleResult)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("changed"))
        XCTAssertEqual(pipeline.semanticWrites.count, 1)
    }

    @MainActor
    func testQueuedStrictWriteCancellationReachesNoWriter() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let write = try makeSemanticWrite(for: fixture.file)

        let entered = TestGate()
        let release = TestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [fixture.file.url]) {
                await entered.open()
                await release.wait()
            }
        }
        await entered.wait()

        let writeTask = Task {
            await viewModel.executeReviewedMetadataWrite(write, publication: .immediate)
        }
        try await waitForQueuedMutation(in: viewModel)
        writeTask.cancel()
        await release.open()
        await holder.value
        let result = await writeTask.value

        guard case .cancelled = result else {
            return XCTFail("Expected structural cancellation, got \(result)")
        }
        XCTAssertTrue(pipeline.semanticWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testSourceMembershipRemovalRevokesQueuedPermitBeforeAdmission() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let write = try makeSemanticWrite(for: fixture.file)

        let entered = TestGate()
        let release = TestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [fixture.file.url]) {
                await entered.open()
                await release.wait()
            }
        }
        await entered.wait()

        let writeTask = Task {
            await viewModel.executeReviewedMetadataWrite(write, publication: .immediate)
        }
        try await waitForQueuedMutation(in: viewModel)
        viewModel.removeQuickImportFile(id: fixture.file.id)
        await release.open()
        await holder.value
        let result = await writeTask.value

        guard case .failure = result else {
            return XCTFail("Expected revoked permit failure, got \(result)")
        }
        XCTAssertTrue(pipeline.semanticWrites.isEmpty)
        XCTAssertEqual(viewModel.metadataCommitPermits.activePermitCount, 0)
    }

    @MainActor
    func testRecoveryDecisionRevokesQueuedPermitBeforeAdmission() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])
        let write = try makeSemanticWrite(for: fixture.file)

        let entered = TestGate()
        let release = TestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [fixture.file.url]) {
                await entered.open()
                await release.wait()
            }
        }
        await entered.wait()

        let writeTask = Task {
            await viewModel.executeReviewedMetadataWrite(write, publication: .immediate)
        }
        try await waitForQueuedMutation(in: viewModel)
        viewModel.markFileRequiresRefresh(id: fixture.file.id)
        await release.open()
        await holder.value
        let result = await writeTask.value

        guard case .failure = result else {
            return XCTFail("Expected recovery-blocked failure, got \(result)")
        }
        XCTAssertTrue(pipeline.semanticWrites.isEmpty)
    }

    @MainActor
    func testEqualObservationRepublishDoesNotRevokePermit() {
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingReviewedPipeline(reloadFile: nil))
        let fixture = AudioFileTestFactory.make(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("republished.mp3")
        )
        let target = ReviewedMetadataTarget(verified: fixture)
        guard let target else { return XCTFail("Expected a coherent fixture observation") }
        let permit = viewModel.metadataCommitPermits.register(target: target, operationID: UUID())
        viewModel.revokeCommitPermitsIfObservationIncompatible(fixture)
        XCTAssertEqual(viewModel.metadataCommitPermits.activePermitCount, 1)
        XCTAssertNil(permit.rejection, "Equal observation republish must not revoke a pending permit")
        XCTAssertEqual(permit.admit(), .admitted)
    }

    @MainActor
    func testConflictAwareDraftPermitSurvivesRevisionOnlyObservationAndRevokesOnPathOrRecoveryChange() throws {
        let v1 = try XCTUnwrap(AudioFileTestFactory.fixtureFileVersion)
        let v2 = try XCTUnwrap(AudioFileTestFactory.secondaryFixtureFileVersion)
        XCTAssertNotEqual(v1, v2)

        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingReviewedPipeline(reloadFile: nil))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("draft-permit.mp3")
        let original = AudioFileTestFactory.makeObserved(
            url: url,
            title: "Original",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: url, fileSize: 100),
            metadataFileVersion: v1
        )
        guard let target = ReviewedMetadataTarget(verified: original) else {
            return XCTFail("Expected a coherent fixture observation")
        }

        let draftPermit = viewModel.metadataCommitPermits.register(
            target: target,
            allowsChangedRevision: true,
            operationID: UUID()
        )
        let strictPermit = viewModel.metadataCommitPermits.register(
            target: target,
            allowsChangedRevision: false,
            operationID: UUID()
        )

        // Revision-only observation at the same path/ID must revoke strict
        // permits while leaving conflict-aware draft permits eligible for merge.
        let revised = AudioFileTestFactory.makeObserved(
            id: original.id,
            url: url,
            title: "Externally Edited",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: url, fileSize: 120),
            metadataFileVersion: v2
        )
        viewModel.revokeCommitPermitsIfObservationIncompatible(revised)
        XCTAssertNotNil(strictPermit.rejection, "Strict permit must revoke on changed disk revision")
        XCTAssertNil(draftPermit.rejection, "Conflict-aware draft permit must survive revision-only refresh for conflict resolution")

        // A recovery-required observation at the same path must still revoke the draft permit.
        let recoveryBlocked = original.projectingDisplay(to: url)
        viewModel.revokeCommitPermitsIfObservationIncompatible(recoveryBlocked)
        XCTAssertNotNil(draftPermit.rejection, "Recovery-required observation must revoke conflict-aware draft permit")
    }

    @MainActor
    func testProgressTokenOwnershipPreventsOldOperationFromClearingNewerProgress() {
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingReviewedPipeline(reloadFile: nil))
        let firstToken = viewModel.beginMetadataSaveProgress(
            title: "First",
            subtitle: "track1.mp3",
            totalUnitCount: 2
        )
        let secondToken = viewModel.beginMetadataSaveProgress(
            title: "Second",
            subtitle: "track2.mp3",
            totalUnitCount: 3
        )
        viewModel.endMetadataSaveProgress(token: firstToken)
        XCTAssertEqual(viewModel.metadataSaveProgress?.title, "Second")
        viewModel.endMetadataSaveProgress(token: secondToken)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testProjectMetadataWriteRejectsUnsupportedAdvisoryAndAcceptsUnknownExtensionNoOp() throws {
        let pipeline = TagLibAudioMetadataPipeline()
        var unsupportedAdvisory = MetadataEditPayload(
            SingleFileEditModel(from: AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/a.m4a")))
        )
        unsupportedAdvisory.unsupportedAdvisoryImport = "999"
        let advisoryProjection = try pipeline.projectMetadataWrite(.semantic(unsupportedAdvisory), fileExtension: "m4a")
        guard case .rejected = advisoryProjection.validation else {
            return XCTFail("Expected unsupported advisory import to reject during projection")
        }

        let unknownFile = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/a.unknownext"))
        let emptyNoOp = MetadataEditPayload(
            SingleFileEditModel(from: unknownFile),
            comparedTo: unknownFile
        )
        let noOpProjection = try pipeline.projectMetadataWrite(.semantic(emptyNoOp), fileExtension: "unknownext")
        XCTAssertTrue(noOpProjection.isExecutable)
        XCTAssertTrue(noOpProjection.isNoOp)
    }

    // MARK: - S8 provider / MuseAmp / erase migrations

    @MainActor
    func testProviderPlanEntryCarriesFrozenWriteAndAppliesThroughStrictRoute() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])

        let entry = iTunesTaggingWriteEntry(file: fixture.file, values: [.title: "Provider title"])
        XCTAssertNotNil(entry.reviewedWrite)
        await viewModel.applyiTunesTaggingPlan([entry])

        XCTAssertEqual(pipeline.semanticWrites.count, 1)
        XCTAssertEqual(pipeline.semanticWrites.first?.version, entry.reviewedWrite?.target.version)
        XCTAssertEqual(pipeline.semanticWrites.first?.payload.title, "Provider title")
    }

    @MainActor
    func testUnreviewedProviderEntryFailsClosedWithoutWriterCall() async throws {
        let pipeline = RecordingReviewedPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-entry.mp3")
        let entry = iTunesTaggingWriteEntry(
            fileID: UUID(),
            fileName: url.lastPathComponent,
            values: [.title: "Legacy"],
            expectedFileFingerprint: nil
        )
        await viewModel.applyiTunesTaggingPlan([entry])
        XCTAssertTrue(pipeline.semanticWrites.isEmpty)
    }

    @MainActor
    func testMuseAmpWritesFrozenCommentThroughStrictRoute() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])

        viewModel.createMuseAmpIDs(for: [fixture.file])
        try await waitUntil { viewModel.metadataSaveProgress == nil }
        XCTAssertEqual(pipeline.semanticWrites.count, 1)
        XCTAssertEqual(pipeline.semanticWrites.first?.version, fixture.file.metadataFileVersion)
        XCTAssertTrue(pipeline.semanticWrites.first?.payload.comment.contains("albumID") == true)
    }

    @MainActor
    func testEraseUsesReviewedEraseIntentAndCapturedRevision() async throws {
        let fixture = try makeObservedFixture()
        defer { removeDirectory(fixture.directory) }
        let pipeline = RecordingReviewedPipeline(reloadFile: fixture.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture.file])

        viewModel.eraseAllMetadata(fixture.file)
        try await waitUntil { viewModel.metadataSaveProgress == nil }
        XCTAssertEqual(pipeline.eraseVersions.count, 1)
        XCTAssertEqual(pipeline.eraseVersions.first, fixture.file.metadataFileVersion)
    }

    @MainActor
    func testConfirmedEraseAndMuseAmpCapturesRejectNewerRevisionAndUnapprovedSelection() async throws {
        let first = try makeObservedFixture()
        defer { removeDirectory(first.directory) }
        let second = try makeObservedFixture()
        defer { removeDirectory(second.directory) }
        let v2 = try XCTUnwrap(AudioFileTestFactory.secondaryFixtureFileVersion)
        XCTAssertNotEqual(first.file.metadataFileVersion, v2)

        let pipeline = RecordingReviewedPipeline(reloadFile: first.file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first.file, second.file])
        viewModel.setSelectedAudioIDs([first.file.id])

        // Capture both confirmation snapshots when only `first` (at V1) is selected.
        let eraseCapture = viewModel.captureConfirmedSelectionAction()
        let museAmpCapture = viewModel.captureConfirmedSelectionAction()
        XCTAssertEqual(eraseCapture.files.map(\.id), [first.file.id])

        // While the confirmation dialog is open, a refresh replaces `first` with V2
        // AND the selection switches to `second`.
        let refreshedFirst = AudioFileTestFactory.makeObserved(
            id: first.file.id,
            url: first.file.url,
            title: "Updated On Disk",
            fileFingerprint: AudioFileTestFactory.fingerprint(for: first.file.url, fileSize: 999),
            metadataFileVersion: v2
        )
        _ = viewModel.replaceLoadedFile(
            refreshedFirst,
            refreshGeneration: viewModel.makeFileModelRefreshGeneration(),
            deferVisibleRefresh: false
        )
        viewModel.setSelectedAudioIDs([second.file.id])

        // Affirming Erase must neither erase `first` (stale V1) nor touch `second` (unapproved).
        viewModel.executeConfirmedEraseAllMetadata(eraseCapture)
        try await waitUntil { viewModel.metadataSaveProgress == nil }
        XCTAssertTrue(pipeline.eraseVersions.isEmpty, "Confirmed Erase must reject newer V2 observation and never touch unapproved selection")

        // Affirming Create MuseAmp IDs must likewise reject stale V1 and never write to `second`.
        viewModel.executeConfirmedCreateMuseAmpIDs(museAmpCapture)
        try await waitUntil { viewModel.metadataSaveProgress == nil }
        XCTAssertTrue(pipeline.semanticWrites.isEmpty, "Confirmed MuseAmp must reject newer V2 observation and never touch unapproved selection")
    }

    // MARK: - S5 structural cancellation classification

    @MainActor
    func testBatchSummaryClassifiesCancellationStructurally() {
        var summary = BatchMetadataOperationSummary(totalTargets: 3)
        summary.succeeded = 1
        summary.recordCancelledFiles(["cancelled.flac"])
        summary.failureIssues.append(
            BatchMetadataWriteIssue(fileName: "failed.flac", messages: ["Permission denied."])
        )
        XCTAssertEqual(summary.cancelledCount, 1)
        XCTAssertEqual(summary.failureIssues.count, 2)

        var cancelledOnly = BatchMetadataOperationSummary(totalTargets: 2)
        cancelledOnly.recordCancelledFiles(["one.flac", "two.flac"])
        XCTAssertEqual(cancelledOnly.cancelledCount, 2)
        XCTAssertEqual(cancelledOnly.hudStyle, .warning)
        XCTAssertEqual(cancelledOnly.hudTitle, "Operation Cancelled")
    }

    @MainActor
    func testBatchOperationClaimsProgressBeforeModalFolderPromptAndBlocksOverlap() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let viewModel = makeUnscopedViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        var promptCount = 0
        var sawActiveProgressInsidePrompt = false
        var progressTitleInsidePrompt: String?
        viewModel.mutationDirectoryAccessRequester = { _ in
            promptCount += 1
            sawActiveProgressInsidePrompt = viewModel.metadataSaveProgress != nil
            progressTitleInsidePrompt = viewModel.metadataSaveProgress?.title
            if promptCount == 1 {
                // Attempt an overlapping batch operation while the modal prompt is open.
                viewModel.eraseAllMetadata([file])
            }
            return "Access denied for test."
        }

        viewModel.createMuseAmpIDs(for: [file])

        XCTAssertEqual(promptCount, 1, "Overlapping command must not re-enter folder access prompt")
        XCTAssertTrue(
            sawActiveProgressInsidePrompt,
            "Batch operation must claim progress ownership before the modal folder prompt"
        )
        XCTAssertEqual(progressTitleInsidePrompt, "Creating MuseAmp IDs")
        XCTAssertNil(
            viewModel.metadataSaveProgress,
            "Denied folder access must release progress cleanly using the owner token"
        )
    }

    @MainActor
    func testRawEditorAndTrackRenumberSkipFolderPromptForIneligibleTargets() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }

        let pipeline = TagLibAudioMetadataPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let viewModel = makeUnscopedViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        // Prepare valid Raw Editor and Track Renumber plans while the file is still eligible.
        let rawTarget = MetadataEditorTarget(file: file)
        let originalMap = try XCTUnwrap(rawTarget.metadataConflictBaseline?.values)
        var editedMap = originalMap
        editedMap["TITLE"] = ["Should Not Prompt"]
        let rawRequest = MetadataEditorApplyRequest(
            presentationID: MetadataEditorPresentationID(),
            applyID: MetadataEditorApplyID(),
            targets: [rawTarget],
            pendingTargets: [rawTarget],
            submittedOriginalPropertyMaps: [file.id: originalMap],
            submittedPropertyMaps: [file.id: editedMap],
            pendingChanges: [
                RawFieldValueChange(
                    targetID: file.id,
                    key: "TITLE",
                    beforeValues: originalMap["TITLE"],
                    afterValues: ["Should Not Prompt"]
                )
            ],
            draftGeneration: 1
        )
        let renumberPlan = viewModel.makeTrackRenumberPlan(
            orderedFiles: [file],
            selectedIDs: [file.id],
            direction: .ascending,
            startNumberText: "1"
        )
        XCTAssertEqual(renumberPlan.executableRows.count, 1)

        var promptCount = 0
        viewModel.mutationDirectoryAccessRequester = { _ in
            promptCount += 1
            return "Denied for test"
        }

        // Positive control: while eligible, folder access IS requested once.
        let eligibleOutcome = await viewModel.applyRawMetadataApplyRequest(rawRequest)
        XCTAssertEqual(promptCount, 1, "Positive control: eligible target must trigger folder access prompt")
        XCTAssertEqual(eligibleOutcome.failedTargetIDs, [file.id])

        // Now make the file ineligible before execution (recovery-blocked).
        viewModel.markFileRequiresRefresh(id: file.id)

        let rawOutcome = await viewModel.applyRawMetadataApplyRequest(rawRequest)
        XCTAssertEqual(promptCount, 1, "Raw Editor must not prompt for folder access on ineligible targets")
        XCTAssertEqual(rawOutcome.failedTargetIDs, [file.id])

        let renumberResult = await viewModel.renumberTrackNumbers(using: renumberPlan)
        XCTAssertEqual(promptCount, 1, "Track Renumber must not prompt for folder access on ineligible targets")
        XCTAssertEqual(renumberResult.failed, 1)
        XCTAssertEqual(renumberResult.succeeded, 0)
    }

    @MainActor
    func testRenumberSkipsLaterFolderInvalidatedDuringFirstPrompt() async throws {
        let urlA = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        defer { MetadataTestTokens.removeFixtureCopy(at: urlA) }
        let urlB = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        defer { MetadataTestTokens.removeFixtureCopy(at: urlB) }
        let pipeline = TagLibAudioMetadataPipeline()
        let files = try await [pipeline.loadAudioFile(at: urlA, id: UUID()), pipeline.loadAudioFile(at: urlB, id: UUID())]
        let vm = makeUnscopedViewModel(metadataPipeline: pipeline)
        vm.mergeQuickImportFiles(files)
        let plan = vm.makeTrackRenumberPlan(orderedFiles: files, selectedIDs: Set(files.map(\.id)),
                                            direction: .ascending, startNumberText: "8")
        XCTAssertEqual(plan.executableRows.count, 2)
        let snapshots = try files.map { try Data(contentsOf: $0.url) }
        var prompted: [String] = []
        var blockedFolder: String?
        var blockedID: AudioFile.ID?
        vm.mutationDirectoryAccessRequester = { directory in
            let directoryKey = FileSystemPathSemantics.key(for: directory)
            prompted.append(directoryKey)
            if prompted.count == 1 {
                if let other = files.first(where: { FileSystemPathSemantics.key(for: $0.url.deletingLastPathComponent()) != directoryKey }) {
                    blockedFolder = FileSystemPathSemantics.key(for: other.url.deletingLastPathComponent())
                    blockedID = other.id
                    vm.markFileRequiresRefresh(id: other.id)
                }
                return nil
            }
            return "Stop after capturing the next request."
        }
        let result = await vm.renumberTrackNumbers(using: plan)
        let unapprovedFolder = try XCTUnwrap(blockedFolder)
        XCTAssertFalse(prompted.contains(unapprovedFolder), "A second folder must not be requested after its only row became recovery-blocked during the first request")
        let ineligibleID = try XCTUnwrap(blockedID)
        XCTAssertTrue(vm.hasRecoveryDecision(for: ineligibleID))
        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(try files.map { try Data(contentsOf: $0.url) }, snapshots)
    }

    @MainActor
    private func makeUnscopedViewModel(metadataPipeline: any AudioMetadataPipeline) -> AudioViewModel {
        let suiteName = "AudioMatorUnscopedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let journalStore = LocalRenameJournalStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorUnscopedJournal-\(UUID().uuidString)", isDirectory: true)
        )
        return AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: metadataPipeline,
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: defaults,
            renameJournalStore: journalStore,
            renameJournalAutoClassification: false,
            quickImportEnvironment: QuickImportEnvironment(
                identityProvider: QuickImportEnvironment.production.identityProvider,
                scopeAccess: UnscopedTestQuickImportScopeAccess(),
                loadPolicy: .production
            )
        )
    }

    // MARK: - Helpers

    @MainActor
    private func waitForQueuedMutation(in viewModel: AudioViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await viewModel.fileMutationCoordinator.queuedMutationCount == 0,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let queued = await viewModel.fileMutationCoordinator.queuedMutationCount
        XCTAssertGreaterThan(queued, 0, "Expected the strict write to queue behind the reservation")
    }

    @MainActor
    private func waitUntil(
        deadlineSeconds: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(deadlineSeconds))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

/// Records the strict adapter calls and reloads a synthetic coherent observation.
private nonisolated final class RecordingReviewedPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct SemanticWriteRecord: Sendable {
        let url: URL
        let version: MetadataFileVersion
        let payload: MetadataEditPayload
    }

    private let lock = NSLock()
    private let reloadFile: AudioFile?
    private var semanticRecords: [SemanticWriteRecord] = []
    private var eraseRecordedVersions: [MetadataFileVersion] = []

    init(reloadFile: AudioFile?) {
        self.reloadFile = reloadFile
    }

    var semanticWrites: [SemanticWriteRecord] {
        lock.withLock { semanticRecords }
    }

    var eraseVersions: [MetadataFileVersion] {
        lock.withLock { eraseRecordedVersions }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        guard let reloadFile else { throw CocoaError(.fileNoSuchFile) }
        return reloadFile
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            semanticRecords.append(
                SemanticWriteRecord(url: url, version: expectedVersion, payload: edit)
            )
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadataReviewed(
        at url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        lock.withLock { eraseRecordedVersions.append(expectedVersion) }
        return AudioMetadataWriteResult(warnings: [])
    }
}

private nonisolated struct UnscopedTestQuickImportScopeAccess: QuickImportScopeAccessing {
    nonisolated func startAccessingScope(for url: URL) -> Bool { false }
    nonisolated func stopAccessingScope(for url: URL) {}
}
