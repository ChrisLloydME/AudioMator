import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
final class FileRenameTransactionTests: XCTestCase {
    func testRollbackFailureReportsHiddenTemporaryFileAndRecoveryItem() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameTransactionTests-\(UUID().uuidString)", isDirectory: true)
        let firstSourceURL = rootURL.appendingPathComponent("first.mp3")
        let firstDestinationURL = rootURL.appendingPathComponent("renamed-first.mp3")
        let secondSourceURL = rootURL.appendingPathComponent("second.mp3")
        let secondDestinationURL = rootURL.appendingPathComponent("renamed-second.mp3")
        let fileSystem = FaultInjectingRenameFileSystem(
            existingURLs: [firstSourceURL, secondSourceURL],
            shouldFailMove: { sourceURL, destinationURL in
                if sourceURL == secondSourceURL {
                    return TestMoveError.primaryFailure
                }

                if
                    destinationURL == firstSourceURL,
                    sourceURL.lastPathComponent.hasPrefix(".audiomator-rename-")
                {
                    return TestMoveError.rollbackFailure
                }

                return nil
            }
        )

        let result = executeFileRenameTransaction(
            [
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: firstSourceURL,
                    destinationURL: firstDestinationURL,
                    expectedFileFingerprint: AudioFileTestFactory.fingerprint(for: firstSourceURL)
                ),
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: secondSourceURL,
                    destinationURL: secondDestinationURL,
                    expectedFileFingerprint: AudioFileTestFactory.fingerprint(for: secondSourceURL)
                )
            ],
            fileSystem: fileSystem
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Expected the injected staging failure to abort the transaction.")
        }

        let recoveryItem = try XCTUnwrap(failure.recoveryItems.first)
        XCTAssertEqual(failure.recoveryItems.count, 1)
        XCTAssertEqual(recoveryItem.originalURL, firstSourceURL)
        XCTAssertEqual(recoveryItem.intendedURL, firstDestinationURL)
        XCTAssertTrue(
            try XCTUnwrap(recoveryItem.finalURL).lastPathComponent.hasPrefix(".audiomator-rename-")
        )
        XCTAssertNotNil(recoveryItem.rollbackError)
        XCTAssertTrue(failure.message.contains("Recovery required"))
    }

    func testFinalizationRollbackFailureReportsFileAtDestination() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameFinalizationTests-\(UUID().uuidString)", isDirectory: true)
        let firstSourceURL = rootURL.appendingPathComponent("first.mp3")
        let firstDestinationURL = rootURL.appendingPathComponent("renamed-first.mp3")
        let secondSourceURL = rootURL.appendingPathComponent("second.mp3")
        let secondDestinationURL = rootURL.appendingPathComponent("renamed-second.mp3")
        let fileSystem = FaultInjectingRenameFileSystem(
            existingURLs: [firstSourceURL, secondSourceURL],
            shouldFailMove: { sourceURL, destinationURL in
                if destinationURL == secondDestinationURL {
                    return TestMoveError.primaryFailure
                }

                if
                    sourceURL == firstDestinationURL,
                    destinationURL.lastPathComponent.hasPrefix(".audiomator-rename-")
                {
                    return TestMoveError.rollbackFailure
                }

                return nil
            }
        )

        let result = executeFileRenameTransaction(
            [
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: firstSourceURL,
                    destinationURL: firstDestinationURL,
                    expectedFileFingerprint: AudioFileTestFactory.fingerprint(for: firstSourceURL)
                ),
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: secondSourceURL,
                    destinationURL: secondDestinationURL,
                    expectedFileFingerprint: AudioFileTestFactory.fingerprint(for: secondSourceURL)
                )
            ],
            fileSystem: fileSystem
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Expected the injected finalization failure to abort the transaction.")
        }

        let recoveryItem = try XCTUnwrap(failure.recoveryItems.first)
        XCTAssertEqual(failure.recoveryItems.count, 1)
        XCTAssertEqual(recoveryItem.originalURL, firstSourceURL)
        XCTAssertEqual(recoveryItem.finalURL, firstDestinationURL)
        XCTAssertNotNil(recoveryItem.rollbackError)
        XCTAssertTrue(failure.message.contains(firstDestinationURL.path))
    }

    func testChangedSourceIsRejectedBeforeAnyFileIsMoved() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameIdentityTests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("source.mp3")
        let destinationURL = rootURL.appendingPathComponent("renamed.mp3")
        let previewFingerprint = AudioFileTestFactory.fingerprint(for: sourceURL, fileSize: 100)
        let changedFingerprint = AudioFileTestFactory.fingerprint(for: sourceURL, fileSize: 200)
        let fileSystem = FaultInjectingRenameFileSystem(
            existingURLs: [sourceURL],
            fingerprints: [sourceURL: changedFingerprint],
            shouldFailMove: { _, _ in nil }
        )

        let result = executeFileRenameTransaction(
            [
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    expectedFileFingerprint: previewFingerprint
                )
            ],
            fileSystem: fileSystem
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Expected a source changed after preview to be rejected.")
        }
        XCTAssertTrue(failure.message.contains("changed after the preview"))
        XCTAssertTrue(fileSystem.fileExists(at: sourceURL))
        XCTAssertFalse(fileSystem.fileExists(at: destinationURL))
        XCTAssertEqual(fileSystem.moveCount, 0)
    }

    func testDeletedSourceIsRejectedBeforeAnyFileIsMoved() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameDeletedSourceTests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("deleted.mp3")
        let destinationURL = rootURL.appendingPathComponent("renamed.mp3")
        let fileSystem = FaultInjectingRenameFileSystem(
            existingURLs: [],
            shouldFailMove: { _, _ in nil }
        )

        let result = executeFileRenameTransaction(
            [
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    expectedFileFingerprint: AudioFileTestFactory.fingerprint(for: sourceURL)
                )
            ],
            fileSystem: fileSystem
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Expected a deleted source to abort the transaction.")
        }
        XCTAssertTrue(failure.message.contains("source missing"))
        XCTAssertEqual(failure.recoveryItems.count, 1)
        XCTAssertTrue(failure.recoveryItems[0].finalLocations.isEmpty)
        XCTAssertTrue(failure.message.contains("location unknown"))
        XCTAssertEqual(fileSystem.moveCount, 0)
    }
}

private final class FaultInjectingRenameFileSystem: FileRenameFileSystem, @unchecked Sendable {
    typealias FailureRule = @Sendable (URL, URL) -> Error?

    private let lock = NSLock()
    private var existingPaths: Set<String>
    private let fingerprintsByPath: [String: AudioFileFingerprint]
    private let shouldFailMove: FailureRule
    private(set) var moveCount = 0

    init(
        existingURLs: [URL],
        fingerprints: [URL: AudioFileFingerprint] = [:],
        shouldFailMove: @escaping FailureRule
    ) {
        existingPaths = Set(existingURLs.map(\.path))
        fingerprintsByPath = Dictionary(uniqueKeysWithValues: fingerprints.map { ($0.key.path, $0.value) })
        self.shouldFailMove = shouldFailMove
    }

    func fileExists(at url: URL) -> Bool {
        lock.withLock { existingPaths.contains(url.path) }
    }

    func fingerprint(at url: URL) throws -> AudioFileFingerprint {
        try lock.withLock {
            guard existingPaths.contains(url.path) else {
                throw TestMoveError.sourceMissing
            }
            return fingerprintsByPath[url.path] ?? AudioFileTestFactory.fingerprint(for: url)
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try lock.withLock {
            moveCount += 1
            if let error = shouldFailMove(sourceURL, destinationURL) {
                throw error
            }

            guard existingPaths.contains(sourceURL.path) else {
                throw TestMoveError.sourceMissing
            }
            guard !existingPaths.contains(destinationURL.path) else {
                throw TestMoveError.destinationExists
            }

            existingPaths.remove(sourceURL.path)
            existingPaths.insert(destinationURL.path)
        }
    }
}

private enum TestMoveError: LocalizedError {
    case primaryFailure
    case rollbackFailure
    case sourceMissing
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .primaryFailure:
            return "Injected primary move failure"
        case .rollbackFailure:
            return "Injected rollback move failure"
        case .sourceMissing:
            return "Injected source missing"
        case .destinationExists:
            return "Injected destination exists"
        }
    }
}
#endif
