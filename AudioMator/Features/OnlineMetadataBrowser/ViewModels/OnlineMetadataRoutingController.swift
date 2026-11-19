import Foundation

/// Routes the main-window Online Metadata entry points. Local seeding happens here; the
/// only request handoff is the explicit Find-in-MusicBrainz presentation intent, which the
/// window session consumes exactly once.
@MainActor
final class OnlineMetadataRoutingController {
    private let musicBrainzStore: MusicBrainzBrowserStore
    private let lrclibStore: LRCLIBLyricsBrowserStore
    private let activationStore: OnlineMetadataActivationStore

    init(
        musicBrainzStore: MusicBrainzBrowserStore,
        lrclibStore: LRCLIBLyricsBrowserStore,
        activationStore: OnlineMetadataActivationStore
    ) {
        self.musicBrainzStore = musicBrainzStore
        self.lrclibStore = lrclibStore
        self.activationStore = activationStore
    }

    /// Generic Online Metadata command: replace the local provider state and present the
    /// source picker. No provider client is invoked.
    func openGeneric(selectedFiles: [AudioFile], openWindow: () -> Void) {
        let seed = OnlineMetadataSearchSeedBuilder.musicBrainzSeed(from: selectedFiles)
        replaceLocalProviderState(selectedFiles: selectedFiles, musicBrainzSeed: seed)
        activationStore.publish(.showProviderPicker)
        openWindow()
    }

    /// Explicit Find in MusicBrainz command: seed locally, then hand the captured query to
    /// the window through a consume-once intent. Returns false (and does nothing) when the
    /// selection cannot produce a seed, preserving the current empty-selection behavior.
    @discardableResult
    func findInMusicBrainz(selectedFiles: [AudioFile], openWindow: () -> Void) -> Bool {
        guard let seed = OnlineMetadataSearchSeedBuilder.musicBrainzSeed(from: selectedFiles) else {
            return false
        }
        replaceLocalProviderState(selectedFiles: selectedFiles, musicBrainzSeed: seed)
        activationStore.publish(.findInMusicBrainz(seed))
        openWindow()
        return true
    }

    /// A replacement command follows the AM-08 ownership policy explicitly: the MusicBrainz
    /// store cancels its search in `apply(seed:)`, and the LRCLIB store's N1 `seed(from:)`
    /// invalidates the session generation, cancels outstanding lookups and every write that
    /// has not crossed the admission boundary. No unrelated job is silently reseeded.
    private func replaceLocalProviderState(
        selectedFiles: [AudioFile],
        musicBrainzSeed: MusicBrainzSearchSeed?
    ) {
        // A replacement command clears prior published results before seeding the current
        // selection so a reused window cannot show a stale result set under new fields.
        musicBrainzStore.resetToDefault()
        musicBrainzStore.apply(seed: musicBrainzSeed)
        lrclibStore.seed(from: selectedFiles)
    }
}
