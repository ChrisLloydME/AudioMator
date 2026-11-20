import Foundation
import XCTest
@testable import AudioMator

/// Native probes for the exclusive same-directory move primitive on a disposable
/// temporary directory. These prove `RENAME_EXCL` behaviour (no overwrite) and the
/// case-only-after-staging assumption used by the journal design; they never touch
/// a real library.
nonisolated final class RenameFileSystemProbeTests: XCTestCase {
    private var rootURL: URL!
    private let fileSystem = LocalRenameFileSystem()

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRenameFSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testExclusiveMoveDoesNotOverwriteOccupiedDestination() throws {
        let sourceURL = rootURL.appendingPathComponent("source.wav")
        let occupiedURL = rootURL.appendingPathComponent("occupied.wav")
        try Data("source-bytes".utf8).write(to: sourceURL)
        try Data("foreign-bytes".utf8).write(to: occupiedURL)

        let handle = try fileSystem.openDirectory(at: rootURL)
        let supported = try fileSystem.volumeSupportsExclusiveRename(forDirectoryAt: rootURL)

        if supported {
            XCTAssertThrowsError(
                try fileSystem.exclusiveMove(
                    named: sourceURL.lastPathComponent,
                    to: occupiedURL.lastPathComponent,
                    in: handle
                )
            ) { error in
                XCTAssertEqual(error as? RenameFileSystemError, .destinationOccupied)
            }
            XCTAssertEqual(try String(contentsOf: occupiedURL, encoding: .utf8), "foreign-bytes")
            XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), "source-bytes")
        } else {
            XCTAssertThrowsError(
                try fileSystem.exclusiveMove(
                    named: sourceURL.lastPathComponent,
                    to: occupiedURL.lastPathComponent,
                    in: handle
                )
            ) { error in
                XCTAssertEqual(error as? RenameFileSystemError, .exclusiveRenameUnsupported)
            }
        }
    }

    func testExclusiveMoveToFreeNameSucceedsAndVerifiesIdentity() throws {
        let supported = try fileSystem.volumeSupportsExclusiveRename(forDirectoryAt: rootURL)
        XCTAssertTrue(
            supported,
            "The disposable test directory volume must support exclusive renaming for the F2 product contract"
        )

        let sourceURL = rootURL.appendingPathComponent("source.wav")
        let destinationURL = rootURL.appendingPathComponent("destination.wav")
        try Data("payload".utf8).write(to: sourceURL)
        let expectedIdentity = try fileSystem.entryIdentity(at: sourceURL)

        let handle = try fileSystem.openDirectory(at: rootURL)
        try fileSystem.exclusiveMove(
            named: sourceURL.lastPathComponent,
            to: destinationURL.lastPathComponent,
            in: handle
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try String(contentsOf: destinationURL, encoding: .utf8), "payload")
        let movedIdentity = try XCTUnwrap(
            try fileSystem.entryIdentity(named: destinationURL.lastPathComponent, in: handle)
        )
        XCTAssertEqual(movedIdentity.device, expectedIdentity.device)
        XCTAssertEqual(movedIdentity.inode, expectedIdentity.inode)
        XCTAssertEqual(movedIdentity.kind, expectedIdentity.kind)
    }

    func testCaseOnlyRenameAfterStagingSucceedsOnSupportedVolume() throws {
        let supported = try fileSystem.volumeSupportsExclusiveRename(forDirectoryAt: rootURL)
        let sourceURL = rootURL.appendingPathComponent("SongTitle.wav")
        let stagedURL = RenameStagingName.url(
            for: sourceURL,
            operationID: UUID(uuidString: "5B2E4A76-4A4C-4D6C-9B3C-1D2E3F4A5B6C")!,
            index: 0
        )
        let intendedURL = rootURL.appendingPathComponent("songtitle.wav")
        try Data("case-payload".utf8).write(to: sourceURL)

        let handle = try fileSystem.openDirectory(at: rootURL)
        guard supported else {
            XCTAssertThrowsError(
                try fileSystem.exclusiveMove(
                    named: sourceURL.lastPathComponent,
                    to: stagedURL.lastPathComponent,
                    in: handle
                )
            ) { error in
                XCTAssertEqual(error as? RenameFileSystemError, .exclusiveRenameUnsupported)
            }
            return
        }

        try fileSystem.exclusiveMove(
            named: sourceURL.lastPathComponent,
            to: stagedURL.lastPathComponent,
            in: handle
        )
        // The staged move frees the original folded name, so the final move to a
        // differently-cased spelling is an exclusive move to a free name.
        try fileSystem.exclusiveMove(
            named: stagedURL.lastPathComponent,
            to: intendedURL.lastPathComponent,
            in: handle
        )

        XCTAssertEqual(try String(contentsOf: intendedURL, encoding: .utf8), "case-payload")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
        let actualName = try fileSystem.actualEntryName(
            inDirectoryAt: rootURL,
            matching: intendedURL.lastPathComponent
        )
        XCTAssertEqual(actualName, intendedURL.lastPathComponent)
    }

    func testHeldDirectoryRejectsReplacedAuthorizedPath() throws {
        let directoryURL = rootURL.appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let handle = try fileSystem.openDirectory(at: directoryURL)
        XCTAssertTrue(fileSystem.authorizedPathStillIdentifiesDirectory(handle))

        let movedURL = rootURL.appendingPathComponent("MovedAway", isDirectory: true)
        try FileManager.default.moveItem(at: directoryURL, to: movedURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        XCTAssertFalse(
            fileSystem.authorizedPathStillIdentifiesDirectory(handle),
            "A recreated path must not identify the originally held directory"
        )
    }
}
