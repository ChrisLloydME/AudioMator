import Foundation
import Combine

enum MusicBrainzBrowserDestination: Hashable, Identifiable {
    case recording(MusicBrainzRecordingResult)
    case release(MusicBrainzReleaseSearchResult)
    case track(MusicBrainzReleaseDetail.Medium.Track)

    var id: String {
        switch self {
        case .recording(let result):
            return "recording:\(result.id)"
        case .release(let result):
            return "release:\(result.id)"
        case .track(let track):
            return "track:\(track.id)"
        }
    }
}

struct MusicBrainzSearchSeed {
    var mode: MusicBrainzSearchMode
    var title: String
    var artist: String
    var album: String
    var link: String
    var sourceDescription: String

    var query: MusicBrainzSearchQuery {
        MusicBrainzSearchQuery(
            mode: mode,
            title: title,
            artist: artist,
            album: album,
            link: link
        )
    }
}

@MainActor
final class MusicBrainzBrowserStore: ObservableObject {
    @Published var mode: MusicBrainzSearchMode = .track
    @Published var titleQuery: String = ""
    @Published var artistQuery: String = ""
    @Published var albumQuery: String = ""
    @Published var linkQuery: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var results: MusicBrainzSearchResults = .recordings([])
    @Published private(set) var lastSubmittedQuery: MusicBrainzSearchQuery?
    @Published private(set) var sourceDescription: String = "Edit the fields below or seed them from the current AudioMator selection."
    @Published private(set) var navigationResetToken: UUID = UUID()

    private let client: MusicBrainzClient
    private var searchTask: Task<Void, Never>?

    init(client: MusicBrainzClient) {
        self.client = client
    }

    convenience init() {
        self.init(client: MusicBrainzClient())
    }

    deinit {
        searchTask?.cancel()
    }

    var currentQuery: MusicBrainzSearchQuery {
        MusicBrainzSearchQuery(
            mode: mode,
            title: titleQuery,
            artist: artistQuery,
            album: albumQuery,
            link: linkQuery
        )
    }

    var hasSearchText: Bool {
        !currentQuery.isEmpty
    }

    var visibleResultMode: MusicBrainzSearchMode {
        lastSubmittedQuery?.mode ?? mode
    }

    func apply(seed: MusicBrainzSearchSeed?) {
        guard let seed else { return }

        resetNavigation()
        mode = seed.mode
        titleQuery = seed.title
        artistQuery = seed.artist
        albumQuery = seed.album
        linkQuery = seed.link
        sourceDescription = seed.sourceDescription
        errorMessage = nil
    }

    func clearSearch() {
        searchTask?.cancel()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumQuery = ""
        linkQuery = ""
        mode = .track
        results = .recordings([])
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = "Edit the fields below or seed them from the current AudioMator selection."
    }

    func handleModeChange(from oldMode: MusicBrainzSearchMode, to newMode: MusicBrainzSearchMode) {
        guard oldMode != newMode else { return }
        searchTask?.cancel()
        resetNavigation()
        isSearching = false
        errorMessage = nil
        lastSubmittedQuery = nil

        switch newMode {
        case .track:
            results = .recordings([])
        case .album:
            if albumQuery.isEmpty, !titleQuery.isEmpty {
                albumQuery = titleQuery
            }
            titleQuery = ""
            results = .releases([])
        case .link:
            results = .recordings([])
        }
    }

    func search() {
        let query = currentQuery

        guard !query.isEmpty else {
            resetNavigation()
            results = query.mode == .track ? .recordings([]) : .releases([])
            errorMessage = MusicBrainzClientError.emptyQuery.localizedDescription
            lastSubmittedQuery = nil
            isSearching = false
            return
        }

        resetNavigation()
        errorMessage = nil
        isSearching = true
        lastSubmittedQuery = query
        searchTask?.cancel()

        searchTask = Task { [client] in
            do {
                let results = try await client.search(matching: query)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.results = results
                    self.errorMessage = nil
                    self.isSearching = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.results = query.mode == .track ? .recordings([]) : .releases([])
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }

    func metadataDetail(for destination: MusicBrainzBrowserDestination) async throws -> MusicBrainzMetadataDetail {
        switch destination {
        case .recording(let result):
            return .recording(
                try await client.recordingDetail(
                    id: result.id,
                    fallbackReleases: result.releases
                )
            )
        case .release(let result):
            return .release(try await client.releaseDetail(id: result.id))
        case .track(let track):
            if track.recordingID.isEmpty {
                return .track(MusicBrainzTrackDetail(track: track, recordingDetail: nil))
            }

            return .track(
                MusicBrainzTrackDetail(
                    track: track,
                    recordingDetail: try await client.recordingDetail(
                        id: track.recordingID,
                        fallbackReleases: []
                    )
                )
            )
        }
    }

    private func resetNavigation() {
        navigationResetToken = UUID()
    }
}
