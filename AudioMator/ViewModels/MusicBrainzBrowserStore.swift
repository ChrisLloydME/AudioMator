import Foundation
import Combine

struct MusicBrainzSearchSeed {
    var mode: MusicBrainzSearchMode
    var title: String
    var artist: String
    var album: String
    var sourceDescription: String

    var query: MusicBrainzSearchQuery {
        MusicBrainzSearchQuery(
            mode: mode,
            title: title,
            artist: artist,
            album: album
        )
    }
}

@MainActor
final class MusicBrainzBrowserStore: ObservableObject {
    @Published var mode: MusicBrainzSearchMode = .track
    @Published var titleQuery: String = ""
    @Published var artistQuery: String = ""
    @Published var albumQuery: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var results: MusicBrainzSearchResults = .recordings([])
    @Published private(set) var lastSubmittedQuery: MusicBrainzSearchQuery?
    @Published private(set) var sourceDescription: String = "Edit the fields below or seed them from the current AudioMator selection."

    private let client: MusicBrainzClient
    private var searchTask: Task<Void, Never>?

    init(client: MusicBrainzClient = MusicBrainzClient()) {
        self.client = client
    }

    deinit {
        searchTask?.cancel()
    }

    var currentQuery: MusicBrainzSearchQuery {
        MusicBrainzSearchQuery(
            mode: mode,
            title: titleQuery,
            artist: artistQuery,
            album: albumQuery
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

        mode = seed.mode
        titleQuery = seed.title
        artistQuery = seed.artist
        albumQuery = seed.album
        sourceDescription = seed.sourceDescription
        errorMessage = nil
    }

    func clearSearch() {
        searchTask?.cancel()
        titleQuery = ""
        artistQuery = ""
        albumQuery = ""
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
        }
    }

    func search() {
        let query = currentQuery

        guard !query.isEmpty else {
            results = query.mode == .track ? .recordings([]) : .releases([])
            errorMessage = MusicBrainzClientError.emptyQuery.localizedDescription
            lastSubmittedQuery = nil
            isSearching = false
            return
        }

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
}
