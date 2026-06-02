import Foundation

enum ITunesArtworkCoreEntity: String {
    case album
    case idAlbum
}

struct ITunesArtworkCoreRequest: Equatable {
    let query: String
    let entity: ITunesArtworkCoreEntity
    let country: String
    let limit: Int

    func searchURL() throws -> URL {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw ITunesArtworkCoreError.emptyQuery }

        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedCountry.count == 2 else { throw ITunesArtworkCoreError.invalidCountry }
        guard (1...200).contains(limit) else { throw ITunesArtworkCoreError.invalidLimit }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"

        switch entity {
        case .idAlbum:
            components.path = "/lookup"
            components.queryItems = [
                URLQueryItem(name: "id", value: trimmedQuery),
                URLQueryItem(name: "country", value: normalizedCountry),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case .album:
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "term", value: trimmedQuery),
                URLQueryItem(name: "country", value: normalizedCountry),
                URLQueryItem(name: "entity", value: entity.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        }

        guard let url = components.url else { throw ITunesArtworkCoreError.failedToBuildURL }
        return url
    }
}

struct ITunesArtworkCoreResult: Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let thumbnailURL: URL?
    let standardURL: URL?
    let hiresURL: URL?
    let uncompressedURL: URL?
    let pixelWidth: Int
    let pixelHeight: Int

    var preferredPreviewURLs: [URL] {
        uniqueURLs([hiresURL, uncompressedURL, standardURL, thumbnailURL])
    }

    var preferredDownloadURLs: [URL] {
        uniqueURLs([uncompressedURL, hiresURL, standardURL, thumbnailURL])
    }

    private func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            guard let url else { return nil }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }
    }
}

enum ITunesArtworkCoreError: Error, Equatable {
    case emptyQuery
    case invalidCountry
    case invalidLimit
    case failedToBuildURL
    case invalidResponseBody
}

enum ITunesArtworkCore {
    static func transformResults(from jsonData: Data, entity: ITunesArtworkCoreEntity) throws -> [ITunesArtworkCoreResult] {
        guard
            let rootObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let rawResults = rootObject["results"] as? [[String: Any]]
        else {
            throw ITunesArtworkCoreError.invalidResponseBody
        }

        var transformed: [ITunesArtworkCoreResult] = []
        var seenIDs = Set<String>()

        for rawResult in rawResults {
            if entity == .idAlbum, (rawResult["collectionType"] as? String) != "Album" {
                continue
            }

            guard let artworkURL100 = rawResult["artworkUrl100"] as? String else {
                continue
            }

            let thumbnailURLString = artworkURL100
            let standardURLString = artworkURL100.replacingOccurrences(of: "100x100", with: "600x600")
            let hiresCandidate = artworkURL100.replacingOccurrences(of: "100x100bb", with: "100000x100000-999")
            let hiresURLString = normalizedHiresURL(from: hiresCandidate)
            let uncompressedURLString = normalizedUncompressedURL(from: hiresURLString)

            let title = [rawResult["collectionName"] as? String, rawResult["artistName"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            guard !title.isEmpty else { continue }

            let resultID = [
                uncompressedURLString,
                hiresURLString,
                standardURLString,
                title
            ]
            .compactMap { $0 }
            .joined(separator: "|")
            guard seenIDs.insert(resultID).inserted else { continue }

            transformed.append(
                ITunesArtworkCoreResult(
                    id: resultID,
                    title: title,
                    subtitle: rawResult["primaryGenreName"] as? String,
                    thumbnailURL: URL(string: thumbnailURLString),
                    standardURL: URL(string: standardURLString),
                    hiresURL: hiresURLString.flatMap(URL.init(string:)),
                    uncompressedURL: uncompressedURLString.flatMap(URL.init(string:)),
                    pixelWidth: uncompressedURLString == nil ? 600 : 3000,
                    pixelHeight: uncompressedURLString == nil ? 600 : 3000
                )
            )
        }

        return transformed
    }

    static func normalizedHiresURL(from hiresCandidate: String) -> String? {
        guard let path = URL(string: hiresCandidate)?.path else { return nil }
        return "https://is5-ssl.mzstatic.com\(path)"
    }

    static func normalizedUncompressedURL(from hiresURL: String?) -> String? {
        guard let hiresURL else { return nil }

        let parts = hiresURL.components(separatedBy: "/image/thumb/")
        guard parts.count == 2 else { return nil }

        var imageParts = parts[1].components(separatedBy: "/")
        guard !imageParts.isEmpty else { return nil }
        imageParts.removeLast()
        return "https://a5.mzstatic.com/us/r1000/0/\(imageParts.joined(separator: "/"))"
    }
}
