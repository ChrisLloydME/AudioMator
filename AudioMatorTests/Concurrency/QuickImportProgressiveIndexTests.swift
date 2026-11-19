import Combine
import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class QuickImportProgressiveIndexTests: XCTestCase {
    // MARK: - Counter budgets

    func test480Forced24MeetsIdentityKeyAndLeaseBudgets() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 480)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced24)
        defer { harness.tearDown() }

        let recorder = observePublications(of: harness.viewModel)
        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 480)

        assertBudget(
            provider: provider,
            access: access,
            expectedCount: 480,
            expectedPublications: 20
        )
        XCTAssertEqual(recorder.batches.count, 20, "One publication per non-empty forced-24 batch")
        assertPublishedOrderAndUniqueness(harness.viewModel, expectedURLs: urls)

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.consistencyIssues, [])
        XCTAssertEqual(diagnostics.metrics.publicationCount, 20)
        XCTAssertEqual(diagnostics.metrics.publishedRowCount, 480)
        XCTAssertEqual(diagnostics.metrics.terminalMergeCount, 0)
        XCTAssertEqual(diagnostics.metrics.batchCount, 20)
        XCTAssertEqual(diagnostics.metrics.totalBatchItemCount, 480)

        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 481)
    }

    func test480Forced48PublishesTenBatchesWithIdenticalWorkCounters() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 480)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        let recorder = observePublications(of: harness.viewModel)
        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 480)

        XCTAssertEqual(recorder.batches.count, 10, "One publication per non-empty forced-48 batch")
        XCTAssertEqual(provider.snapshot.identityPreparationCount, 480)
        XCTAssertEqual(provider.snapshot.fileKeyComputationCount, 480)
        XCTAssertEqual(provider.snapshot.parentKeyComputationCount, 1)
        XCTAssertEqual(access.snapshot.startCount, 481)
        assertPublishedOrderAndUniqueness(harness.viewModel, expectedURLs: urls)

        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 481)
    }

    func test960And4000StayLinearAcrossForcedBatchSizes() async throws {
        try requireFixtures()

        let counters480 = try await runSyntheticLane(count: 480, policy: .forced48)
        let counters960 = try await runSyntheticLane(count: 960, policy: .forced48)
        let counters4000 = try await runSyntheticLane(count: 4_000, policy: .forced48)

        XCTAssertEqual(counters480.identityPreparations, 480)
        XCTAssertEqual(counters480.parentPreparations, 1)
        XCTAssertEqual(counters960.identityPreparations, 960)
        XCTAssertEqual(counters960.parentPreparations, 1)
        XCTAssertEqual(counters4000.identityPreparations, 4_000)
        XCTAssertEqual(counters4000.parentPreparations, 1)

        // Doubling files at most doubles path work plus fixed setup counters.
        XCTAssertLessThanOrEqual(
            counters960.pathKeyComputations,
            2 * counters480.pathKeyComputations + 8
        )
        XCTAssertLessThanOrEqual(
            counters4000.pathKeyComputations,
            9 * counters960.pathKeyComputations / 2 + 64
        )
        XCTAssertEqual(counters480.publications, 10)
        XCTAssertEqual(counters960.publications, 20)
        XCTAssertEqual(counters4000.publications, 84)
        XCTAssertEqual(counters480.consistencyIssues, [])
        XCTAssertEqual(counters960.consistencyIssues, [])
        XCTAssertEqual(counters4000.consistencyIssues, [])
    }

    func testForcedBatchSizeDoesNotChangeIdentityWork() async throws {
        try requireFixtures()
        let forced24 = try await runSyntheticLane(count: 480, policy: .forced24)
        let forced48 = try await runSyntheticLane(count: 480, policy: .forced48)

        XCTAssertEqual(forced24.identityPreparations, forced48.identityPreparations)
        XCTAssertEqual(forced24.fileKeyComputations, forced48.fileKeyComputations)
        XCTAssertEqual(forced24.parentPreparations, forced48.parentPreparations)
        XCTAssertEqual(forced24.scopeStarts, forced48.scopeStarts)
        XCTAssertEqual(forced24.publications, 20, "forced24 cadence: ceil(480/24)")
        XCTAssertEqual(forced48.publications, 10, "forced48 cadence: ceil(480/48)")
        // No full-collection pass or terminal merge exists in either cadence.
        XCTAssertEqual(forced24.terminalMerges, 0)
        XCTAssertEqual(forced48.terminalMerges, 0)
    }

    // MARK: - Scope leases

    func testScopeLeasesAreBalancedAndStartedOncePerKey() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 64)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced24)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 64)

        let starts = access.snapshot
        XCTAssertEqual(starts.startCount, 65, "64 files + one shared parent, each started once")
        XCTAssertEqual(starts.repeatedStartAttempts, 0, "A live lease is never started twice")
        XCTAssertEqual(
            harness.viewModel.quickImportDiagnostics().leaseMetrics.liveLeaseCount,
            65
        )

        harness.viewModel.clearQuickImportFiles()
        let final = access.snapshot
        XCTAssertEqual(final.stopCount, 65)
        XCTAssertEqual(
            harness.viewModel.quickImportDiagnostics().leaseMetrics.startCount,
            harness.viewModel.quickImportDiagnostics().leaseMetrics.stopCount
        )
    }

    func testNotRequiredScopeIsNeverStoppedAndNeverRetriedByBatchSync() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 8)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess(defaultGrant: false)
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 8)

        let starts = access.snapshot
        XCTAssertEqual(starts.startCount, 9, "A failed start is tracked once per key, not retried per batch")
        harness.viewModel.clearQuickImportFiles()
        XCTAssertEqual(access.snapshot.stopCount, 0, "A scope that never started is never stopped")
        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.leaseMetrics.notRequiredCount, 9)
        XCTAssertEqual(diagnostics.leaseMetrics.revokedCount, 0)
    }

    func testRevokedScopeIsRetriedOnlyAtANewAuthorizationEpoch() async throws {
        try requireFixtures()
        let url = syntheticURLs(count: 1)[0]
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess(defaultGrant: true)
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: [url])
        try await waitForImport(harness.viewModel, expectedCount: 1)
        harness.viewModel.clearQuickImportFiles()
        XCTAssertEqual(
            access.snapshot.stopCount,
            2,
            "File and parent scopes stop exactly once; access=\(access.snapshot) lease=\(harness.viewModel.quickImportDiagnostics().leaseMetrics)"
        )

        access.setDefaultGrant(false)
        harness.viewModel.importQuickFiles(from: [url])
        try await waitForImport(harness.viewModel, expectedCount: 1)
        let afterFailure = access.snapshot
        XCTAssertEqual(
            afterFailure.startCount,
            4,
            "A revoked key retries once at the explicit import event; access=\(afterFailure) lease=\(harness.viewModel.quickImportDiagnostics().leaseMetrics)"
        )
        XCTAssertEqual(
            afterFailure.stopCount,
            2,
            "Revoked scopes hold no stop obligation; access=\(afterFailure)"
        )
        XCTAssertEqual(
            harness.viewModel.quickImportDiagnostics().leaseMetrics.revokedCount,
            2
        )
        harness.viewModel.clearQuickImportFiles()

        // Same authorization epoch cannot retry; a new explicit import can.
        let suppressed = access.snapshot
        access.setDefaultGrant(true)
        harness.viewModel.importQuickFiles(from: [url])
        try await waitForImport(harness.viewModel, expectedCount: 1)
        XCTAssertEqual(
            access.snapshot.startCount,
            suppressed.startCount + 2,
            "A newer explicit authorization retries both keys; before=\(suppressed) after=\(access.snapshot)"
        )
        harness.viewModel.clearQuickImportFiles()
        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(
            diagnostics.leaseMetrics.grantedCount,
            diagnostics.leaseMetrics.stopCount,
            "Every granted scope start is balanced by exactly one stop; lease=\(diagnostics.leaseMetrics)"
        )
    }

    // MARK: - Retarget rejection

    func testSymlinkRetargetBetweenPreparationAndLoadIsDeclinedWithSelectAgain() async throws {
        try requireFixtures()
        let root = try makeTemporaryDirectory(prefix: "QuickImportSymlinkRetarget")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstTarget = root.appendingPathComponent("first.mp3")
        let secondTarget = root.appendingPathComponent("second.mp3")
        try Data("first".utf8).write(to: firstTarget)
        try Data("second".utf8).write(to: secondTarget)
        let alias = root.appendingPathComponent("alias.mp3")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: firstTarget)

        let gate = QuickImportProgressiveGate()
        let pipeline = ProgressiveQuickImportMetadataPipeline(mode: .realFingerprint, gate: gate)
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: pipeline,
            provider: FileSystemQuickImportPathIdentityProvider(),
            access: access,
            policy: .forced48
        )
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: [alias])
        try await gate.waitUntilEntered()

        // Retarget the symlink after the candidate identity was prepared.
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: secondTarget)
        await gate.release()
        try await waitForImport(harness.viewModel, expectedCount: 0)

        XCTAssertTrue(
            harness.viewModel.files.isEmpty,
            "A retargeted symlink must not publish the file that now sits at the alias"
        )
        XCTAssertEqual(harness.viewModel.metadataWriteHUD?.style, .warning)
        XCTAssertTrue(
            harness.viewModel.metadataWriteHUD?.subtitle.contains("Select it again") == true,
            "The declined result must be reported as select-again instead of retried"
        )
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().metrics.rejectedReadCount, 1)
        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 2)
    }

    func testReplacedParentEntryBetweenPreparationAndLoadIsDeclined() async throws {
        try requireFixtures()
        let root = try makeTemporaryDirectory(prefix: "QuickImportParentRetarget")
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let fileURL = child.appendingPathComponent("track.mp3")
        try Data("original".utf8).write(to: fileURL)

        let gate = QuickImportProgressiveGate()
        let pipeline = ProgressiveQuickImportMetadataPipeline(mode: .realFingerprint, gate: gate)
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: pipeline,
            provider: FileSystemQuickImportPathIdentityProvider(),
            access: access,
            policy: .forced48
        )
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: [fileURL])
        try await gate.waitUntilEntered()

        // Replace the whole parent directory with a new directory containing a
        // same-named entry. The canonical path is unchanged; device/inode is not.
        let movedChild = root.appendingPathComponent("child-moved", isDirectory: true)
        try FileManager.default.moveItem(at: child, to: movedChild)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: fileURL)
        await gate.release()
        try await waitForImport(harness.viewModel, expectedCount: 0)

        XCTAssertTrue(
            harness.viewModel.files.isEmpty,
            "A replaced parent entry must be declined even though the canonical path matches"
        )
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().metrics.rejectedReadCount, 1)
        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 2)
    }

    // MARK: - Supersession, ordering, duplicates, reimport

    func testOverlappingRequestsSupersedeTheOlderToken() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 2)
        let gate = QuickImportProgressiveGate()
        let pipeline = ProgressiveQuickImportMetadataPipeline(gate: gate)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await gate.waitUntilEntered(atLeast: 2)
        // A newer request for one overlapping URL is admitted while the older
        // request's loads are still suspended.
        harness.viewModel.importQuickFiles(from: [urls[0]])
        try await gate.waitUntilEntered(atLeast: 3)
        await gate.release()
        try await waitForImport(harness.viewModel, expectedCount: 2)

        XCTAssertEqual(harness.viewModel.files.count, 2)
        XCTAssertEqual(Set(harness.viewModel.files.map(\.url)), Set(urls))
        XCTAssertEqual(
            harness.viewModel.quickImportDiagnostics().metrics.rejectedStaleCount,
            1,
            "The older request's superseded key must not progress"
        )
        let ids = harness.viewModel.files.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "No duplicate published rows")
        // The two requests overlap, so the newer request's row may be appended
        // after the older request's later rows. Each request still publishes its
        // own accepted rows exactly once in contiguous order.
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().consistencyIssues, [])
    }

    func testDuplicateAliasCollapsesToOneRow() async throws {
        try requireFixtures()
        let directory = syntheticURLs(count: 4)[0].deletingLastPathComponent()
        let fileURL = directory.appendingPathComponent("real-track.mp3")
        // Two identical lexical URLs represent a duplicate selection; the intake
        // dedupe must collapse them before any identity work.
        let urls = [fileURL, URL(fileURLWithPath: fileURL.path), fileURL]
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 1)
        XCTAssertEqual(provider.snapshot.identityPreparationCount, 1, "Exact duplicates are deduped at intake")
        XCTAssertEqual(harness.viewModel.files.count, 1)
        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 2)
    }

    func testReimportReplacesRowInPlaceWithStableID() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 3)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 3)
        let originalIDs = harness.viewModel.files.map(\.id)
        let originalOrder = harness.viewModel.files.map(\.url)

        let preparationsBeforeReimport = provider.snapshot.identityPreparationCount
        harness.viewModel.importQuickFiles(from: [urls[1], urls[0]])
        try await waitForImport(harness.viewModel, expectedCount: 3)
        // Wait until the second request terminated.
        try await waitUntil { harness.viewModel.activeQuickImportTaskCount == 0 }

        XCTAssertEqual(harness.viewModel.files.map(\.id), originalIDs, "Reimport keeps the stable row IDs")
        XCTAssertEqual(harness.viewModel.files.map(\.url), originalOrder, "Replace keeps the original row positions")
        XCTAssertEqual(
            provider.snapshot.identityPreparationCount - preparationsBeforeReimport,
            2,
            "Reimport prepares each selected candidate once"
        )
        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.consistencyIssues, [])
        harness.viewModel.clearQuickImportFiles()
    }

    // MARK: - Clear/cancel and merge seam

    func testClearReleasesLeasesAndRejectsLateBatches() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 48)
        let gate = QuickImportProgressiveGate()
        let pipeline = ProgressiveQuickImportMetadataPipeline(gate: gate, gatedURLs: Set([urls[47]]))
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced24)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await gate.waitUntilEntered(atLeast: 1)
        harness.viewModel.clearQuickImportFiles()
        await gate.release()
        try await waitUntil { harness.viewModel.activeQuickImportTaskCount == 0 }
        XCTAssertTrue(harness.viewModel.files.isEmpty)

        let final = access.snapshot
        XCTAssertEqual(final.startCount, 49, "48 files + parent started once")
        XCTAssertEqual(final.stopCount, 49, "Clear stops every granted lease exactly once")
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().consistencyIssues, [])
    }

    func testMergeSeamMaintainsIndexAndLeases() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 8)
        let files = (0..<8).map { index in
            AudioFileTestFactory.make(url: urls[index], title: "Track \(index)")
        }
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: ProgressiveQuickImportMetadataPipeline(),
            provider: provider,
            access: access,
            policy: .production
        )
        defer { harness.tearDown() }

        harness.viewModel.mergeQuickImportFiles(files)
        XCTAssertEqual(harness.viewModel.files.count, 8)
        XCTAssertEqual(provider.snapshot.identityPreparationCount, 8)
        XCTAssertEqual(provider.snapshot.parentKeyComputationCount, 1)
        XCTAssertEqual(access.snapshot.startCount, 9)
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().consistencyIssues, [])

        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 9)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: AudioViewModel
        let suiteName: String
        let userDefaults: UserDefaults
        let journalDirectory: URL
        let issueLogURL: URL

        func tearDown() {
            viewModel.clearQuickImportFiles()
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: journalDirectory)
            try? FileManager.default.removeItem(at: issueLogURL)
        }
    }

    private func makeHarness(
        pipeline: any AudioMetadataPipeline,
        provider: any QuickImportPathIdentityProviding,
        access: any QuickImportScopeAccessing,
        policy: QuickImportLoadPolicy
    ) throws -> Harness {
        let suiteName = "AudioMator.F5Progressive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5Journal-\(UUID().uuidString)", isDirectory: true)
        let issueLogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5Issues-\(UUID().uuidString).json")
        let environment = QuickImportEnvironment(
            identityProvider: provider,
            scopeAccess: access,
            loadPolicy: policy
        )
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: issueLogURL),
            conflictPolicyDefaults: defaults,
            renameJournalStore: LocalRenameJournalStore(directoryURL: journalDirectory),
            renameJournalAutoClassification: false,
            quickImportEnvironment: environment
        )
        return Harness(
            viewModel: viewModel,
            suiteName: suiteName,
            userDefaults: defaults,
            journalDirectory: journalDirectory,
            issueLogURL: issueLogURL
        )
    }

    private struct LaneCounters {
        let identityPreparations: Int
        let fileKeyComputations: Int
        let parentPreparations: Int
        let scopeStarts: Int
        let publications: Int
        let terminalMerges: Int
        let consistencyIssues: [String]

        var pathKeyComputations: Int { fileKeyComputations + parentPreparations }
    }

    private func runSyntheticLane(
        count: Int,
        policy: QuickImportLoadPolicy
    ) async throws -> LaneCounters {
        let expectedBatchCount = (count + policy.forceFlushBatchSize - 1) / policy.forceFlushBatchSize
        let urls = syntheticURLs(count: count)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(
            pipeline: pipeline,
            provider: provider,
            access: access,
            policy: policy
        )
        defer { harness.tearDown() }

        let recorder = observePublications(of: harness.viewModel)
        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: count)

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        assertPublishedOrderAndUniqueness(harness.viewModel, expectedURLs: urls)
        XCTAssertTrue(recorder.batches.allSatisfy { !$0.isEmpty }, "Never publish an empty batch")
        XCTAssertEqual(recorder.batches.count, expectedBatchCount)
        for snapshot in recorder.batches {
            let ids = snapshot.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "No duplicate rows inside one publication")
        }
        let finalIDs = recorder.batches.last?.map(\.id) ?? []
        XCTAssertEqual(finalIDs.count, count)
        XCTAssertEqual(Set(finalIDs).count, count)
        // Every publication is a growing prefix snapshot, never a full re-emit
        // of a collection that was replaced.
        var previousCount = 0
        for snapshot in recorder.batches {
            XCTAssertGreaterThan(snapshot.count, previousCount)
            previousCount = snapshot.count
        }

        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: count + 1)
        return LaneCounters(
            identityPreparations: provider.snapshot.identityPreparationCount,
            fileKeyComputations: provider.snapshot.fileKeyComputationCount,
            parentPreparations: provider.snapshot.parentKeyComputationCount,
            scopeStarts: access.snapshot.startCount,
            publications: diagnostics.metrics.publicationCount,
            terminalMerges: diagnostics.metrics.terminalMergeCount,
            consistencyIssues: diagnostics.consistencyIssues
        )
    }

    private final class PublicationRecorder {
        var batches: [[AudioFile]] = []
        var cancellables: [AnyCancellable] = []
    }

    private func observePublications(of viewModel: AudioViewModel) -> PublicationRecorder {
        let recorder = PublicationRecorder()
        let cancellable = viewModel.$files.dropFirst().sink { files in
            recorder.batches.append(files)
        }
        recorder.cancellables.append(cancellable)
        publicationRecorders.append(recorder)
        return recorder
    }

    private func assertBudget(
        provider: SyntheticQuickImportIdentityProvider,
        access: CountingQuickImportScopeAccess,
        expectedCount: Int,
        expectedPublications: Int
    ) {
        XCTAssertEqual(provider.snapshot.identityPreparationCount, expectedCount)
        XCTAssertEqual(provider.snapshot.fileKeyComputationCount, expectedCount)
        XCTAssertEqual(provider.snapshot.fileIdentityCaptureCount, expectedCount)
        XCTAssertEqual(provider.snapshot.parentKeyComputationCount, 1)
        XCTAssertEqual(provider.snapshot.parentIdentityCaptureCount, 1)
        XCTAssertEqual(access.snapshot.startCount, expectedCount + 1)
        XCTAssertEqual(access.snapshot.repeatedStartAttempts, 0)
        XCTAssertGreaterThan(expectedPublications, 0)
    }

    private func assertBalancedScope(
        access: CountingQuickImportScopeAccess,
        expectedStarts: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = access.snapshot
        XCTAssertEqual(snapshot.startCount, expectedStarts, file: file, line: line)
        XCTAssertEqual(snapshot.stopCount, expectedStarts, file: file, line: line)
        XCTAssertEqual(snapshot.repeatedStartAttempts, 0, file: file, line: line)
    }

    private func assertPublishedOrderAndUniqueness(
        _ viewModel: AudioViewModel,
        expectedURLs: [URL],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedOrder = expectedURLs.sorted(by: AudioViewModel.compareURLs)
        XCTAssertEqual(viewModel.files.map(\.url), expectedOrder, file: file, line: line)
        let ids = viewModel.files.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, file: file, line: line)
    }

    private func waitForImport(
        _ viewModel: AudioViewModel,
        expectedCount: Int,
        timeout: TimeInterval = 120
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while (viewModel.activeQuickImportTaskCount != 0 || viewModel.files.count != expectedCount),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(viewModel.activeQuickImportTaskCount, 0)
        XCTAssertEqual(viewModel.files.count, expectedCount)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }

    private func requireFixtures() throws {
        try XCTSkipIf(
            AudioFileTestFactory.fixtureFileVersion == nil,
            "App-hosted fixture snapshot is unavailable in this runner"
        )
    }

    private func syntheticURLs(count: Int) -> [URL] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5Synthetic-\(UUID().uuidString)", isDirectory: true)
        return (0..<count).map { index in
            root.appendingPathComponent(String(format: "%05d-track.mp3", index))
        }
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // Retains subscriptions/recorders for the lifetime of one test instance;
    // XCTest creates a fresh instance per test method.
    private var publicationRecorders: [PublicationRecorder] = []
}
#endif
