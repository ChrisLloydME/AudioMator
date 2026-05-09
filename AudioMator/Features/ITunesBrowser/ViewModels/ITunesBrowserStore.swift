import Foundation
import Combine

enum ITunesBrowserDestination: Hashable, Identifiable {
    case track(ITunesTrackResult)
    case album(ITunesAlbumResult)

    var id: String {
        switch self {
        case .track(let result): return "track:\(result.trackID)"
        case .album(let result): return "album:\(result.collectionID)"
        }
    }
}

@MainActor
final class ITunesBrowserStore: ObservableObject {
    @Published var mode: ITunesSearchMode = .track
    @Published var titleQuery: String = ""
    @Published var artistQuery: String = ""
    @Published var albumArtistQuery: String = ""
    @Published var albumQuery: String = ""
    @Published var upcQuery: String = ""
    @Published var linkQuery: String = ""
    @Published var storefront: ITunesStorefront = .us
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var results: ITunesSearchResults = .tracks([])
    @Published private(set) var lastSubmittedQuery: ITunesSearchQuery?
    @Published private(set) var sourceDescription: String = "Seed iTunes from the current AudioMator selection or search manually."
    @Published private(set) var navigationResetToken = UUID()

    private let client: ITunesClient
    private var searchTask: Task<Void, Never>?
    private var fileInputs: [ITunesFileSearchInput] = []
    private var albumDetailsByID: [Int: ITunesAlbumDetail] = [:]

    init(client: ITunesClient = ITunesClient()) {
        self.client = client
    }

    deinit {
        searchTask?.cancel()
    }

    var currentQuery: ITunesSearchQuery {
        ITunesSearchQuery(
            mode: mode,
            title: titleQuery,
            artist: mode == .album ? albumArtistQuery : artistQuery,
            album: albumQuery,
            upc: upcQuery,
            link: linkQuery,
            country: storefront.countryCode,
            fileInputs: fileInputs
        )
    }

    var hasSearchText: Bool { !currentQuery.isEmpty }
    var hasFileSelection: Bool { !(fileSelectionSummary?.files.isEmpty ?? true) }
    var fileSelectionSummary: ITunesFileSelectionSummary? { currentQuery.fileSelectionSummary }
    var seededFileInputs: [ITunesFileSearchInput] { fileInputs }

    func seed(from files: [AudioFile]) {
        searchTask?.cancel()
        resetNavigation()
        fileInputs = files.map(Self.fileInput)
        guard let first = fileInputs.first else {
            resetToDefault()
            return
        }

        titleQuery = first.title
        artistQuery = first.artist
        albumArtistQuery = first.albumArtist.isEmpty ? first.artist : first.albumArtist
        albumQuery = first.album
        upcQuery = first.barcode
        linkQuery = ""
        mode = fileInputs.count > 1 ? .file : .track
        results = Self.emptyResults(for: currentQuery)
        errorMessage = nil
        lastSubmittedQuery = nil
        sourceDescription = files.count == 1
            ? "From the selected file metadata, filename, and path."
            : "From \(files.count) selected files, with filename and path fallback."
    }

    func resetToDefault() {
        searchTask?.cancel()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumArtistQuery = ""
        albumQuery = ""
        upcQuery = ""
        linkQuery = ""
        fileInputs = []
        mode = .track
        results = .tracks([])
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = "Seed iTunes from the current AudioMator selection or search manually."
    }

    func clearSearch() {
        searchTask?.cancel()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumArtistQuery = ""
        albumQuery = ""
        upcQuery = ""
        linkQuery = ""
        mode = fileInputs.isEmpty ? .track : .file
        results = Self.emptyResults(for: currentQuery)
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
    }

    func handleModeChange(from oldMode: ITunesSearchMode, to newMode: ITunesSearchMode) {
        guard oldMode != newMode else { return }
        searchTask?.cancel()
        resetNavigation()
        isSearching = false
        errorMessage = nil
        lastSubmittedQuery = nil

        if newMode == .album, albumQuery.isEmpty, !titleQuery.isEmpty {
            albumQuery = titleQuery
            titleQuery = ""
        }
        if newMode == .album, albumArtistQuery.isEmpty, !artistQuery.isEmpty {
            albumArtistQuery = artistQuery
        }

        results = Self.emptyResults(for: currentQuery)
    }

    func search() {
        let query = currentQuery
        guard !query.isEmpty else {
            errorMessage = ITunesClientError.emptyQuery.localizedDescription
            lastSubmittedQuery = nil
            isSearching = false
            results = Self.emptyResults(for: query)
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
                await MainActor.run { self.isSearching = false }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.results = Self.emptyResults(for: query)
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }

    func albumDetail(for album: ITunesAlbumResult) async throws -> ITunesAlbumDetail {
        if var cached = albumDetailsByID[album.collectionID] {
            cached = detailByResolvingSelectionPreview(for: cached, fallbackPreview: album.selectionMatchPreview)
            albumDetailsByID[album.collectionID] = cached
            return cached
        }

        var detail = try await client.albumDetail(collectionID: album.collectionID, country: storefront.countryCode)
        detail = detailByResolvingSelectionPreview(for: detail, fallbackPreview: album.selectionMatchPreview)
        albumDetailsByID[album.collectionID] = detail
        return detail
    }

    private func detailByResolvingSelectionPreview(
        for detail: ITunesAlbumDetail,
        fallbackPreview: ITunesAlbumMatchPreview?
    ) -> ITunesAlbumDetail {
        var resolved = detail
        if let fallbackPreview {
            resolved.selectionMatchPreview = fallbackPreview
            return resolved
        }
        guard let summary = fileSelectionSummary else { return resolved }
        resolved.selectionMatchPreview = ITunesAlbumMatcher.match(selection: summary, detail: resolved)
        return resolved
    }

    private func resetNavigation() {
        navigationResetToken = UUID()
    }

    private static func emptyResults(for query: ITunesSearchQuery) -> ITunesSearchResults {
        switch query.mode {
        case .album, .file, .upc:
            return .albums([])
        case .track, .link:
            return .tracks([])
        }
    }

    private static func fileInput(for file: AudioFile) -> ITunesFileSearchInput {
        let fallback = MusicBrainzFilenameFallbackResolver.makeSearchInput(for: file)
        return ITunesFileSearchInput(
            id: file.id.uuidString,
            displayTitle: fallback.displayTitle,
            title: fallback.title,
            artist: fallback.artist,
            albumArtist: fallback.albumArtist,
            album: fallback.album,
            trackNumber: fallback.trackNumber,
            discNumber: fallback.discNumber,
            trackTotal: file.trackTotal,
            durationMilliseconds: file.duration.isFinite && file.duration > 0 ? Int((file.duration * 1000).rounded()) : nil,
            releaseDate: fallback.releaseDate,
            barcode: file.barcode,
            itunesAlbumID: file.itunesAlbumID,
            itunesArtistID: file.itunesArtistID,
            itunesCatalogID: file.itunesCatalogID
        )
    }
}
