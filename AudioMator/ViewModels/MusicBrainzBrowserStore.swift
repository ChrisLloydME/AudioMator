import Foundation
import Combine

struct MusicBrainzSearchSeed {
    var title: String
    var artist: String
    var album: String
    var sourceDescription: String

    var query: MusicBrainzSearchQuery {
        MusicBrainzSearchQuery(
            title: title,
            artist: artist,
            album: album
        )
    }
}

@MainActor
final class MusicBrainzBrowserStore: ObservableObject {
    @Published var titleQuery: String = ""
    @Published var artistQuery: String = ""
    @Published var albumQuery: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var results: [MusicBrainzRecordingResult] = []
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
            title: titleQuery,
            artist: artistQuery,
            album: albumQuery
        )
    }

    var hasSearchText: Bool {
        !currentQuery.isEmpty
    }

    func apply(seed: MusicBrainzSearchSeed?) {
        guard let seed else { return }

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
        results = []
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = "Edit the fields below or seed them from the current AudioMator selection."
    }

    func search() {
        let query = currentQuery

        guard !query.isEmpty else {
            results = []
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
                let results = try await client.searchRecordings(matching: query)
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
                    self.results = []
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }
}
