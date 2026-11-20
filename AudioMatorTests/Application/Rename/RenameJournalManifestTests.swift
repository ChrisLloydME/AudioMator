import Foundation
import XCTest
@testable import AudioMator

/// Unit coverage for the versioned rename-journal record: exact identity
/// evidence, deterministic stage names and persisted-path validation.
nonisolated final class RenameJournalManifestTests: XCTestCase {
    private let operationID = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!
    private let rootURL = URL(fileURLWithPath: "/tmp/AudioMatorJournalManifestTests", isDirectory: true)

    func testPreparedManifestRoundTripsIdentityEvidenceExactly() throws {
        let manifest = makeManifest()

        try manifest.validate()
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(RenameJournalManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.phase, .prepared)
        XCTAssertNil(decoded.committedAt)
        XCTAssertEqual(decoded.entries.count, 1)

        let recordedIdentity = try XCTUnwrap(decoded.entries.first?.sourceIdentity)
        let observedIdentity = try XCTUnwrap(manifest.entries.first?.sourceIdentity).renameEntryIdentity
        XCTAssertTrue(recordedIdentity.matchesEntryIdentity(observedIdentity))
        XCTAssertEqual(
            recordedIdentity.renameEntryIdentity.modificationDate,
            manifest.entries[0].sourceIdentity.renameEntryIdentity.modificationDate
        )
    }

    func testValidationRejectsNonDeterministicStageName() throws {
        let manifest = makeManifest(intendedURL: rootURL.appendingPathComponent("b.wav"))
        var entries = manifest.entries
        entries[0] = RenameJournalEntry(
            index: 0,
            originalURL: entries[0].originalURL,
            temporaryURL: rootURL.appendingPathComponent(".audiomator-rename-\(UUID().uuidString).wav").absoluteString,
            intendedURL: entries[0].intendedURL,
            sourceIdentity: entries[0].sourceIdentity,
            linkTarget: nil
        )
        let tampered = RenameJournalManifest(
            formatVersion: manifest.formatVersion,
            operationID: manifest.operationID,
            phase: manifest.phase,
            createdAt: manifest.createdAt,
            committedAt: nil,
            diagnostics: [],
            entries: entries
        )

        XCTAssertThrowsError(try tampered.validate()) { error in
            XCTAssertEqual(error as? RenameJournalValidationError, .invalidTemporaryName)
        }
    }

    func testValidationRejectsMixedParentsAndUnsupportedVersion() throws {
        let manifest = makeManifest(intendedURL: URL(fileURLWithPath: "/tmp/OtherFolder/b.wav"))
        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? RenameJournalValidationError, .mixedParents)
        }

        let future = RenameJournalManifest(
            formatVersion: RenameJournalFormat.currentVersion + 1,
            operationID: manifest.operationID,
            phase: .prepared,
            createdAt: manifest.createdAt,
            committedAt: nil,
            diagnostics: [],
            entries: manifest.entries
        )
        XCTAssertThrowsError(try future.validate()) { error in
            XCTAssertEqual(
                error as? RenameJournalValidationError,
                .unsupportedVersion(RenameJournalFormat.currentVersion + 1)
            )
        }
    }

    func testIdentityMatchingRequiresVolumeEvidenceWhenRecorded() throws {
        let recordedIdentity = RenameEntryIdentity(
            device: 7,
            inode: 42,
            kind: .regular,
            size: 128,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000.123456),
            creationDate: Date(timeIntervalSince1970: 1_690_000_000.5),
            volumeIdentifier: "VOLUME-A",
            linkTarget: nil
        )
        let journalIdentity = try RenameJournalEntryIdentity(recordedIdentity)

        let sameEntryWithoutVolume = RenameEntryIdentity(
            device: recordedIdentity.device,
            inode: recordedIdentity.inode,
            kind: recordedIdentity.kind,
            size: recordedIdentity.size,
            modificationDate: recordedIdentity.modificationDate,
            creationDate: recordedIdentity.creationDate,
            volumeIdentifier: nil,
            linkTarget: nil
        )
        XCTAssertFalse(journalIdentity.matchesEntryIdentity(sameEntryWithoutVolume))
        XCTAssertTrue(journalIdentity.matchesEntryIdentity(recordedIdentity))

        let noVolumeRecord = try RenameJournalEntryIdentity(sameEntryWithoutVolume)
        XCTAssertTrue(noVolumeRecord.matchesEntryIdentity(sameEntryWithoutVolume))
        XCTAssertFalse(noVolumeRecord.matchesEntryIdentity(recordedIdentity))
    }

    func testStagingNameIsDeterministicAndIndexBound() {
        let sourceURL = rootURL.appendingPathComponent("source.wav")
        let first = RenameStagingName.url(for: sourceURL, operationID: operationID, index: 0)
        let firstAgain = RenameStagingName.url(for: sourceURL, operationID: operationID, index: 0)
        let second = RenameStagingName.url(for: sourceURL, operationID: operationID, index: 1)

        XCTAssertEqual(first, firstAgain)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix(RenameStagingName.prefix + "."))
        XCTAssertEqual(first.pathExtension, "wav")
        XCTAssertEqual(first.deletingLastPathComponent(), sourceURL.deletingLastPathComponent())
        XCTAssertTrue(RenameStagingName.validates(
            first,
            for: sourceURL,
            operationID: operationID,
            index: 0
        ))
    }

    func testValidateRejectsUnchangedOriginalAndIntendedURL() {
        let unchanged = makeManifest(intendedURL: rootURL.appendingPathComponent("a.wav"))
        XCTAssertThrowsError(try unchanged.validate()) { error in
            XCTAssertEqual(error as? RenameJournalValidationError, .roleCollision)
        }
    }

    func testRenameEntryIdentityWithUnknownDeviceAndInodeNeverMatches() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = RenameEntryIdentity(
            device: nil,
            inode: nil,
            kind: .regular,
            size: 128,
            modificationDate: now,
            creationDate: nil
        )
        let second = RenameEntryIdentity(
            device: nil,
            inode: nil,
            kind: .regular,
            size: 128,
            modificationDate: now,
            creationDate: nil
        )
        XCTAssertFalse(
            first.isSameDirectoryEntry(as: second),
            "Unknown device/inode must never count as a physical directory-entry match"
        )
    }

    private func makeManifest(
        intendedURL: URL? = nil
    ) -> RenameJournalManifest {
        let originalURL = rootURL.appendingPathComponent("a.wav")
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
            formatVersion: RenameJournalFormat.currentVersion,
            operationID: operationID,
            phase: .prepared,
            createdAt: 1_700_000_100.25,
            committedAt: nil,
            diagnostics: [],
            entries: [
                RenameJournalEntry(
                    index: 0,
                    originalURL: originalURL.absoluteString,
                    temporaryURL: temporaryURL.absoluteString,
                    intendedURL: (intendedURL ?? rootURL.appendingPathComponent("b.wav")).absoluteString,
                    sourceIdentity: sourceIdentity,
                    linkTarget: nil
                )
            ]
        )
    }
}
