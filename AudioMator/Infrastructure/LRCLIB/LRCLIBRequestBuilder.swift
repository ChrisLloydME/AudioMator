import Foundation

enum LRCLIBRequestBuilder {
    nonisolated static let baseURL = URL(string: "https://lrclib.net")!

    nonisolated static func makeSearchRequest(
        for query: LRCLIBSearchQuery,
        userAgent: String,
        timeoutInterval: TimeInterval = 15
    ) throws -> URLRequest {
        guard !query.isEmpty else { throw LRCLIBClientError.emptyQuery }

        var components = URLComponents(
            url: baseURL.appending(path: "api").appending(path: "search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems(for: query)

        guard let url = components?.url else {
            throw LRCLIBClientError.invalidRequest
        }

        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
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
