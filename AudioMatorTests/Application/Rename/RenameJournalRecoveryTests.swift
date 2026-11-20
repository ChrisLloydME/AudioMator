import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
/// View-model coverage for the F2 journal wiring: read-only startup bootstrap,
/// path-keyed mutation blocks, busy classification, explicit acknowledgement and
/// missing-folder classification. No test triggers a scope prompt and no test
/// relies on automatic file movement.
nonisolated final class RenameJournalRecoveryTests: XCTestCase {
    private var baseURL: URL!
    private var rootURL: URL!
    private var journalURL: URL!
    private let fileSystem = LocalRenameFileSystem()
    private var store: LocalRenameJournalStore!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameJournalRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        rootURL = baseURL.appendingPathComponent("Files", isDirectory: true)
        journalURL = baseURL.appendingPathComponent("RenameJournal", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        store = LocalRenameJournalStore(directoryURL: journalURL)
    }

    override func tearDownWithError() throws {
        store = nil
        if let baseURL {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    @MainActor
    func testStartupBootstrapInstallsPathBlocksWithoutMovingFiles() async throws {
        let crash = try makeStagedCrashState()
        let viewModel = makeViewModel()
        await viewModel.refreshRenameJournalRecovery()

        XCTAssertEqual(viewModel.renameJournalManifests.count, 1)
        XCTAssertTrue(viewModel.isRenameJournalBlocked(url: crash.originalURL))
        XCTAssertTrue(viewModel.isRenameJournalBlocked(url: crash.stagingURL))
        XCTAssertTrue(viewModel.isRenameJournalBlocked(url: crash.intendedURL))

        let operation = try XCTUnwrap(viewModel.renameJournalRecovery.operations.first)
        XCTAssertTrue(operation.canRestore)
        XCTAssertFalse(operation.entries.isEmpty)
        XCTAssertEqual(operation.entries.first?.roleText, String(localized: "At a temporary name"))

        // Read-only bootstrap: the stage file is still the only copy and the
        // original path remains absent until an explicit restore.
        XCTAssertTrue(FileManager.default.fileExists(atPath: crash.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: crash.originalURL.path))
        XCTAssertEqual(try String(contentsOf: crash.stagingURL, encoding: .utf8), "crash-payload")
    }

    @MainActor
    func testSharedWriterGuardRejectsBlockedJournalPathWithoutSessionDecision() async throws {
        let crash = try makeStagedCrashState()
        let viewModel = makeViewModel()
        await viewModel.refreshRenameJournalRecovery()

        XCTAssertThrowsError(
            try viewModel.validateMetadataWriteRecovery(id: UUID(), url: crash.originalURL)
        ) { error in
            XCTAssertTrue(error is RenameJournalRecoveryError)
        }
        XCTAssertTrue(viewModel.renameJournalManifests.first?.phase == .prepared)
    }

    @MainActor
    func testBusyClassificationWhenAnotherInstanceHoldsTheJournalLock() async throws {
        _ = try makeStagedCrashState()
        let secondStore = LocalRenameJournalStore(directoryURL: journalURL)
        let lock = try XCTUnwrap(try secondStore.tryAcquireLock())
        defer { lock.release() }

        let viewModel = makeViewModel()
        await viewModel.refreshRenameJournalRecovery()

        XCTAssertTrue(viewModel.renameJournalRecovery.isBusy)
        XCTAssertTrue(viewModel.renameJournalRecovery.operations.allSatisfy { !$0.canRestore })
        XCTAssertTrue(viewModel.renameJournalRecovery.operations.allSatisfy {
            $0.statusTitle == String(localized: "Another copy of AudioMator is using rename recovery")
        })
    }

    @MainActor
    func testAcknowledgeCommittedRecordRemovesOnlyTheRecord() async throws {
        let committed = try makeCommittedState()
        let viewModel = makeViewModel()
        await viewModel.refreshRenameJournalRecovery()

        let operation = try XCTUnwrap(viewModel.renameJournalRecovery.operations.first)
        XCTAssertTrue(operation.canAcknowledge)
        XCTAssertFalse(operation.canRestore)

        let result = await viewModel.acknowledgeRenameJournalOperation(id: operation.id)
        guard case .success = result else {
            return XCTFail("Expected the committed record to be acknowledged: \(result)")
        }
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: committed.intendedURL, encoding: .utf8),
            "committed-payload"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: committed.originalURL.path))
        XCTAssertTrue(viewModel.renameJournalRecovery.operations.isEmpty)
    }

    @MainActor
    func testUnavailableRecordFolderOffersNoAutomaticRestore() async throws {
        let crash = try makeStagedCrashState()
        let movedRootURL = baseURL.appendingPathComponent("FilesMovedAway", isDirectory: true)
        try FileManager.default.moveItem(at: rootURL, to: movedRootURL)
        defer { try? FileManager.default.moveItem(at: movedRootURL, to: rootURL) }

        let viewModel = makeViewModel()
        await viewModel.refreshRenameJournalRecovery()

        let operation = try XCTUnwrap(viewModel.renameJournalRecovery.operations.first)
        XCTAssertFalse(operation.canRestore)
        XCTAssertTrue(operation.entries.allSatisfy { $0.roleText == String(localized: "Folder unavailable") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: crash.stagingURL.path) == false)
    }

    func testReservationKeysCoverSymlinkEntryAndTarget() throws {
        let targetURL = baseURL.appendingPathComponent("target.wav")
        let symlinkURL = baseURL.appendingPathComponent("link.wav")
        try Data("symlink-payload".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        let symlinkKeys = FileSystemPathSemantics.reservationKeys(for: symlinkURL)
        let targetKeys = FileSystemPathSemantics.reservationKeys(for: targetURL)
        let entryKey = FileSystemPathSemantics.directoryEntryKey(for: symlinkURL)
        let targetEntryKey = FileSystemPathSemantics.directoryEntryKey(for: targetURL)

        XCTAssertTrue(symlinkKeys.contains(entryKey))
        XCTAssertTrue(targetKeys.contains(targetEntryKey))
        XCTAssertNotEqual(entryKey, targetEntryKey)
        // The symlink comparison identity resolves to the target, so both
        // reservations conflict on the target location as well as their entries.
        XCTAssertTrue(symlinkKeys.contains(FileSystemPathSemantics.key(for: targetURL)))
        XCTAssertFalse(symlinkKeys.isDisjoint(with: targetKeys))
    }

    @MainActor
    func testRestoreRenameJournalOperationAuthorizesUnavailableFolderThenRestores() async throws {
        let crash = try makeStagedCrashState()
        let gatedFS = InitiallyUnavailableRenameFileSystem(base: fileSystem)
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: TagLibAudioMetadataPipeline(),
            renameFileSystem: gatedFS,
            renameJournalStore: store
        )
        var requestedDirectories: [URL] = []
        viewModel.mutationDirectoryAccessRequester = { directoryURL in
            requestedDirectories.append(directoryURL)
            gatedFS.unlock()
            return nil
        }

        await viewModel.refreshRenameJournalRecovery()
        let presentation = try XCTUnwrap(viewModel.renameJournalRecovery.operations.first)
        XCTAssertTrue(presentation.isPrepared)
        XCTAssertFalse(presentation.canRestore)
        XCTAssertTrue(presentation.canAuthorizeAndRestore, "Unavailable prepared records must expose explicit Authorize & Restore")
        XCTAssertEqual(presentation.missingDirectoryURLs.count, 1)

        let result = await viewModel.restoreRenameJournalOperation(id: crash.manifest.operationID)
        guard case .success = result else {
            return XCTFail("Expected unavailable folder to authorize then restore cleanly, got \(result)")
        }
        XCTAssertFalse(requestedDirectories.isEmpty, "Restore must request folder access before failing on .preparedUnavailable")
        XCTAssertTrue(FileManager.default.fileExists(atPath: crash.originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: crash.stagingURL.path))
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel() -> AudioViewModel {
        AudioViewModelTestFactory.make(
            metadataPipeline: TagLibAudioMetadataPipeline(),
            renameFileSystem: fileSystem,
            renameJournalStore: store
        )
    }

    private struct StagedCrash {
        let manifest: RenameJournalManifest
        let originalURL: URL
        let stagingURL: URL
        let intendedURL: URL
    }

    private func makeStagedCrashState() throws -> StagedCrash {
        let operationID = UUID()
        let originalURL = rootURL.appendingPathComponent("crash-original.wav")
        let intendedURL = rootURL.appendingPathComponent("crash-renamed.wav")
        let stagingURL = RenameStagingName.url(
            for: originalURL,
            operationID: operationID,
            index: 0
        )
        try Data("crash-payload".utf8).write(to: originalURL)

        let baseIdentity = try fileSystem.entryIdentity(at: originalURL)
        let journalIdentity = try RenameJournalEntryIdentity(
            RenameEntryIdentity(
                device: baseIdentity.device,
                inode: baseIdentity.inode,
                kind: baseIdentity.kind,
                size: baseIdentity.size,
                modificationDate: baseIdentity.modificationDate,
                creationDate: baseIdentity.creationDate,
                volumeIdentifier: fileSystem.volumeIdentifier(forDirectoryAt: rootURL),
                linkTarget: nil
            )
        )
        let manifest = RenameJournalManifest(
            formatVersion: RenameJournalFormat.currentVersion,
            operationID: operationID,
            phase: .prepared,
            createdAt: Date().timeIntervalSince1970,
            committedAt: nil,
            diagnostics: [],
            entries: [
                RenameJournalEntry(
                    index: 0,
                    originalURL: originalURL.absoluteString,
                    temporaryURL: stagingURL.absoluteString,
                    intendedURL: intendedURL.absoluteString,
                    sourceIdentity: journalIdentity,
                    linkTarget: nil
                )
            ]
        )
        try store.ensureDirectory()
        try store.writePrepared(manifest)

        let handle = try fileSystem.openDirectory(at: rootURL)
        try fileSystem.exclusiveMove(
            named: originalURL.lastPathComponent,
            to: stagingURL.lastPathComponent,
            in: handle
        )
        return StagedCrash(
            manifest: manifest,
            originalURL: originalURL,
            stagingURL: stagingURL,
            intendedURL: intendedURL
        )
    }

    private struct CommittedState {
        let intendedURL: URL
        let originalURL: URL
    }

    private func makeCommittedState() throws -> CommittedState {
        let operationID = UUID()
        let originalURL = rootURL.appendingPathComponent("done-original.wav")
        let intendedURL = rootURL.appendingPathComponent("done-renamed.wav")
        try Data("committed-payload".utf8).write(to: originalURL)
        let baseIdentity = try fileSystem.entryIdentity(at: originalURL)
        let journalIdentity = try RenameJournalEntryIdentity(
            RenameEntryIdentity(
                device: baseIdentity.device,
                inode: baseIdentity.inode,
                kind: baseIdentity.kind,
                size: baseIdentity.size,
                modificationDate: baseIdentity.modificationDate,
                creationDate: baseIdentity.creationDate,
                volumeIdentifier: fileSystem.volumeIdentifier(forDirectoryAt: rootURL),
                linkTarget: nil
            )
        )
        let stagingURL = RenameStagingName.url(
            for: originalURL,
            operationID: operationID,
            index: 0
        )
        let prepared = RenameJournalManifest(
            formatVersion: RenameJournalFormat.currentVersion,
            operationID: operationID,
            phase: .prepared,
            createdAt: Date().timeIntervalSince1970,
            committedAt: nil,
            diagnostics: [],
            entries: [
                RenameJournalEntry(
                    index: 0,
                    originalURL: originalURL.absoluteString,
                    temporaryURL: stagingURL.absoluteString,
                    intendedURL: intendedURL.absoluteString,
                    sourceIdentity: journalIdentity,
                    linkTarget: nil
                )
            ]
        )
        try store.ensureDirectory()
        try store.writePrepared(prepared)
        let committed = RenameJournalManifest(
            formatVersion: prepared.formatVersion,
            operationID: operationID,
            phase: .committed,
            createdAt: prepared.createdAt,
            committedAt: Date().timeIntervalSince1970,
            diagnostics: [],
            entries: prepared.entries
        )
        try store.markCommitted(committed)
        try FileManager.default.moveItem(at: originalURL, to: intendedURL)
        return CommittedState(intendedURL: intendedURL, originalURL: originalURL)
    }
}

/// Simulates a sandboxed folder that cannot be read until explicit folder
/// authorization succeeds.
private nonisolated final class InitiallyUnavailableRenameFileSystem: RenameFileSystem, @unchecked Sendable {
    let base: LocalRenameFileSystem
    private let lock = NSLock()
    private var unlocked = false

    init(base: LocalRenameFileSystem) {
        self.base = base
    }

    func unlock() {
        lock.withLock { unlocked = true }
    }

    private var isUnlocked: Bool { lock.withLock { unlocked } }

    func fileExists(at url: URL) -> Bool { isUnlocked ? base.fileExists(at: url) : false }
    func fingerprint(at url: URL) throws -> AudioFileFingerprint {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.fingerprint(at: url)
    }
    func entryIdentity(at url: URL) throws -> RenameEntryIdentity {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.entryIdentity(at: url)
    }
    func entryIdentityIfPresent(at url: URL) throws -> RenameEntryIdentity? {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.entryIdentityIfPresent(at: url)
    }
    func linkTarget(at url: URL) -> String? { isUnlocked ? base.linkTarget(at: url) : nil }
    func volumeIdentifier(forDirectoryAt url: URL) -> String? {
        isUnlocked ? base.volumeIdentifier(forDirectoryAt: url) : nil
    }
    func volumeSupportsExclusiveRename(forDirectoryAt url: URL) throws -> Bool {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.volumeSupportsExclusiveRename(forDirectoryAt: url)
    }
    func openDirectory(at url: URL) throws -> RenameDirectoryHandle {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.openDirectory(at: url)
    }
    func directoryIdentity(_ handle: RenameDirectoryHandle) throws -> RenameDirectoryIdentity {
        try base.directoryIdentity(handle)
    }
    func authorizedPathStillIdentifiesDirectory(_ handle: RenameDirectoryHandle) -> Bool {
        isUnlocked && base.authorizedPathStillIdentifiesDirectory(handle)
    }
    func entryIdentity(named name: String, in handle: RenameDirectoryHandle) throws -> RenameEntryIdentity? {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.entryIdentity(named: name, in: handle)
    }
    func actualEntryName(inDirectoryAt url: URL, matching name: String) throws -> String? {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        return try base.actualEntryName(inDirectoryAt: url, matching: name)
    }
    func exclusiveMove(
        named sourceName: String,
        to destinationName: String,
        in handle: RenameDirectoryHandle
    ) throws {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        try base.exclusiveMove(named: sourceName, to: destinationName, in: handle)
    }
    func syncDirectory(_ handle: RenameDirectoryHandle) throws {
        guard isUnlocked else { throw RenameFileSystemError.io(code: EACCES) }
        try base.syncDirectory(handle)
    }
}
#endif
