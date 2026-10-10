import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

final class FileRevisionConflictTests: XCTestCase {
    func testPermissionOnlyChangeRejectsOldVersionDespiteIdenticalContents() throws {
        let url = try fixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let bytes = try Data(contentsOf: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let version = try TagLibMetadataManager.fileVersion(at: url)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try AudioFileFingerprint.capture(at: url), fingerprint)
        XCTAssertNotEqual(try TagLibMetadataManager.fileVersion(at: url), version)
        try validateExpectedFileFingerprint(fingerprint, at: url)
        XCTAssertThrowsError(try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.title: .text("Must not commit")]),
            to: url,
            expectedVersion: version
        )) { error in
            guard case TagLibManagerError.fileChanged = error else {
                return XCTFail("Expected the reported version conflict, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testTimestampOnlyChangeRejectsFingerprintDespiteIdenticalContents() throws {
        let url = try fixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let bytes = try Data(contentsOf: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)

        try FileManager.default.setAttributes(
            [.modificationDate: fingerprint.contentModificationDate.addingTimeInterval(10)],
            ofItemAtPath: url.path
        )

        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertThrowsError(try validateExpectedFileFingerprint(fingerprint, at: url))
    }

    func testContentChangeWithRestoredModificationTimeStillRejectsPackageVersion() throws {
        let url = try fixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Use an exact whole-second value; Foundation Date round-tripping an
        // arbitrary nanosecond timestamp can itself alter the fingerprint.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: url.path
        )
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let version = try TagLibMetadataManager.fileVersion(at: url)
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: 0)
        let firstByte = try XCTUnwrap(handle.read(upToCount: 1)?.first)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data([firstByte ^ 1]))
        try handle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: fingerprint.contentModificationDate],
            ofItemAtPath: url.path
        )

        XCTAssertEqual(try AudioFileFingerprint.capture(at: url), fingerprint)
        XCTAssertNotEqual(try TagLibMetadataManager.fileVersion(at: url), version)
    }

    func testUnchangedSnapshotCanCommitWithExpectedVersion() throws {
        let url = try fixtureCopy()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = try TagLibMetadataManager.readBasicSnapshot(from: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)

        try validateExpectedFileFingerprint(fingerprint, at: url)
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.title: .text("Versioned edit")]),
            to: url,
            expectedVersion: snapshot.fileVersion
        )
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: url).title, "Versioned edit")
    }

    private func fixtureCopy() throws -> URL {
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(
            bundle.url(forResource: "testAudioFile.flac", withExtension: nil, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRevision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }
}
