import Foundation
import XCTest
@testable import AudioMator

/// Durable-store coverage: versioned round trip, committed rewrite, stable
/// non-blocking lock, duplicate protection and retention of malformed records.
nonisolated final class RenameJournalStoreTests: XCTestCase {
    private var rootURL: URL!
    private var journalURL: URL!
    private var store: LocalRenameJournalStore!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorJournalStoreTests-\(UUID().uuidString)", isDirectory: true)
        journalURL = rootURL.appendingPathComponent("RenameJournal", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        store = LocalRenameJournalStore(directoryURL: journalURL)
    }

    override func tearDownWithError() throws {
        store = nil
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testPreparedThenCommittedThenRemoved() throws {
        let operationID = UUID()
        let prepared = makeManifest(operationID: operationID, phase: .prepared)
        try store.ensureDirectory()
        try store.writePrepared(prepared)

        var loaded = store.loadManifests()
        XCTAssertEqual(loaded.manifests.count, 1)
        XCTAssertEqual(loaded.manifests.first?.phase, .prepared)
        XCTAssertTrue(loaded.issues.isEmpty)

        let committed = makeManifest(operationID: operationID, phase: .committed)
        try store.markCommitted(committed)
        loaded = store.loadManifests()
        XCTAssertEqual(loaded.manifests.first?.phase, .committed)

        try store.removeManifest(operationID: operationID)
        XCTAssertTrue(store.loadManifests().manifests.isEmpty)
        XCTAssertTrue(store.loadManifests().issues.isEmpty)
    }

    func testMalformedUnsupportedAndTemporaryRecordsAreRetained() throws {
        try store.ensureDirectory()
        let malformedURL = journalURL.appendingPathComponent(
            RenameJournalFormat.manifestFileName(operationID: UUID()),
            isDirectory: false
        )
        try Data("this is not json".utf8).write(to: malformedURL)

        let futureOperationID = UUID()
        let futureURL = journalURL.appendingPathComponent(
            RenameJournalFormat.manifestFileName(operationID: futureOperationID),
            isDirectory: false
        )
        let futureManifest = makeManifest(
            operationID: futureOperationID,
            phase: .prepared,
            formatVersion: RenameJournalFormat.currentVersion + 1
        )
        try JSONEncoder().encode(futureManifest).write(to: futureURL)

        let temporaryURL = journalURL.appendingPathComponent(
            RenameJournalFormat.temporaryFileName(operationID: UUID()),
            isDirectory: false
        )
        try Data("partial".utf8).write(to: temporaryURL)

        let loaded = store.loadManifests()
        XCTAssertTrue(loaded.manifests.isEmpty)
        let categories = Set(loaded.issues.map(\.category))
        XCTAssertTrue(categories.contains(.unreadable))
        XCTAssertTrue(categories.contains(.unsupportedVersion))
        XCTAssertTrue(categories.contains(.incompleteWrite))

        XCTAssertTrue(FileManager.default.fileExists(atPath: malformedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: futureURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryURL.path))
    }

    func testDuplicatePreparedWriteIsRejectedAndOriginalRecordRetained() throws {
        let manifest = makeManifest(operationID: UUID(), phase: .prepared)
        try store.ensureDirectory()
        try store.writePrepared(manifest)

        XCTAssertThrowsError(try store.writePrepared(manifest)) { error in
            guard let storeError = error as? RenameJournalStoreError,
                  case .duplicateOperation(let operationID) = storeError
            else {
                return XCTFail("Expected duplicateOperation, got \(error)")
            }
            XCTAssertEqual(operationID, manifest.operationID)
        }

        let loaded = store.loadManifests()
        XCTAssertEqual(loaded.manifests.count, 1)
        XCTAssertEqual(loaded.manifests.first?.phase, .prepared)
    }

    func testLockIsNonBlockingAcrossStoresAndReleases() throws {
        let secondStore = LocalRenameJournalStore(directoryURL: journalURL)

        let firstLock = try XCTUnwrap(try store.tryAcquireLock())
        XCTAssertNil(try secondStore.tryAcquireLock(), "A second store must observe the live lock")

        firstLock.release()
        let secondLock = try XCTUnwrap(try secondStore.tryAcquireLock())
        secondLock.release()
        XCTAssertNotNil(try store.tryAcquireLock())
    }

    func testLockFileInodeIsStableAcrossManifestWrites() throws {
        try store.ensureDirectory()
        let initialLock = try store.tryAcquireLock()
        initialLock?.release()
        let lockURL = journalURL.appendingPathComponent(
            RenameJournalFormat.lockFileName,
            isDirectory: false
        )
        let before = try FileEntryIdentityCapture.capture(at: lockURL)

        let manifest = makeManifest(operationID: UUID(), phase: .prepared)
        try store.writePrepared(manifest)
        try store.removeManifest(operationID: manifest.operationID)

        let after = try FileEntryIdentityCapture.capture(at: lockURL)
        XCTAssertEqual(before.device, after.device)
        XCTAssertEqual(before.inode, after.inode)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }

    func testDirectoryBarrierSupportProbeDoesNotCrash() throws {
        try store.ensureDirectory()
        switch store.directoryBarrierSupport() {
        case .supported:
            XCTAssertTrue(true)
        case .unsupported:
            XCTAssertTrue(true)
        }
    }

    private func makeManifest(
        operationID: UUID,
        phase: RenameJournalPhase,
        formatVersion: Int = RenameJournalFormat.currentVersion
    ) -> RenameJournalManifest {
        let originalURL = rootURL.appendingPathComponent("a.wav")
        let intendedURL = rootURL.appendingPathComponent("b.wav")
        let temporaryURL = RenameStagingName.url(
            for: originalURL,
            operationID: operationID,
            index: 0
        )
        let sourceIdentity = RenameJournalEntryIdentity(
            device: 7,
            inode: 42,
            kind: .regular,
            size: 128,
            modificationTimeIntervalSince1970: 1_700_000_000.123456,
            creationTimeIntervalSince1970: 1_690_000_000.5,
            volumeIdentifier: "VOLUME-A"
        )
        return RenameJournalManifest(
            formatVersion: formatVersion,
            operationID: operationID,
            phase: phase,
            createdAt: 1_700_000_100.25,
            committedAt: phase == .committed ? 1_700_000_200.25 : nil,
            diagnostics: [],
            entries: [
                RenameJournalEntry(
                    index: 0,
                    originalURL: originalURL.absoluteString,
                    temporaryURL: temporaryURL.absoluteString,
                    intendedURL: intendedURL.absoluteString,
                    sourceIdentity: sourceIdentity,
                    linkTarget: nil
                )
            ]
        )
    }
}
