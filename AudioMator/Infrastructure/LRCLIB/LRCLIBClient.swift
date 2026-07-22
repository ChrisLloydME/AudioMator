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
        self.durationSeconds = AudioNumericConversion.positiveDurationSeconds(file.duration)
            ?? fallback.durationMilliseconds.flatMap {
                AudioNumericConversion.positiveDurationSeconds(Double($0) / 1_000)
            }
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
        try LRCLIBRequestBuilder.makeSearchRequest(for: query, userAgent: userAgent)
    }
}
