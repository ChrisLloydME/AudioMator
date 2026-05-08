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
    var albumArtist: String
    var album: String
    var trackNumber: String
    var trackTotal: Int
    var durationMilliseconds: Int?
    var releaseDate: String
    var isrc: String
    var barcode: String
    var musicBrainzAlbumID: String
    var musicBrainzTrackID: String
    var fileInputs: [MusicBrainzFileSearchInput]
    var link: String
    var sourceDescription: String

    var query: MusicBrainzSearchQuery {
        MusicBrainzSearchQuery(
            mode: mode,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            trackNumber: trackNumber,
            trackTotal: trackTotal,
            durationMilliseconds: durationMilliseconds,
            releaseDate: releaseDate,
            isrc: isrc,
            barcode: barcode,
            musicBrainzAlbumID: musicBrainzAlbumID,
            musicBrainzTrackID: musicBrainzTrackID,
            fileInputs: fileInputs,
            link: link
        )
    }
}

@MainActor
final class MusicBrainzBrowserStore: ObservableObject {
    static let fullReleaseRecordingPreloadLimit = 35

    @Published var mode: MusicBrainzSearchMode = .track
    @Published var titleQuery: String = ""
    @Published var artistQuery: String = ""
    @Published var albumArtistQuery: String = ""
    @Published var albumQuery: String = ""
    @Published var trackNumberQuery: String = ""
    @Published var linkQuery: String = ""
    @Published var releaseFilters: MusicBrainzReleaseFilters = MusicBrainzReleaseFilters()
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var results: MusicBrainzSearchResults = .recordings([])
    @Published private(set) var lastSubmittedQuery: MusicBrainzSearchQuery?
    @Published private(set) var sourceDescription: String = "Edit the fields below or seed them from the current AudioMator selection."
    @Published private(set) var navigationResetToken: UUID = UUID()

    private let client: MusicBrainzClient
    private var searchTask: Task<Void, Never>?
    private var recordingDetailsByID: [String: MusicBrainzRecordingDetail] = [:]
    private var fileTrackTotal: Int = 0
    private var fileDurationMilliseconds: Int?
    private var fileReleaseDate: String = ""
    private var fileISRC: String = ""
    private var fileBarcode: String = ""
    private var fileMusicBrainzAlbumID: String = ""
    private var fileMusicBrainzTrackID: String = ""
    private var fileInputs: [MusicBrainzFileSearchInput] = []

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
        let resolvedTrackTotal = mode == .file ? fileTrackTotal : 0
        let resolvedDurationMilliseconds = mode == .file ? fileDurationMilliseconds : nil
        let resolvedReleaseDate = mode == .file ? fileReleaseDate : ""
        let resolvedISRC = mode == .file ? fileISRC : ""
        let resolvedBarcode = mode == .file ? fileBarcode : ""
        let resolvedMusicBrainzAlbumID = mode == .file ? fileMusicBrainzAlbumID : ""
        let resolvedMusicBrainzTrackID = mode == .file ? fileMusicBrainzTrackID : ""

        return MusicBrainzSearchQuery(
            mode: mode,
            title: titleQuery,
            artist: artistQuery,
            albumArtist: albumArtistQuery,
            album: albumQuery,
            trackNumber: trackNumberQuery,
            trackTotal: resolvedTrackTotal,
            durationMilliseconds: resolvedDurationMilliseconds,
            releaseDate: resolvedReleaseDate,
            isrc: resolvedISRC,
            barcode: resolvedBarcode,
            musicBrainzAlbumID: resolvedMusicBrainzAlbumID,
            musicBrainzTrackID: resolvedMusicBrainzTrackID,
            fileInputs: fileInputs,
            link: linkQuery,
            releaseFilters: mode == .link ? MusicBrainzReleaseFilters() : releaseFilters
        )
    }

    var hasSearchText: Bool {
        !currentQuery.isEmpty
    }

    var visibleResultMode: MusicBrainzSearchMode {
        lastSubmittedQuery?.mode ?? mode
    }

    var fileSelectionSummary: MusicBrainzFileSelectionSummary? {
        currentQuery.fileSelectionSummary
    }

    var hasFileSelection: Bool {
        !(fileSelectionSummary?.files.isEmpty ?? true)
    }

    var isMultiFileSelection: Bool {
        fileSelectionSummary?.isMultiFile ?? false
    }

    func apply(seed: MusicBrainzSearchSeed?) {
        guard let seed else {
            resetToDefault()
            return
        }

        resetNavigation()
        mode = seed.mode
        titleQuery = seed.title
        artistQuery = seed.artist
        albumArtistQuery = seed.albumArtist
        albumQuery = seed.album
        trackNumberQuery = seed.trackNumber
        fileTrackTotal = seed.trackTotal
        fileDurationMilliseconds = seed.durationMilliseconds
        fileReleaseDate = seed.releaseDate
        fileISRC = seed.isrc
        fileBarcode = seed.barcode
        fileMusicBrainzAlbumID = seed.musicBrainzAlbumID
        fileMusicBrainzTrackID = seed.musicBrainzTrackID
        fileInputs = seed.fileInputs
        linkQuery = seed.link
        sourceDescription = seed.sourceDescription
        errorMessage = nil
    }

    func resetToDefault() {
        searchTask?.cancel()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumArtistQuery = ""
        albumQuery = ""
        trackNumberQuery = ""
        fileTrackTotal = 0
        fileDurationMilliseconds = nil
        fileReleaseDate = ""
        fileISRC = ""
        fileBarcode = ""
        fileMusicBrainzAlbumID = ""
        fileMusicBrainzTrackID = ""
        fileInputs = []
        linkQuery = ""
        releaseFilters = MusicBrainzReleaseFilters()
        mode = .track
        results = .recordings([])
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = "Edit the fields below or seed them from the current AudioMator selection."
    }

    func closeWindowSession() {
        searchTask?.cancel()
        recordingDetailsByID = [:]
        resetToDefault()
    }

    func clearSearch() {
        searchTask?.cancel()
        resetNavigation()
        titleQuery = ""
        artistQuery = ""
        albumArtistQuery = ""
        albumQuery = ""
        trackNumberQuery = ""
        fileTrackTotal = 0
        fileDurationMilliseconds = nil
        fileReleaseDate = ""
        fileISRC = ""
        fileBarcode = ""
        fileMusicBrainzAlbumID = ""
        fileMusicBrainzTrackID = ""
        linkQuery = ""
        mode = fileInputs.isEmpty ? .track : .file
        results = Self.emptyResults(for: currentQuery)
        errorMessage = nil
        lastSubmittedQuery = nil
        isSearching = false
        sourceDescription = fileInputs.isEmpty
            ? "Edit the fields below or seed them from the current AudioMator selection."
            : "Seeded from the current AudioMator selection."
    }

    func resetFilters() {
        releaseFilters = MusicBrainzReleaseFilters()
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
            results = Self.emptyResults(for: currentQuery)
        case .album:
            if albumQuery.isEmpty, !titleQuery.isEmpty {
                albumQuery = titleQuery
            }
            titleQuery = ""
            results = Self.emptyResults(for: currentQuery)
        case .file:
            results = Self.emptyResults(for: currentQuery)
        case .link:
            results = Self.emptyResults(for: currentQuery)
        }
    }

    func search() {
        let query = currentQuery

        guard !query.isEmpty else {
            resetNavigation()
            results = Self.emptyResults(for: query)
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
                    self.results = Self.emptyResults(for: query)
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
            var detail = try await client.releaseDetail(id: result.id)
            detail.selectionMatchPreview = result.selectionMatchPreview
            return .release(detail)
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

    func recordingDetail(id: String) async throws -> MusicBrainzRecordingDetail {
        if let cachedDetail = recordingDetailsByID[id] {
            return cachedDetail
        }

        let detail = try await client.recordingDetail(id: id, fallbackReleases: [])
        recordingDetailsByID[id] = detail
        return detail
    }

    func cachedRecordingDetail(id: String) -> MusicBrainzRecordingDetail? {
        recordingDetailsByID[id]
    }

    func recordingPreloadTargetIDs(for release: MusicBrainzReleaseDetail) -> Set<String> {
        let releaseRecordingIDs = Self.recordingIDsForReleaseTracks(release)

        if releaseRecordingIDs.count <= Self.fullReleaseRecordingPreloadLimit {
            return releaseRecordingIDs
        }

        guard let preview = release.selectionMatchPreview else { return [] }
        return Set(preview.matchedAssignments.map(\.track.recordingID).filter { !$0.isEmpty })
    }

    func preloadRecordingDetails(
        for release: MusicBrainzReleaseDetail,
        progress: @MainActor (_ completedCount: Int, _ totalCount: Int) -> Void
    ) async {
        let recordingIDs = recordingPreloadTargetIDs(for: release)
        guard !recordingIDs.isEmpty else {
            progress(0, 0)
            return
        }

        var completedCount = 0
        progress(completedCount, recordingIDs.count)

        for recordingID in recordingIDs.sorted() {
            guard !Task.isCancelled else { return }

            if recordingDetailsByID[recordingID] == nil {
                do {
                    let detail = try await client.recordingDetail(id: recordingID, fallbackReleases: [])
                    recordingDetailsByID[recordingID] = detail
                } catch {
                    // Keep release loading resilient; missing recording detail only hides deep relationship fields.
                }
            }

            completedCount += 1
            progress(completedCount, recordingIDs.count)
        }
    }

    private func resetNavigation() {
        navigationResetToken = UUID()
    }

    private static func emptyResults(for query: MusicBrainzSearchQuery) -> MusicBrainzSearchResults {
        switch query.mode {
        case .album:
            return .releases([])
        case .file:
            return query.isMultiFileSelection ? .releases([]) : .recordings([])
        case .track, .link:
            return .recordings([])
        }
    }

    private static func recordingIDsForReleaseTracks(_ release: MusicBrainzReleaseDetail) -> Set<String> {
        Set(
            release.media
                .flatMap(\.tracks)
                .map(\.recordingID)
                .filter { !$0.isEmpty }
        )
    }
}
