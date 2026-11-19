import Foundation
import XCTest
@testable import AudioMator

/// First-pass service coverage on disposable directories: commit ordering, source
/// and destination protections, capability rejection, busy journal ownership, and
/// read-only classification plus identity-checked restoration after a simulated
/// process interruption.
nonisolated final class RenameTransactionServiceTests: XCTestCase {
    private var baseURL: URL!
    private var rootURL: URL!
    private var journalURL: URL!
    private let fileSystem = LocalRenameFileSystem()
    private var store: LocalRenameJournalStore!
    private var service: RenameTransactionService!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameServiceTests-\(UUID().uuidString)", isDirectory: true)
        rootURL = baseURL.appendingPathComponent("Files", isDirectory: true)
        journalURL = baseURL.appendingPathComponent("RenameJournal", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        store = LocalRenameJournalStore(directoryURL: journalURL)
        service = RenameTransactionService(fileSystem: fileSystem, journal: store)
    }

    override func tearDownWithError() throws {
        store = nil
        service = nil
        if let baseURL {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    func testExecuteCommitsRenamesAndRemovesJournal() throws {
        let prepared = try makePrepared(names: [
            ("first.wav", "renamed-first.wav"),
            ("second.wav", "renamed-second.wav")
        ])
        let operationID = prepared.operationID

        switch service.execute(prepared) {
        case .committed(let committedID, let moves, _):
            XCTAssertEqual(committedID, operationID)
            XCTAssertEqual(moves.count, 2)
        default:
            return XCTFail("Expected a committed outcome")
        }

        let names = try directoryNames(at: rootURL)
        XCTAssertEqual(names, ["renamed-first.wav", "renamed-second.wav"])
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("renamed-first.wav"), encoding: .utf8),
            "entry-0"
        )
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("renamed-second.wav"), encoding: .utf8),
            "entry-1"
        )
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
        XCTAssertTrue(try journalFileNames().isEmpty)
    }

    func testExecuteRejectsOccupiedDestinationBeforeAnyMove() throws {
        let occupiedURL = rootURL.appendingPathComponent("taken.wav")
        try Data("foreign".utf8).write(to: occupiedURL)
        let sourceURL = rootURL.appendingPathComponent("source.wav")
        try Data("source".utf8).write(to: sourceURL)
        let prepared = try makePrepared(
            entries: [(sourceURL, occupiedURL)]
        )

        switch service.execute(prepared) {
        case .rejected(.destinationOccupied(let index)):
            XCTAssertEqual(index, 0)
        default:
            return XCTFail("Expected destinationOccupied rejection")
        }

        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "source")
        XCTAssertEqual(try String(contentsOf: occupiedURL, encoding: .utf8), "foreign")
        XCTAssertEqual(try directoryNames(at: rootURL), ["source.wav", "taken.wav"])
        XCTAssertTrue(try journalFileNames().isEmpty)
    }

    func testExecuteRejectsUnsupportedExclusiveRenameBeforeAnyMove() throws {
        let unsupportedService = RenameTransactionService(
            fileSystem: ExclusiveRenameUnsupportedFileSystem(base: fileSystem),
            journal: store
        )
        let prepared = try makePrepared(names: [("first.wav", "renamed-first.wav")])

        switch unsupportedService.execute(prepared) {
        case .rejected(.exclusiveRenameUnsupported):
            break
        default:
            return XCTFail("Expected exclusiveRenameUnsupported rejection")
        }

        XCTAssertEqual(try directoryNames(at: rootURL), ["first.wav"])
        XCTAssertTrue(try journalFileNames().isEmpty)
    }

    func testExecuteReturnsBusyWhenJournalLockIsHeld() throws {
        let prepared = try makePrepared(names: [("first.wav", "renamed-first.wav")])
        let lock = try XCTUnwrap(try store.tryAcquireLock())

        defer { lock.release() }
        switch service.execute(prepared) {
        case .busy:
            break
        default:
            return XCTFail("Expected busy while another owner holds the journal lock")
        }
        XCTAssertEqual(try directoryNames(at: rootURL), ["first.wav"])
    }

    func testClassifyThenRestoreAfterStagedInterruption() throws {
        let manifest = try makePreparedManifestAndStageMove()

        let classifications = service.classify([manifest])
        let classification = try XCTUnwrap(classifications.first)
        XCTAssertEqual(classification.status, .preparedNeedsRestore)
        XCTAssertEqual(classification.entries.first?.role, .staged)
        XCTAssertTrue(classification.issueCodes.isEmpty)

        switch service.restoreOriginals(manifest) {
        case .restored(let operationID, let moves, let retainedRecord):
            XCTAssertEqual(operationID, manifest.operationID)
            XCTAssertEqual(moves.count, 1)
            XCTAssertFalse(retainedRecord)
        default:
            return XCTFail("Expected a restored outcome")
        }

        let originalURL = rootURL.appendingPathComponent("original.wav")
        XCTAssertEqual(try String(contentsOf: originalURL, encoding: .utf8), "original-payload")
        XCTAssertEqual(try directoryNames(at: rootURL), ["original.wav"])
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    func testRestoreIsIdempotentWhenEntryAlreadyBackAtOriginal() throws {
        let manifest = try makePreparedManifestAndStageMove()
        let originalURL = URL(string: try XCTUnwrap(manifest.entries.first?.originalURL))!
        let stagingURL = URL(string: try XCTUnwrap(manifest.entries.first?.temporaryURL))!
        let handle = try fileSystem.openDirectory(at: rootURL)
        try fileSystem.exclusiveMove(
            named: stagingURL.lastPathComponent,
            to: originalURL.lastPathComponent,
            in: handle
        )

        let classification = try XCTUnwrap(service.classify([manifest]).first)
        XCTAssertEqual(classification.status, .preparedNoFilesMoved)

        switch service.restoreOriginals(manifest) {
        case .restored(let operationID, _, let retainedRecord):
            XCTAssertEqual(operationID, manifest.operationID)
            XCTAssertFalse(retainedRecord)
        default:
            return XCTFail("Expected an idempotent restored outcome")
        }
        XCTAssertEqual(try String(contentsOf: originalURL, encoding: .utf8), "original-payload")
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    func testClassifyReturnsBusyWhenJournalLockIsHeld() throws {
        let manifest = try makePreparedManifestAndStageMove()
        let lock = try XCTUnwrap(try store.tryAcquireLock())
        defer { lock.release() }

        let classification = try XCTUnwrap(service.classify([manifest]).first)
        XCTAssertEqual(classification.status, .busy)
        XCTAssertTrue(classification.issueCodes.contains(.busy))
    }

    func testSwapIsCommittedAsOneTransaction() throws {
        let firstURL = rootURL.appendingPathComponent("first.wav")
        let secondURL = rootURL.appendingPathComponent("second.wav")
        try Data("first-bytes".utf8).write(to: firstURL)
        try Data("second-bytes".utf8).write(to: secondURL)
        let operationID = UUID()
        let prepared = try makePrepared(entries: [
            (firstURL, secondURL),
            (secondURL, firstURL)
        ], operationID: operationID)

        switch service.execute(prepared) {
        case .committed:
            break
        default:
            return XCTFail("Expected a committed swap")
        }

        // Entries were swapped; each destination holds the other entry's payload.
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "second-bytes")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "first-bytes")
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    func testCaseOnlyRenameIsCommitted() throws {
        let sourceURL = rootURL.appendingPathComponent("SongTitle.wav")
        try Data("case-bytes".utf8).write(to: sourceURL)
        let intendedURL = rootURL.appendingPathComponent("songtitle.wav")
        let prepared = try makePrepared(entries: [(sourceURL, intendedURL)])

        switch service.execute(prepared) {
        case .committed:
            break
        default:
            return XCTFail("Expected a committed case-only rename")
        }

        XCTAssertEqual(try String(contentsOf: intendedURL, encoding: .utf8), "case-bytes")
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    func testJournalWriteFailurePreventsAnyMove() throws {
        let faultStore = FaultInjectingJournalStore(base: store)
        faultStore.failWritePrepared = true
        let faultService = RenameTransactionService(fileSystem: fileSystem, journal: faultStore)
        let prepared = try makePrepared(names: [("first.wav", "renamed-first.wav")])

        switch faultService.execute(prepared) {
        case .rejected(.journalUnavailable):
            break
        default:
            return XCTFail("Expected journalUnavailable rejection")
        }
        XCTAssertEqual(try directoryNames(at: rootURL), ["first.wav"])
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    func testCommittedMarkerFailureRetainsPreparedRecord() throws {
        let faultStore = FaultInjectingJournalStore(base: store)
        faultStore.failMarkCommitted = true
        let faultService = RenameTransactionService(fileSystem: fileSystem, journal: faultStore)
        let prepared = try makePrepared(names: [("first.wav", "renamed-first.wav")])

        switch faultService.execute(prepared) {
        case .unresolved(_, let classification, let reason):
            XCTAssertEqual(classification.status, .preparedAllAtIntended)
            XCTAssertEqual(reason, .committedRecordFailed)
        default:
            return XCTFail("Expected an unresolved outcome when the committed marker cannot be written")
        }

        let retained = try XCTUnwrap(store.loadManifests().manifests.first)
        XCTAssertEqual(retained.phase, .prepared)
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("renamed-first.wav"), encoding: .utf8),
            "entry-0"
        )
    }

    func testCommittedRecordRetainedWhenCleanupFails() throws {
        let faultStore = FaultInjectingJournalStore(base: store)
        faultStore.failRemoveManifest = true
        let faultService = RenameTransactionService(fileSystem: fileSystem, journal: faultStore)
        let prepared = try makePrepared(names: [("first.wav", "renamed-first.wav")])

        switch faultService.execute(prepared) {
        case .committed(_, let moves, let diagnostics):
            XCTAssertEqual(moves.count, 1)
            XCTAssertTrue(diagnostics.contains(.journalCleanupDeferred))
        default:
            return XCTFail("Expected a committed outcome with a retained cleanup record")
        }

        let retained = try XCTUnwrap(store.loadManifests().manifests.first)
        XCTAssertEqual(retained.phase, .committed)
        XCTAssertEqual(
            try String(contentsOf: rootURL.appendingPathComponent("renamed-first.wav"), encoding: .utf8),
            "entry-0"
        )
    }

    func testClassifyUnavailableWhenParentDirectoryIsMovedAway() throws {
        let manifest = try makePreparedManifestAndStageMove()
        let movedRootURL = baseURL.appendingPathComponent("FilesMovedAway", isDirectory: true)
        try FileManager.default.moveItem(at: rootURL, to: movedRootURL)
        defer { try? FileManager.default.moveItem(at: movedRootURL, to: rootURL) }

        let classification = try XCTUnwrap(service.classify([manifest]).first)
        XCTAssertEqual(classification.status, .preparedUnavailable)
        XCTAssertEqual(classification.entries.first?.role, .unavailable)

        switch service.restoreOriginals(manifest) {
        case .unresolved(_, let updated, _):
            XCTAssertEqual(updated.status, .preparedUnavailable)
        default:
            return XCTFail("Expected unavailable classification to prevent a restore")
        }
        XCTAssertEqual(store.loadManifests().manifests.first?.phase, .prepared)
    }

    // MARK: - Helpers

    private func makePrepared(
        names: [(sourceName: String, intendedName: String)]
    ) throws -> PreparedRenameTransaction {
        let directoryURL = try XCTUnwrap(rootURL)
        var fileURLs: [(source: URL, intended: URL)] = []
        for (index, names) in names.enumerated() {
            let sourceURL = directoryURL.appendingPathComponent(names.sourceName)
            let intendedURL = directoryURL.appendingPathComponent(names.intendedName)
            try Data("entry-\(index)".utf8).write(to: sourceURL)
            fileURLs.append((sourceURL, intendedURL))
        }
        return try makePrepared(entries: fileURLs)
    }

    private func makePrepared(
        entries fileURLs: [(source: URL, intended: URL)],
        operationID: UUID = UUID()
    ) throws -> PreparedRenameTransaction {
        var entries: [PreparedRenameEntry] = []
        for (index, urls) in fileURLs.enumerated() {
            entries.append(
                PreparedRenameEntry(
                    index: index,
                    fileID: UUID(),
                    originalURL: urls.source,
                    temporaryURL: RenameStagingName.url(
                        for: urls.source,
                        operationID: operationID,
                        index: index
                    ),
                    intendedURL: urls.intended,
                    expectedSourceFingerprint: try AudioFileFingerprint.capture(at: urls.source)
                )
            )
        }
        return PreparedRenameTransaction(operationID: operationID, entries: entries)
    }

    /// Writes a prepared manifest with real captured identity evidence, stages the
    /// single source to its deterministic temporary name, and returns the manifest.
    /// This models a process that terminated after its first stage move.
    private func makePreparedManifestAndStageMove() throws -> RenameJournalManifest {
        let operationID = UUID()
        let originalURL = rootURL.appendingPathComponent("original.wav")
        let intendedURL = rootURL.appendingPathComponent("renamed.wav")
        try Data("original-payload".utf8).write(to: originalURL)

        let baseIdentity = try fileSystem.entryIdentity(at: originalURL)
        let volumeIdentifier = fileSystem.volumeIdentifier(forDirectoryAt: rootURL)
        let enrichedIdentity = RenameEntryIdentity(
            device: baseIdentity.device,
            inode: baseIdentity.inode,
            kind: baseIdentity.kind,
            size: baseIdentity.size,
            modificationDate: baseIdentity.modificationDate,
            creationDate: baseIdentity.creationDate,
            volumeIdentifier: volumeIdentifier,
            linkTarget: nil
        )
        let journalIdentity = try RenameJournalEntryIdentity(enrichedIdentity)
        let stagingURL = RenameStagingName.url(
            for: originalURL,
            operationID: operationID,
            index: 0
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
        try manifest.validate()
        try store.writePrepared(manifest)

        let handle = try fileSystem.openDirectory(at: rootURL)
        try fileSystem.exclusiveMove(
            named: originalURL.lastPathComponent,
            to: stagingURL.lastPathComponent,
            in: handle
        )
        return manifest
    }

    private func directoryNames(at url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasPrefix(RenameStagingName.prefix) == false }
            .sorted()
    }

    private func journalFileNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: journalURL.path)
            .filter { $0 != RenameJournalFormat.lockFileName }
            .sorted()
    }
}

/// Filesystem double whose volume reports no exclusive-rename support. All
/// operations otherwise forward to the local implementation.
private nonisolated struct ExclusiveRenameUnsupportedFileSystem: RenameFileSystem {
    let base: LocalRenameFileSystem

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func fingerprint(at url: URL) throws -> AudioFileFingerprint { try base.fingerprint(at: url) }
    func entryIdentity(at url: URL) throws -> RenameEntryIdentity { try base.entryIdentity(at: url) }
    func entryIdentityIfPresent(at url: URL) throws -> RenameEntryIdentity? {
        try base.entryIdentityIfPresent(at: url)
    }
    func linkTarget(at url: URL) -> String? { base.linkTarget(at: url) }
    func volumeIdentifier(forDirectoryAt url: URL) -> String? {
        base.volumeIdentifier(forDirectoryAt: url)
    }
    func volumeSupportsExclusiveRename(forDirectoryAt url: URL) throws -> Bool { false }
    func openDirectory(at url: URL) throws -> RenameDirectoryHandle {
        try base.openDirectory(at: url)
    }
    func directoryIdentity(_ handle: RenameDirectoryHandle) throws -> RenameDirectoryIdentity {
        try base.directoryIdentity(handle)
    }
    func authorizedPathStillIdentifiesDirectory(_ handle: RenameDirectoryHandle) -> Bool {
        base.authorizedPathStillIdentifiesDirectory(handle)
    }
    func entryIdentity(named name: String, in handle: RenameDirectoryHandle) throws -> RenameEntryIdentity? {
        try base.entryIdentity(named: name, in: handle)
    }
    func actualEntryName(inDirectoryAt url: URL, matching name: String) throws -> String? {
        try base.actualEntryName(inDirectoryAt: url, matching: name)
    }
    func exclusiveMove(
        named sourceName: String,
        to destinationName: String,
        in handle: RenameDirectoryHandle
    ) throws {
        try base.exclusiveMove(named: sourceName, to: destinationName, in: handle)
    }
    func syncDirectory(_ handle: RenameDirectoryHandle) throws {
        try base.syncDirectory(handle)
    }
}

/// Journal store double that can fail one durable transition while forwarding all
/// other operations to the real store.
private nonisolated final class FaultInjectingJournalStore: RenameJournalStoring, @unchecked Sendable {
    let base: LocalRenameJournalStore
    var failWritePrepared = false
    var failMarkCommitted = false
    var failRemoveManifest = false

    init(base: LocalRenameJournalStore) {
        self.base = base
    }

    var directoryURL: URL { base.directoryURL }

    func ensureDirectory() throws { try base.ensureDirectory() }
    func loadManifests() -> RenameJournalLoadResult { base.loadManifests() }
    func tryAcquireLock() throws -> RenameJournalLock? { try base.tryAcquireLock() }
    func directoryBarrierSupport() -> RenameDirectoryBarrierSupport { base.directoryBarrierSupport() }

    func writePrepared(_ manifest: RenameJournalManifest) throws {
        if failWritePrepared {
            throw RenameJournalStoreError.writeFailed(code: 5)
        }
        try base.writePrepared(manifest)
    }

    func markCommitted(_ manifest: RenameJournalManifest) throws {
        if failMarkCommitted {
            throw RenameJournalStoreError.writeFailed(code: 5)
        }
        try base.markCommitted(manifest)
    }

    func removeManifest(operationID: UUID) throws {
        if failRemoveManifest {
            throw RenameJournalStoreError.removalFailed(code: 5)
        }
        try base.removeManifest(operationID: operationID)
    }
}
