import Foundation
import Combine

/// Owns the singleton window's presented provider and consumes activation intents. It is
/// the only place that turns a presentation intent into a provider request, so onAppear,
/// onChange and source selection cannot both hand off the same explicit action.
@MainActor
final class OnlineMetadataBrowserSessionModel: ObservableObject {
    @Published private(set) var selectedSource: MetadataBrowserSource?

    private let activationStore: OnlineMetadataActivationStore
    private let musicBrainzStore: MusicBrainzBrowserStore
    private let lrclibStore: LRCLIBLyricsBrowserStore
    private let selectedFilesProvider: () -> [AudioFile]

    init(
        initialSource: MetadataBrowserSource?,
        activationStore: OnlineMetadataActivationStore,
        musicBrainzStore: MusicBrainzBrowserStore,
        lrclibStore: LRCLIBLyricsBrowserStore,
        selectedFilesProvider: @escaping () -> [AudioFile]
    ) {
        self.selectedSource = initialSource
        self.activationStore = activationStore
        self.musicBrainzStore = musicBrainzStore
        self.lrclibStore = lrclibStore
        self.selectedFilesProvider = selectedFilesProvider
    }

    /// Idempotent: called from both `onAppear` and the activation store's onChange. The
    /// store clears the intent on the main actor, so only one call can observe it.
    func consumePendingIntent() {
        guard let intent = activationStore.takePendingIntent() else { return }

        switch intent.action {
        case .showProviderPicker:
            selectedSource = nil
        case .findInMusicBrainz(let seed):
            selectedSource = .musicBrainz
            musicBrainzStore.apply(seed: seed)
            musicBrainzStore.search()
        }
    }

    /// Selecting a source is local-only. If the window was opened without a routing command
    /// (for example macOS window restoration), the provider is seeded from the current
    /// selection locally; no provider request is started.
    func select(_ source: MetadataBrowserSource) {
        seedLocallyIfNeeded(source)
        selectedSource = source
    }

    /// Back to Sources cancels tracked provider work through the owning store APIs while
    /// retaining the locally seeded inputs so the tiles show local state.
    func backToSources() {
        switch selectedSource {
        case .musicBrainz:
            musicBrainzStore.cancelSearch()
        case .lrclib:
            lrclibStore.leaveBrowser()
        case .iTunes, .none:
            break
        }
        selectedSource = nil
    }

    /// Window-close teardown. The iTunes provider view owns its own store teardown on
    /// disappear; MusicBrainz and LRCLIB are app-owned and are closed here.
    func closeWindowSession() {
        musicBrainzStore.closeWindowSession()
        lrclibStore.closeWindowSession()
        selectedSource = nil
    }

    private func seedLocallyIfNeeded(_ source: MetadataBrowserSource) {
        switch source {
        case .musicBrainz:
            guard musicBrainzStore.fileSelectionSummary == nil,
                  let seed = OnlineMetadataSearchSeedBuilder.musicBrainzSeed(from: selectedFilesProvider())
            else { return }
            musicBrainzStore.apply(seed: seed)
        case .lrclib:
            guard !lrclibStore.hasFiles else { return }
            lrclibStore.seed(from: selectedFilesProvider())
        case .iTunes:
            // The iTunes browser view seeds its own store locally on appearance.
            break
        }
    }
}
