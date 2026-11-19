import Foundation
import XCTest
@testable import AudioMatorCoreLogic

final class QuickImportPathIndexTests: XCTestCase {
    func testInsertAppendsInOrderAndMaintainsRefCounts() {
        var index = QuickImportPathIndex()
        let first = record(path: "/tmp/import/01.mp3", id: UUID(), token: UUID())
        let second = record(path: "/tmp/import/02.mp3", id: UUID(), token: UUID())

        let firstMutation = index.insertOrReplace(first)
        XCTAssertEqual(firstMutation.change, .inserted(id: first.id, at: 0))
        XCTAssertNil(firstMutation.previousRecord)
        XCTAssertEqual(index.orderedIDs, [first.id])

        let secondMutation = index.insertOrReplace(second)
        XCTAssertEqual(secondMutation.change, .inserted(id: second.id, at: 1))
        XCTAssertEqual(index.orderedIDs, [first.id, second.id])
        XCTAssertEqual(index.fileKeyRefCount(first.identity.fileKey), 1)
        XCTAssertEqual(index.parentKeyRefCount(first.identity.parentKey), 2)
        XCTAssertEqual(index.consistencyIssues(), [])
    }

    func testReplaceKeepsOriginalRowPositionAndParentRefCounts() {
        var index = QuickImportPathIndex()
        let first = record(path: "/tmp/import/01.mp3", id: UUID(), token: UUID())
        let second = record(path: "/tmp/import/02.mp3", id: UUID(), token: UUID())
        index.insertOrReplace(first)
        index.insertOrReplace(second)

        let moved = record(
            path: "/tmp/import/01.mp3",
            id: first.id,
            token: UUID(),
            parentPath: "/tmp/import/disc-one"
        )
        let mutation = index.insertOrReplace(moved)
        XCTAssertEqual(mutation.change, .replaced(id: first.id, at: 0))
        XCTAssertEqual(mutation.previousRecord?.identity.fileKey, first.identity.fileKey)
        XCTAssertEqual(index.orderedIDs, [first.id, second.id])
        XCTAssertEqual(index.parentKeyRefCount(first.identity.parentKey), 1)
        XCTAssertEqual(index.parentKeyRefCount(moved.identity.parentKey), 1)
        XCTAssertEqual(index.consistencyIssues(), [])
    }

    func testAliasCollapsesToSingleRowForTheSameFileKey() {
        var index = QuickImportPathIndex()
        let originalID = UUID()
        let target = record(
            path: "/tmp/import/target.mp3",
            id: originalID,
            token: UUID()
        )
        index.insertOrReplace(target)

        // Alias resolved to the same canonical file key but with a different row ID.
        let alias = record(
            path: "/tmp/import/alias.mp3",
            id: UUID(),
            token: UUID(),
            canonicalPath: "/tmp/import/target.mp3"
        )
        let mutation = index.insertOrReplace(alias)
        XCTAssertEqual(mutation.change, .replaced(id: alias.id, at: 0))
        XCTAssertEqual(index.orderedIDs, [alias.id])
        XCTAssertEqual(index.orderedIDs.count, 1)
        XCTAssertEqual(index.fileKeyRefCount(target.identity.fileKey), 1)
        XCTAssertEqual(index.consistencyIssues(), [])
    }

    func testRemoveCompactsAndDropsRefCounts() {
        var index = QuickImportPathIndex()
        let first = record(path: "/tmp/import/01.mp3", id: UUID(), token: UUID())
        let second = record(path: "/tmp/import/02.mp3", id: UUID(), token: UUID())
        let third = record(path: "/tmp/import/03.mp3", id: UUID(), token: UUID())
        for record in [first, second, third] {
            index.insertOrReplace(record)
        }

        let mutation = index.remove(id: second.id)
        XCTAssertEqual(mutation?.change, .removed(id: second.id, at: 1))
        XCTAssertEqual(index.orderedIDs, [first.id, third.id])
        XCTAssertEqual(index.parentKeyRefCount(first.identity.parentKey), 2)
        XCTAssertEqual(index.consistencyIssues(), [])

        XCTAssertNil(index.remove(id: second.id), "Removing the same ID twice must not resurrect it")
        XCTAssertNil(index.record(forID: second.id))
    }

    func testMigrateMovesKeysAndPreservesOrder() {
        var index = QuickImportPathIndex()
        let first = record(path: "/tmp/import/01.mp3", id: UUID(), token: UUID())
        let second = record(path: "/tmp/import/02.mp3", id: UUID(), token: UUID())
        index.insertOrReplace(first)
        index.insertOrReplace(second)

        let destination = record(
            path: "/tmp/renamed/01 - Renamed.mp3",
            id: first.id,
            token: UUID()
        )
        let mutation = index.migrate(id: first.id, to: destination.identity)
        XCTAssertEqual(mutation?.change, .replaced(id: first.id, at: 0))
        XCTAssertNil(index.id(forFileKey: first.identity.fileKey))
        XCTAssertEqual(index.id(forFileKey: destination.identity.fileKey), first.id)
        XCTAssertEqual(index.fileKeyRefCount(destination.identity.fileKey), 1)
        XCTAssertEqual(index.parentKeyRefCount(destination.identity.parentKey), 1)
        XCTAssertEqual(index.parentKeyRefCount(first.identity.parentKey), 1)
        XCTAssertEqual(index.consistencyIssues(), [])

        XCTAssertNil(index.migrate(id: UUID(), to: destination.identity))
    }

    func testUpdateRequestTokenLeavesMembershipIdentityUnchanged() {
        var index = QuickImportPathIndex()
        let membership = record(path: "/tmp/import/01.mp3", id: UUID(), token: UUID())
        index.insertOrReplace(membership)

        let replacementToken = UUID()
        index.updateRequestToken(id: membership.id, token: replacementToken)
        XCTAssertEqual(index.record(forID: membership.id)?.requestToken, replacementToken)
        XCTAssertEqual(index.record(forID: membership.id)?.identity, membership.identity)
        XCTAssertEqual(index.consistencyIssues(), [])
    }

    func testRemoveAllClearsEveryMapping() {
        var index = QuickImportPathIndex()
        index.insertOrReplace(record(path: "/tmp/import/01.mp3", id: UUID(), token: UUID()))
        index.removeAll()
        XCTAssertTrue(index.orderedIDs.isEmpty)
        XCTAssertTrue(index.recordsByID.isEmpty)
        XCTAssertTrue(index.fileKeyRefCounts.isEmpty)
        XCTAssertTrue(index.parentKeyRefCounts.isEmpty)
        XCTAssertEqual(index.consistencyIssues(), [])
    }

    // MARK: - Identity provider

    func testFileSystemProviderResolvesFileAndParentOnceWithConsistentEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickImportProvider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("01.mp3")
        let secondURL = root.appendingPathComponent("02.mp3")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let provider = FileSystemQuickImportPathIdentityProvider()
        let first = provider.prepareIdentity(forFileURL: firstURL, parent: nil)
        let second = provider.prepareIdentity(
            forFileURL: secondURL,
            parent: first.parentEvidence
        )

        XCTAssertEqual(first.operationalURL, firstURL.standardizedFileURL)
        XCTAssertEqual(first.canonicalPath, try AudioFileFingerprint.capture(at: firstURL).normalizedPath)
        XCTAssertEqual(first.fileKey, FileSystemPathSemantics.key(for: firstURL))
        XCTAssertEqual(first.directoryEntryKey, FileSystemPathSemantics.directoryEntryKey(for: firstURL))
        XCTAssertEqual(first.parentKey, FileSystemPathSemantics.key(for: root))
        XCTAssertEqual(second.parentKey, first.parentKey)
        XCTAssertEqual(second.parentEvidence.parentCanonicalPath, first.parentEvidence.parentCanonicalPath)
        XCTAssertNotEqual(first.fileKey, second.fileKey)
        XCTAssertNotNil(first.fileIdentity)
        XCTAssertNotNil(first.parentIdentity)
    }

    func testFileSystemProviderKeepsLexicalURLForSymlinkAlias() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickImportSymlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.mp3")
        try Data().write(to: target)
        let alias = root.appendingPathComponent("alias.mp3")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)

        let provider = FileSystemQuickImportPathIdentityProvider()
        let aliasIdentity = provider.prepareIdentity(forFileURL: alias, parent: nil)
        let targetIdentity = provider.prepareIdentity(forFileURL: target, parent: nil)

        XCTAssertEqual(aliasIdentity.operationalURL, alias.standardizedFileURL)
        XCTAssertEqual(aliasIdentity.fileKey, targetIdentity.fileKey)
        XCTAssertEqual(aliasIdentity.canonicalPath, targetIdentity.canonicalPath)
        XCTAssertNotEqual(aliasIdentity.operationalURL, targetIdentity.operationalURL)
    }

    func testLoadPolicyPresetsKeepProductionCadenceAndDeterministicForcedSizes() {
        XCTAssertEqual(QuickImportLoadPolicy.production.partialBatchSize, 24)
        XCTAssertEqual(QuickImportLoadPolicy.production.forceFlushBatchSize, 48)
        XCTAssertEqual(QuickImportLoadPolicy.production.minimumFlushInterval, 0.2)
        XCTAssertEqual(QuickImportLoadPolicy.forced24.forceFlushBatchSize, 24)
        XCTAssertEqual(QuickImportLoadPolicy.forced24.partialBatchSize, 24)
        XCTAssertEqual(QuickImportLoadPolicy.forced48.forceFlushBatchSize, 48)
        XCTAssertEqual(QuickImportLoadPolicy.forced48.partialBatchSize, 48)
    }

    // MARK: - Helpers

    private func record(
        path: String,
        id: UUID,
        token: UUID,
        parentPath: String? = nil,
        canonicalPath: String? = nil
    ) -> QuickImportMembershipRecord {
        let url = URL(fileURLWithPath: path)
        let parentURL = URL(fileURLWithPath: parentPath ?? url.deletingLastPathComponent().path)
        let resolvedCanonicalPath = canonicalPath ?? path
        let parentEvidence = QuickImportParentEvidence(
            parentURL: parentURL,
            parentKey: "parent:" + parentURL.path,
            parentCanonicalPath: parentURL.path,
            parentIsCaseSensitive: true,
            parentIdentity: QuickImportEntryIdentity(device: 1, inode: 1)
        )
        let identity = QuickImportPathIdentity(
            operationalURL: url,
            canonicalPath: resolvedCanonicalPath,
            fileKey: resolvedCanonicalPath,
            directoryEntryKey: "entry:" + parentURL.path + "/" + url.lastPathComponent,
            parentEvidence: parentEvidence,
            fileIdentity: QuickImportEntryIdentity(device: 1, inode: 2)
        )
        return QuickImportMembershipRecord(id: id, identity: identity, requestToken: token)
    }
}
