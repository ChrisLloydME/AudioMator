import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
/// Rename transaction coverage after the F2 journal extraction. The service is
/// exercised with real disposable directories and injected filesystem faults; the
/// view-model recovery state is read-only and must never move files by itself.
nonisolated final class FileRenameTransactionTests: XCTestCase {
    private var baseURL: URL!
    private var rootURL: URL!
    private var journalURL: URL!
    private let fileSystem = LocalRenameFileSystem()
    private var store: LocalRenameJournalStore!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameTransactionTests-\(UUID().uuidString)", isDirectory: true)
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
    func testRollbackFailureReportsHiddenTemporaryFileAndRecoveryItem() async throws {
        let fault = FaultInjectingRenameFileSystem(mode: .failSecondStageAndRollback)
        let service = RenameTransactionService(fileSystem: fault, journal: store)
        let operationID = UUID()
        let prepared = try makePrepared(
            names: [("first.mp3", "renamed-first.mp3"), ("second.mp3", "renamed-second.mp3")],
            operationID: operationID
        )

        var stagedObservedURL: URL?
        switch service.execute(prepared) {
        case .unresolved(let unresolvedID, let classification, _):
            XCTAssertEqual(unresolvedID, operationID)
            let first = try XCTUnwrap(classification.entries.first)
            XCTAssertEqual(first.role, .staged)
            let observedURL = try XCTUnwrap(first.observedURL)
            stagedObservedURL = observedURL
            XCTAssertTrue(observedURL.lastPathComponent.hasPrefix(RenameStagingName.prefix))
            XCTAssertEqual(observedURL.pathExtension, "mp3")
        default:
            return XCTFail("Expected an unresolved journal outcome after rollback failure")
        }

        let retainedManifest = try XCTUnwrap(store.loadManifests().manifests.first)
        XCTAssertEqual(retainedManifest.phase, .prepared)
        XCTAssertEqual(retainedManifest.operationID, operationID)

        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: TagLibAudioMetadataPipeline(),
            renameFileSystem: fileSystem,
            renameJournalStore: store
        )
        await viewModel.refreshRenameJournalRecovery()
        let operation = try XCTUnwrap(viewModel.renameJournalRecovery.operations.first)
        XCTAssertTrue(operation.canRestore)
        XCTAssertEqual(operation.entries.count, 2)
        XCTAssertEqual(operation.entries.first?.roleText, String(localized: "At a temporary name"))

        // Read-only bootstrap: the hidden stage file is untouched and the original
        // path remains absent until an explicit restore.
        let stagedURL = try XCTUnwrap(stagedObservedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.entries[0].originalURL.path))
        XCTAssertTrue(viewModel.isRenameJournalBlocked(url: prepared.entries[0].originalURL))
    }

    func testFinalizationRollbackFailureReportsFileAtDestination() async throws {
        let fault = FaultInjectingRenameFileSystem(mode: .failSecondFinalAndRollback)
        let service = RenameTransactionService(fileSystem: fault, journal: store)
        let prepared = try makePrepared(names: [
            ("first.mp3", "renamed-first.mp3"),
            ("second.mp3", "renamed-second.mp3")
        ])

        switch service.execute(prepared) {
        case .unresolved(_, let classification, _):
            let first = try XCTUnwrap(classification.entries.first)
            XCTAssertEqual(first.role, .intended)
            XCTAssertEqual(first.observedURL, prepared.entries[0].intendedURL)
            XCTAssertEqual(
                try String(contentsOf: prepared.entries[0].intendedURL, encoding: .utf8),
                "entry-0"
            )
        default:
            return XCTFail("Expected an unresolved journal outcome after finalization rollback failure")
        }

        XCTAssertEqual(store.loadManifests().manifests.first?.phase, .prepared)
        XCTAssertEqual(
            try String(contentsOf: prepared.entries[0].intendedURL, encoding: .utf8),
            "entry-0"
        )
        XCTAssertEqual(store.loadManifests().manifests.count, 1)
    }

    func testRollbackDoesNotMoveAReplacementFileIntoTheOriginalPath() async throws {
        let fault = FaultInjectingRenameFileSystem(mode: .replaceAfterFirstFinal)
        let service = RenameTransactionService(fileSystem: fault, journal: store)
        let prepared = try makePrepared(names: [
            ("first.mp3", "renamed-first.mp3"),
            ("second.mp3", "renamed-second.mp3")
        ])

        switch service.execute(prepared) {
        case .unresolved:
            break
        default:
            return XCTFail("Expected an unresolved journal outcome after a replaced destination")
        }

        let replacementURL = prepared.entries[0].intendedURL
        XCTAssertEqual(try String(contentsOf: replacementURL, encoding: .utf8), "replacement")
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.entries[0].originalURL.path))
        XCTAssertNotEqual(try String(contentsOf: replacementURL, encoding: .utf8), "entry-0")
        XCTAssertEqual(store.loadManifests().manifests.first?.phase, .prepared)
    }

    func testChangedSourceIsRejectedBeforeAnyFileIsMoved() throws {
        let sourceURL = rootURL.appendingPathComponent("source.mp3")
        try Data(repeating: 1, count: 128).write(to: sourceURL)
        let previewFingerprint = try AudioFileFingerprint.capture(at: sourceURL)
        try Data(repeating: 2, count: 4096).write(to: sourceURL)
        let operationID = UUID()
        let prepared = PreparedRenameTransaction(
            operationID: operationID,
            entries: [
                PreparedRenameEntry(
                    index: 0,
                    fileID: UUID(),
                    originalURL: sourceURL,
                    temporaryURL: RenameStagingName.url(
                        for: sourceURL,
                        operationID: operationID,
                        index: 0
                    ),
                    intendedURL: rootURL.appendingPathComponent("renamed.mp3"),
                    expectedSourceFingerprint: previewFingerprint
                )
            ]
        )
        let service = RenameTransactionService(fileSystem: fileSystem, journal: store)

        switch service.execute(prepared) {
        case .rejected(.sourceChanged(let index)):
            XCTAssertEqual(index, 0)
        default:
            return XCTFail("Expected sourceChanged rejection")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try visibleEntries(), ["source.mp3"])
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    func testDeletedSourceIsRejectedBeforeAnyFileIsMoved() throws {
        let sourceURL = rootURL.appendingPathComponent("deleted.mp3")
        try Data("deleted".utf8).write(to: sourceURL)
        let fingerprint = try AudioFileFingerprint.capture(at: sourceURL)
        try FileManager.default.removeItem(at: sourceURL)
        let operationID = UUID()
        let prepared = PreparedRenameTransaction(
            operationID: operationID,
            entries: [
                PreparedRenameEntry(
                    index: 0,
                    fileID: UUID(),
                    originalURL: sourceURL,
                    temporaryURL: RenameStagingName.url(
                        for: sourceURL,
                        operationID: operationID,
                        index: 0
                    ),
                    intendedURL: rootURL.appendingPathComponent("renamed.mp3"),
                    expectedSourceFingerprint: fingerprint
                )
            ]
        )
        let service = RenameTransactionService(fileSystem: fileSystem, journal: store)

        switch service.execute(prepared) {
        case .rejected(.sourceMissing(let index)):
            XCTAssertEqual(index, 0)
        default:
            return XCTFail("Expected sourceMissing rejection")
        }
        XCTAssertTrue(try visibleEntries().isEmpty)
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
    }

    // MARK: - Helpers

    private func makePrepared(
        names: [(sourceName: String, intendedName: String)],
        operationID: UUID = UUID()
    ) throws -> PreparedRenameTransaction {
        var entries: [PreparedRenameEntry] = []
        for (index, names) in names.enumerated() {
            let sourceURL = rootURL.appendingPathComponent(names.sourceName)
            let intendedURL = rootURL.appendingPathComponent(names.intendedName)
            try Data("entry-\(index)".utf8).write(to: sourceURL)
            entries.append(
                PreparedRenameEntry(
                    index: index,
                    fileID: UUID(),
                    originalURL: sourceURL,
                    temporaryURL: RenameStagingName.url(
                        for: sourceURL,
                        operationID: operationID,
                        index: index
                    ),
                    intendedURL: intendedURL,
                    expectedSourceFingerprint: try AudioFileFingerprint.capture(at: sourceURL)
                )
            )
        }
        return PreparedRenameTransaction(operationID: operationID, entries: entries)
    }

    private func visibleEntries() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
            .filter { !$0.hasPrefix(RenameStagingName.prefix) }
            .sorted()
    }
}

/// Fault filesystem for journal-service tests. All non-move operations forward to
/// the real local implementation so entry identity, stage names and journal
/// evidence stay consistent with production behaviour.
private nonisolated final class FaultInjectingRenameFileSystem: RenameFileSystem, @unchecked Sendable {
    enum Mode {
        case failSecondStageAndRollback
        case failSecondFinalAndRollback
        case replaceAfterFirstFinal
    }

    private let base = LocalRenameFileSystem()
    private let mode: Mode
    private let lock = NSLock()
    private var stageMoveCount = 0
    private var finalMoveCount = 0
    private var primaryFailureRaised = false

    init(mode: Mode) {
        self.mode = mode
    }

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
    func volumeSupportsExclusiveRename(forDirectoryAt url: URL) throws -> Bool {
        try base.volumeSupportsExclusiveRename(forDirectoryAt: url)
    }
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
    func syncDirectory(_ handle: RenameDirectoryHandle) throws {
        try base.syncDirectory(handle)
    }

    func exclusiveMove(
        named sourceName: String,
        to destinationName: String,
        in handle: RenameDirectoryHandle
    ) throws {
        let isStageSource = sourceName.hasPrefix(RenameStagingName.prefix)
        let isStageDestination = destinationName.hasPrefix(RenameStagingName.prefix)

        lock.lock()
        let isFinalMove = !isStageDestination
        if isStageDestination {
            stageMoveCount += 1
        } else {
            finalMoveCount += 1
        }
        let stageCount = stageMoveCount
        let finalCount = finalMoveCount
        lock.unlock()

        switch mode {
        case .failSecondStageAndRollback:
            if isStageDestination, stageCount == 2 {
                throw RenameFileSystemError.io(code: 5)
            }
            if isStageSource, !isStageDestination {
                throw RenameFileSystemError.io(code: 5)
            }
        case .failSecondFinalAndRollback:
            if isFinalMove, finalCount == 2 {
                primaryFailureRaised = true
                throw RenameFileSystemError.io(code: 5)
            }
            if primaryFailureRaised, !isStageSource, isStageDestination {
                throw RenameFileSystemError.io(code: 5)
            }
        case .replaceAfterFirstFinal:
            if isFinalMove, finalCount == 1 {
                try base.exclusiveMove(named: sourceName, to: destinationName, in: handle)
                let destinationURL = handle.url.appendingPathComponent(destinationName, isDirectory: false)
                try? FileManager.default.removeItem(at: destinationURL)
                try Data("replacement".utf8).write(to: destinationURL)
                return
            }
        }

        try base.exclusiveMove(named: sourceName, to: destinationName, in: handle)
    }
}
#endif
