import Foundation
@testable import AudioMator

/// Creates a view model with isolated defaults and save-issue storage.
///
/// The app-hosted test bundle runs inside AudioMator.app, so the production
/// convenience initializer would otherwise restore the developer's watched
/// folders, start directory monitors, and write the real save-issue log.
@MainActor
enum AudioViewModelTestFactory {
    static func make(
        metadataPipeline: any AudioMetadataPipeline,
        artworkLookupService: any iTunesArtworkServicing = iTunesArtworkService(),
        artworkLookupOperationTimeout: Duration = .seconds(30),
        saveIssueLogStore: SaveIssueLogStore? = nil,
        moveReadbackTimeout: Duration = .seconds(60),
        renameFileSystem: any RenameFileSystem = LocalRenameFileSystem(),
        renameJournalStore: (any RenameJournalStoring)? = nil,
        writableFixtures: [AudioFile] = []
    ) -> AudioViewModel {
        let suiteName = "AudioMatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let journalStore = renameJournalStore ?? LocalRenameJournalStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorTestsRenameJournal-\(UUID().uuidString)", isDirectory: true)
        )
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: metadataPipeline,
            saveIssueLogStore: saveIssueLogStore ?? makeIssueLogStore(),
            artworkLookupService: artworkLookupService,
            artworkLookupOperationTimeout: artworkLookupOperationTimeout,
            conflictPolicyDefaults: defaults,
            moveReadbackTimeout: moveReadbackTimeout,
            renameFileSystem: renameFileSystem,
            renameJournalStore: journalStore,
            renameJournalAutoClassification: false
        )
        if !writableFixtures.isEmpty {
            let approvedDirectories = Set(writableFixtures.map {
                FileSystemPathSemantics.key(for: $0.url.deletingLastPathComponent())
            })
            viewModel.mutationDirectoryAccessRequester = { directory in
                guard approvedDirectories.contains(FileSystemPathSemantics.key(for: directory)) else {
                    return "Missing test authorization for mutation directory: \(directory.path)"
                }
                return nil
            }
        }
        return viewModel
    }

    static func makeIssueLogStore() -> SaveIssueLogStore {
        SaveIssueLogStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorTests-\(UUID().uuidString)-issues.json"))
    }
}
