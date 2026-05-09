import Foundation

enum ITunesSearchMode: String, CaseIterable, Identifiable {
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

enum ITunesStorefront: String, CaseIterable, Identifiable, Hashable {
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

struct ITunesFileSearchInput: Identifiable, Equatable, Hashable {
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
        Self.normalizedIndex(trackNumber)
    }

    var normalizedDiscNumber: Int? {
        Self.normalizedIndex(discNumber)
    }

    private static func normalizedIndex(_ rawValue: String) -> Int? {
        let normalized = rawValue
            .split(separator: "/")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawValue
        guard !normalized.isEmpty else { return nil }
        let stripped = String(normalized.drop(while: { $0 == "0" }))
        return Int(stripped.isEmpty ? normalized : stripped).flatMap { $0 > 0 ? $0 : nil }
    }
}

struct ITunesFileSelectionSummary: Equatable, Hashable {
    let files: [ITunesFileSearchInput]
    let albumCandidate: String
    let albumArtistCandidate: String
    let primaryArtistCandidate: String
    let trackCountCandidate: Int
    let barcodeCandidate: String
    let itunesAlbumIDCandidate: String

    init(files: [ITunesFileSearchInput]) {
        self.files = files
        self.albumCandidate = Self.majorityValue(files.map(\.album))
        self.albumArtistCandidate = Self.majorityValue(
            files.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist }
        )
        self.primaryArtistCandidate = Self.majorityValue(files.map(\.artist))
        self.trackCountCandidate = max(Self.majorityInt(files.map(\.trackTotal).filter { $0 > 0 }) ?? 0, files.count)
        self.barcodeCandidate = Self.majorityValue(files.map(\.barcode))
        self.itunesAlbumIDCandidate = Self.majorityValue(files.map(\.itunesAlbumID))
    }

    var isMultiFile: Bool { files.count > 1 }

    private static func majorityValue(_ values: [String]) -> String {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        var counts: [String: Int] = [:]
        var best = cleaned[0]
        var bestCount = 0
        for value in cleaned {
            let count = (counts[value] ?? 0) + 1
            counts[value] = count
            if count > bestCount {
                best = value
                bestCount = count
            }
        }
        return best
    }

    private static func majorityInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        var best = values[0]
        var bestCount = 0
        for value in values {
            let count = (counts[value] ?? 0) + 1
            counts[value] = count
            if count > bestCount {
                best = value
                bestCount = count
            }
        }
        return best
    }
}

struct ITunesSearchQuery: Equatable {
    var mode: ITunesSearchMode = .track
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var upc: String = ""
    var link: String = ""
    var country: String = "us"
    var fileInputs: [ITunesFileSearchInput] = []

    var isEmpty: Bool {
        switch mode {
        case .track:
            return title.trimmedForITunes.isEmpty && artist.trimmedForITunes.isEmpty && album.trimmedForITunes.isEmpty
        case .album:
            return album.trimmedForITunes.isEmpty && artist.trimmedForITunes.isEmpty
        case .file:
            return effectiveFileInputs.isEmpty
        case .link:
            return link.trimmedForITunes.isEmpty
        case .upc:
            return upc.trimmedForITunes.isEmpty
        }
    }

    var effectiveFileInputs: [ITunesFileSearchInput] { fileInputs }

    var fileSelectionSummary: ITunesFileSelectionSummary? {
        guard !effectiveFileInputs.isEmpty else { return nil }
        return ITunesFileSelectionSummary(files: effectiveFileInputs)
    }

    var searchTerm: String {
        switch mode {
        case .track:
            return [title, artist, album].map(\.trimmedForITunes).filter { !$0.isEmpty }.joined(separator: " ")
        case .album:
            return [album, artist].map(\.trimmedForITunes).filter { !$0.isEmpty }.joined(separator: " ")
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

enum ITunesSearchResults: Equatable {
    case tracks([ITunesTrackResult])
    case albums([ITunesAlbumResult])

    var count: Int {
        switch self {
        case .tracks(let values): return values.count
        case .albums(let values): return values.count
        }
    }

    var isEmpty: Bool { count == 0 }
}

struct ITunesTrackResult: Identifiable, Equatable, Hashable {
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
    var isExplicit: Bool { trackExplicitness == "explicit" || collectionExplicitness == "explicit" }
}

struct ITunesAlbumResult: Identifiable, Equatable, Hashable {
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
    var selectionMatchPreview: ITunesAlbumMatchPreview?
    var selectionMatchScore: Double?

    var id: Int { collectionID }
    var isExplicit: Bool { collectionExplicitness == "explicit" }
}

struct ITunesAlbumDetail: Equatable, Hashable {
    let album: ITunesAlbumResult
    let tracks: [ITunesTrackResult]
    var selectionMatchPreview: ITunesAlbumMatchPreview?
}

struct ITunesAlbumMatchAssignment: Identifiable, Equatable, Hashable {
    let id: String
    let file: ITunesFileSearchInput
    let track: ITunesTrackResult
    let score: Double
    let reason: String
}

struct ITunesAlbumMatchPreview: Equatable, Hashable {
    let totalSelectedFiles: Int
    let matchedAssignments: [ITunesAlbumMatchAssignment]
    let unmatchedFiles: [ITunesFileSearchInput]
    let unassignedTracks: [ITunesTrackResult]
    let overallScore: Double
}

enum ITunesAlbumMatcher {
    static func match(selection: ITunesFileSelectionSummary, detail: ITunesAlbumDetail) -> ITunesAlbumMatchPreview {
        var remainingTracks = detail.tracks
        var assignments: [ITunesAlbumMatchAssignment] = []
        var unmatched: [ITunesFileSearchInput] = []

        for file in selection.files {
            let scored = remainingTracks.map { track in
                (track, trackScore(track, file: file))
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return trackSort($0.0, $1.0)
            }

            guard let best = scored.first, best.1 >= 0.32 else {
                unmatched.append(file)
                continue
            }

            remainingTracks.removeAll { $0.trackID == best.0.trackID }
            assignments.append(
                ITunesAlbumMatchAssignment(
                    id: "\(file.id):\(best.0.trackID)",
                    file: file,
                    track: best.0,
                    score: best.1,
                    reason: matchReason(track: best.0, file: file)
                )
            )
        }

        let average = assignments.isEmpty
            ? 0
            : assignments.map(\.score).reduce(0, +) / Double(assignments.count)
        let coverage = selection.files.isEmpty ? 0 : Double(assignments.count) / Double(selection.files.count)

        return ITunesAlbumMatchPreview(
            totalSelectedFiles: selection.files.count,
            matchedAssignments: assignments,
            unmatchedFiles: unmatched,
            unassignedTracks: remainingTracks,
            overallScore: (average * 0.72) + (coverage * 0.28)
        )
    }

    static func rerankTracks(_ tracks: [ITunesTrackResult], file: ITunesFileSearchInput) -> [ITunesTrackResult] {
        tracks.sorted {
            let lhsScore = trackScore($0, file: file)
            let rhsScore = trackScore($1, file: file)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return trackSort($0, $1)
        }
    }

    private static func trackScore(_ track: ITunesTrackResult, file: ITunesFileSearchInput) -> Double {
        var score = 0.0
        let normalizedTrackName = normalized(track.trackName)
        let normalizedFileTitle = normalized(file.title)

        if normalizedTrackName == normalizedFileTitle, !file.title.isEmpty { score += 0.34 }
        else if normalizedTrackName.contains(normalizedFileTitle), !file.title.isEmpty { score += 0.18 }
        if normalized(track.artistName) == normalized(file.artist), !file.artist.isEmpty { score += 0.16 }
        if normalized(track.collectionName) == normalized(file.album), !file.album.isEmpty { score += 0.10 }
        if let number = file.normalizedTrackNumber, number == track.trackNumber { score += 0.34 }
        if let disc = file.normalizedDiscNumber, disc == track.discNumber { score += 0.10 }
        if let localDuration = file.durationMilliseconds, let remoteDuration = track.durationMilliseconds {
            let delta = abs(localDuration - remoteDuration)
            if delta <= 2_500 { score += 0.12 }
            else if delta <= 7_500 { score += 0.06 }
        }
        return min(score, 1.0)
    }

    private static func matchReason(track: ITunesTrackResult, file: ITunesFileSearchInput) -> String {
        var parts: [String] = []
        if let disc = file.normalizedDiscNumber, disc == track.discNumber { parts.append("disc number") }
        if let number = file.normalizedTrackNumber, number == track.trackNumber { parts.append("track number") }
        if normalized(track.trackName) == normalized(file.title), !file.title.isEmpty { parts.append("title") }
        if normalized(track.artistName) == normalized(file.artist), !file.artist.isEmpty { parts.append("artist") }
        if let localDuration = file.durationMilliseconds, let remoteDuration = track.durationMilliseconds,
           abs(localDuration - remoteDuration) <= 2_500 {
            parts.append("duration")
        }
        return parts.isEmpty ? "metadata similarity" : parts.joined(separator: ", ")
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trackSort(_ lhs: ITunesTrackResult, _ rhs: ITunesTrackResult) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.trackName < rhs.trackName
    }
}

enum ITunesClientError: LocalizedError {
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

struct ITunesClient: Sendable {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func search(matching query: ITunesSearchQuery, limit: Int = 25) async throws -> ITunesSearchResults {
        guard !query.isEmpty else { throw ITunesClientError.emptyQuery }

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

    func albumDetail(collectionID: Int, country: String) async throws -> ITunesAlbumDetail {
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

        guard let album else { throw ITunesClientError.invalidResponseBody }
        return ITunesAlbumDetail(album: album, tracks: tracks, selectionMatchPreview: nil)
    }

    private func searchFiles(matching query: ITunesSearchQuery, limit: Int) async throws -> ITunesSearchResults {
        guard let summary = query.fileSelectionSummary else { throw ITunesClientError.emptyQuery }

        if let collectionID = Int(summary.itunesAlbumIDCandidate) {
            var detail = try await albumDetail(collectionID: collectionID, country: query.country)
            detail.selectionMatchPreview = ITunesAlbumMatcher.match(selection: summary, detail: detail)
            return .albums([detail.album.withPreview(detail.selectionMatchPreview)])
        }

        if !summary.barcodeCandidate.isEmpty, let detail = try await lookupUPC(summary.barcodeCandidate, country: query.country) {
            var resolved = detail
            resolved.selectionMatchPreview = ITunesAlbumMatcher.match(selection: summary, detail: resolved)
            return .albums([resolved.album.withPreview(resolved.selectionMatchPreview)])
        }

        if summary.isMultiFile {
            let albums = try await searchAlbums(term: query.searchTerm, country: query.country, limit: max(limit, 12))
            var matchedAlbums: [ITunesAlbumResult] = []

            for album in albums.prefix(8) {
                do {
                    var detail = try await albumDetail(collectionID: album.collectionID, country: query.country)
                    let preview = ITunesAlbumMatcher.match(selection: summary, detail: detail)
                    detail.selectionMatchPreview = preview
                    matchedAlbums.append(album.withPreview(preview))
                } catch {
                    matchedAlbums.append(album)
                }
            }

            return .albums(
                matchedAlbums.sorted {
                    ($0.selectionMatchScore ?? 0) == ($1.selectionMatchScore ?? 0)
                        ? $0.trackCount > $1.trackCount
                        : ($0.selectionMatchScore ?? 0) > ($1.selectionMatchScore ?? 0)
                }
            )
        }

        let tracks = try await searchTracks(term: query.searchTerm, country: query.country, limit: max(limit, 50))
        guard let file = summary.files.first else { return .tracks(tracks) }
        return .tracks(ITunesAlbumMatcher.rerankTracks(tracks, file: file))
    }

    private func searchByLink(_ link: String, country: String) async throws -> ITunesSearchResults {
        let parsed = try ITunesLinkParser.parse(link)

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

    private func lookupUPC(_ upc: String, country: String) async throws -> ITunesAlbumDetail? {
        let results = try await request(
            path: "/lookup",
            queryItems: [
                URLQueryItem(name: "upc", value: upc.trimmedForITunes),
                URLQueryItem(name: "country", value: normalizedCountry(country)),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "200")
            ]
        )
        let album = results.compactMap(Self.albumResult(from:)).first
        let tracks = results.compactMap(Self.trackResult(from:)).sorted(by: Self.trackSort)
        return album.map { ITunesAlbumDetail(album: $0, tracks: tracks, selectionMatchPreview: nil) }
    }

    private func searchTracks(term: String, country: String, limit: Int) async throws -> [ITunesTrackResult] {
        let results = try await request(
            path: "/search",
            queryItems: searchItems(term: term, country: country, entity: "song", limit: limit)
        )
        return results.compactMap(Self.trackResult(from:))
    }

    private func searchAlbums(term: String, country: String, limit: Int) async throws -> [ITunesAlbumResult] {
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
        guard normalized.count == 2 else { throw ITunesClientError.invalidCountry }
        return normalized
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> [[String: Any]] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else { throw ITunesClientError.failedToBuildURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ITunesClientError.invalidResponseBody }
        guard (200..<300).contains(http.statusCode) else { throw ITunesClientError.requestFailed(http.statusCode) }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [[String: Any]]
        else {
            throw ITunesClientError.invalidResponseBody
        }
        return results
    }

    private static func trackResult(from raw: [String: Any]) -> ITunesTrackResult? {
        guard let trackID = raw["trackId"] as? Int else { return nil }
        return ITunesTrackResult(
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

    private static func albumResult(from raw: [String: Any]) -> ITunesAlbumResult? {
        guard let collectionID = raw["collectionId"] as? Int else { return nil }
        return ITunesAlbumResult(
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

    private static func trackSort(_ lhs: ITunesTrackResult, _ rhs: ITunesTrackResult) -> Bool {
        if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
        if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
        return lhs.trackName < rhs.trackName
    }
}

private extension ITunesAlbumResult {
    func withPreview(_ preview: ITunesAlbumMatchPreview?) -> ITunesAlbumResult {
        var copy = self
        copy.selectionMatchPreview = preview
        copy.selectionMatchScore = preview?.overallScore
        return copy
    }
}

enum ITunesParsedLink {
    case album(Int)
    case track(Int)
}

enum ITunesLinkParser {
    static func parse(_ rawValue: String) throws -> ITunesParsedLink {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) {
            return .album(id)
        }

        guard let components = URLComponents(string: trimmed) else {
            throw ITunesClientError.unsupportedLink
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

        throw ITunesClientError.unsupportedLink
    }
}

private extension String {
    var trimmedForITunes: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
