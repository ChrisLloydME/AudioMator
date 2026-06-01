import Foundation

enum GitHubAPIRequest {
    nonisolated static func make(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AudioMator", forHTTPHeaderField: "User-Agent")
        return request
    }
}
