import Foundation

struct MusicBrainzSearchQuery: Equatable {
    var title: String
    var artist: String
    var album: String

    init(
        title: String = "",
        artist: String = "",
        album: String = ""
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        title.isEmpty && artist.isEmpty && album.isEmpty
    }

    var summaryText: String {
        var parts: [String] = []

        if !title.isEmpty {
            parts.append("title: \(title)")
        }

        if !artist.isEmpty {
            parts.append("artist: \(artist)")
        }

        if !album.isEmpty {
            parts.append("album: \(album)")
        }

        return parts.joined(separator: " • ")
    }
}

struct MusicBrainzRecordingResult: Identifiable, Equatable {
    struct Release: Identifiable, Equatable {
        let id: String
        let title: String
        let date: String
        let country: String
        let status: String

        var musicBrainzURL: URL? {
            URL(string: "https://musicbrainz.org/release/\(id)")
        }
    }

    let id: String
    let title: String
    let artistCredit: String
    let score: Int
    let disambiguation: String
    let firstReleaseDate: String
    let durationMilliseconds: Int?
    let releases: [Release]

    var musicBrainzURL: URL? {
        URL(string: "https://musicbrainz.org/recording/\(id)")
    }

    var primaryRelease: Release? {
        releases.first
    }
}

enum MusicBrainzClientError: LocalizedError {
    case emptyQuery
    case invalidRequest
    case requestFailed(statusCode: Int)
    case invalidResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter at least one field before searching MusicBrainz."
        case .invalidRequest:
            return "The MusicBrainz request could not be created."
        case .requestFailed(let statusCode):
            return "MusicBrainz returned HTTP \(statusCode)."
        case .invalidResponse:
            return "MusicBrainz returned an unexpected response."
        case .decodingFailed(let detail):
            return "MusicBrainz returned data, but AudioMator could not decode it. \(detail)"
        }
    }
}

actor MusicBrainzRateLimiter {
    private let minimumIntervalNanoseconds: UInt64
    private var lastRequestUptimeNanoseconds: UInt64?

    init(minimumIntervalNanoseconds: UInt64 = 1_100_000_000) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
    }

    func waitIfNeeded() async throws {
        let now = DispatchTime.now().uptimeNanoseconds

        if let lastRequestUptimeNanoseconds {
            let elapsed = now &- lastRequestUptimeNanoseconds
            if elapsed < minimumIntervalNanoseconds {
                try await Task.sleep(nanoseconds: minimumIntervalNanoseconds - elapsed)
            }
        }

        lastRequestUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    }
}

struct MusicBrainzClient {
    private static let baseURL = URL(string: "https://musicbrainz.org/ws/2")!

    private let session: URLSession
    private let decoder: JSONDecoder
    private let rateLimiter: MusicBrainzRateLimiter
    private let userAgent: String

    init(
        session: URLSession = .shared,
        rateLimiter: MusicBrainzRateLimiter = MusicBrainzRateLimiter()
    ) {
        self.session = session
        self.rateLimiter = rateLimiter

        let decoder = JSONDecoder()
        self.decoder = decoder

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        // MusicBrainz asks clients to identify themselves clearly. Replace this with a contact
        // URL or email before distributing the app more broadly.
        self.userAgent = "AudioMator/\(version) (local macOS project)"
    }

    func searchRecordings(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> [MusicBrainzRecordingResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let luceneQuery = MusicBrainzLuceneQueryBuilder.recordingSearchQuery(from: query)

        var components = URLComponents(
            url: Self.baseURL.appending(path: "recording"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "query", value: luceneQuery),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
        ]

        guard let url = components?.url else {
            throw MusicBrainzClientError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        try await rateLimiter.waitIfNeeded()
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MusicBrainzClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let payload: MusicBrainzRecordingSearchResponse
        do {
            payload = try decoder.decode(MusicBrainzRecordingSearchResponse.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }
        return payload.recordings.map(MusicBrainzRecordingResult.init)
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        func codingPathDescription(_ path: [CodingKey]) -> String {
            let parts = path.map(\.stringValue).filter { !$0.isEmpty }
            return parts.isEmpty ? "(root)" : parts.joined(separator: ".")
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(codingPathDescription(context.codingPath))."
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(codingPathDescription(context.codingPath))."
        case .dataCorrupted(let context):
            return "Corrupted data at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error."
        }
    }
}

private enum MusicBrainzLuceneQueryBuilder {
    private static let reservedCharacters: Set<Character> = Set(#"+-&|!(){}[]^"~*?:\/"#)

    static func recordingSearchQuery(from query: MusicBrainzSearchQuery) -> String {
        var clauses: [String] = []

        if !query.title.isEmpty {
            clauses.append(fieldClause(name: "recording", value: query.title))
        }

        if !query.artist.isEmpty {
            clauses.append(fieldClause(name: "artist", value: query.artist))
        }

        if !query.album.isEmpty {
            clauses.append(fieldClause(name: "release", value: query.album))
        }

        return clauses.joined(separator: " AND ")
    }

    private static func fieldClause(name: String, value: String) -> String {
        let escaped = escapeLucene(value)
        return "\(name):\"\(escaped)\""
    }

    private static func escapeLucene(_ raw: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(raw.count)

        for character in raw {
            if reservedCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        return escaped
    }
}

private struct MusicBrainzRecordingSearchResponse: Decodable {
    let recordings: [MusicBrainzRecordingDTO]
}

private struct MusicBrainzRecordingDTO: Decodable {
    let id: String
    let title: String
    let score: Int
    let disambiguation: String
    let firstReleaseDate: String
    let length: Int?
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let releases: [MusicBrainzReleaseDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case disambiguation
        case length
        case releases
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        firstReleaseDate = try container.decodeIfPresent(String.self, forKey: .firstReleaseDate) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        releases = try container.decodeIfPresent([MusicBrainzReleaseDTO].self, forKey: .releases) ?? []

        if let score = try container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = score
        } else if
            let scoreString = try container.decodeIfPresent(String.self, forKey: .score),
            let score = Int(scoreString)
        {
            self.score = score
        } else {
            self.score = 0
        }
    }
}

private struct MusicBrainzArtistCreditDTO: Decodable {
    let name: String?
    let joinPhrase: String
    let artist: MusicBrainzArtistDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case artist
        case joinPhrase = "joinphrase"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        joinPhrase = try container.decodeIfPresent(String.self, forKey: .joinPhrase) ?? ""
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
    }
}

private struct MusicBrainzArtistDTO: Decodable {
    let name: String?
}

private struct MusicBrainzReleaseDTO: Decodable {
    let id: String
    let title: String
    let date: String
    let country: String
    let status: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case status
    }
}

private extension MusicBrainzRecordingResult {
    init(dto: MusicBrainzRecordingDTO) {
        id = dto.id
        title = dto.title
        score = dto.score
        disambiguation = dto.disambiguation
        firstReleaseDate = dto.firstReleaseDate
        durationMilliseconds = dto.length
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        releases = dto.releases.compactMap {
            guard !$0.id.isEmpty, !$0.title.isEmpty else { return nil }
            return Release(
                id: $0.id,
                title: $0.title,
                date: $0.date,
                country: $0.country,
                status: $0.status
            )
        }
    }
}
