import Foundation

struct GitHubReleaseNote: Decodable, Identifiable {
    let id: Int
    let name: String?
    let tagName: String
    let body: String
    let htmlURL: URL
    let publishedAt: Date?
    let isPrerelease: Bool
    let isDraft: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case isPrerelease = "prerelease"
        case isDraft = "draft"
    }

    var displayTitle: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? tagName : trimmedName
    }
}

enum GitHubReleaseNotesClientError: LocalizedError {
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}

struct GitHubReleaseNotesClient {
    private static let releasesEndpoint = URL(string: "https://api.github.com/repos/ChrisLloydME/AudioMator/releases")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchReleases() async throws -> [GitHubReleaseNote] {
        var components = URLComponents(url: Self.releasesEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "per_page", value: "50")
        ]

        guard let url = components?.url else {
            throw GitHubReleaseNotesClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AudioMator", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseNotesClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(GitHubAPIError.self, from: data)
            throw GitHubReleaseNotesClientError.requestFailed(
                apiError?.message ?? "GitHub request failed with status \(httpResponse.statusCode)."
            )
        }

        let releases = try decoder.decode([GitHubReleaseNote].self, from: data)
        return releases.filter { !$0.isDraft }
    }
}

private struct GitHubAPIError: Decodable {
    let message: String
}
