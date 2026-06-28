import Foundation

enum iTunesSearchMode: String, CaseIterable, Identifiable {
    case track
    case album
    case file
    case link
    case upc

    var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .track: return "Track"
        case .album: return "Album"
        case .file: return "File"
        case .link: return "Link"
        case .upc: return "UPC"
        }
    }
}

enum iTunesStorefront: String, CaseIterable, Identifiable, Hashable {
    case us
    case cn
    case hk
    case tw
    case jp
    case kr
    case gb
    case de
    case fr
    case ca
    case au

    var id: String { rawValue }
    var countryCode: String { rawValue }

    var emoji: String {
        switch self {
        case .us: return "🇺🇸"
        case .cn: return "🇨🇳"
        case .hk: return "🇭🇰"
        case .tw: return "🇹🇼"
        case .jp: return "🇯🇵"
        case .kr: return "🇰🇷"
        case .gb: return "🇬🇧"
        case .de: return "🇩🇪"
        case .fr: return "🇫🇷"
        case .ca: return "🇨🇦"
        case .au: return "🇦🇺"
        }
    }

    var displayName: String {
        switch self {
        case .us: return "United States"
        case .cn: return "China Mainland"
        case .hk: return "Hong Kong"
        case .tw: return "Taiwan"
        case .jp: return "Japan"
        case .kr: return "South Korea"
        case .gb: return "United Kingdom"
        case .de: return "Germany"
        case .fr: return "France"
        case .ca: return "Canada"
        case .au: return "Australia"
        }
    }

    var menuTitle: String {
        "\(emoji) \(displayName)"
    }
}

struct iTunesFileSearchInput: Identifiable, Equatable, Hashable {
    let id: String
    let displayTitle: String
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let trackNumber: String
    let discNumber: String
    let trackTotal: Int
    let durationMilliseconds: Int?
    let releaseDate: String
    let barcode: String
    let itunesAlbumID: String
    let itunesArtistID: String
    let itunesCatalogID: String

    var preferredDisplayTitle: String {
        if !title.isEmpty { return title }
        if !displayTitle.isEmpty { return displayTitle }
        return "Selected File"
    }

    var normalizedTrackNumber: Int? {
        OnlineMetadataSelectionCore.normalizedPositiveIndex(trackNumber)
    }

    var normalizedDiscNumber: Int? {
        OnlineMetadataSelectionCore.normalizedPositiveIndex(discNumber)
    }

    var normalizedReleaseYear: String {
        OnlineMetadataSelectionCore.normalizedReleaseYear(releaseDate)
    }

    var artistCandidates: [String] {
        let values = [artist, albumArtist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (Array(NSOrderedSet(array: values)) as? [String]) ?? values
    }
}

struct iTunesFileSelectionSummary: Equatable, Hashable {
    let files: [iTunesFileSearchInput]
    let albumCandidate: String
    let albumArtistCandidate: String
    let primaryArtistCandidate: String
    let totalSelectedFiles: Int
    let trackCountCandidate: Int
    let releaseYearCandidate: String
    let barcodeCandidate: String
    let itunesAlbumIDCandidate: String
    let distinctAlbumCount: Int
    let distinctArtistCount: Int

    init(files: [iTunesFileSearchInput]) {
        self.files = files
        let summary = OnlineMetadataSelectionCore.summary(
            albums: files.map(\.album),
            albumArtists: files.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist },
            primaryArtists: files.map(\.artist),
            trackTotals: files.map(\.trackTotal),
            releaseDates: files.map(\.releaseDate),
            barcodes: files.map(\.barcode),
            providerAlbumIDs: files.map(\.itunesAlbumID)
        )
        self.totalSelectedFiles = summary.totalSelectedFiles
        self.albumCandidate = summary.albumCandidate
        self.albumArtistCandidate = summary.albumArtistCandidate
        self.primaryArtistCandidate = summary.primaryArtistCandidate
        self.trackCountCandidate = summary.trackCountCandidate
        self.releaseYearCandidate = summary.releaseYearCandidate
        self.barcodeCandidate = summary.barcodeCandidate
        self.itunesAlbumIDCandidate = summary.providerAlbumIDCandidate
        self.distinctAlbumCount = summary.distinctAlbumCount
        self.distinctArtistCount = summary.distinctArtistCount
    }

    var isMultiFile: Bool { files.count > 1 }
    var selectionLooksMixed: Bool { distinctAlbumCount > 1 || distinctArtistCount > 1 }

}

struct iTunesSearchQuery: Equatable {
    var mode: iTunesSearchMode = .track
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var upc: String = ""
    var link: String = ""
    var country: String = "us"
    var fileInputs: [iTunesFileSearchInput] = []

    var isEmpty: Bool {
        switch mode {
        case .track:
            return title.trimmedForiTunes.isEmpty && artist.trimmedForiTunes.isEmpty && album.trimmedForiTunes.isEmpty
        case .album:
            return album.trimmedForiTunes.isEmpty && artist.trimmedForiTunes.isEmpty
        case .file:
            return effectiveFileInputs.isEmpty
        case .link:
            return link.trimmedForiTunes.isEmpty
        case .upc:
            return upc.trimmedForiTunes.isEmpty
        }
    }

    var effectiveFileInputs: [iTunesFileSearchInput] { fileInputs }

    var fileSelectionSummary: iTunesFileSelectionSummary? {
        guard !effectiveFileInputs.isEmpty else { return nil }
        return iTunesFileSelectionSummary(files: effectiveFileInputs)
    }

    var searchTerm: String {
        switch mode {
        case .track:
            return [title, artist, album].map(\.trimmedForiTunes).filter { !$0.isEmpty }.joined(separator: " ")
        case .album:
            return [album, artist].map(\.trimmedForiTunes).filter { !$0.isEmpty }.joined(separator: " ")
        case .file:
            guard let summary = fileSelectionSummary else { return "" }
            if summary.isMultiFile {
                return [summary.albumCandidate, summary.albumArtistCandidate].filter { !$0.isEmpty }.joined(separator: " ")
            }
            guard let file = summary.files.first else { return "" }
            return [file.title, file.artist, file.album].filter { !$0.isEmpty }.joined(separator: " ")
        case .link:
            return link
        case .upc:
            return upc
        }
    }
}

enum iTunesSearchResults: Equatable {
    case tracks([iTunesTrackResult])
    case albums([iTunesAlbumResult])

    var count: Int {
        switch self {
        case .tracks(let values): return values.count
        case .albums(let values): return values.count
        }
    }

    var isEmpty: Bool { count == 0 }
}

struct iTunesTrackResult: Identifiable, Equatable, Hashable {
    let trackID: Int
    let collectionID: Int?
    let artistID: Int?
    let collectionArtistID: Int?
    let trackName: String
    let artistName: String
    let collectionArtistName: String
    let collectionName: String
    let trackNumber: Int
    let trackCount: Int
    let discNumber: Int
    let discCount: Int
    let durationMilliseconds: Int?
    let releaseDate: String
    let primaryGenreName: String
    let country: String
    let copyright: String
    let contentAdvisoryRating: String
    let kind: String
    let wrapperType: String
    let trackExplicitness: String
    let collectionExplicitness: String
    let trackViewURL: URL?
    let collectionViewURL: URL?
    let artistViewURL: URL?

    var id: Int { trackID }
    var isExplicit: Bool { contentAdvisory == .explicit }
    var contentAdvisory: ContentAdvisory? {
        ContentAdvisory.fromiTunesExplicitness(trackExplicitness)
    }
}

struct iTunesAlbumResult: Identifiable, Equatable, Hashable {
    let collectionID: Int
    let artistID: Int?
    let collectionArtistID: Int?
    let collectionName: String
    let artistName: String
    let collectionArtistName: String
    let trackCount: Int
    let releaseDate: String
    let primaryGenreName: String
    let country: String
    let copyright: String
    let contentAdvisoryRating: String
    let collectionExplicitness: String
    let collectionViewURL: URL?
    let artistViewURL: URL?
    var selectionMatchPreview: iTunesAlbumMatchPreview?
    var selectionMatchScore: Double?

    var id: Int { collectionID }
    var isExplicit: Bool { collectionExplicitness == "explicit" }
    var contentAdvisory: ContentAdvisory? {
        ContentAdvisory.fromiTunesExplicitness(collectionExplicitness)
    }
}

struct iTunesAlbumDetail: Equatable, Hashable {
    let album: iTunesAlbumResult
    let tracks: [iTunesTrackResult]
    var selectionMatchPreview: iTunesAlbumMatchPreview?
}

struct iTunesAlbumMatchAssignment: Identifiable, Equatable, Hashable {
    let id: String
    let file: iTunesFileSearchInput
    let track: iTunesTrackResult
    let score: Double
    let reason: String
}

struct iTunesAlbumMatchPreview: Equatable, Hashable {
    let totalSelectedFiles: Int
    let matchedAssignments: [iTunesAlbumMatchAssignment]
    let unmatchedFiles: [iTunesFileSearchInput]
    let unassignedTracks: [iTunesTrackResult]
    let overallScore: Double
}

enum iTunesAlbumMatcher {
    static func match(selection: iTunesFileSelectionSummary, detail: iTunesAlbumDetail) -> iTunesAlbumMatchPreview {
        let exactAssignments = greedyAssignments(
            from: buildCandidates(
                files: selection.files,
                tracks: detail.tracks,
                album: detail.album,
                exactOnly: true
            )
        )
        let exactFileIDs = Set(exactAssignments.map(\.file.id))
        let exactTrackIDs = Set(exactAssignments.map(\.track.trackID))

        let similarityAssignments = greedyAssignments(
            from: buildCandidates(
                files: selection.files.filter { !exactFileIDs.contains($0.id) },
                tracks: detail.tracks.filter { !exactTrackIDs.contains($0.trackID) },
                album: detail.album,
                exactOnly: false
            )
        )

        let assignments = (exactAssignments + similarityAssignments)
            .sorted {
                ($0.file.normalizedDiscNumber ?? 0, $0.file.normalizedTrackNumber ?? 0, $0.file.preferredDisplayTitle)
                    < ($1.file.normalizedDiscNumber ?? 0, $1.file.normalizedTrackNumber ?? 0, $1.file.preferredDisplayTitle)
            }

        let assignedFileIDs = Set(assignments.map(\.file.id))
        let assignedTrackIDs = Set(assignments.map(\.track.trackID))
        let unmatched = selection.files.filter { !assignedFileIDs.contains($0.id) }
        let unassignedTracks = detail.tracks.filter { !assignedTrackIDs.contains($0.trackID) }

        let averageTrackScore = assignments.isEmpty
            ? 0
            : assignments.map(\.score).reduce(0, +) / Double(assignments.count)
        let coverage = selection.files.isEmpty ? 0 : Double(assignments.count) / Double(selection.files.count)
        let albumScore = releaseScore(selection: selection, album: detail.album)
        var overallScore = (albumScore * 0.32) + (averageTrackScore * 0.43) + (coverage * 0.25)
        overallScore -= min(0.2, Double(unmatched.count) * 0.035)
        if selection.selectionLooksMixed {
            overallScore -= 0.05
        }

        return iTunesAlbumMatchPreview(
            totalSelectedFiles: selection.files.count,
            matchedAssignments: assignments,
            unmatchedFiles: unmatched,
            unassignedTracks: unassignedTracks,
            overallScore: min(1, max(0, overallScore))
        )
    }

    static func rerankTracks(_ tracks: [iTunesTrackResult], file: iTunesFileSearchInput) -> [iTunesTrackResult] {
        tracks.sorted {
            let lhsScore = trackSimilarityScore(track: $0, file: file, album: nil)
            let rhsScore = trackSimilarityScore(track: $1, file: file, album: nil)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return trackSort($0, $1)
        }
    }

    private static func buildCandidates(
        files: [iTunesFileSearchInput],
        tracks: [iTunesTrackResult],
        album: iTunesAlbumResult?,
        exactOnly: Bool
    ) -> [iTunesAlbumMatchAssignment] {
        var candidates: [iTunesAlbumMatchAssignment] = []

        for file in files {
            for track in tracks {
                guard let candidate = candidateAssignment(file: file, track: track, album: album, exactOnly: exactOnly) else {
                    continue
                }
                candidates.append(candidate)
            }
        }

        return candidates.sorted {
            if $0.score == $1.score {
                return $0.file.preferredDisplayTitle < $1.file.preferredDisplayTitle
            }
            return $0.score > $1.score
        }
    }

    private static func greedyAssignments(from candidates: [iTunesAlbumMatchAssignment]) -> [iTunesAlbumMatchAssignment] {
        var assignedFileIDs: Set<String> = []
        var assignedTrackIDs: Set<Int> = []
        var assignments: [iTunesAlbumMatchAssignment] = []

        for candidate in candidates {
            guard !assignedFileIDs.contains(candidate.file.id) else { continue }
            guard !assignedTrackIDs.contains(candidate.track.trackID) else { continue }

            assignedFileIDs.insert(candidate.file.id)
            assignedTrackIDs.insert(candidate.track.trackID)
            assignments.append(candidate)
        }

        return assignments
    }

    private static func candidateAssignment(
        file: iTunesFileSearchInput,
        track: iTunesTrackResult,
        album: iTunesAlbumResult?,
        exactOnly: Bool
    ) -> iTunesAlbumMatchAssignment? {
        if let exactReason = exactMatchReason(file: file, track: track) {
            return iTunesAlbumMatchAssignment(
                id: "\(file.id):\(track.trackID)",
                file: file,
                track: track,
                score: exactReason.score,
                reason: exactReason.reason
            )
        }

        guard !exactOnly else { return nil }

        var score = trackSimilarityScore(track: track, file: file, album: album)
        let isTitleVersionMatch = titleVersionMatch(file.title, track.trackName)
        guard score >= 0.48 || (isTitleVersionMatch && score >= 0.38) else { return nil }
        if isTitleVersionMatch {
            score = max(score, 0.62)
        }

        return iTunesAlbumMatchAssignment(
            id: "\(file.id):\(track.trackID)",
            file: file,
            track: track,
            score: score,
            reason: matchReason(file: file, track: track, isTitleVersionMatch: isTitleVersionMatch)
        )
    }

    private static func exactMatchReason(file: iTunesFileSearchInput, track: iTunesTrackResult) -> (score: Double, reason: String)? {
        let sameTrackNumber = file.normalizedTrackNumber == track.trackNumber
        let sameDiscNumber = file.normalizedDiscNumber == nil || file.normalizedDiscNumber == track.discNumber
        let titleScore = titleSimilarity(file.title, track.trackName)

        if sameTrackNumber, sameDiscNumber, titleScore >= 0.88 {
            return (0.94, "Track number + title")
        }

        if titleScore >= 0.96,
           durationSimilarity(file.durationMilliseconds, track.durationMilliseconds) >= 0.9,
           bestSimilarity(file.artistCandidates, candidates: [track.artistName, track.collectionArtistName]) >= 0.82 {
            return (0.93, "Title + artist + duration")
        }

        return nil
    }

    private static func trackSimilarityScore(
        track: iTunesTrackResult,
        file: iTunesFileSearchInput,
        album: iTunesAlbumResult?
    ) -> Double {
        let albumTitle = album?.collectionName ?? track.collectionName
        let albumArtist = album?.collectionArtistName ?? track.collectionArtistName
        let titleScore = titleSimilarity(file.title, track.trackName)
        let artistScore = bestSimilarity(file.artistCandidates, candidates: [track.artistName, albumArtist])
        let albumScore = FuzzyStringSimilarity.score(file.album, albumTitle)
        let durationScore = durationSimilarity(file.durationMilliseconds, track.durationMilliseconds)
        let trackNumberScore = trackIndexSimilarity(file.normalizedTrackNumber, candidateValue: track.trackNumber)
        let discNumberScore = discIndexSimilarity(file.normalizedDiscNumber, candidateValue: track.discNumber)

        return min(
            1,
            (titleScore * 0.40) +
            (artistScore * 0.17) +
            (durationScore * 0.16) +
            (trackNumberScore * 0.16) +
            (albumScore * 0.07) +
            (discNumberScore * 0.04)
        )
    }

    private static func releaseScore(selection: iTunesFileSelectionSummary, album: iTunesAlbumResult) -> Double {
        let albumScore = FuzzyStringSimilarity.score(selection.albumCandidate, album.collectionName) * 0.36
        let artistScore = bestSimilarity(
            [selection.albumArtistCandidate, selection.primaryArtistCandidate].filter { !$0.isEmpty },
            candidates: [album.collectionArtistName, album.artistName]
        ) * 0.26
        let yearScore = yearSimilarity(selection.releaseYearCandidate, candidateDate: album.releaseDate) * 0.10
        let countScore = trackCountSimilarity(selectedCount: selection.trackCountCandidate, albumTrackCount: album.trackCount) * 0.18
        let idScore = Int(selection.itunesAlbumIDCandidate) == album.collectionID ? 0.10 : 0

        return min(1, albumScore + artistScore + yearScore + countScore + idScore)
    }

    private static func trackIndexSimilarity(_ expected: Int?, candidateValue: Int) -> Double {
        guard let expected, candidateValue > 0 else { return 0 }
        if expected == candidateValue { return 1 }
        if abs(expected - candidateValue) == 1 { return 0.35 }
        return 0
    }

    private static func discIndexSimilarity(_ expected: Int?, candidateValue: Int) -> Double {
        guard let expected, candidateValue > 0 else { return 0 }
        return expected == candidateValue ? 1 : 0
    }

    private static func durationSimilarity(_ lhs: Int?, _ rhs: Int?) -> Double {
        guard let lhs, let rhs else { return 0 }
        let difference = abs(lhs - rhs)
        guard difference < 30_000 else { return 0 }
        return 1 - (Double(difference) / 30_000)
    }

    private static func yearSimilarity(_ queryYear: String, candidateDate: String) -> Double {
        let digits = candidateDate.filter(\.isNumber)
        guard digits.count >= 4, !queryYear.isEmpty else { return 0 }
        let candidateYear = String(digits.prefix(4))
        guard let queryValue = Int(queryYear), let candidateValue = Int(candidateYear) else { return 0 }

        switch abs(queryValue - candidateValue) {
        case 0: return 1
        case 1: return 0.65
        case 2: return 0.3
        default: return 0
        }
    }

    private static func trackCountSimilarity(selectedCount: Int, albumTrackCount: Int) -> Double {
        guard selectedCount > 0, albumTrackCount > 0 else { return 0 }
        if selectedCount == albumTrackCount { return 1 }
        if selectedCount < albumTrackCount { return 0.3 }
        return 0
    }

    private static func bestSimilarity(_ queries: [String], candidates: [String]) -> Double {
        var best = 0.0
        for query in queries {
            for candidate in candidates {
                best = max(best, FuzzyStringSimilarity.score(query, candidate))
            }
        }
        return best
    }

    private static func matchReason(
        file: iTunesFileSearchInput,
        track: iTunesTrackResult,
        isTitleVersionMatch: Bool
    ) -> String {
        if file.normalizedTrackNumber == track.trackNumber {
            return "Track number + metadata"
        }

        if isTitleVersionMatch {
            return "Title version"
        }

        return "Metadata similarity"
    }

    private static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        max(FuzzyStringSimilarity.score(lhs, rhs), titleVersionMatch(lhs, rhs) ? 0.98 : 0)
    }

    private static func titleVersionMatch(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedLHS = FuzzyStringSimilarity.normalize(lhs)
        let normalizedRHS = FuzzyStringSimilarity.normalize(rhs)
        guard !normalizedLHS.isEmpty, !normalizedRHS.isEmpty else { return false }
        guard normalizedLHS != normalizedRHS else { return true }

        let shorter = normalizedLHS.count <= normalizedRHS.count ? normalizedLHS : normalizedRHS
        let longer = normalizedLHS.count <= normalizedRHS.count ? normalizedRHS : normalizedLHS
        let shorterTokens = FuzzyStringSimilarity.tokens(in: shorter)

        guard shorter.count >= 12 || shorterTokens.count >= 3 else { return false }
        return FuzzyStringSimilarity.tokenSequenceContains(longer, sequence: shorter)
    }

    private static func trackSort(_ lhs: iTunesTrackResult, _ rhs: iTunesTrackResult) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.trackName < rhs.trackName
    }
}

enum iTunesClientError: LocalizedError {
    case emptyQuery
    case invalidCountry
    case failedToBuildURL
    case unsupportedLink
    case requestFailed(Int)
    case invalidResponseBody

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Query cannot be empty."
        case .invalidCountry:
            return "Country must be a two-letter storefront code."
        case .failedToBuildURL:
            return "Failed to build the iTunes request."
        case .unsupportedLink:
            return "That link did not contain a supported Apple Music or iTunes album/track ID."
        case .requestFailed(let code):
            return "The iTunes request failed with status code \(code)."
        case .invalidResponseBody:
            return "The iTunes response could not be decoded."
        }
    }
}

struct iTunesClient: Sendable {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func search(matching query: iTunesSearchQuery, limit: Int = 25) async throws -> iTunesSearchResults {
        guard !query.isEmpty else { throw iTunesClientError.emptyQuery }

        switch query.mode {
        case .track:
            return .tracks(try await searchTracks(term: query.searchTerm, country: query.country, limit: limit))
        case .album:
            return .albums(try await searchAlbums(term: query.searchTerm, country: query.country, limit: limit))
        case .file:
            return try await searchFiles(matching: query, limit: limit)
        case .link:
            return try await searchByLink(query.link, country: query.country)
        case .upc:
            let detail = try await lookupUPC(query.upc, country: query.country)
            return .albums(detail.map { [$0.album] } ?? [])
        }
    }

    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        let results = try await request(
            path: "/lookup",
            queryItems: [
                URLQueryItem(name: "id", value: String(collectionID)),
                URLQueryItem(name: "country", value: normalizedCountry(country)),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "200")
            ]
        )

        let album = results.compactMap(Self.albumResult(from:)).first
        let tracks = results.compactMap(Self.trackResult(from:)).sorted(by: Self.trackSort)

        guard let album else { throw iTunesClientError.invalidResponseBody }
        return iTunesAlbumDetail(album: album, tracks: tracks, selectionMatchPreview: nil)
    }

    private func searchFiles(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        guard let summary = query.fileSelectionSummary else { throw iTunesClientError.emptyQuery }

        if let collectionID = Int(summary.itunesAlbumIDCandidate) {
            var detail = try await albumDetail(collectionID: collectionID, country: query.country)
            detail.selectionMatchPreview = iTunesAlbumMatcher.match(selection: summary, detail: detail)
            return .albums([detail.album.withPreview(detail.selectionMatchPreview)])
        }

        if !summary.barcodeCandidate.isEmpty, let detail = try await lookupUPC(summary.barcodeCandidate, country: query.country) {
            var resolved = detail
            resolved.selectionMatchPreview = iTunesAlbumMatcher.match(selection: summary, detail: resolved)
            return .albums([resolved.album.withPreview(resolved.selectionMatchPreview)])
        }

        if summary.isMultiFile {
            let albums = try await albumCandidates(for: summary, query: query, limit: max(limit, 25))
            var matchedAlbumsByID: [Int: iTunesAlbumResult] = [:]

            for album in albums.prefix(18) {
                do {
                    var detail = try await albumDetail(collectionID: album.collectionID, country: query.country)
                    let preview = iTunesAlbumMatcher.match(selection: summary, detail: detail)
                    detail.selectionMatchPreview = preview
                    matchedAlbumsByID[album.collectionID] = detail.album.withPreview(preview)
                } catch {
                    matchedAlbumsByID[album.collectionID] = album
                }
            }

            return .albums(
                Array(matchedAlbumsByID.values).sorted {
                    ($0.selectionMatchScore ?? 0) == ($1.selectionMatchScore ?? 0)
                        ? $0.trackCount > $1.trackCount
                        : ($0.selectionMatchScore ?? 0) > ($1.selectionMatchScore ?? 0)
                }
            )
        }

        let tracks = try await searchTracks(term: query.searchTerm, country: query.country, limit: max(limit, 50))
        guard let file = summary.files.first else { return .tracks(tracks) }
        return .tracks(iTunesAlbumMatcher.rerankTracks(tracks, file: file))
    }

    private func albumCandidates(
        for summary: iTunesFileSelectionSummary,
        query: iTunesSearchQuery,
        limit: Int
    ) async throws -> [iTunesAlbumResult] {
        var albumsByID: [Int: iTunesAlbumResult] = [:]

        func append(_ albums: [iTunesAlbumResult]) {
            for album in albums {
                albumsByID[album.collectionID] = album
            }
        }

        append(try await searchAlbums(term: query.searchTerm, country: query.country, limit: limit))

        let albumArtistTerm = [summary.albumCandidate, summary.albumArtistCandidate]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !albumArtistTerm.isEmpty, albumArtistTerm != query.searchTerm {
            do {
                append(try await searchAlbums(term: albumArtistTerm, country: query.country, limit: min(limit, 25)))
            } catch {
                // Keep the primary album search usable if a secondary recall query fails.
            }
        }

        let representativeFiles = representativeFilesForAlbumDiscovery(summary.files)
        for file in representativeFiles {
            let term = [file.title, file.artist, file.album]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !term.isEmpty else { continue }

            let tracks: [iTunesTrackResult]
            do {
                tracks = try await searchTracks(term: term, country: query.country, limit: 12)
            } catch {
                continue
            }
            for track in iTunesAlbumMatcher.rerankTracks(tracks, file: file) {
                guard let collectionID = track.collectionID, albumsByID[collectionID] == nil else { continue }
                albumsByID[collectionID] = iTunesAlbumResult(
                    collectionID: collectionID,
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
        }

        return Array(albumsByID.values).sorted {
            if $0.trackCount == $1.trackCount {
                return $0.collectionName < $1.collectionName
            }
            return $0.trackCount > $1.trackCount
        }
    }

    private func representativeFilesForAlbumDiscovery(_ files: [iTunesFileSearchInput]) -> [iTunesFileSearchInput] {
        let preferred = files.sorted {
            let lhsNumber = $0.normalizedTrackNumber ?? Int.max
            let rhsNumber = $1.normalizedTrackNumber ?? Int.max
            if lhsNumber != rhsNumber { return lhsNumber < rhsNumber }
            return $0.preferredDisplayTitle < $1.preferredDisplayTitle
        }

        var result: [iTunesFileSearchInput] = []
        for file in preferred {
            guard !file.title.isEmpty || !file.artist.isEmpty else { continue }
            result.append(file)
            if result.count >= 5 { break }
        }
        return result
    }

    private func searchByLink(_ link: String, country: String) async throws -> iTunesSearchResults {
        let parsed = try iTunesLinkParser.parse(link)

        switch parsed {
        case .album(let id):
            return .albums([try await albumDetail(collectionID: id, country: country).album])
        case .track(let id):
            let results = try await request(
                path: "/lookup",
                queryItems: [
                    URLQueryItem(name: "id", value: String(id)),
                    URLQueryItem(name: "country", value: normalizedCountry(country))
                ]
            )
            return .tracks(results.compactMap(Self.trackResult(from:)))
        }
    }

    private func lookupUPC(_ upc: String, country: String) async throws -> iTunesAlbumDetail? {
        let results = try await request(
            path: "/lookup",
            queryItems: [
                URLQueryItem(name: "upc", value: upc.trimmedForiTunes),
                URLQueryItem(name: "country", value: normalizedCountry(country)),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "200")
            ]
        )
        let album = results.compactMap(Self.albumResult(from:)).first
        let tracks = results.compactMap(Self.trackResult(from:)).sorted(by: Self.trackSort)
        return album.map { iTunesAlbumDetail(album: $0, tracks: tracks, selectionMatchPreview: nil) }
    }

    private func searchTracks(term: String, country: String, limit: Int) async throws -> [iTunesTrackResult] {
        let results = try await request(
            path: "/search",
            queryItems: searchItems(term: term, country: country, entity: "song", limit: limit)
        )
        return results.compactMap(Self.trackResult(from:))
    }

    private func searchAlbums(term: String, country: String, limit: Int) async throws -> [iTunesAlbumResult] {
        let results = try await request(
            path: "/search",
            queryItems: searchItems(term: term, country: country, entity: "album", limit: limit)
        )
        return results.compactMap(Self.albumResult(from:))
    }

    private func searchItems(term: String, country: String, entity: String, limit: Int) throws -> [URLQueryItem] {
        [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: try normalizedCountry(country)),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))
        ]
    }

    private func normalizedCountry(_ country: String) throws -> String {
        let normalized = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 2 else { throw iTunesClientError.invalidCountry }
        return normalized
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> [[String: Any]] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else { throw iTunesClientError.failedToBuildURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw iTunesClientError.invalidResponseBody }
        guard (200..<300).contains(http.statusCode) else { throw iTunesClientError.requestFailed(http.statusCode) }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [[String: Any]]
        else {
            throw iTunesClientError.invalidResponseBody
        }
        return results
    }

    private static func trackResult(from raw: [String: Any]) -> iTunesTrackResult? {
        guard let trackID = raw["trackId"] as? Int else { return nil }
        return iTunesTrackResult(
            trackID: trackID,
            collectionID: raw["collectionId"] as? Int,
            artistID: raw["artistId"] as? Int,
            collectionArtistID: raw["collectionArtistId"] as? Int,
            trackName: raw["trackName"] as? String ?? "",
            artistName: raw["artistName"] as? String ?? "",
            collectionArtistName: raw["collectionArtistName"] as? String ?? "",
            collectionName: raw["collectionName"] as? String ?? "",
            trackNumber: raw["trackNumber"] as? Int ?? 0,
            trackCount: raw["trackCount"] as? Int ?? 0,
            discNumber: raw["discNumber"] as? Int ?? 0,
            discCount: raw["discCount"] as? Int ?? 0,
            durationMilliseconds: raw["trackTimeMillis"] as? Int,
            releaseDate: normalizedDate(raw["releaseDate"] as? String),
            primaryGenreName: raw["primaryGenreName"] as? String ?? "",
            country: raw["country"] as? String ?? "",
            copyright: raw["copyright"] as? String ?? "",
            contentAdvisoryRating: raw["contentAdvisoryRating"] as? String ?? "",
            kind: raw["kind"] as? String ?? "",
            wrapperType: raw["wrapperType"] as? String ?? "",
            trackExplicitness: raw["trackExplicitness"] as? String ?? "",
            collectionExplicitness: raw["collectionExplicitness"] as? String ?? "",
            trackViewURL: (raw["trackViewUrl"] as? String).flatMap(URL.init(string:)),
            collectionViewURL: (raw["collectionViewUrl"] as? String).flatMap(URL.init(string:)),
            artistViewURL: (raw["artistViewUrl"] as? String).flatMap(URL.init(string:))
        )
    }

    private static func albumResult(from raw: [String: Any]) -> iTunesAlbumResult? {
        guard let collectionID = raw["collectionId"] as? Int else { return nil }
        return iTunesAlbumResult(
            collectionID: collectionID,
            artistID: raw["artistId"] as? Int,
            collectionArtistID: raw["collectionArtistId"] as? Int,
            collectionName: raw["collectionName"] as? String ?? "",
            artistName: raw["artistName"] as? String ?? "",
            collectionArtistName: raw["collectionArtistName"] as? String ?? "",
            trackCount: raw["trackCount"] as? Int ?? 0,
            releaseDate: normalizedDate(raw["releaseDate"] as? String),
            primaryGenreName: raw["primaryGenreName"] as? String ?? "",
            country: raw["country"] as? String ?? "",
            copyright: raw["copyright"] as? String ?? "",
            contentAdvisoryRating: raw["contentAdvisoryRating"] as? String ?? "",
            collectionExplicitness: raw["collectionExplicitness"] as? String ?? "",
            collectionViewURL: (raw["collectionViewUrl"] as? String).flatMap(URL.init(string:)),
            artistViewURL: (raw["artistViewUrl"] as? String).flatMap(URL.init(string:)),
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }

    private static func normalizedDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return String(value.prefix(10))
    }

    private static func trackSort(_ lhs: iTunesTrackResult, _ rhs: iTunesTrackResult) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.trackName < rhs.trackName
    }
}

private extension iTunesAlbumResult {
    func withPreview(_ preview: iTunesAlbumMatchPreview?) -> iTunesAlbumResult {
        var copy = self
        copy.selectionMatchPreview = preview
        copy.selectionMatchScore = preview?.overallScore
        return copy
    }
}

enum iTunesParsedLink {
    case album(Int)
    case track(Int)
}

enum iTunesLinkParser {
    static func parse(_ rawValue: String) throws -> iTunesParsedLink {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) {
            return .album(id)
        }

        guard let components = URLComponents(string: trimmed) else {
            throw iTunesClientError.unsupportedLink
        }

        let items = components.queryItems ?? []
        if let trackID = items.first(where: { $0.name == "i" })?.value.flatMap(Int.init) {
            return .track(trackID)
        }
        if let albumID = items.first(where: { $0.name == "id" })?.value.flatMap(Int.init) {
            return .album(albumID)
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        if let idPart = pathParts.last(where: { $0.hasPrefix("id") }) {
            let digits = String(idPart.dropFirst(2))
            if let id = Int(digits) {
                return .album(id)
            }
        }

        throw iTunesClientError.unsupportedLink
    }
}

private extension String {
    var trimmedForiTunes: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
