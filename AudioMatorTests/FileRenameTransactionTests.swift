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
                    destinationURL: firstDestinationURL
                ),
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: secondSourceURL,
                    destinationURL: secondDestinationURL
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
                    destinationURL: firstDestinationURL
                ),
                FileRenameOperation(
                    id: UUID(),
                    sourceURL: secondSourceURL,
                    destinationURL: secondDestinationURL
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
}

private final class FaultInjectingRenameFileSystem: FileRenameFileSystem, @unchecked Sendable {
    typealias FailureRule = @Sendable (URL, URL) -> Error?

    private let lock = NSLock()
    private var existingPaths: Set<String>
    private let shouldFailMove: FailureRule

    init(existingURLs: [URL], shouldFailMove: @escaping FailureRule) {
        existingPaths = Set(existingURLs.map(\.path))
        self.shouldFailMove = shouldFailMove
    }

    func fileExists(at url: URL) -> Bool {
        lock.withLock { existingPaths.contains(url.path) }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try lock.withLock {
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
