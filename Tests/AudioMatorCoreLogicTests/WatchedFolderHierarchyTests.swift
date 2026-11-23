import Foundation
import XCTest
@testable import AudioMatorCoreLogic

final class WatchedFolderHierarchyTests: XCTestCase {
    func testBuildsNestedHierarchyFromPathsRegardlessOfTags() {
        let rootID = UUID()
        let rootURL = URL(fileURLWithPath: "/tmp/Rip Archive", isDirectory: true)
        let directoryURLs = [
            rootURL,
            rootURL.appendingPathComponent("Album B", isDirectory: true),
            rootURL.appendingPathComponent("Album A", isDirectory: true),
            rootURL.appendingPathComponent("Album A/Disc 10", isDirectory: true),
            rootURL.appendingPathComponent("Album A/Disc 2", isDirectory: true),
            rootURL.appendingPathComponent("Album A/Disc 1", isDirectory: true)
        ]
        let audioURLs = [
            rootURL.appendingPathComponent("Album A/Disc 1/01.flac"),
            rootURL.appendingPathComponent("Album A/Disc 2/01.flac"),
            rootURL.appendingPathComponent("Album A/Disc 10/01.flac"),
            rootURL.appendingPathComponent("Album B/01.flac")
        ]

        let hierarchy = WatchedFolderHierarchy.build(
            rootFolderID: rootID,
            rootURL: rootURL,
            directoryURLs: directoryURLs,
            audioFileURLs: audioURLs
        )

        XCTAssertEqual(hierarchy.rootChildren.map(\.displayName), ["Album A", "Album B"])
        let albumA = hierarchy.rootChildren[0]
        let albumB = hierarchy.rootChildren[1]
        XCTAssertTrue(albumA.hasChildren)
        XCTAssertFalse(albumB.hasChildren)
        XCTAssertEqual(albumA.children.map(\.displayName), ["Disc 1", "Disc 2", "Disc 10"])
        XCTAssertEqual(albumA.children[0].relativeDisplayPath, "Album A / Disc 1")
        XCTAssertEqual(
            albumA.children[0].selection,
            .watchedSubfolder(rootFolderID: rootID, relativePathKey: albumA.children[0].relativePathKey)
        )
    }

    func testRootAndSubfolderScopingAndPrefixCollisionSafety() {
        let rootID = UUID()
        let rootURL = URL(fileURLWithPath: "/tmp/Rip Archive", isDirectory: true)
        let looseFile = rootURL.appendingPathComponent("loose.flac")
        let disc1Track = rootURL.appendingPathComponent("Album A/Disc 1/01.flac")
        let disc2Track = rootURL.appendingPathComponent("Album A/Disc 2/01.flac")
        let disc10Track = rootURL.appendingPathComponent("Album A/Disc 10/01.flac")
        let deluxeTrack = rootURL.appendingPathComponent("Album A (Deluxe)/01.flac")
        let albumBTrack = rootURL.appendingPathComponent("Album B/01.flac")
        let outsideTrack = URL(fileURLWithPath: "/tmp/Other Folder/01.flac")

        let audioURLs = [looseFile, disc1Track, disc2Track, disc10Track, deluxeTrack, albumBTrack]
        let hierarchy = WatchedFolderHierarchy.build(
            rootFolderID: rootID,
            rootURL: rootURL,
            directoryURLs: [rootURL],
            audioFileURLs: audioURLs
        )

        let albumANode = hierarchy.rootChildren.first { $0.displayName == "Album A" }
        let disc1Node = albumANode?.children.first { $0.displayName == "Disc 1" }
        let albumBNode = hierarchy.rootChildren.first { $0.displayName == "Album B" }

        XCTAssertNotNil(albumANode)
        XCTAssertNotNil(disc1Node)
        XCTAssertNotNil(albumBNode)

        // Album A includes Disc 1, Disc 2, Disc 10, and excludes Album A (Deluxe), Album B, loose root files, and outside files.
        let albumAKey = albumANode!.relativePathKey
        XCTAssertTrue(hierarchy.containsFile(at: disc1Track, withinRelativePathKey: albumAKey))
        XCTAssertTrue(hierarchy.containsFile(at: disc2Track, withinRelativePathKey: albumAKey))
        XCTAssertTrue(hierarchy.containsFile(at: disc10Track, withinRelativePathKey: albumAKey))
        XCTAssertFalse(hierarchy.containsFile(at: deluxeTrack, withinRelativePathKey: albumAKey))
        XCTAssertFalse(hierarchy.containsFile(at: albumBTrack, withinRelativePathKey: albumAKey))
        XCTAssertFalse(hierarchy.containsFile(at: looseFile, withinRelativePathKey: albumAKey))
        XCTAssertFalse(hierarchy.containsFile(at: outsideTrack, withinRelativePathKey: albumAKey))

        // Disc 1 includes only Disc 1 and excludes Disc 2 and Disc 10.
        let disc1Key = disc1Node!.relativePathKey
        XCTAssertTrue(hierarchy.containsFile(at: disc1Track, withinRelativePathKey: disc1Key))
        XCTAssertFalse(hierarchy.containsFile(at: disc2Track, withinRelativePathKey: disc1Key))
        XCTAssertFalse(hierarchy.containsFile(at: disc10Track, withinRelativePathKey: disc1Key))
        XCTAssertFalse(hierarchy.containsFile(at: albumBTrack, withinRelativePathKey: disc1Key))

        // Empty relative key matches root and every descendant, never outside paths.
        XCTAssertTrue(hierarchy.containsFile(at: looseFile, withinRelativePathKey: ""))
        XCTAssertTrue(hierarchy.containsFile(at: disc1Track, withinRelativePathKey: ""))
        XCTAssertFalse(hierarchy.containsFile(at: outsideTrack, withinRelativePathKey: ""))
    }

    func testIntermediateAncestorsAreCreatedFromAudioPathsAlone() {
        let rootID = UUID()
        let rootURL = URL(fileURLWithPath: "/tmp/Rip Archive", isDirectory: true)
        let audioURL = rootURL.appendingPathComponent("Artist/Album A/Disc 1/01.wav")

        let hierarchy = WatchedFolderHierarchy.build(
            rootFolderID: rootID,
            rootURL: rootURL,
            directoryURLs: [],
            audioFileURLs: [audioURL]
        )

        XCTAssertEqual(hierarchy.rootChildren.map(\.displayName), ["Artist"])
        XCTAssertEqual(hierarchy.rootChildren[0].children.map(\.displayName), ["Album A"])
        XCTAssertEqual(hierarchy.rootChildren[0].children[0].children.map(\.displayName), ["Disc 1"])
        XCTAssertEqual(hierarchy.nodesByRelativePathKey.count, 3)
    }

    func testEmptyOnDiskSubfoldersAppearInHierarchy() {
        let rootID = UUID()
        let rootURL = URL(fileURLWithPath: "/tmp/Rip Archive", isDirectory: true)
        let emptyAlbum = rootURL.appendingPathComponent("Empty Album", isDirectory: true)
        let albumBTrack = rootURL.appendingPathComponent("Album B/01.flac")

        let hierarchy = WatchedFolderHierarchy.build(
            rootFolderID: rootID,
            rootURL: rootURL,
            directoryURLs: [rootURL, emptyAlbum],
            audioFileURLs: [albumBTrack]
        )

        XCTAssertEqual(hierarchy.rootChildren.map(\.displayName), ["Album B", "Empty Album"])
        let emptyNode = hierarchy.rootChildren.first { $0.displayName == "Empty Album" }!
        XCTAssertFalse(hierarchy.containsFile(at: albumBTrack, withinRelativePathKey: emptyNode.relativePathKey))
    }

    func testNearestSurvivingSelectionFallsBackUpwardWithinSameRoot() {
        let rootID = UUID()
        let rootURL = URL(fileURLWithPath: "/tmp/Rip Archive", isDirectory: true)

        let withDisc2Only = WatchedFolderHierarchy.build(
            rootFolderID: rootID,
            rootURL: rootURL,
            directoryURLs: [
                rootURL,
                rootURL.appendingPathComponent("Album A", isDirectory: true),
                rootURL.appendingPathComponent("Album A/Disc 2", isDirectory: true)
            ]
        )
        let albumAKey = withDisc2Only.rootChildren[0].relativePathKey
        let disc2Key = withDisc2Only.rootChildren[0].children[0].relativePathKey

        // Surviving subfolder remains selected.
        XCTAssertEqual(
            withDisc2Only.nearestSurvivingSelection(for: disc2Key),
            .watchedSubfolder(rootFolderID: rootID, relativePathKey: disc2Key)
        )

        // Disappeared nested subfolder falls back to surviving parent Album A.
        XCTAssertEqual(
            withDisc2Only.nearestSurvivingSelection(for: "\(albumAKey)/disc 1/bonus"),
            .watchedSubfolder(rootFolderID: rootID, relativePathKey: albumAKey)
        )

        // When Album A also disappears, falls back to the watched folder root.
        let withAlbumBOnly = WatchedFolderHierarchy.build(
            rootFolderID: rootID,
            rootURL: rootURL,
            directoryURLs: [
                rootURL,
                rootURL.appendingPathComponent("Album B", isDirectory: true)
            ]
        )
        XCTAssertEqual(
            withAlbumBOnly.nearestSurvivingSelection(for: "\(albumAKey)/disc 1"),
            .watchedFolder(rootID)
        )
    }

    func testHandlesRealSymlinkedRootAndUnicodeNormalization() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorHierarchy-\(UUID().uuidString)", isDirectory: true)
        let realRoot = baseURL.appendingPathComponent("RealRoot", isDirectory: true)
        let symlinkRoot = baseURL.appendingPathComponent("LinkRoot", isDirectory: true)
        let nfcAlbum = realRoot.appendingPathComponent("Caf\u{00E9}", isDirectory: true)
        let disc1 = nfcAlbum.appendingPathComponent("Disc 1", isDirectory: true)
        try FileManager.default.createDirectory(at: disc1, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: realRoot)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let nfdDisc1File = symlinkRoot
            .appendingPathComponent("Cafe\u{0301}", isDirectory: true)
            .appendingPathComponent("Disc 1", isDirectory: true)
            .appendingPathComponent("01.flac")

        let hierarchy = WatchedFolderHierarchy.build(
            rootFolderID: UUID(),
            rootURL: symlinkRoot,
            directoryURLs: [realRoot, nfcAlbum, disc1],
            audioFileURLs: [nfdDisc1File]
        )

        XCTAssertEqual(hierarchy.rootChildren.count, 1)
        XCTAssertEqual(hierarchy.rootChildren[0].displayName, "Caf\u{00E9}")
        XCTAssertEqual(hierarchy.rootChildren[0].children.map(\.displayName), ["Disc 1"])
        XCTAssertTrue(
            hierarchy.containsFile(
                at: nfdDisc1File,
                withinRelativePathKey: hierarchy.rootChildren[0].relativePathKey
            )
        )
        XCTAssertTrue(
            hierarchy.containsFile(
                at: nfdDisc1File,
                withinRelativePathKey: hierarchy.rootChildren[0].children[0].relativePathKey
            )
        )

        let realTrack = disc1.appendingPathComponent("01.flac")
        let outsideTrack = baseURL.appendingPathComponent("outside.flac")
        let aliasIntoDisc = baseURL.appendingPathComponent("alias.flac")
        let aliasOutOfDisc = disc1.appendingPathComponent("outside-alias.flac")
        try Data().write(to: realTrack)
        try Data().write(to: outsideTrack)
        try FileManager.default.createSymbolicLink(at: aliasIntoDisc, withDestinationURL: realTrack)
        try FileManager.default.createSymbolicLink(at: aliasOutOfDisc, withDestinationURL: outsideTrack)

        let discKey = hierarchy.rootChildren[0].children[0].relativePathKey
        XCTAssertTrue(hierarchy.containsFile(at: aliasIntoDisc, withinRelativePathKey: discKey))
        XCTAssertFalse(hierarchy.containsFile(at: aliasOutOfDisc, withinRelativePathKey: discKey))
    }

    func testSidebarSelectionSourceModeAndWatchedRootFolderID() {
        let rootID = UUID()
        let subfolder = SidebarSelection.watchedSubfolder(rootFolderID: rootID, relativePathKey: "album a")

        XCTAssertEqual(SidebarSelection.quickImport.sourceMode, .quickImport)
        XCTAssertNil(SidebarSelection.quickImport.watchedRootFolderID)

        XCTAssertEqual(SidebarSelection.watchedLibrary.sourceMode, .watchedFolders)
        XCTAssertNil(SidebarSelection.watchedLibrary.watchedRootFolderID)

        XCTAssertEqual(SidebarSelection.watchedFolder(rootID).sourceMode, .watchedFolders)
        XCTAssertEqual(SidebarSelection.watchedFolder(rootID).watchedRootFolderID, rootID)

        XCTAssertEqual(subfolder.sourceMode, .watchedFolders)
        XCTAssertEqual(subfolder.watchedRootFolderID, rootID)
    }
}
