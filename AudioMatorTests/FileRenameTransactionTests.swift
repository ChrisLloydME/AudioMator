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

    func testRollbackDoesNotMoveAReplacementFileIntoTheOriginalPath() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameReplacementTests-\(UUID().uuidString)", isDirectory: true)
        let firstSourceURL = rootURL.appendingPathComponent("first.mp3")
        let firstDestinationURL = rootURL.appendingPathComponent("renamed-first.mp3")
        let secondSourceURL = rootURL.appendingPathComponent("second.mp3")
        let secondDestinationURL = rootURL.appendingPathComponent("renamed-second.mp3")
        let fileSystem = DestinationReplacingRenameFileSystem(
            firstSourceURL: firstSourceURL,
            firstDestinationURL: firstDestinationURL,
            secondSourceURL: secondSourceURL,
            secondDestinationURL: secondDestinationURL
        )

        let result = executeFileRenameTransaction(
            [
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: firstSourceURL,
                    destinationURL: firstDestinationURL,
                    expectedFileFingerprint: fileSystem.firstExpectedFingerprint
                ),
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: secondSourceURL,
                    destinationURL: secondDestinationURL,
                    expectedFileFingerprint: fileSystem.secondExpectedFingerprint
                )
            ],
            fileSystem: fileSystem
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Expected the second finalization failure to start rollback.")
        }

        XCTAssertFalse(fileSystem.fileExists(at: firstSourceURL))
        XCTAssertTrue(fileSystem.replacementRemains(at: firstDestinationURL))
        XCTAssertEqual(failure.recoveryItems.count, 1)
        XCTAssertEqual(failure.recoveryItems.first?.originalURL, firstSourceURL)
        XCTAssertTrue(failure.recoveryItems.first?.finalLocations.isEmpty == true)
        XCTAssertTrue(failure.message.contains("Recovery required"))
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

private final class DestinationReplacingRenameFileSystem: FileRenameFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private let firstDestinationURL: URL
    private let secondDestinationURL: URL
    private var fingerprintsByPath: [String: AudioFileFingerprint]

    let firstExpectedFingerprint: AudioFileFingerprint
    let secondExpectedFingerprint: AudioFileFingerprint

    init(
        firstSourceURL: URL,
        firstDestinationURL: URL,
        secondSourceURL: URL,
        secondDestinationURL: URL
    ) {
        self.firstDestinationURL = firstDestinationURL
        self.secondDestinationURL = secondDestinationURL
        firstExpectedFingerprint = Self.fingerprint(for: firstSourceURL, fileNumber: 101)
        secondExpectedFingerprint = Self.fingerprint(for: secondSourceURL, fileNumber: 202)
        fingerprintsByPath = [
            firstSourceURL.path: firstExpectedFingerprint,
            secondSourceURL.path: secondExpectedFingerprint
        ]
    }

    func fileExists(at url: URL) -> Bool {
        lock.withLock { fingerprintsByPath[url.path] != nil }
    }

    func fingerprint(at url: URL) throws -> AudioFileFingerprint {
        try lock.withLock {
            guard let fingerprint = fingerprintsByPath[url.path] else {
                throw TestMoveError.sourceMissing
            }
            return fingerprint
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try lock.withLock {
            if destinationURL == secondDestinationURL {
                throw TestMoveError.primaryFailure
            }
            guard let sourceFingerprint = fingerprintsByPath[sourceURL.path] else {
                throw TestMoveError.sourceMissing
            }
            guard fingerprintsByPath[destinationURL.path] == nil else {
                throw TestMoveError.destinationExists
            }

            fingerprintsByPath[sourceURL.path] = nil
            fingerprintsByPath[destinationURL.path] = Self.moving(
                sourceFingerprint,
                to: destinationURL
            )

            if destinationURL == firstDestinationURL {
                fingerprintsByPath[destinationURL.path] = Self.fingerprint(
                    for: destinationURL,
                    fileNumber: 999
                )
            }
        }
    }

    func replacementRemains(at url: URL) -> Bool {
        lock.withLock { fingerprintsByPath[url.path]?.fileNumber == 999 }
    }

    private static func moving(_ fingerprint: AudioFileFingerprint, to url: URL) -> AudioFileFingerprint {
        AudioFileFingerprint(
            normalizedPath: url.standardizedFileURL.path,
            fileSize: fingerprint.fileSize,
            contentModificationDate: fingerprint.contentModificationDate,
            fileSystemNumber: fingerprint.fileSystemNumber,
            fileNumber: fingerprint.fileNumber
        )
    }

    private static func fingerprint(for url: URL, fileNumber: UInt64) -> AudioFileFingerprint {
        AudioFileFingerprint(
            normalizedPath: url.standardizedFileURL.path,
            fileSize: 64,
            contentModificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSystemNumber: 1,
            fileNumber: fileNumber
        )
    }
}

private final class FaultInjectingRenameFileSystem: FileRenameFileSystem, @unchecked Sendable {
    typealias FailureRule = @Sendable (URL, URL) -> Error?

    private let lock = NSLock()
    private var existingPaths: Set<String>
    private var fingerprintsByPath: [String: AudioFileFingerprint]
    private let shouldFailMove: FailureRule
    private(set) var moveCount = 0

    init(
        existingURLs: [URL],
        fingerprints: [URL: AudioFileFingerprint] = [:],
        shouldFailMove: @escaping FailureRule
    ) {
        existingPaths = Set(existingURLs.map(\.path))
        fingerprintsByPath = Dictionary(uniqueKeysWithValues: existingURLs.map {
            ($0.path, AudioFileTestFactory.fingerprint(for: $0))
        })
        for (url, fingerprint) in fingerprints {
            fingerprintsByPath[url.path] = fingerprint
        }
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
            return try XCTUnwrap(fingerprintsByPath[url.path])
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
            let sourceFingerprint = fingerprintsByPath.removeValue(forKey: sourceURL.path)
            if let sourceFingerprint {
                fingerprintsByPath[destinationURL.path] = AudioFileFingerprint(
                    normalizedPath: destinationURL.standardizedFileURL.path,
                    fileSize: sourceFingerprint.fileSize,
                    contentModificationDate: sourceFingerprint.contentModificationDate,
                    fileSystemNumber: sourceFingerprint.fileSystemNumber,
                    fileNumber: sourceFingerprint.fileNumber
                )
            }
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
