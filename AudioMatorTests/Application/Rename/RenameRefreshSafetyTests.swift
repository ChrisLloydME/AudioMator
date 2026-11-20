import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class RenameRefreshSafetyTests: XCTestCase {
    // MARK: - Move publication and in-flight invalidation

    @MainActor
    func testMoveSupersedesPendingOldURLAndLateReadCannotOverwriteNewerObservation() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameReadbackPipeline(mode: .fail))
        viewModel.mergeQuickImportFiles([original])
        viewModel.flushPendingMetadataReloads()
        viewModel.replaceLoadedFile(
            original,
            refreshGeneration: viewModel.makeFileModelRefreshGeneration(),
            deferVisibleRefresh: true
        )

        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])
        viewModel.flushPendingMetadataReloads()

        XCTAssertEqual(viewModel.files.first?.url, environment.destinationURL)
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertNil(moved.fileFingerprint)
        XCTAssertNil(moved.metadataFileVersion)
        XCTAssertNil(moved.metadataConflictBaseline)
    }

    @MainActor
    func testLateMoveReadbackCannotReplaceNewerGeneratedObservation() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameReadbackPipeline(mode: .real, started: started, release: release)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let move = Task { await viewModel.readBackMovedFiles([receipt]) }
        await started.wait()
        let newer = AudioFileTestFactory.makeObserved(
            id: original.id,
            url: environment.destinationURL,
            title: "Newer observation",
            fileFingerprint: try AudioFileFingerprint.capture(at: environment.destinationURL),
            metadataFileVersion: try MetadataTestTokens.mintedVersion(at: environment.destinationURL)
        )
        viewModel.replaceLoadedFile(newer, refreshGeneration: viewModel.makeFileModelRefreshGeneration())
        await release.open()
        _ = await move.value

        XCTAssertEqual(viewModel.files.first?.url, environment.destinationURL)
        XCTAssertEqual(viewModel.files.first?.title, "Newer observation")
        // A newer automatic observation wins the generation race but cannot clear
        // the pending move decision.
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
    }

    // MARK: - Queued writers observe the recovery decision

    @MainActor
    func testRecoveryDecisionBlocksStaleDraftsAndAlreadyQueuedWriters() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let reserved = RenameReadGate()
        let release = RenameReadGate()
        let holder = Task {
            try await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [original.url]) {
                await reserved.open()
                await release.wait()
            }
        }
        await reserved.wait()
        var edit = SingleFileEditModel(from: original)
        edit.title = "Stale draft"
        let capturedEdit = edit
        let save = Task { await viewModel.persistReviewedEditForTest(capturedEdit, to: original) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await viewModel.fileMutationCoordinator.queuedMutationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let queuedCount = await viewModel.fileMutationCoordinator.queuedMutationCount
        XCTAssertEqual(queuedCount, 1)

        viewModel.recordRecoveryDecision(
            .recoveryLocationUnresolved(
                expectedIdentity: EntryIdentityKey(fingerprint: original.fileFingerprint)
            ),
            for: original.id
        )
        await release.open()
        try await holder.value
        guard case .failure(let reason) = await save.value else {
            return XCTFail("Queued stale intent must observe the newer recovery decision")
        }
        XCTAssertTrue(reason.contains("Reload from Disk"))

        let blocked = try XCTUnwrap(viewModel.files.first)
        let rawResult = await viewModel.applyRawMetadataPropertyMaps(
            [original.id: ["TITLE": ["Stale raw edit"]]],
            to: [MetadataEditorTarget(file: blocked)]
        )
        XCTAssertEqual(rawResult.failedTargetIDs, [original.id])
        XCTAssertEqual(pipeline.writeCount, 0)
    }

    // MARK: - Failed readback is fail closed regardless of lightweight probes

    @MainActor
    func testFailedFullReadbackKeepsMovedProjectionReadOnlyEvenWhenLightweightProbesSucceed() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let destinationBytes = try Data(contentsOf: environment.destinationURL)
        let warnings = await viewModel.readBackMovedFiles([receipt])

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertNil(moved.fileFingerprint)
        XCTAssertNil(moved.metadataFileVersion)
        XCTAssertNil(moved.metadataConflictBaseline)
        XCTAssertTrue(warnings.first?.contains("Reload from Disk") == true || warnings.first?.contains("couldn’t be reloaded") == true)

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Must not write"
        guard case .failure = await viewModel.persistReviewedEditForTest(edit, to: moved) else {
            return XCTFail("Inspector save must fail closed after a failed full readback")
        }
        let rawResult = await viewModel.applyRawMetadataPropertyMaps(
            [moved.id: ["TITLE": ["Must not write"]]],
            to: [MetadataEditorTarget(file: moved)]
        )
        XCTAssertEqual(rawResult.failedTargetIDs, [moved.id])
        XCTAssertEqual(pipeline.writeCount, 0)
        XCTAssertEqual(try Data(contentsOf: environment.destinationURL), destinationBytes)
    }

    @MainActor
    func testFailedRenameRefreshDisablesMetadataWritesWhenRevisionCannotBeRecovered() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertFalse(warnings.isEmpty)

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Must not write"
        guard case .failure(let reason) = await viewModel.persistReviewedEditForTest(edit, to: moved) else {
            return XCTFail("Expected a refresh-required failure")
        }
        XCTAssertTrue(reason.contains("Reload from Disk"))
        XCTAssertEqual(pipeline.writeCount, 0)
    }

    @MainActor
    func testReceiptMatchedReadbackRestoresAuthorityOnlyForItsMove() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .real)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(warnings.isEmpty)
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(moved.observation)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: moved.id))

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Verified move write"
        guard case .success = await viewModel.persistReviewedEditForTest(edit, to: moved, comparedTo: moved) else {
            return XCTFail("A receipt-matched readback must restore metadata write authority")
        }
        XCTAssertEqual(pipeline.writeCount, 1)
        XCTAssertNotNil(pipeline.lastExpectedVersion)
    }

    /// End-to-end disk evidence: a real move, a real bounded readback and a real
    /// post-move write through the production adapter. Verifies the persisted
    /// value, preserved number/disc components and untouched unrelated raw values.
    @MainActor
    func testReceiptMatchedReadbackRestoresAuthorityForRealPostMoveWrite() async throws {
        let environment = try makeEnvironment()
        let sourceURL = environment.sourceURL
        let destinationURL = environment.destinationURL
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        defer { MetadataTestTokens.removeFixtureCopy(at: sourceURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        let source = try await pipeline.loadAudioFile(at: sourceURL, id: UUID())
        let beforeMap = try pipeline.rawMetadataValueMap(for: sourceURL)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([source])

        // A real move, not a copy: the source directory entry no longer exists.
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        let receipt = try makeReceipt(for: source, from: sourceURL, to: destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "; "))
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, destinationURL)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(moved.observation)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: moved.id))

        var edit = SingleFileEditModel(from: moved)
        edit.title = "Real post-move write"
        guard case .success = await viewModel.persistReviewedEditForTest(edit, to: moved, comparedTo: moved) else {
            return XCTFail("A receipt-matched readback must allow a real post-move write")
        }

        let persisted = try await pipeline.loadAudioFile(at: destinationURL, id: source.id)
        XCTAssertEqual(persisted.title, "Real post-move write")
        XCTAssertEqual(persisted.trackTotal, source.trackTotal)
        XCTAssertEqual(persisted.disc, source.disc)
        XCTAssertEqual(persisted.discTotal, source.discTotal)

        let afterMap = try pipeline.rawMetadataValueMap(for: destinationURL)
        let changedKeys = Set(beforeMap.keys).union(afterMap.keys).filter { beforeMap[$0] != afterMap[$0] }
        XCTAssertTrue(changedKeys.contains("TITLE"))
        XCTAssertTrue(
            changedKeys.subtracting(["TITLE"]).isEmpty,
            "Unrelated raw values must survive the post-move write: \(changedKeys.subtracting(["TITLE"]))"
        )
    }

    /// Journal receipts carry extra identity evidence (volume identifier, symlink
    /// target) captured on a different platform surface than F1's `lstat`
    /// readback. The readback must compare the stable entry identity (device,
    /// inode, kind) so a real committed rename still restores authority.
    @MainActor
    func testReceiptIdentityWithJournalEvidenceStillMatchesPlainReadbackCapture() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .real)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let plain = try FileEntryIdentityCapture.capture(at: environment.destinationURL)
        let enriched = RenameEntryIdentity(
            device: plain.device,
            inode: plain.inode,
            kind: plain.kind,
            size: plain.size,
            modificationDate: plain.modificationDate,
            creationDate: plain.creationDate,
            volumeIdentifier: "volume-evidence-only",
            linkTarget: nil
        )
        let receipt = FileRenameMoveReceipt(
            moveID: FileMoveID(),
            fileID: original.id,
            sourceURL: environment.sourceURL,
            destinationURL: environment.destinationURL,
            entryIdentity: enriched
        )
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "; "))
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(moved.observation)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: moved.id))
    }

    @MainActor
    func testSixFileBatchRenameReadbackSucceedsAcrossFourLaneLimiter() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorBatchReadback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fixtureURL = try XCTUnwrap(
            Bundle(for: RenameRefreshSafetyTests.self).url(forResource: "testAudioFile", withExtension: "flac")
                ?? Bundle(for: RenameRefreshSafetyTests.self).url(forResource: "testAudioFile", withExtension: "mp3")
        )
        let ext = fixtureURL.pathExtension
        let pipeline = RenameReadbackPipeline(mode: .real)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)

        var originals: [AudioFile] = []
        var receipts: [FileRenameMoveReceipt] = []
        for index in 0..<6 {
            let sourceURL = tempDir.appendingPathComponent("source-\(index).\(ext)")
            let destURL = tempDir.appendingPathComponent("dest-\(index).\(ext)")
            try FileManager.default.copyItem(at: fixtureURL, to: sourceURL)
            let original = try await TagLibAudioMetadataPipeline().loadAudioFile(at: sourceURL, id: UUID())
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            let identity = try FileEntryIdentityCapture.capture(at: destURL)
            originals.append(original)
            receipts.append(
                FileRenameMoveReceipt(
                    moveID: FileMoveID(),
                    fileID: original.id,
                    sourceURL: sourceURL,
                    destinationURL: destURL,
                    entryIdentity: identity
                )
            )
        }

        viewModel.mergeQuickImportFiles(originals)
        viewModel.publishMovePlaceholders(receipts)
        let warnings = await viewModel.readBackMovedFiles(receipts)

        XCTAssertTrue(warnings.isEmpty, "All 6 files must wait for a free readback lane and succeed: \(warnings)")
        XCTAssertEqual(viewModel.files.count, 6)
        for receipt in receipts {
            let moved = try XCTUnwrap(viewModel.committedFile(withID: receipt.fileID))
            XCTAssertEqual(moved.url, receipt.destinationURL)
            XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
            XCTAssertNotNil(moved.observation)
            XCTAssertFalse(viewModel.hasRecoveryDecision(for: receipt.fileID))
        }
    }

    @MainActor
    func testUnresolvedRenameBlocksAffectedPathsBeforeReleasingReservation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorUnresolvedBlock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("track.flac")
        let destURL = tempDir.appendingPathComponent("renamed.flac")
        let fixtureURL = try XCTUnwrap(
            Bundle(for: RenameRefreshSafetyTests.self).url(forResource: "testAudioFile", withExtension: "flac")
                ?? Bundle(for: RenameRefreshSafetyTests.self).url(forResource: "testAudioFile", withExtension: "mp3")
        )
        try FileManager.default.copyItem(at: fixtureURL, to: sourceURL)
        let loaded = try await TagLibAudioMetadataPipeline().loadAudioFile(at: sourceURL, id: UUID())
        let journalDir = tempDir.appendingPathComponent("journal", isDirectory: true)
        let journalStore = LocalRenameJournalStore(directoryURL: journalDir)
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: RenameReadbackPipeline(mode: .real),
            renameJournalStore: journalStore
        )
        viewModel.mergeQuickImportFiles([loaded])

        let operationID = UUID()
        let entry = PreparedRenameEntry(
            index: 0,
            fileID: loaded.id,
            originalURL: sourceURL,
            temporaryURL: RenameStagingName.url(for: sourceURL, operationID: operationID, index: 0),
            intendedURL: destURL,
            expectedSourceFingerprint: try XCTUnwrap(loaded.fileFingerprint)
        )
        viewModel.registerUnresolvedRenameJournalBlocks(
            operationID: operationID,
            preparedEntries: [entry]
        )

        XCTAssertTrue(viewModel.isRenameJournalBlocked(url: sourceURL))
        XCTAssertTrue(viewModel.isRenameJournalBlocked(url: destURL))
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: loaded.id))
        var edit = SingleFileEditModel(from: loaded)
        edit.title = "Should be blocked"
        let result = await viewModel.persistReviewedEditForTest(edit, to: loaded, comparedTo: loaded)
        guard case .failure = result else {
            return XCTFail("Queued write must fail once unresolved journal blocks are registered")
        }
    }

    @MainActor
    func testReadbackAcrossSamePathReplacementStaysBlocked() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameReadbackPipeline(mode: .real, started: started, release: release)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let readback = Task { await viewModel.readBackMovedFiles([receipt]) }
        await started.wait()
        // Replace the directory entry while the read is in flight.
        try FileManager.default.removeItem(at: environment.destinationURL)
        try Data("different entry".utf8).write(to: environment.destinationURL)
        let replacementBytes = try Data(contentsOf: environment.destinationURL)
        await release.open()
        _ = await readback.value

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertEqual(try Data(contentsOf: environment.destinationURL), replacementBytes)
    }

    @MainActor
    func testReadbackTimeoutKeepsBlockedAndLateLoadCannotPublish() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let started = RenameReadGate()
        let release = RenameReadGate()
        let pipeline = RenameReadbackPipeline(mode: .real, started: started, release: release)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: pipeline,
            moveReadbackTimeout: .milliseconds(100)
        )
        viewModel.mergeQuickImportFiles([original])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)

        await release.open()
        try await Task.sleep(for: .milliseconds(300))
        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertNil(moved.observation)
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: moved.id))
    }

    // MARK: - Recovery decisions survive automatic observations

    @MainActor
    func testRefreshRequiredRecoveryCannotBeUndoneByQueuedOrOlderReload() throws {
        let original = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/recovery.mp3"))
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameReadbackPipeline(mode: .fail))
        viewModel.mergeQuickImportFiles([original])
        viewModel.flushPendingMetadataReloads()
        let generation = viewModel.makeFileModelRefreshGeneration()
        XCTAssertTrue(viewModel.replaceLoadedFile(original, refreshGeneration: generation, deferVisibleRefresh: true))

        let lateGeneration = viewModel.makeFileModelRefreshGeneration()
        viewModel.markFileRequiresRefresh(id: original.id)
        viewModel.flushPendingMetadataReloads()

        XCTAssertTrue(try XCTUnwrap(viewModel.loadedFile(withID: original.id)).requiresMetadataRefreshBeforeWriting)
        XCTAssertFalse(viewModel.replaceLoadedFile(original, refreshGeneration: lateGeneration))
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
    }

    @MainActor
    func testMoveReadbackDoesNotClearOlderRecoveryDecision() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RenameReadbackPipeline(mode: .real))
        viewModel.mergeQuickImportFiles([original])
        viewModel.markFileRequiresRefresh(id: original.id)

        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])
        _ = await viewModel.readBackMovedFiles([receipt])

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertTrue(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: moved.id))
    }

    @MainActor
    func testExplicitReloadAfterMoveReadbackFailureRestoresWritableObservation() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let original = try observedFile(at: environment.sourceURL, title: "Original")
        let pipeline = RenameReadbackPipeline(mode: .fail)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])
        _ = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)

        pipeline.setMode(.real)
        await viewModel.reloadSelectedFilesFromDisk()

        let moved = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(moved.url, environment.destinationURL)
        XCTAssertNotNil(moved.observation)
        XCTAssertFalse(moved.requiresMetadataRefreshBeforeWriting)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: moved.id))
        XCTAssertTrue(viewModel.pendingReplacementFileReviews.isEmpty)
    }

    @MainActor
    func testReplacementFileReloadSurfacesReviewAndExplicitAcceptanceRestoresEditing() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)

        let pipeline = TagLibAudioMetadataPipeline()
        let original = try await pipeline.loadAudioFile(at: environment.sourceURL, id: UUID())
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mutationDirectoryAccessRequester = { _ in nil }
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])

        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        // Replace the renamed destination with a different valid FLAC (distinct inode & tags).
        let stagedReplacementURL = environment.destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("staged-replacement-\(UUID().uuidString.prefix(8)).flac")
        try FileManager.default.copyItem(at: environment.sourceURL, to: stagedReplacementURL)
        _ = try pipeline.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["TITLE": ["Replacement Track"]]),
            to: stagedReplacementURL,
            expectedVersion: nil
        )
        try FileManager.default.removeItem(at: environment.destinationURL)
        try FileManager.default.moveItem(at: stagedReplacementURL, to: environment.destinationURL)
        let replacementIdentity = EntryIdentityKey(
            try FileEntryIdentityCapture.capture(at: environment.destinationURL)
        )
        XCTAssertFalse(EntryIdentityKey(receipt.entryIdentity).matches(replacementIdentity))

        let warnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(warnings.first?.contains("Reload from Disk") == true)
        XCTAssertTrue(warnings.first?.contains("replacement") == true)
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: original.id))
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)

        // Plain Reload from Disk keeps the move decision blocked AND surfaces explicit review.
        await viewModel.reloadSelectedFilesFromDisk()
        XCTAssertTrue(
            viewModel.hasRecoveryDecision(for: original.id),
            "Plain Reload from Disk must not silently clear a move decision for a different directory entry"
        )
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
        XCTAssertEqual(viewModel.pendingReplacementFileReviews.count, 1)
        let review = try XCTUnwrap(viewModel.pendingReplacementFileReviews.first)
        XCTAssertEqual(review.fileID, original.id)
        XCTAssertEqual(review.title, "Replacement Track")
        XCTAssertEqual(EntryIdentityKey(fingerprint: review.target.fingerprint), replacementIdentity)

        // Explicit acceptance verifies the replacement identity on disk and restores editing.
        await viewModel.acceptPendingReplacementFiles(viewModel.pendingReplacementFileReviews)
        XCTAssertTrue(viewModel.pendingReplacementFileReviews.isEmpty)
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: original.id))
        let accepted = try XCTUnwrap(viewModel.files.first)
        XCTAssertEqual(accepted.url, environment.destinationURL)
        XCTAssertEqual(accepted.title, "Replacement Track")
        XCTAssertFalse(accepted.requiresMetadataRefreshBeforeWriting)
        XCTAssertNotNil(accepted.observation)

        // Confirm the accepted replacement FLAC is genuinely writable on disk.
        var edit = SingleFileEditModel(from: accepted)
        edit.title = "Accepted and Saved"
        guard case .success = await viewModel.persistReviewedEditForTest(edit, to: accepted) else {
            return XCTFail("Expected a real FLAC write to succeed after explicit replacement acceptance")
        }
        let persisted = try await pipeline.loadAudioFile(at: environment.destinationURL, id: original.id)
        XCTAssertEqual(persisted.title, "Accepted and Saved")
    }

    @MainActor
    func testExplicitReplacementAcceptanceRejectsThirdReplacementAndNeverClearsJournalPending() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)

        let pipeline = TagLibAudioMetadataPipeline()
        let original = try await pipeline.loadAudioFile(at: environment.sourceURL, id: UUID())
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])

        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.publishMovePlaceholders([receipt])

        // Replace destination with replacement #2 and surface review via Reload from Disk.
        let replacementTwoURL = environment.destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("replacement-two-\(UUID().uuidString.prefix(8)).flac")
        try FileManager.default.copyItem(at: environment.sourceURL, to: replacementTwoURL)
        try FileManager.default.removeItem(at: environment.destinationURL)
        try FileManager.default.moveItem(at: replacementTwoURL, to: environment.destinationURL)

        await viewModel.reloadSelectedFilesFromDisk()
        XCTAssertEqual(viewModel.pendingReplacementFileReviews.count, 1)

        // Swap in replacement #3 (another inode) before the user clicks Accept Replacement.
        let replacementThreeURL = environment.destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("replacement-three-\(UUID().uuidString.prefix(8)).flac")
        try FileManager.default.copyItem(at: environment.sourceURL, to: replacementThreeURL)
        try FileManager.default.removeItem(at: environment.destinationURL)
        try FileManager.default.moveItem(at: replacementThreeURL, to: environment.destinationURL)

        await viewModel.acceptPendingReplacementFiles(viewModel.pendingReplacementFileReviews)
        XCTAssertTrue(
            viewModel.hasRecoveryDecision(for: original.id),
            "A third replacement before acceptance must keep editing paused"
        )
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)

        // Journal pending decisions must never be surfaced for or cleared by replacement acceptance.
        let journalOperationID = UUID()
        viewModel.recordRecoveryDecision(.journalPending(journalOperationID), for: original.id)
        await viewModel.reloadSelectedFilesFromDisk()
        XCTAssertTrue(
            viewModel.pendingReplacementFileReviews.isEmpty,
            "Files blocked by a journal decision must go through Rename Recovery, not replacement acceptance"
        )

        let freshThree = try await pipeline.loadAudioFile(at: environment.destinationURL, id: original.id)
        let targetThree = try XCTUnwrap(ReviewedMetadataTarget(verified: freshThree))
        viewModel.replaceLoadedFile(
            freshThree,
            refreshGeneration: viewModel.makeFileModelRefreshGeneration(),
            clearing: .explicitReplacementAcceptance(targetThree)
        )
        XCTAssertTrue(viewModel.hasJournalRecoveryDecision(for: original.id))
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: original.id))
        XCTAssertTrue(try XCTUnwrap(viewModel.files.first).requiresMetadataRefreshBeforeWriting)
    }

    @MainActor
    func testReplacementAcceptanceRejectsNewRevisionAndSupersededReview() async throws {
        let environment = try makeEnvironment()
        defer { MetadataTestTokens.removeFixtureCopy(at: environment.sourceURL) }
        let pipeline = TagLibAudioMetadataPipeline()
        let original = try await pipeline.loadAudioFile(at: environment.sourceURL, id: UUID())
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        let receipt = try makeReceipt(for: original, from: environment.sourceURL, to: environment.destinationURL)
        viewModel.mergeQuickImportFiles([original])
        viewModel.publishMovePlaceholders([receipt])
        viewModel.setSelectedAudioIDs([original.id])

        // Keep the moved entry alive to make reuse of its node number impossible.
        let movedAside = environment.destinationURL.appendingPathExtension("previous")
        try FileManager.default.moveItem(at: environment.destinationURL, to: movedAside)
        try FileManager.default.copyItem(at: environment.sourceURL, to: environment.destinationURL)
        await viewModel.reloadSelectedFilesFromDisk()
        let review = try XCTUnwrap(viewModel.pendingReplacementFileReviews.first)
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: original.id))
        let before = try await pipeline.loadAudioFile(at: environment.destinationURL, id: original.id)
        XCTAssertEqual(before.title, review.title)
        XCTAssertFalse(EntryIdentityKey(receipt.entryIdentity).matches(EntryIdentityKey(fingerprint: review.target.fingerprint)))

        let changedCopy = environment.destinationURL.deletingLastPathComponent().appendingPathComponent("updated-replacement.flac")
        try FileManager.default.copyItem(at: environment.sourceURL, to: changedCopy)
        _ = try pipeline.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["TITLE": ["Changed after the review was displayed"]]),
            to: changedCopy, expectedVersion: nil
        )
        let newBytes = try Data(contentsOf: changedCopy)
        do {
            let handle = try FileHandle(forWritingTo: environment.destinationURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: newBytes)
        }

        let changed = try await pipeline.loadAudioFile(at: environment.destinationURL, id: original.id)
        XCTAssertEqual(changed.title, "Changed after the review was displayed")
        XCTAssertTrue(EntryIdentityKey(fingerprint: review.target.fingerprint).matches(EntryIdentityKey(fingerprint: changed.fileFingerprint)))
        XCTAssertNotEqual(before.metadataFileVersion, changed.metadataFileVersion)

        await viewModel.acceptPendingReplacementFiles([review])
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: original.id), "Acceptance must not clear protection for a revision that the dialog never displayed")
        let presented = try XCTUnwrap(viewModel.files.first)
        XCTAssertNil(ReviewedMetadataTarget(verified: presented), "The unreviewed revision must stay ineligible for writes")
        XCTAssertEqual(try Data(contentsOf: environment.destinationURL), newBytes)

        await viewModel.reloadSelectedFilesFromDisk()
        let revisedReview = try XCTUnwrap(viewModel.pendingReplacementFileReviews.first)
        XCTAssertEqual(revisedReview.title, changed.title)
        XCTAssertNotEqual(revisedReview.target.version, review.target.version)

        await viewModel.acceptPendingReplacementFiles([review])
        XCTAssertTrue(viewModel.hasRecoveryDecision(for: original.id))
        XCTAssertEqual(viewModel.pendingReplacementFileReviews, [revisedReview])

        await viewModel.acceptPendingReplacementFiles([revisedReview])
        XCTAssertFalse(viewModel.hasRecoveryDecision(for: original.id))
        let confirmed = try XCTUnwrap(viewModel.committedFile(withID: original.id))
        XCTAssertEqual(confirmed.metadataFileVersion, changed.metadataFileVersion)
        XCTAssertEqual(try Data(contentsOf: environment.destinationURL), newBytes)
    }

    // MARK: - Planner and preflight

    @MainActor
    func testBlockedSourceIsSourceUnavailableAndCannotBePlanned() throws {
        let displayOnly = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/blocked-source.flac"),
            title: "Blocked",
            includeDefaultFileFingerprint: false
        )
        let plan = makeFileRenamePlan(template: "{{title}}", targetFiles: [displayOnly])
        XCTAssertEqual(plan.rows.first?.status, .sourceUnavailable)
        XCTAssertTrue(plan.operations.isEmpty)
        XCTAssertFalse(plan.canApply)
    }

    // MARK: - Helpers

    private struct Environment {
        let sourceURL: URL
        let destinationURL: URL
    }

    @MainActor
    private func makeEnvironment() throws -> Environment {
        let source = try MetadataTestTokens.makeFixtureCopy()
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent("renamed-\(UUID().uuidString.prefix(8)).flac")
        return Environment(sourceURL: source, destinationURL: destination)
    }

    @MainActor
    private func observedFile(at url: URL, title: String) throws -> AudioFile {
        AudioFileTestFactory.makeObserved(
            url: url,
            title: title,
            fileFingerprint: try AudioFileFingerprint.capture(at: url),
            metadataFileVersion: try MetadataTestTokens.mintedVersion(at: url)
        )
    }

    @MainActor
    private func makeReceipt(
        for file: AudioFile,
        from sourceURL: URL,
        to destinationURL: URL
    ) throws -> FileRenameMoveReceipt {
        // The receipt carries the directory-entry identity observed at the end
        // of the move, which is the destination entry. Test fixtures simulate a
        // completed move by copying the source to the destination first.
        FileRenameMoveReceipt(
            moveID: FileMoveID(),
            fileID: file.id,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            entryIdentity: try FileEntryIdentityCapture.capture(at: destinationURL)
        )
    }
}

// MARK: - Recording pipeline

private nonisolated final class RenameReadbackPipeline: AudioMetadataPipeline, @unchecked Sendable {
    enum LoadMode {
        case fail
        case real
    }

    private let lock = NSLock()
    private var mode: LoadMode
    private var recordedWriteCount = 0
    private var recordedExpectedVersions: [MetadataFileVersion?] = []
    private let started: RenameReadGate?
    private let release: RenameReadGate?

    init(mode: LoadMode, started: RenameReadGate? = nil, release: RenameReadGate? = nil) {
        self.mode = mode
        self.started = started
        self.release = release
    }

    var writeCount: Int { lock.withLock { recordedWriteCount } }
    var lastExpectedVersion: MetadataFileVersion? { lock.withLock { recordedExpectedVersions.last ?? nil } }

    func setMode(_ mode: LoadMode) { lock.withLock { self.mode = mode } }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let started { await started.open() }
        if let release { await release.wait() }
        let mode = lock.withLock { self.mode }
        switch mode {
        case .fail:
            throw CocoaError(.fileReadCorruptFile)
        case .real:
            return try await TagLibAudioMetadataPipeline().loadAudioFile(at: url, id: id)
        }
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try TagLibMetadataManager.readSnapshot(from: url, includingAudioContent: true)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try TagLibMetadataManager.fileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try TagLibAudioMetadataPipeline().rawMetadataValueMap(for: url)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recordWrite(expectedVersion)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recordWrite(expectedVersion)
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        recordWrite(expectedVersion)
        return AudioMetadataWriteResult(warnings: [])
    }

    private nonisolated func recordWrite(_ version: MetadataFileVersion?) {
        lock.withLock {
            recordedWriteCount += 1
            recordedExpectedVersions.append(version)
        }
    }
}

private actor RenameReadGate {
    private var opened = false
    private var pending: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { pending.append($0) }
    }

    func open() {
        opened = true
        let waiters = pending
        pending.removeAll()
        waiters.forEach { $0.resume() }
    }
}
