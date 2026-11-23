import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Presentation coverage for the rename-recovery failure path.
///
/// Drives the real `AudioViewModel.renameFiles(using:)` route with a durable
/// journal store whose committed marker cannot be written. The transaction
/// service runs detached, moves the files, then reports an unresolved outcome;
/// the view model must render the localized recovery file count through
/// `fileCountLabel` exactly as it did before the F2 transaction extraction.
nonisolated final class RenameRecoveryPresentationTests: XCTestCase {
    @MainActor
    func testUnresolvedRenameFailureReportsLocalizedSingleFileCount() async throws {
        let fixtureURL = try MetadataTestTokens.makeFixtureCopy()
        defer { MetadataTestTokens.removeFixtureCopy(at: fixtureURL) }
        let file = try observedFile(at: fixtureURL, title: "renamed-single")

        let result = try await renameIntoInjectedFailure(files: [file])

        XCTAssertEqual(result.recoveryItems.count, 1)
        let message = try XCTUnwrap(result.failureMessage)
        XCTAssertTrue(
            message.contains("Recovery required for 1 file:"),
            "Single-file recovery must use the localized singular count label; got: \(message)"
        )
    }

    @MainActor
    func testUnresolvedRenameFailureReportsLocalizedMultipleFileCount() async throws {
        let firstURL = try MetadataTestTokens.makeFixtureCopy()
        let secondURL = try MetadataTestTokens.makeFixtureCopy()
        defer {
            MetadataTestTokens.removeFixtureCopy(at: firstURL)
            MetadataTestTokens.removeFixtureCopy(at: secondURL)
        }
        let first = try observedFile(at: firstURL, title: "renamed-first")
        let second = try observedFile(at: secondURL, title: "renamed-second")

        let result = try await renameIntoInjectedFailure(files: [first, second])

        XCTAssertEqual(result.recoveryItems.count, 2)
        let message = try XCTUnwrap(result.failureMessage)
        XCTAssertTrue(
            message.contains("Recovery required for 2 files:"),
            "Multi-file recovery must use the localized plural count label; got: \(message)"
        )
    }

    // MARK: - Headless rename execution

    @MainActor
    private func renameIntoInjectedFailure(files: [AudioFile]) async throws -> FileRenameResult {
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AudioMatorTestsCommittedMarkerFailure-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: journalDirectory) }
        let baseJournal = LocalRenameJournalStore(directoryURL: journalDirectory)
        let failingJournal = CommittedMarkerFailingJournal(base: baseJournal)

        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: TagLibAudioMetadataPipeline(),
            renameFileSystem: LocalRenameFileSystem(),
            renameJournalStore: failingJournal,
            writableFixtures: files
        )
        viewModel.mergeQuickImportFiles(files)
        viewModel.flushPendingMetadataReloads()

        let plan = makeFileRenamePlan(template: "{{title}}", targetFiles: files)
        XCTAssertEqual(plan.operations.count, files.count, "Fixture plan must produce one move per file")

        return await viewModel.renameFiles(using: plan)
    }

    @MainActor
    private func observedFile(at url: URL, title: String) throws -> AudioFile {
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        return AudioFileTestFactory.makeObserved(
            url: url,
            title: title,
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
    }
}

/// Delegates every durable-journal operation to the real store except the
/// committed marker, which fails exactly once per execute so the service reports
/// an unresolved outcome with the prepared manifest retained.
private nonisolated final class CommittedMarkerFailingJournal: RenameJournalStoring {
    private let base: any RenameJournalStoring

    init(base: any RenameJournalStoring) {
        self.base = base
    }

    var directoryURL: URL { base.directoryURL }

    func ensureDirectory() throws { try base.ensureDirectory() }

    func loadManifests() -> RenameJournalLoadResult { base.loadManifests() }

    func tryAcquireLock() throws -> RenameJournalLock? { try base.tryAcquireLock() }

    func directoryBarrierSupport() -> RenameDirectoryBarrierSupport { base.directoryBarrierSupport() }

    func writePrepared(_ manifest: RenameJournalManifest) throws { try base.writePrepared(manifest) }

    func markCommitted(_ manifest: RenameJournalManifest) throws {
        throw CocoaError(.fileWriteUnknown)
    }

    func removeManifest(operationID: UUID) throws { try base.removeManifest(operationID: operationID) }
}
