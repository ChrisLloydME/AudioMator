import Combine
import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
nonisolated final class QuickImportProgressiveIndexTests: XCTestCase {
    // MARK: - Counter budgets

    @MainActor
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
            harness.viewModel,
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testPerCallbackPublicationPathKeyWorkIsZero() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 480)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced24)
        defer { harness.tearDown() }

        let recorder = observePublications(of: harness.viewModel, identityProvider: provider)
        harness.viewModel.importQuickFiles(from: urls)
        try await waitForImport(harness.viewModel, expectedCount: 480)

        XCTAssertEqual(recorder.batches.count, 20)
        XCTAssertEqual(
            recorder.providerFileKeyComputationCounts,
            Array(repeating: 480, count: 20),
            "Every publication callback must add zero path-key work (all candidates were prepared once up front)"
        )
        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(
            diagnostics.metrics.batchPublicationRowCounts,
            Array(repeating: 24, count: 20),
            "Per-callback accepted-row counters must match the forced batch cadence"
        )
        XCTAssertEqual(diagnostics.metrics.batchPublicationRowCounts.reduce(0, +), 480)
        XCTAssertEqual(provider.snapshot.identityPreparationCount, 480, "One identity preparation per candidate")
        XCTAssertEqual(provider.snapshot.parentKeyComputationCount, 1)
        XCTAssertEqual(diagnostics.metrics.terminalMergeCount, 0)
        XCTAssertEqual(diagnostics.metrics.terminalMergedRowCount, 0)
        harness.viewModel.clearQuickImportFiles()
    }

    @MainActor
    func testTerminalMergeDetectorCountsSyntheticTerminalMutation() throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 2)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: ProgressiveQuickImportMetadataPipeline(),
            provider: provider,
            access: access,
            policy: .forced24
        )
        defer { harness.tearDown() }
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().metrics.terminalMergeCount, 0)

        // Row-delta detector path: a synthetic row added inside a terminal body
        // must be detected even though no production merge seam is involved.
        harness.viewModel.runTerminalMergeDetectorForTesting {
            harness.viewModel.quickImportFiles.append(AudioFileTestFactory.make(url: urls[0]))
        }
        var metrics = harness.viewModel.quickImportDiagnostics().metrics
        XCTAssertEqual(metrics.terminalMergeCount, 1)
        XCTAssertEqual(metrics.terminalMergedRowCount, 1)

        // Merge-seam path: calling the documented merge seam from a terminal body
        // is also counted (seam increment plus its row delta).
        harness.viewModel.runTerminalMergeDetectorForTesting {
            harness.viewModel.mergeQuickImportFiles([AudioFileTestFactory.make(url: urls[1])])
        }
        metrics = harness.viewModel.quickImportDiagnostics().metrics
        XCTAssertEqual(metrics.terminalMergeCount, 3, "One seam detection and one row-delta detection")
        XCTAssertEqual(metrics.terminalMergedRowCount, 2)

        // A clean terminal pass must leave both counters unchanged.
        harness.viewModel.runTerminalMergeDetectorForTesting { }
        metrics = harness.viewModel.quickImportDiagnostics().metrics
        XCTAssertEqual(metrics.terminalMergeCount, 3)
        XCTAssertEqual(metrics.terminalMergedRowCount, 2)
    }

    // MARK: - Retarget rejection

    @MainActor
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

    @MainActor
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

    @MainActor
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
        let overlapDiagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(overlapDiagnostics.consistencyIssues, [])
        XCTAssertEqual(overlapDiagnostics.activeRequestCount, 0)
        XCTAssertEqual(overlapDiagnostics.metrics.terminalMergeCount, 0)
        for url in urls {
            let fileKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: url)
            XCTAssertNotNil(overlapDiagnostics.tokensByFileKey[fileKey])
            XCTAssertNotNil(overlapDiagnostics.admittedSequenceByFileKey[fileKey])
        }
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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
        let clearedDiagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(clearedDiagnostics.consistencyIssues, [])
        XCTAssertTrue(clearedDiagnostics.tokensByFileKey.isEmpty, "Clear drops every replacement token")
        XCTAssertTrue(clearedDiagnostics.admittedSequenceByFileKey.isEmpty)
        XCTAssertEqual(clearedDiagnostics.activeRequestCount, 0)
        XCTAssertEqual(clearedDiagnostics.metrics.terminalMergeCount, 0)
    }

    @MainActor
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

    // MARK: - Request-token ownership across overlapping requests (D2)

    @MainActor
    func testOlderRequestFailureDoesNotPruneNewerRequestToken() async throws {
        try requireFixtures()
        let urls = syntheticURLs(count: 1)
        let fileURL = urls[0]
        let gate = QuickImportProgressiveGate()
        let pipeline = ProgressiveQuickImportMetadataPipeline(gate: gate)
        pipeline.setFailFirstAttempts(1, for: fileURL)
        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(pipeline: pipeline, provider: provider, access: access, policy: .forced48)
        defer { harness.tearDown() }

        harness.viewModel.importQuickFiles(from: urls)
        try await waitUntil { pipeline.attemptCount(for: fileURL) == 1 }
        try await gate.waitUntilEntered(atLeast: 1)
        harness.viewModel.importQuickFiles(from: urls)
        try await waitUntil { pipeline.attemptCount(for: fileURL) == 2 }
        try await gate.waitUntilEntered(atLeast: 2)

        let fileKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: fileURL)
        let newerToken = harness.viewModel.quickImportDiagnostics().tokensByFileKey[fileKey]
        XCTAssertNotNil(newerToken, "The newer request must own the key before the older request terminates")
        await gate.release()
        try await waitForImport(harness.viewModel, expectedCount: 1)
        try await waitUntil { harness.viewModel.activeQuickImportTaskCount == 0 }

        XCTAssertEqual(
            harness.viewModel.files.count,
            1,
            "The older request's terminal must not prune the newer request's token and silently drop its row"
        )
        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.tokensByFileKey[fileKey], newerToken)
        XCTAssertNotNil(diagnostics.admittedSequenceByFileKey[fileKey])
        XCTAssertNil(harness.viewModel.metadataWriteHUD, "The superseded older failure must not surface")
        XCTAssertEqual(diagnostics.metrics.terminalMergeCount, 0)
        XCTAssertEqual(diagnostics.consistencyIssues, [])
        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 2)
    }

    @MainActor
    func testPruneUnpublishedKeysOnlyRemovesOwnedRegistryEntries() throws {
        let environment = QuickImportEnvironment(
            identityProvider: SyntheticQuickImportIdentityProvider(),
            scopeAccess: CountingQuickImportScopeAccess(),
            loadPolicy: .forced24
        )
        var bookkeeping = QuickImportBookkeeping(environment: environment)
        let sharedKey = "/tmp/shared.mp3"
        let orphanKey = "/tmp/orphan.mp3"
        let olderToken = UUID()
        let newerToken = UUID()

        // The newer request owns sharedKey: the older request's prepared ownership
        // is stale and must not delete the live token/sequence.
        bookkeeping.tokensByFileKey[sharedKey] = newerToken
        bookkeeping.admittedSequenceByFileKey[sharedKey] = 9
        // orphanKey was never published and the older request still owns it.
        bookkeeping.tokensByFileKey[orphanKey] = olderToken
        bookkeeping.admittedSequenceByFileKey[orphanKey] = 3

        var olderRequest = QuickImportRequestState(
            requestID: UUID(),
            sequence: 3,
            generation: 0,
            refreshGeneration: 0,
            taskID: UUID(),
            authorizationEpoch: 0
        )
        olderRequest.preparedKeys[sharedKey] = QuickImportRequestKeyOwnership(sequence: 3, token: olderToken)
        olderRequest.preparedKeys[orphanKey] = QuickImportRequestKeyOwnership(sequence: 3, token: olderToken)
        bookkeeping.requests[olderRequest.requestID] = olderRequest

        bookkeeping.pruneUnpublishedKeys(for: olderRequest)

        XCTAssertEqual(bookkeeping.tokensByFileKey[sharedKey], newerToken, "A newer owner's token must survive")
        XCTAssertEqual(bookkeeping.admittedSequenceByFileKey[sharedKey], 9)
        XCTAssertNil(bookkeeping.tokensByFileKey[orphanKey], "The request's own unpublished token is pruned")
        XCTAssertNil(bookkeeping.admittedSequenceByFileKey[orphanKey])
    }

    @MainActor
    func testInterleavedBatchesKeepOneTokenPerKeyAndNoTerminalMutation() async throws {
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
        harness.viewModel.importQuickFiles(from: urls)
        try await gate.waitUntilEntered(atLeast: 4)
        await gate.release()
        try await waitForImport(harness.viewModel, expectedCount: 2)
        try await waitUntil { harness.viewModel.activeQuickImportTaskCount == 0 }

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.activeRequestCount, 0)
        XCTAssertEqual(diagnostics.metrics.terminalMergeCount, 0)
        XCTAssertEqual(diagnostics.metrics.terminalMergedRowCount, 0)
        for url in urls {
            let fileKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: url)
            XCTAssertNotNil(diagnostics.tokensByFileKey[fileKey], "Each published key keeps one live token")
            XCTAssertNotNil(diagnostics.admittedSequenceByFileKey[fileKey])
        }
        XCTAssertEqual(Set(harness.viewModel.files.map(\.url)), Set(urls))
        XCTAssertEqual(Set(harness.viewModel.files.map(\.id)).count, 2)
        harness.viewModel.clearQuickImportFiles()
        assertBalancedScope(access: access, expectedStarts: 3)
    }

    // MARK: - Rename and journal-recovery index + lease migration

    @MainActor
    func testMovePlaceholdersMigratesMembershipIndexTokensAndLeases() async throws {
        try requireFixtures()
        let root = try makeTemporaryDirectory(prefix: "QuickImportMove")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("disc-one", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("disc-two", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("01.mp3")
        let siblingURL = sourceDirectory.appendingPathComponent("02.mp3")
        let destinationURL = destinationDirectory.appendingPathComponent("01 - Renamed.mp3")
        try Data().write(to: sourceURL)
        try Data().write(to: siblingURL)

        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: ProgressiveQuickImportMetadataPipeline(),
            provider: provider,
            access: access,
            policy: .forced48
        )
        defer { harness.tearDown() }
        harness.viewModel.mergeQuickImportFiles([
            AudioFileTestFactory.make(url: sourceURL, title: "One"),
            AudioFileTestFactory.make(url: siblingURL, title: "Two")
        ])
        let movedRow = try XCTUnwrap(harness.viewModel.files.first { $0.url == sourceURL })
        let siblingRow = try XCTUnwrap(harness.viewModel.files.first { $0.url == siblingURL })
        XCTAssertEqual(access.snapshot.startCount, 3, "Two file scopes and the shared source parent")

        harness.viewModel.publishMovePlaceholders([
            moveReceipt(fileID: movedRow.id, sourceURL: sourceURL, destinationURL: destinationURL)
        ])

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.consistencyIssues, [])
        let movedIdentity = try XCTUnwrap(diagnostics.membershipIdentitiesByID[movedRow.id])
        let oldKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: sourceURL)
        let newKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: destinationURL)
        XCTAssertEqual(movedIdentity.operationalURL, destinationURL.standardizedFileURL)
        XCTAssertEqual(movedIdentity.fileKey, newKey)
        XCTAssertEqual(
            movedIdentity.parentKey,
            SyntheticQuickImportIdentityProvider.parentKey(forFileURL: destinationURL)
        )
        XCTAssertEqual(diagnostics.fileKeyRefCounts[newKey], 1)
        XCTAssertNil(diagnostics.fileKeyRefCounts[oldKey])
        let destinationParentKey = SyntheticQuickImportIdentityProvider.parentKey(forFileURL: destinationURL)
        let sourceParentKey = SyntheticQuickImportIdentityProvider.parentKey(forFileURL: sourceURL)
        XCTAssertEqual(diagnostics.parentKeyRefCounts[destinationParentKey], 1)
        XCTAssertEqual(diagnostics.parentKeyRefCounts[sourceParentKey], 1, "The sibling keeps the source parent")
        XCTAssertNotNil(diagnostics.tokensByFileKey[oldKey], "The old location keeps a tombstone token")
        XCTAssertNotNil(diagnostics.tokensByFileKey[newKey])
        XCTAssertNotEqual(diagnostics.tokensByFileKey[oldKey], diagnostics.tokensByFileKey[newKey])
        XCTAssertGreaterThan(
            try XCTUnwrap(diagnostics.admittedSequenceByFileKey[newKey]),
            try XCTUnwrap(diagnostics.admittedSequenceByFileKey[oldKey])
        )
        XCTAssertEqual(
            harness.viewModel.files.first { $0.id == movedRow.id }?.url,
            destinationURL.standardizedFileURL,
            "The hidden membership URL must be published under the destination"
        )

        let oldFileLeaseKey = AudioViewModel.quickImportIntakeLeaseKey(for: sourceURL)
        let newFileLeaseKey = AudioViewModel.quickImportIntakeLeaseKey(for: destinationURL)
        XCTAssertNil(diagnostics.leaseOwnersByKey[oldFileLeaseKey])
        XCTAssertEqual(diagnostics.leaseOwnersByKey[newFileLeaseKey], [.membership(movedRow.id)])
        XCTAssertEqual(diagnostics.leaseOwnersByKey[sourceParentKey], [.membership(siblingRow.id)])
        XCTAssertEqual(diagnostics.leaseOwnersByKey[destinationParentKey], [.membership(movedRow.id)])
        XCTAssertEqual(
            diagnostics.leaseStatesByKey[sourceParentKey],
            .granted(url: sourceDirectory.standardizedFileURL)
        )
        XCTAssertEqual(diagnostics.metrics.moveMigrationIdentityMismatchCount, 0)

        let scopeBeforeClear = access.snapshot
        XCTAssertEqual(scopeBeforeClear.startCount, 4, "The destination parent starts once; file and source parent transfer")
        XCTAssertEqual(scopeBeforeClear.stopCount, 0)
        XCTAssertNil(scopeBeforeClear.startCountsByURL[destinationURL.standardizedFileURL])
        XCTAssertEqual(scopeBeforeClear.startCountsByURL[destinationDirectory.standardizedFileURL], 1)

        harness.viewModel.clearQuickImportFiles()
        let finalScope = access.snapshot
        XCTAssertEqual(finalScope.startCount, finalScope.stopCount, "Every migrated lease stops exactly once")
        XCTAssertEqual(finalScope.startCount, 4)
        XCTAssertEqual(harness.viewModel.quickImportDiagnostics().metrics.terminalMergeCount, 0)
    }

    @MainActor
    func testSharedParentCrossDirectoryRenameKeepsSingleGrantPerKey() async throws {
        try requireFixtures()
        let root = try makeTemporaryDirectory(prefix: "QuickImportSharedMove")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("disc-one", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("disc-two", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let firstSourceURL = sourceDirectory.appendingPathComponent("01.mp3")
        let secondSourceURL = sourceDirectory.appendingPathComponent("02.mp3")
        let firstDestinationURL = destinationDirectory.appendingPathComponent("01.mp3")
        let secondDestinationURL = destinationDirectory.appendingPathComponent("02.mp3")
        try Data().write(to: firstSourceURL)
        try Data().write(to: secondSourceURL)

        let provider = SyntheticQuickImportIdentityProvider()
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: ProgressiveQuickImportMetadataPipeline(),
            provider: provider,
            access: access,
            policy: .forced48
        )
        defer { harness.tearDown() }
        harness.viewModel.mergeQuickImportFiles([
            AudioFileTestFactory.make(url: firstSourceURL),
            AudioFileTestFactory.make(url: secondSourceURL)
        ])
        let firstRow = try XCTUnwrap(harness.viewModel.files.first { $0.url == firstSourceURL })
        let secondRow = try XCTUnwrap(harness.viewModel.files.first { $0.url == secondSourceURL })

        harness.viewModel.publishMovePlaceholders([
            moveReceipt(fileID: firstRow.id, sourceURL: firstSourceURL, destinationURL: firstDestinationURL),
            moveReceipt(fileID: secondRow.id, sourceURL: secondSourceURL, destinationURL: secondDestinationURL)
        ])

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        let sourceParentKey = SyntheticQuickImportIdentityProvider.parentKey(forFileURL: firstSourceURL)
        let destinationParentKey = SyntheticQuickImportIdentityProvider.parentKey(forFileURL: firstDestinationURL)
        XCTAssertNil(diagnostics.leaseOwnersByKey[sourceParentKey])
        XCTAssertEqual(
            diagnostics.leaseOwnersByKey[destinationParentKey],
            [.membership(firstRow.id), .membership(secondRow.id)]
        )
        XCTAssertEqual(diagnostics.parentKeyRefCounts[sourceParentKey] ?? 0, 0)
        XCTAssertEqual(diagnostics.parentKeyRefCounts[destinationParentKey], 2)
        XCTAssertEqual(diagnostics.fileKeyRefCounts[SyntheticQuickImportIdentityProvider.canonicalKey(for: firstDestinationURL)], 1)
        XCTAssertEqual(diagnostics.fileKeyRefCounts[SyntheticQuickImportIdentityProvider.canonicalKey(for: secondDestinationURL)], 1)
        XCTAssertNil(diagnostics.fileKeyRefCounts[SyntheticQuickImportIdentityProvider.canonicalKey(for: firstSourceURL)])

        let leaseMetrics = diagnostics.leaseMetrics
        XCTAssertEqual(leaseMetrics.dedupedGrantTransferStopCount, 1, "Only the redundant source-parent start is stopped")
        XCTAssertEqual(leaseMetrics.transferCount, 2, "Each file lease transfers its single grant")
        let scopeBeforeClear = access.snapshot
        XCTAssertEqual(scopeBeforeClear.startCount, 4, "Two file scopes, one source parent, one destination parent")
        XCTAssertEqual(scopeBeforeClear.stopCount, 1)
        XCTAssertEqual(scopeBeforeClear.stopCountsByURL[sourceDirectory.standardizedFileURL], 1)
        XCTAssertNil(scopeBeforeClear.stopCountsByURL[destinationDirectory.standardizedFileURL])

        harness.viewModel.clearQuickImportFiles()
        let finalScope = access.snapshot
        XCTAssertEqual(finalScope.startCount, finalScope.stopCount, "Cross-directory migration must not over-stop")
        XCTAssertEqual(finalScope.stopCountsByURL[sourceDirectory.standardizedFileURL], 1)
        XCTAssertEqual(finalScope.stopCountsByURL[destinationDirectory.standardizedFileURL], 1)
    }

    @MainActor
    func testJournalRestoreMigratesMembershipToOriginalURLByIdentityEvidence() async throws {
        try requireFixtures()
        let root = try makeTemporaryDirectory(prefix: "QuickImportRestore")
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryDirectory = root.appendingPathComponent("library", isDirectory: true)
        let renamedDirectory = root.appendingPathComponent("renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: renamedDirectory, withIntermediateDirectories: true)
        let originalURL = libraryDirectory.appendingPathComponent("track.mp3")
        let intendedURL = renamedDirectory.appendingPathComponent("track.mp3")
        try Data().write(to: intendedURL)

        let provider = SyntheticQuickImportIdentityProvider()
        let journalIdentity = QuickImportEntryIdentity(device: 7, inode: 42)
        provider.setFileIdentityOverride(journalIdentity, for: intendedURL)
        provider.setFileIdentityOverride(journalIdentity, for: originalURL)
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: ProgressiveQuickImportMetadataPipeline(),
            provider: provider,
            access: access,
            policy: .forced48
        )
        defer { harness.tearDown() }
        harness.viewModel.mergeQuickImportFiles([AudioFileTestFactory.make(url: intendedURL)])
        let row = try XCTUnwrap(harness.viewModel.files.first)
        XCTAssertEqual(access.snapshot.startCount, 2, "The file scope and its parent")

        let manifest = try journalManifest(
            originalURL: originalURL,
            intendedURL: intendedURL,
            sourceIdentity: journalIdentity
        )
        harness.viewModel.migrateQuickImportMembershipsAfterJournalRestore(
            manifest: manifest,
            restoredFileIDs: [row.id]
        )

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        XCTAssertEqual(diagnostics.consistencyIssues, [])
        let originalKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: originalURL)
        let intendedKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: intendedURL)
        let originalParentKey = SyntheticQuickImportIdentityProvider.parentKey(forFileURL: originalURL)
        let intendedParentKey = SyntheticQuickImportIdentityProvider.parentKey(forFileURL: intendedURL)
        let restoredIdentity = try XCTUnwrap(diagnostics.membershipIdentitiesByID[row.id])
        XCTAssertEqual(restoredIdentity.operationalURL, originalURL.standardizedFileURL)
        XCTAssertEqual(restoredIdentity.fileKey, originalKey)
        XCTAssertEqual(restoredIdentity.parentKey, originalParentKey)
        XCTAssertEqual(harness.viewModel.files.first { $0.id == row.id }?.url, originalURL.standardizedFileURL)
        XCTAssertEqual(diagnostics.fileKeyRefCounts[originalKey], 1)
        XCTAssertNil(diagnostics.fileKeyRefCounts[intendedKey])
        XCTAssertEqual(diagnostics.parentKeyRefCounts[originalParentKey], 1)
        XCTAssertEqual(diagnostics.parentKeyRefCounts[intendedParentKey] ?? 0, 0)
        XCTAssertNotNil(diagnostics.tokensByFileKey[originalKey])
        XCTAssertNotNil(diagnostics.tokensByFileKey[intendedKey], "The moved location keeps a tombstone token")
        XCTAssertNotEqual(diagnostics.tokensByFileKey[originalKey], diagnostics.tokensByFileKey[intendedKey])
        XCTAssertGreaterThan(
            try XCTUnwrap(diagnostics.admittedSequenceByFileKey[originalKey]),
            try XCTUnwrap(diagnostics.admittedSequenceByFileKey[intendedKey])
        )
        XCTAssertNil(diagnostics.leaseOwnersByKey[AudioViewModel.quickImportIntakeLeaseKey(for: intendedURL)])
        XCTAssertEqual(
            diagnostics.leaseOwnersByKey[AudioViewModel.quickImportIntakeLeaseKey(for: originalURL)],
            [.membership(row.id)]
        )
        XCTAssertEqual(diagnostics.leaseOwnersByKey[originalParentKey], [.membership(row.id)])
        XCTAssertNil(diagnostics.leaseOwnersByKey[intendedParentKey])
        XCTAssertEqual(diagnostics.metrics.restoredMembershipMigrationCount, 1)

        harness.viewModel.clearQuickImportFiles()
        let finalScope = access.snapshot
        XCTAssertEqual(finalScope.startCount, finalScope.stopCount, "Transferred grants keep one start and one stop")
        XCTAssertEqual(finalScope.startCount, 2)
    }

    @MainActor
    func testJournalRestoreSkipsMigrationWhenIdentityEvidenceDoesNotMatch() async throws {
        try requireFixtures()
        let root = try makeTemporaryDirectory(prefix: "QuickImportRestoreMismatch")
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryDirectory = root.appendingPathComponent("library", isDirectory: true)
        let renamedDirectory = root.appendingPathComponent("renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: renamedDirectory, withIntermediateDirectories: true)
        let originalURL = libraryDirectory.appendingPathComponent("track.mp3")
        let intendedURL = renamedDirectory.appendingPathComponent("track.mp3")
        try Data().write(to: intendedURL)

        let provider = SyntheticQuickImportIdentityProvider()
        let membershipIdentity = QuickImportEntryIdentity(device: 7, inode: 42)
        provider.setFileIdentityOverride(membershipIdentity, for: intendedURL)
        provider.setFileIdentityOverride(membershipIdentity, for: originalURL)
        let access = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: ProgressiveQuickImportMetadataPipeline(),
            provider: provider,
            access: access,
            policy: .forced48
        )
        defer { harness.tearDown() }
        harness.viewModel.mergeQuickImportFiles([AudioFileTestFactory.make(url: intendedURL)])
        let row = try XCTUnwrap(harness.viewModel.files.first)
        let manifest = try journalManifest(
            originalURL: originalURL,
            intendedURL: intendedURL,
            sourceIdentity: QuickImportEntryIdentity(device: 8, inode: 99)
        )

        harness.viewModel.migrateQuickImportMembershipsAfterJournalRestore(
            manifest: manifest,
            restoredFileIDs: [row.id]
        )

        let diagnostics = harness.viewModel.quickImportDiagnostics()
        let intendedKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: intendedURL)
        let originalKey = SyntheticQuickImportIdentityProvider.canonicalKey(for: originalURL)
        XCTAssertEqual(harness.viewModel.files.first { $0.id == row.id }?.url, intendedURL.standardizedFileURL)
        XCTAssertEqual(diagnostics.membershipIdentitiesByID[row.id]?.fileKey, intendedKey)
        XCTAssertNil(diagnostics.tokensByFileKey[originalKey])
        XCTAssertEqual(diagnostics.fileKeyRefCounts[intendedKey], 1)
        XCTAssertEqual(diagnostics.metrics.restoredMembershipMigrationCount, 0)
        harness.viewModel.clearQuickImportFiles()
        XCTAssertEqual(access.snapshot.startCount, access.snapshot.stopCount)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: AudioViewModel
        let suiteName: String
        let userDefaults: UserDefaults
        let journalDirectory: URL
        let issueLogURL: URL

        @MainActor
        func tearDown() {
            viewModel.clearQuickImportFiles()
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: journalDirectory)
            try? FileManager.default.removeItem(at: issueLogURL)
        }
    }

    @MainActor
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

    @MainActor
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
        XCTAssertEqual(
            diagnostics.metrics.batchPublicationRowCounts.count,
            expectedBatchCount,
            "One per-callback accepted-row counter per publication"
        )
        XCTAssertEqual(diagnostics.metrics.batchPublicationRowCounts.reduce(0, +), count)
        XCTAssertEqual(
            diagnostics.metrics.batchPublicationRowCounts.max(),
            min(policy.forceFlushBatchSize, count),
            "Each callback publishes at most the forced batch size"
        )
        XCTAssertEqual(diagnostics.metrics.terminalMergedRowCount, 0)
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
        /// Provider file-key counter sampled at each publication callback. It must
        /// be constant: all candidate path-key work happens before publication.
        var providerFileKeyComputationCounts: [Int] = []
        var cancellables: [AnyCancellable] = []
    }

    @MainActor
    private func observePublications(
        of viewModel: AudioViewModel,
        identityProvider: SyntheticQuickImportIdentityProvider? = nil
    ) -> PublicationRecorder {
        let recorder = PublicationRecorder()
        let cancellable = viewModel.$files.dropFirst().sink { files in
            recorder.batches.append(files)
            if let identityProvider {
                recorder.providerFileKeyComputationCounts.append(
                    identityProvider.snapshot.fileKeyComputationCount
                )
            }
        }
        recorder.cancellables.append(cancellable)
        publicationRecorders.append(recorder)
        return recorder
    }

    @MainActor
    private func assertBudget(
        _ viewModel: AudioViewModel,
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
        let diagnostics = viewModel.quickImportDiagnostics()
        XCTAssertEqual(
            diagnostics.metrics.publicationCount,
            expectedPublications,
            "The forced cadence must publish exactly ceil(count/batch) batches"
        )
        XCTAssertEqual(diagnostics.metrics.publishedRowCount, expectedCount)
        XCTAssertEqual(diagnostics.metrics.terminalMergeCount, 0, "No terminal path may merge published rows")
        XCTAssertEqual(diagnostics.metrics.terminalMergedRowCount, 0)
    }

    @MainActor
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

    @MainActor
    private func assertPublishedOrderAndUniqueness(
        _ viewModel: AudioViewModel,
        expectedURLs: [URL],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Independent lexical oracle: the synthetic fixture names are fixed-width
        // ASCII, so filename ordering is a deterministic expectation that does not
        // call the production comparator under test.
        let expectedOrder = expectedURLs.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent) == .orderedAscending
        }
        XCTAssertEqual(viewModel.files.map(\.url), expectedOrder, file: file, line: line)
        let ids = viewModel.files.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, file: file, line: line)
    }

    @MainActor
    private func moveReceipt(
        fileID: UUID,
        sourceURL: URL,
        destinationURL: URL
    ) -> FileRenameMoveReceipt {
        let destination = destinationURL.standardizedFileURL
        let evidence = SyntheticQuickImportIdentityProvider.syntheticEntryIdentity(for: destination)
        return FileRenameMoveReceipt(
            moveID: FileMoveID(),
            fileID: fileID,
            sourceURL: sourceURL,
            destinationURL: destination,
            entryIdentity: RenameEntryIdentity(
                device: evidence.device,
                inode: evidence.inode,
                kind: .regular,
                size: 0,
                modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
                creationDate: nil
            )
        )
    }

    @MainActor
    private func journalManifest(
        originalURL: URL,
        intendedURL: URL,
        sourceIdentity: QuickImportEntryIdentity
    ) throws -> RenameJournalManifest {
        let identity = RenameEntryIdentity(
            device: sourceIdentity.device,
            inode: sourceIdentity.inode,
            kind: .regular,
            size: 0,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            creationDate: nil
        )
        let entry = RenameJournalEntry(
            index: 0,
            originalURL: originalURL.standardizedFileURL.path,
            temporaryURL: originalURL.standardizedFileURL.deletingLastPathComponent()
                .appendingPathComponent(".audiomator-rename-stage").path,
            intendedURL: intendedURL.standardizedFileURL.path,
            sourceIdentity: try RenameJournalEntryIdentity(identity),
            linkTarget: nil
        )
        return RenameJournalManifest(
            formatVersion: RenameJournalFormat.currentVersion,
            operationID: UUID(),
            phase: .committed,
            createdAt: 1_700_000_000,
            committedAt: 1_700_000_100,
            diagnostics: [],
            entries: [entry]
        )
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    private func requireFixtures() throws {
        try XCTSkipIf(
            AudioFileTestFactory.fixtureFileVersion == nil,
            "App-hosted fixture snapshot is unavailable in this runner"
        )
    }

    @MainActor
    private func syntheticURLs(count: Int) -> [URL] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5Synthetic-\(UUID().uuidString)", isDirectory: true)
        return (0..<count).map { index in
            root.appendingPathComponent(String(format: "%05d-track.mp3", index))
        }
    }

    @MainActor
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
