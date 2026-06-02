import Foundation

struct LRCLIBFileSearchInput: Identifiable, Equatable, Hashable, Sendable {
    let id: AudioFile.ID
    let fileName: String
    let title: String
    let artist: String
    let album: String
    let durationSeconds: Int?

    init(file: AudioFile) {
        let fallback = MusicBrainzFilenameFallbackResolver.makeSearchInput(for: file)
        self.id = file.id
        self.fileName = file.url.lastPathComponent
        self.title = Self.preferred(file.title, fallback: fallback.title)
        self.artist = Self.preferred(file.artist, fallback: fallback.artist)
        self.album = Self.preferred(file.album, fallback: fallback.album)
        self.durationSeconds = file.duration.isFinite && file.duration > 0
            ? Int(file.duration.rounded())
            : fallback.durationMilliseconds.map { Int((Double($0) / 1000.0).rounded()) }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return fileName
    }

    var query: LRCLIBSearchQuery {
        LRCLIBSearchQuery(
            trackName: title,
            artistName: artist,
            albumName: album,
            durationSeconds: durationSeconds
        )
    }

    private static func preferred(_ primary: String, fallback: String) -> String {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrimary.isEmpty { return trimmedPrimary }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LRCLIBClient: LRCLIBLyricsSearching {
    nonisolated private static let baseURL = URL(string: "https://lrclib.net")!

    private let session: URLSession
    private let userAgent: String

    nonisolated init(session: URLSession = .shared) {
        self.session = session

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.chrislloydme.AudioMator"
        let contactURL = "https://github.com/ChrisLloydME/AudioMator"
        self.userAgent = "AudioMator/\(version) (\(contactURL); \(bundleIdentifier))"
    }

    nonisolated func search(matching query: LRCLIBSearchQuery, limit: Int = 20) async throws -> [LRCLIBLyricsCandidate] {
        guard !query.isEmpty else { throw LRCLIBClientError.emptyQuery }

        let request = try makeSearchRequest(for: query)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LRCLIBClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LRCLIBClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let candidates = try JSONDecoder().decode([LRCLIBLyricsCandidate].self, from: data)
        return Array(candidates.prefix(max(1, limit)))
    }

    nonisolated func makeSearchRequest(for query: LRCLIBSearchQuery) throws -> URLRequest {
        guard !query.isEmpty else { throw LRCLIBClientError.emptyQuery }

        var components = URLComponents(
            url: Self.baseURL.appending(path: "api").appending(path: "search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = Self.queryItems(for: query)

        guard let url = components?.url else {
            throw LRCLIBClientError.invalidRequest
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    nonisolated private static func queryItems(for query: LRCLIBSearchQuery) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        appendItem(name: "track_name", value: query.trackName, to: &items)
        appendItem(name: "artist_name", value: query.artistName, to: &items)
        appendItem(name: "album_name", value: query.albumName, to: &items)
        if let durationSeconds = query.durationSeconds, durationSeconds > 0 {
            items.append(URLQueryItem(name: "duration", value: String(durationSeconds)))
        }
        return items
    }

    nonisolated private static func appendItem(name: String, value: String, to items: inout [URLQueryItem]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(URLQueryItem(name: name, value: trimmed))
    }
}
