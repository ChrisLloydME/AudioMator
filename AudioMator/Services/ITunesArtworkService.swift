import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ITunesArtworkSearchEntity: String, Sendable {
    case album
    case idAlbum
}

struct ITunesArtworkSearchRequest: Sendable {
    let query: String
    let entity: ITunesArtworkSearchEntity
    let country: String
    let limit: Int

    init(
        query: String,
        entity: ITunesArtworkSearchEntity,
        country: String = "us",
        limit: Int = 24
    ) {
        self.query = query
        self.entity = entity
        self.country = country
        self.limit = limit
    }
}

struct ITunesArtworkSearchResult: Identifiable, Sendable {
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

enum ITunesArtworkServiceError: LocalizedError {
    case emptyQuery
    case invalidCountry
    case invalidLimit
    case failedToBuildURL
    case requestFailed(statusCode: Int)
    case invalidResponseBody
    case invalidArtworkData
    case imageDecodingFailed
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Query cannot be empty."
        case .invalidCountry:
            return "Country must be a two-letter storefront code."
        case .invalidLimit:
            return "Limit must be between 1 and 200."
        case .failedToBuildURL:
            return "Failed to build the iTunes artwork request."
        case .requestFailed(let statusCode):
            return "The iTunes artwork request failed with status code \(statusCode)."
        case .invalidResponseBody:
            return "The iTunes artwork response could not be decoded."
        case .invalidArtworkData:
            return "The selected artwork could not be downloaded."
        case .imageDecodingFailed:
            return "The downloaded artwork image could not be opened."
        case .imageEncodingFailed:
            return "The downloaded artwork image could not be converted to PNG."
        }
    }
}

struct ITunesArtworkService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ request: ITunesArtworkSearchRequest) async throws -> [ITunesArtworkSearchResult] {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw ITunesArtworkServiceError.emptyQuery
        }

        let normalizedCountry = request.country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCountry.count == 2 else {
            throw ITunesArtworkServiceError.invalidCountry
        }

        guard (1...200).contains(request.limit) else {
            throw ITunesArtworkServiceError.invalidLimit
        }

        guard let url = buildSearchURL(
            query: trimmedQuery,
            entity: request.entity,
            country: normalizedCountry.lowercased(),
            limit: request.limit
        ) else {
            throw ITunesArtworkServiceError.failedToBuildURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ITunesArtworkServiceError.invalidResponseBody
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ITunesArtworkServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try transformResults(from: data, entity: request.entity)
    }

    func downloadArtwork(for result: ITunesArtworkSearchResult) async throws -> PendingArtwork {
        guard !result.preferredDownloadURLs.isEmpty else {
            throw ITunesArtworkServiceError.invalidArtworkData
        }

        var downloadedData: Data?

        for artworkURL in result.preferredDownloadURLs {
            do {
                let (data, response) = try await session.data(from: artworkURL)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                guard (200..<300).contains(httpResponse.statusCode), !data.isEmpty else { continue }
                downloadedData = data
                break
            } catch {
                continue
            }
        }

        guard let downloadedData else {
            throw ITunesArtworkServiceError.invalidArtworkData
        }

        guard let image = PlatformImage(data: downloadedData) else {
            throw ITunesArtworkServiceError.imageDecodingFailed
        }

        guard
            let pngData = image.audiomatorPNGData,
            let previewImage = PlatformImage(data: pngData)
        else {
            throw ITunesArtworkServiceError.imageEncodingFailed
        }

        return PendingArtwork(
            image: previewImage,
            data: pngData,
            mimeType: "image/png"
        )
    }

    private func buildSearchURL(
        query: String,
        entity: ITunesArtworkSearchEntity,
        country: String,
        limit: Int
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"

        switch entity {
        case .idAlbum:
            components.path = "/lookup"
            components.queryItems = [
                URLQueryItem(name: "id", value: query),
                URLQueryItem(name: "country", value: country),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        case .album:
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "term", value: query),
                URLQueryItem(name: "country", value: country),
                URLQueryItem(name: "entity", value: entity.rawValue),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        }

        return components.url
    }

    private func transformResults(
        from jsonData: Data,
        entity: ITunesArtworkSearchEntity
    ) throws -> [ITunesArtworkSearchResult] {
        guard
            let rootObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let rawResults = rootObject["results"] as? [[String: Any]]
        else {
            throw ITunesArtworkServiceError.invalidResponseBody
        }

        var transformed: [ITunesArtworkSearchResult] = []
        transformed.reserveCapacity(rawResults.count)

        var seenIDs = Set<String>()

        for rawResult in rawResults {
            if entity == .idAlbum,
               (rawResult["collectionType"] as? String) != "Album" {
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

            let subtitle = rawResult["primaryGenreName"] as? String
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
                ITunesArtworkSearchResult(
                    id: resultID,
                    title: title,
                    subtitle: subtitle,
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

    private func normalizedHiresURL(from hiresCandidate: String) -> String? {
        guard let path = URL(string: hiresCandidate)?.path else { return nil }
        return "https://is5-ssl.mzstatic.com\(path)"
    }

    private func normalizedUncompressedURL(from hiresURL: String?) -> String? {
        guard let hiresURL else { return nil }

        let parts = hiresURL.components(separatedBy: "/image/thumb/")
        guard parts.count == 2 else { return nil }

        var imageParts = parts[1].components(separatedBy: "/")
        guard !imageParts.isEmpty else { return nil }
        imageParts.removeLast()
        return "https://a5.mzstatic.com/us/r1000/0/\(imageParts.joined(separator: "/"))"
    }
}
