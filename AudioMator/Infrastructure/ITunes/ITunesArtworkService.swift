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

        let url: URL
        do {
            url = try ITunesArtworkCoreRequest(
                query: trimmedQuery,
                entity: ITunesArtworkCoreEntity(entity: request.entity),
                country: normalizedCountry,
                limit: request.limit
            ).searchURL()
        } catch {
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

    private func transformResults(
        from jsonData: Data,
        entity: ITunesArtworkSearchEntity
    ) throws -> [ITunesArtworkSearchResult] {
        do {
            return try ITunesArtworkCore.transformResults(
                from: jsonData,
                entity: ITunesArtworkCoreEntity(entity: entity)
            ).map(ITunesArtworkSearchResult.init(coreResult:))
        } catch {
            throw ITunesArtworkServiceError.invalidResponseBody
        }
    }
}

private extension ITunesArtworkCoreEntity {
    nonisolated init(entity: ITunesArtworkSearchEntity) {
        switch entity {
        case .album:
            self = .album
        case .idAlbum:
            self = .idAlbum
        }
    }
}

private extension ITunesArtworkSearchResult {
    nonisolated init(coreResult: ITunesArtworkCoreResult) {
        self.init(
            id: coreResult.id,
            title: coreResult.title,
            subtitle: coreResult.subtitle,
            thumbnailURL: coreResult.thumbnailURL,
            standardURL: coreResult.standardURL,
            hiresURL: coreResult.hiresURL,
            uncompressedURL: coreResult.uncompressedURL,
            pixelWidth: coreResult.pixelWidth,
            pixelHeight: coreResult.pixelHeight
        )
    }
}
