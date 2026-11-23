import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

#if os(macOS)
nonisolated final class WatchedFolderHierarchyWorkflowTests: XCTestCase {
    @MainActor
    func testAcceptanceExampleUntaggedFLACHierarchyScopingAndBatchEditLeavesOtherAlbumUntouched() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let rootURL = try makeTemporaryDirectory(prefix: "AudioMatorRipArchive")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let albumADisc1Track1 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 1/01.flac"),
            pipeline: pipeline
        )
        let albumADisc1Track2 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 1/02.flac"),
            pipeline: pipeline
        )
        let albumADisc2Track1 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 2/01.flac"),
            pipeline: pipeline
        )
        let albumBTrack1 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album B/01.flac"),
            pipeline: pipeline
        )
        let albumBTrack2 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album B/02.flac"),
            pipeline: pipeline
        )
        let albumBTrack1OriginalBytes = try Data(contentsOf: albumBTrack1)
        let albumBTrack2OriginalBytes = try Data(contentsOf: albumBTrack2)

        let (viewModel, folder, cleanup) = try makeWatchedViewModel(rootURL: rootURL, pipeline: pipeline)
        defer { cleanup() }

        viewModel.setSidebarSelection(.watchedFolder(folder.id))
        let loadedAll = try await waitUntil {
            viewModel.files.count == 5 && viewModel.watchedFolderHierarchy(for: folder.id) != nil
        }
        XCTAssertTrue(loadedAll, "Expected all 5 untagged FLAC files and hierarchy to load")

        // Verify sidebar hierarchy built from paths even though all tracks are untagged.
        XCTAssertTrue(viewModel.files.allSatisfy { $0.album.isEmpty && $0.title.isEmpty && $0.artist.isEmpty })
        let hierarchy = try XCTUnwrap(viewModel.watchedFolderHierarchy(for: folder.id))
        XCTAssertEqual(hierarchy.rootChildren.map(\.displayName), ["Album A", "Album B"])
        let albumANode = hierarchy.rootChildren[0]
        let albumBNode = hierarchy.rootChildren[1]
        XCTAssertEqual(albumANode.children.map(\.displayName), ["Disc 1", "Disc 2"])
        XCTAssertTrue(albumBNode.children.isEmpty)
        let disc1Node = albumANode.children[0]

        // 1. Selecting Rip Archive root shows tracks from both albums.
        XCTAssertEqual(
            Set(viewModel.files.map { FileSystemPathSemantics.key(for: $0.url) }),
            Set([albumADisc1Track1, albumADisc1Track2, albumADisc2Track1, albumBTrack1, albumBTrack2].map(FileSystemPathSemantics.key(for:)))
        )

        // 2. Selecting Disc 1 shows only the tracks on Disc 1.
        viewModel.setSidebarSelection(disc1Node.selection)
        XCTAssertEqual(
            Set(viewModel.files.map { FileSystemPathSemantics.key(for: $0.url) }),
            Set([albumADisc1Track1, albumADisc1Track2].map(FileSystemPathSemantics.key(for:)))
        )

        // 3. Selecting Album A shows tracks from both discs and excludes Album B.
        viewModel.setSidebarSelection(albumANode.selection)
        XCTAssertEqual(
            Set(viewModel.files.map { FileSystemPathSemantics.key(for: $0.url) }),
            Set([albumADisc1Track1, albumADisc1Track2, albumADisc2Track1].map(FileSystemPathSemantics.key(for:)))
        )
        XCTAssertTrue(viewModel.selectedAudioIDs.isEmpty, "Selecting a sidebar folder only changes browsing scope")

        // 4. Selecting all visible tracks in Album A (Command-A flow) cannot include Album B.
        let albumBCommittedIDs = Set(
            [albumBTrack1, albumBTrack2].compactMap { url in
                viewModel.fileIDsByKey[FileSystemPathSemantics.key(for: url)]
            }
        )
        XCTAssertEqual(albumBCommittedIDs.count, 2)
        let albumAVisibleIDs = Set(viewModel.files.map(\.id))
        viewModel.setSelectedAudioIDs(albumAVisibleIDs.union(albumBCommittedIDs))
        XCTAssertEqual(viewModel.selectedAudioIDs, albumAVisibleIDs)
        XCTAssertTrue(viewModel.selectedAudioIDs.isDisjoint(with: albumBCommittedIDs))

        // 5. Batch edit through Inspector writes shared Album tag to both discs and leaves Album B untouched.
        viewModel.multiEdit?.setText("Album A Shared", for: .album)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        ToolbarEditCommands.performSaveEdits(using: viewModel)
        let saveFinished = try await waitUntil(timeoutSeconds: 10) {
            viewModel.metadataSaveProgress == nil && !viewModel.hasUnsavedInspectorChanges
        }
        XCTAssertTrue(saveFinished, "Batch save should complete and clear dirty state")

        for url in [albumADisc1Track1, albumADisc1Track2, albumADisc2Track1] {
            let reloaded = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(reloaded.album, "Album A Shared")
        }
        for url in [albumBTrack1, albumBTrack2] {
            let reloaded = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(reloaded.album, "")
        }
        XCTAssertEqual(try Data(contentsOf: albumBTrack1), albumBTrack1OriginalBytes)
        XCTAssertEqual(try Data(contentsOf: albumBTrack2), albumBTrack2OriginalBytes)
    }

    @MainActor
    func testSwitchingToSubfolderPrunesOutOfScopeTrackSelectionBeforeBatchEdit() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let rootURL = try makeTemporaryDirectory(prefix: "AudioMatorScopePrune")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let albumATrack1 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 1/01.flac"),
            pipeline: pipeline
        )
        let albumATrack2 = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 2/01.flac"),
            pipeline: pipeline
        )
        let albumBTrack = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album B/01.flac"),
            pipeline: pipeline
        )
        let albumBOriginalBytes = try Data(contentsOf: albumBTrack)

        let (viewModel, folder, cleanup) = try makeWatchedViewModel(rootURL: rootURL, pipeline: pipeline)
        defer { cleanup() }

        viewModel.setSidebarSelection(.watchedFolder(folder.id))
        let loaded = try await waitUntil {
            viewModel.files.count == 3 && viewModel.watchedFolderHierarchy(for: folder.id) != nil
        }
        XCTAssertTrue(loaded)

        // Select every track at the root, including Album B.
        viewModel.setSelectedAudioIDs(Set(viewModel.files.map(\.id)))
        XCTAssertEqual(viewModel.selectedAudioIDs.count, 3)

        // Narrow browsing scope to Album A: Album B must be pruned out of track selection and draft targets.
        let albumANode = try XCTUnwrap(
            viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.first { $0.displayName == "Album A" }
        )
        viewModel.setSidebarSelection(albumANode.selection)
        XCTAssertEqual(viewModel.files.count, 2)
        XCTAssertEqual(viewModel.selectedAudioIDs, Set(viewModel.files.map(\.id)))
        XCTAssertEqual(Set(viewModel.inspectorDraft?.targetIDs ?? []), Set(viewModel.files.map(\.id)))

        viewModel.multiEdit?.setText("Only Album A", for: .album)
        ToolbarEditCommands.performSaveEdits(using: viewModel)
        let saveFinished = try await waitUntil(timeoutSeconds: 10) {
            viewModel.metadataSaveProgress == nil && !viewModel.hasUnsavedInspectorChanges
        }
        XCTAssertTrue(saveFinished)

        for url in [albumATrack1, albumATrack2] {
            let reloaded = try await pipeline.loadAudioFile(at: url, id: UUID())
            XCTAssertEqual(reloaded.album, "Only Album A")
        }
        XCTAssertEqual(try Data(contentsOf: albumBTrack), albumBOriginalBytes)
    }

    @MainActor
    func testDisappearedSelectedSubfolderFallsBackToSurvivingParentThenRootOnRefresh() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let rootURL = try makeTemporaryDirectory(prefix: "AudioMatorHierarchyFallback")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let disc1URL = rootURL.appendingPathComponent("Album A/Disc 1", isDirectory: true)
        let albumAURL = rootURL.appendingPathComponent("Album A", isDirectory: true)
        _ = try await makeUntaggedFLAC(at: disc1URL.appendingPathComponent("01.flac"), pipeline: pipeline)
        let disc2Track = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 2/01.flac"),
            pipeline: pipeline
        )
        let albumBTrack = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album B/01.flac"),
            pipeline: pipeline
        )

        let (viewModel, folder, cleanup) = try makeWatchedViewModel(rootURL: rootURL, pipeline: pipeline)
        defer { cleanup() }

        let loaded = try await waitUntil {
            viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.count == 2
        }
        XCTAssertTrue(loaded)

        let albumANode = try XCTUnwrap(
            viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.first { $0.displayName == "Album A" }
        )
        let disc1Node = try XCTUnwrap(albumANode.children.first { $0.displayName == "Disc 1" })

        viewModel.setSidebarSelection(disc1Node.selection)
        XCTAssertEqual(viewModel.activeSidebarSelection, disc1Node.selection)
        XCTAssertEqual(viewModel.files.count, 1)

        // Delete Disc 1 on disk and refresh: selection falls back to surviving parent Album A.
        try FileManager.default.removeItem(at: disc1URL)
        viewModel.refreshWatchedFolder(id: folder.id)

        let fellBackToAlbumA = try await waitUntil {
            viewModel.activeSidebarSelection == albumANode.selection
        }
        XCTAssertTrue(fellBackToAlbumA, "Expected fallback to Album A, got \(viewModel.activeSidebarSelection)")
        XCTAssertEqual(
            viewModel.files.map { FileSystemPathSemantics.key(for: $0.url) },
            [FileSystemPathSemantics.key(for: disc2Track)]
        )

        // Delete Album A on disk and refresh: selection falls back to Rip Archive root.
        try FileManager.default.removeItem(at: albumAURL)
        viewModel.refreshWatchedFolder(id: folder.id)

        let fellBackToRoot = try await waitUntil {
            viewModel.activeSidebarSelection == .watchedFolder(folder.id)
        }
        XCTAssertTrue(fellBackToRoot, "Expected fallback to watched root, got \(viewModel.activeSidebarSelection)")
        XCTAssertEqual(
            viewModel.files.map { FileSystemPathSemantics.key(for: $0.url) },
            [FileSystemPathSemantics.key(for: albumBTrack)]
        )
    }

    @MainActor
    func testPendingSidebarSelectionResolvesToCurrentParentAfterRequestedSubfolderDisappears() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let rootURL = try makeTemporaryDirectory(prefix: "AudioMatorPendingSidebarSelection")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let disc1URL = rootURL.appendingPathComponent("Album A/Disc 1", isDirectory: true)
        try FileManager.default.createDirectory(at: disc1URL, withIntermediateDirectories: true)
        _ = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 2/01.flac"),
            pipeline: pipeline
        )

        let (viewModel, folder, cleanup) = try makeWatchedViewModel(rootURL: rootURL, pipeline: pipeline)
        defer { cleanup() }
        let suiteName = "AudioMatorPendingSidebarSelection.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = SharedState(userDefaults: defaults)

        let loaded = try await waitUntil {
            viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.first?.children.count == 2
        }
        XCTAssertTrue(loaded)

        let album = try XCTUnwrap(viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.first)
        let disc1 = try XCTUnwrap(album.children.first { $0.displayName == "Disc 1" })
        ContentView.commitSidebarSelection(album.selection, using: viewModel, state: state)
        let track = try XCTUnwrap(viewModel.files.first)
        viewModel.setSelectedAudioIDs([track.id])
        viewModel.edit?.album = "Unsaved album"
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        var confirmSelection: (() -> Void)?
        ContentView.performSidebarSelectionChange(
            hasUnsavedInspectorChanges: viewModel.hasUnsavedInspectorChanges,
            suppressesDiscardWarning: false,
            requestDiscardConfirmation: { confirmSelection = $0 },
            discardInspectorEdits: viewModel.cancelEditing
        ) {
            ContentView.commitSidebarSelection(disc1.selection, using: viewModel, state: state)
        }
        XCTAssertEqual(state.selectedSidebarItem, album.selection)

        try FileManager.default.removeItem(at: disc1URL)
        viewModel.refreshWatchedFolder(id: folder.id)
        let removedDisc = try await waitUntil {
            viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.first?.children.count == 1
        }
        XCTAssertTrue(removedDisc)
        XCTAssertEqual(viewModel.activeSidebarSelection, album.selection)

        let confirm = try XCTUnwrap(confirmSelection)
        confirm()

        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(state.selectedSidebarItem, album.selection)
        XCTAssertEqual(viewModel.activeSidebarSelection, album.selection)
        XCTAssertEqual(viewModel.files.map(\.id), [track.id])
    }

    @MainActor
    func testRemovingWatchedFolderWhileSubfolderSelectedClearsHierarchyAndNormalizesSelection() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let rootURL = try makeTemporaryDirectory(prefix: "AudioMatorHierarchyRemove")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        _ = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/01.flac"),
            pipeline: pipeline
        )

        let (viewModel, folder, cleanup) = try makeWatchedViewModel(rootURL: rootURL, pipeline: pipeline)
        defer { cleanup() }

        let loaded = try await waitUntil {
            viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.count == 1
        }
        XCTAssertTrue(loaded)

        let albumANode = try XCTUnwrap(viewModel.watchedFolderHierarchy(for: folder.id)?.rootChildren.first)
        viewModel.setSidebarSelection(albumANode.selection)
        XCTAssertEqual(viewModel.activeSidebarSelection, albumANode.selection)

        viewModel.removeWatchedFolder(id: folder.id)
        XCTAssertNil(viewModel.watchedFolderHierarchy(for: folder.id))
        XCTAssertEqual(viewModel.activeSidebarSelection, .watchedLibrary)
        XCTAssertTrue(viewModel.files.isEmpty)
    }

    @MainActor
    func testQuickImportRemainsFlatWithoutWatchedFolderHierarchy() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        let rootURL = try makeTemporaryDirectory(prefix: "AudioMatorQuickImportFlat")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let trackURL = try await makeUntaggedFLAC(
            at: rootURL.appendingPathComponent("Album A/Disc 1/01.flac"),
            pipeline: pipeline
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let loadedFile = try await pipeline.loadAudioFile(at: trackURL, id: UUID())
        viewModel.mergeQuickImportFiles([loadedFile])
        viewModel.setSidebarSelection(.quickImport)

        XCTAssertTrue(viewModel.watchedFolderHierarchies.isEmpty)
        XCTAssertEqual(viewModel.activeSidebarSelection, .quickImport)
        XCTAssertEqual(viewModel.files.map(\.id), [loadedFile.id])
    }

    // MARK: - Helpers

    @MainActor
    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func makeUntaggedFLAC(at destinationURL: URL, pipeline: TagLibAudioMetadataPipeline) async throws -> URL {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let bundle = Bundle(for: Self.self)
        let sourceURL = try XCTUnwrap(
            bundle.url(forResource: "testAudioFile", withExtension: "flac", subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: "testAudioFile", withExtension: "flac")
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let loaded = try await pipeline.loadAudioFile(at: destinationURL, id: UUID())
        _ = try pipeline.eraseAllMetadata(at: destinationURL, expectedVersion: loaded.metadataFileVersion)
        return destinationURL
    }

    @MainActor
    private func makeWatchedViewModel(
        rootURL: URL,
        pipeline: any AudioMetadataPipeline
    ) throws -> (AudioViewModel, WatchedFolder, () -> Void) {
        let suiteName = "AudioMatorWatchedHierarchyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let folderStore = WatchedFolderStore(userDefaults: defaults)
        let folder = try folderStore.makeFolder(from: rootURL)
        folderStore.saveFolders([folder])

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorWatchedHierarchy-\(UUID().uuidString).json")
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorWatchedHierarchyJournal-\(UUID().uuidString)", isDirectory: true)
        let viewModel = AudioViewModel(
            watchedFolderStore: folderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: logURL),
            conflictPolicyDefaults: defaults,
            renameJournalStore: LocalRenameJournalStore(directoryURL: journalURL),
            renameJournalAutoClassification: false
        )
        viewModel.mutationDirectoryAccessRequester = { _ in nil }

        let cleanup = {
            viewModel.removeWatchedFolders(ids: Set(viewModel.watchedFolders.map(\.id)))
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: logURL)
            try? FileManager.default.removeItem(at: journalURL)
        }
        return (viewModel, folder, cleanup)
    }

    @MainActor
    private func waitUntil(
        timeoutSeconds: TimeInterval = 5,
        condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }
}
#endif
