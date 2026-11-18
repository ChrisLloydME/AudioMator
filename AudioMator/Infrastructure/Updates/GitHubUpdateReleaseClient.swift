import Foundation

struct GitHubUpdateReleaseClient: UpdateReleaseProviding {
    private static let latestReleaseEndpoint = URL(string: "https://api.github.com/repos/ChrisLloydME/AudioMator/releases/latest")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchLatestRelease() async throws -> UpdateReleaseMetadata {
        let request = GitHubAPIRequest.make(url: Self.latestReleaseEndpoint)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.malformedReleaseResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                throw UpdateCheckError.rateLimited
            }

            let apiError = try? decoder.decode(GitHubUpdateAPIError.self, from: data)
            throw UpdateCheckError.requestFailed(
                apiError?.message ?? String(localized: "The update check on GitHub couldn’t be completed. Try again later.\nDetails: HTTP \(httpResponse.statusCode).")
            )
        }

        do {
            let release = try decoder.decode(GitHubLatestReleaseResponse.self, from: data)

            guard let tagName = release.tagName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tagName.isEmpty,
                  let version = ReleaseVersion(releaseTag: tagName)
            else {
                throw UpdateCheckError.missingReleaseVersion
            }

            return UpdateReleaseMetadata(version: version, tagName: tagName)
        } catch let error as UpdateCheckError {
            throw error
        } catch {
            throw UpdateCheckError.malformedReleaseResponse
        }
    }
}

private struct GitHubLatestReleaseResponse: Decodable {
    let tagName: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private struct GitHubUpdateAPIError: Decodable {
    let message: String
}
