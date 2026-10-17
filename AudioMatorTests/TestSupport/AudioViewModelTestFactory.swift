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
        artworkLookupOperationTimeout: Duration = .seconds(30)
    ) -> AudioViewModel {
        let suiteName = "AudioMatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorTests-\(UUID().uuidString)-issues.json")

        return AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: metadataPipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: logURL),
            artworkLookupService: artworkLookupService,
            artworkLookupOperationTimeout: artworkLookupOperationTimeout,
            conflictPolicyDefaults: defaults
        )
    }
}
