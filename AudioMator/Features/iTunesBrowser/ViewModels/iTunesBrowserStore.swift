import Foundation
import Combine

/// Region and language submitted with the search. The provider's raw `country` is display data.
nonisolated struct iTunesSearchContext: Hashable, Sendable {
    let storefront: iTunesStorefront
    let language: iTunesCatalogLanguage?
    let generation: UUID
    let submittedSelection: iTunesFileSelectionSummary?

    init(
        storefront: iTunesStorefront,
        language: iTunesCatalogLanguage? = nil,
        generation: UUID,
        submittedSelection: iTunesFileSelectionSummary?
    ) {
        self.storefront = storefront
        self.language = language
        self.generation = generation
        self.submittedSelection = submittedSelection
    }
}

/// Results and their submitted catalog query share one publication and generation.
nonisolated struct iTunesSearchPublication: Equatable, Sendable {
    let generation: UUID
    let storefront: iTunesStorefront
    let query: iTunesSearchQuery
    let submittedSelection: iTunesFileSelectionSummary?
    let results: iTunesSearchResults
}

private nonisolated struct iTunesDetailCacheKey: Hashable, Sendable {
    let storefront: iTunesStorefront
    let language: iTunesCatalogLanguage?
    let collectionID: Int
}

enum iTunesBrowserDestination: Hashable, Identifiable {
    case track(iTunesTrackResult, iTunesSearchContext)
    case album(iTunesAlbumResult, iTunesSearchContext)

    var id: String {
        switch self {
        case .track(let result, _): return "track:\(result.trackID)"
        case .album(let result, _): return "album:\(result.collectionID)"
        }
    }

    var context: iTunesSearchContext {
        switch self {
        case .track(_, let context), .album(_, let context):
            return context
        }
    }
}

@MainActor
final class iTunesBrowserStore: ObservableObject {
    @Published var mode: iTunesSearchMode = .track
    @Published var titleQuery: String = ""
    @Published var artistQuery: String = ""
    @Published var albumArtistQuery: String = ""
    @Published var albumQuery: String = ""
    @Published var upcQuery: String = ""
    @Published var linkQuery: String = ""
    @Published private(set) var storefront: iTunesStorefront = .us
    @Published private var languageOverride: iTunesCatalogLanguage?
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var publication: iTunesSearchPublication?
    @Published private(set) var lastSubmittedQuery: iTunesSearchQuery?
    @Published private(set) var sourceDescription: String = "Seed iTunes from the current AudioMator selection or search manually."
    @Published private(set) var navigationResetToken = UUID()

    private let client: any iTunesBrowserClient
    private let albumMatcher: @Sendable (iTunesFileSelectionSummary, iTunesAlbumDetail) -> iTunesAlbumMatchPreview
    private let operationTimeout: Duration
    private var searchTask: Task<Void, Never>?
    private var searchOperationID = UUID()
    private var sessionGeneration = UUID()
    private var fileInputs: [iTunesFileSearchInput] = []
    private var albumDetailsByKey: [iTunesDetailCacheKey: iTunesAlbumDetail] = [:]

    init(
        client: any iTunesBrowserClient = iTunesClient(),
        albumMatcher: @escaping @Sendable (iTunesFileSelectionSummary, iTunesAlbumDetail) -> iTunesAlbumMatchPreview = iTunesAlbumMatcher.match,
        operationTimeout: Duration = .seconds(30)
    ) {
        self.client = client
        self.albumMatcher = albumMatcher
        self.operationTimeout = operationTimeout
    }

    deinit {
        searchTask?.cancel()
    }

    var results: iTunesSearchResults {
        publication?.results ?? Self.emptyResults(for: currentQuery)
    }

    var submittedContext: iTunesSearchContext? {
        publication.map {
            iTunesSearchContext(
                storefront: $0.storefront,
                language: $0.query.language,
                generation: $0.generation,
                submittedSelection: $0.submittedSelection
            )
        }
    }

    /// Context used by result navigation. Results are only displayed from a publication, so
    /// this is non-optional for the views; the fallback exists for defensive rendering only.
    var resultContext: iTunesSearchContext {
        submittedContext
            ?? iTunesSearchContext(
                storefront: storefront,
                language: languageOverride,
                generation: UUID(),
                submittedSelection: fileSelectionSummary
            )
    }

    var currentQuery: iTunesSearchQuery {
        iTunesSearchQuery(
            mode: mode,
            title: titleQuery,
            artist: mode == .album ? albumArtistQuery : artistQuery,
            album: albumQuery,
            upc: upcQuery,
            link: linkQuery,
            country: storefront.countryCode,
            language: languageOverride,
            fileInputs: fileInputs
        )
    }

    var hasSearchText: Bool { !currentQuery.isEmpty }
    var fileSelectionSummary: iTunesFileSelectionSummary? { currentQuery.fileSelectionSummary }
    var seededFileInputs: [iTunesFileSearchInput] { fileInputs }

    var storefrontLanguage: iTunesCatalogLanguage {
        languageOverride ?? storefront.catalogLanguages.defaultLanguage
    }

    func selectStorefront(_ newStorefront: iTunesStorefront) {
        guard newStorefront != storefront else { return }
        storefront = newStorefront
        languageOverride = nil
        invalidateCatalogResults()
    }

    func selectStorefrontLanguage(_ language: iTunesCatalogLanguage) {
        guard language != storefrontLanguage else { return }
        let languages = storefront.catalogLanguages
        guard language == languages.defaultLanguage || languages.alternatives.contains(language) else { return }
        languageOverride = language == languages.defaultLanguage ? nil : language
        invalidateCatalogResults()
    }

    private func invalidateCatalogResults() {
        cancelSearch()
        publication = nil
        lastSubmittedQuery = nil
        errorMessage = nil
        resetNavigation()
    }

    func seed(from files: [AudioFile]) {
        cancelSearch()
        resetNavigation()
        fileInputs = files.map(Self.fileInput)
        publication = nil
        lastSubmittedQuery = nil
        isSearching = false
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
        errorMessage = nil
        sourceDescription = files.count == 1
            ? "From the selected file metadata, filename, and path."
            : "From \(files.count) selected files, with filename and path fallback."
    }

    func resetToDefault() {
        cancelSearch()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumArtistQuery = ""
        albumQuery = ""
        upcQuery = ""
        linkQuery = ""
        fileInputs = []
        mode = .track
        publication = nil
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = "Seed iTunes from the current AudioMator selection or search manually."
    }

    /// Ends the current session: outstanding work and the remote-detail cache lose authority.
    /// The visible storefront and language are retained.
    func beginReplacementSession() {
        sessionGeneration = UUID()
        cancelSearch()
        publication = nil
        lastSubmittedQuery = nil
        errorMessage = nil
        isSearching = false
        albumDetailsByKey = [:]
        resetNavigation()
    }

    func closeWindowSession() {
        beginReplacementSession()
        resetToDefault()
    }

    func clearSearch() {
        cancelSearch()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumArtistQuery = ""
        albumQuery = ""
        upcQuery = ""
        linkQuery = ""
        mode = fileInputs.isEmpty ? .track : .file
        publication = nil
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = fileInputs.isEmpty
            ? "Seed iTunes from the current AudioMator selection or search manually."
            : "Seeded from the current AudioMator selection."
    }

    func handleModeChange(from oldMode: iTunesSearchMode, to newMode: iTunesSearchMode) {
        guard oldMode != newMode else { return }
        cancelSearch()
        resetNavigation()
        isSearching = false
        errorMessage = nil
        lastSubmittedQuery = nil
        publication = nil

        if newMode == .album, albumQuery.isEmpty, !titleQuery.isEmpty {
            albumQuery = titleQuery
            titleQuery = ""
        }
        if newMode == .album, albumArtistQuery.isEmpty, !artistQuery.isEmpty {
            albumArtistQuery = artistQuery
        }
    }

    func search() {
        let query = currentQuery
        guard !query.isEmpty else {
            publication = nil
            errorMessage = iTunesClientError.emptyQuery.localizedDescription
            lastSubmittedQuery = nil
            isSearching = false
            return
        }

        resetNavigation()
        errorMessage = nil
        isSearching = true
        lastSubmittedQuery = query
        // Publish the completed results together with the submitted query and generation.
        publication = nil
        cancelSearch(resetLoadingState: false)

        let operationID = UUID()
        searchOperationID = operationID
        let submittedStorefront = storefront
        let submittedSelection = query.fileSelectionSummary
        let publicationGeneration = UUID()
        let submittedSessionGeneration = sessionGeneration

        searchTask = Task { [client, operationTimeout, weak self] in
            do {
                let results = try await withAsyncTimeout(
                    operationTimeout,
                    operationName: String(localized: "Searching iTunes")
                ) {
                    try await client.search(matching: query, limit: 25)
                }
                guard !Task.isCancelled else { return }
                guard
                    let self,
                    self.searchOperationID == operationID,
                    self.sessionGeneration == submittedSessionGeneration,
                    self.storefront == submittedStorefront,
                    self.languageOverride == query.language
                else { return }
                self.searchTask = nil
                self.publication = iTunesSearchPublication(
                    generation: publicationGeneration,
                    storefront: submittedStorefront,
                    query: query,
                    submittedSelection: submittedSelection,
                    results: results
                )
                self.errorMessage = nil
                self.isSearching = false
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                guard
                    let self,
                    self.searchOperationID == operationID,
                    self.sessionGeneration == submittedSessionGeneration,
                    self.storefront == submittedStorefront,
                    self.languageOverride == query.language
                else { return }
                self.searchTask = nil
                self.isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                guard
                    let self,
                    self.searchOperationID == operationID,
                    self.sessionGeneration == submittedSessionGeneration,
                    self.storefront == submittedStorefront,
                    self.languageOverride == query.language
                else { return }
                self.searchTask = nil
                self.publication = nil
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.isSearching = false
            }
        }
    }

    func cancelSearch(resetLoadingState: Bool = true) {
        searchOperationID = UUID()
        searchTask?.cancel()
        searchTask = nil
        if resetLoadingState {
            isSearching = false
        }
    }

    func detailDestination(for track: iTunesTrackResult) -> iTunesBrowserDestination {
        .track(track, resultContext)
    }

    func detailDestination(for album: iTunesAlbumResult) -> iTunesBrowserDestination {
        .album(album, resultContext)
    }

    /// Album-result entry path. The submitted context supplies the region and language.
    func albumDetail(
        for album: iTunesAlbumResult,
        context: iTunesSearchContext
    ) async throws -> iTunesAlbumDetail {
        let key = iTunesDetailCacheKey(
            storefront: context.storefront,
            language: context.language,
            collectionID: album.collectionID
        )
        let submittedSessionGeneration = sessionGeneration

        if let cached = albumDetailsByKey[key] {
            return try await resolvedDetail(for: cached, album: album, context: context)
        }

        let detailClient = client
        let collectionID = album.collectionID
        let country = key.storefront.countryCode
        let language = key.language
        let detail = try await withAsyncTimeout(
            operationTimeout,
            operationName: String(localized: "Loading album details from iTunes")
        ) {
            try await detailClient.albumDetail(collectionID: collectionID, country: country, language: language)
        }
        try Task.checkCancellation()
        guard submittedSessionGeneration == sessionGeneration else {
            // The session that requested this detail is gone; do not repopulate its cache.
            throw CancellationError()
        }
        // Cache only the raw remote detail. Selection previews are resolved per read.
        albumDetailsByKey[key] = detail
        return try await resolvedDetail(for: detail, album: album, context: context)
    }

    /// Track-result entry path. The synthesized album exists only to share the album-detail
    /// cache key and matcher.
    func albumDetail(
        for track: iTunesTrackResult,
        context: iTunesSearchContext
    ) async throws -> iTunesAlbumDetail {
        try await albumDetail(for: Self.synthesizedAlbumResult(from: track), context: context)
    }

    private func resolvedDetail(
        for detail: iTunesAlbumDetail,
        album: iTunesAlbumResult,
        context: iTunesSearchContext
    ) async throws -> iTunesAlbumDetail {
        let fallbackPreview = canReuseFallbackPreview(for: album, context: context)
            ? album.selectionMatchPreview
            : nil
        let resolved = try await Self.detailByResolvingSelectionPreview(
            for: detail,
            fallbackPreview: fallbackPreview,
            selectionSummary: context.submittedSelection,
            albumMatcher: albumMatcher,
            operationTimeout: operationTimeout
        )
        try Task.checkCancellation()
        return resolved
    }

    private func canReuseFallbackPreview(
        for album: iTunesAlbumResult,
        context: iTunesSearchContext
    ) -> Bool {
        guard let publication, album.selectionMatchPreview != nil else { return false }
        return publication.generation == context.generation
            && publication.storefront == context.storefront
            && publication.query.language == context.language
            && publication.submittedSelection == context.submittedSelection
    }

    private nonisolated static func detailByResolvingSelectionPreview(
        for detail: iTunesAlbumDetail,
        fallbackPreview: iTunesAlbumMatchPreview?,
        selectionSummary: iTunesFileSelectionSummary?,
        albumMatcher: @escaping @Sendable (iTunesFileSelectionSummary, iTunesAlbumDetail) -> iTunesAlbumMatchPreview,
        operationTimeout: Duration
    ) async throws -> iTunesAlbumDetail {
        var resolved = detail
        if let fallbackPreview {
            resolved.selectionMatchPreview = fallbackPreview
            return resolved
        }
        guard let selectionSummary else { return resolved }
        let detailForMatching = resolved

        let preview = try await withAsyncTimeout(
            operationTimeout,
            operationName: String(localized: "Finding matching iTunes tracks"),
            priority: .userInitiated
        ) {
            albumMatcher(selectionSummary, detailForMatching)
        }
        resolved.selectionMatchPreview = preview
        return resolved
    }

    private func resetNavigation() {
        navigationResetToken = UUID()
    }

    private nonisolated static func synthesizedAlbumResult(from track: iTunesTrackResult) -> iTunesAlbumResult {
        iTunesAlbumResult(
            collectionID: track.collectionID ?? track.trackID,
            artistID: track.artistID,
            collectionArtistID: track.collectionArtistID,
            collectionName: track.collectionName,
            artistName: track.artistName,
            collectionArtistName: track.collectionArtistName,
            trackCount: track.trackCount,
            releaseDate: track.releaseDate,
            primaryGenreName: track.primaryGenreName,
            country: track.country,
            copyright: track.copyright,
            contentAdvisoryRating: track.contentAdvisoryRating,
            collectionExplicitness: track.collectionExplicitness,
            collectionViewURL: track.collectionViewURL,
            artistViewURL: track.artistViewURL,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }

    private static func emptyResults(for query: iTunesSearchQuery) -> iTunesSearchResults {
        switch query.mode {
        case .album, .file, .upc:
            return .albums([])
        case .track, .link:
            return .tracks([])
        }
    }

    private static func fileInput(for file: AudioFile) -> iTunesFileSearchInput {
        let fallback = MusicBrainzFilenameFallbackResolver.makeSearchInput(for: file)
        return iTunesFileSearchInput(
            id: file.id.uuidString,
            displayTitle: fallback.displayTitle,
            title: fallback.title,
            artist: fallback.artist,
            albumArtist: fallback.albumArtist,
            album: fallback.album,
            trackNumber: fallback.trackNumber,
            discNumber: fallback.discNumber,
            trackTotal: file.trackTotal,
            durationMilliseconds: AudioNumericConversion.positiveDurationMilliseconds(file.duration),
            releaseDate: fallback.releaseDate,
            barcode: file.barcode,
            itunesAlbumID: file.itunesAlbumID,
            itunesArtistID: file.itunesArtistID,
            itunesCatalogID: file.itunesCatalogID
        )
    }
}
