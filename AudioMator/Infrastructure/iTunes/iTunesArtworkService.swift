import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum iTunesArtworkSearchEntity: String, Sendable {
    case album
    case idAlbum
}

nonisolated struct iTunesArtworkSearchRequest: Sendable {
    let query: String
    let entity: iTunesArtworkSearchEntity
    let country: String
    let limit: Int

    init(
        query: String,
        entity: iTunesArtworkSearchEntity,
        country: String = "us",
        limit: Int = 24
    ) {
        self.query = query
        self.entity = entity
        self.country = country
        self.limit = limit
    }
}

nonisolated struct iTunesArtworkSearchResult: Identifiable, Sendable {
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

nonisolated enum iTunesArtworkServiceError: LocalizedError, Sendable {
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

nonisolated struct iTunesDownloadedArtwork: Sendable {
    let pngData: Data
}

nonisolated protocol iTunesArtworkServicing: Sendable {
    func search(_ request: iTunesArtworkSearchRequest) async throws -> [iTunesArtworkSearchResult]
    func downloadArtworkData(for result: iTunesArtworkSearchResult) async throws -> iTunesDownloadedArtwork
}

nonisolated struct iTunesArtworkService: iTunesArtworkServicing, Sendable {
    private static let requestTimeout: TimeInterval = 15
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ request: iTunesArtworkSearchRequest) async throws -> [iTunesArtworkSearchResult] {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw iTunesArtworkServiceError.emptyQuery
        }

        let normalizedCountry = request.country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCountry.count == 2 else {
            throw iTunesArtworkServiceError.invalidCountry
        }

        guard (1...200).contains(request.limit) else {
            throw iTunesArtworkServiceError.invalidLimit
        }

        let url: URL
        do {
            url = try iTunesArtworkCoreRequest(
                query: trimmedQuery,
                entity: iTunesArtworkCoreEntity(entity: request.entity),
                country: normalizedCountry,
                limit: request.limit
            ).searchURL()
        } catch {
            throw iTunesArtworkServiceError.failedToBuildURL
        }

        let urlRequest = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw iTunesArtworkServiceError.invalidResponseBody
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw iTunesArtworkServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return try transformResults(from: data, entity: request.entity)
    }

    func downloadArtworkData(for result: iTunesArtworkSearchResult) async throws -> iTunesDownloadedArtwork {
        guard !result.preferredDownloadURLs.isEmpty else {
            throw iTunesArtworkServiceError.invalidArtworkData
        }

        var downloadedData: Data?

        for artworkURL in result.preferredDownloadURLs {
            try Task.checkCancellation()
            do {
                let request = URLRequest(url: artworkURL, timeoutInterval: Self.requestTimeout)
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                guard (200..<300).contains(httpResponse.statusCode), !data.isEmpty else { continue }
                downloadedData = data
                break
            } catch {
                try Task.checkCancellation()
                continue
            }
        }

        guard let downloadedData else {
            throw iTunesArtworkServiceError.invalidArtworkData
        }

        guard
            let source = CGImageSourceCreateWithData(downloadedData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw iTunesArtworkServiceError.imageDecodingFailed
        }

        let encodedData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encodedData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw iTunesArtworkServiceError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw iTunesArtworkServiceError.imageEncodingFailed
        }

        return iTunesDownloadedArtwork(pngData: encodedData as Data)
    }

    private func transformResults(
        from jsonData: Data,
        entity: iTunesArtworkSearchEntity
    ) throws -> [iTunesArtworkSearchResult] {
        do {
            return try iTunesArtworkCore.transformResults(
                from: jsonData,
                entity: iTunesArtworkCoreEntity(entity: entity)
            ).map(iTunesArtworkSearchResult.init(coreResult:))
        } catch {
            throw iTunesArtworkServiceError.invalidResponseBody
        }
    }
}

private extension iTunesArtworkCoreEntity {
    nonisolated init(entity: iTunesArtworkSearchEntity) {
        switch entity {
        case .album:
            self = .album
        case .idAlbum:
            self = .idAlbum
        }
    }
}

private extension iTunesArtworkSearchResult {
    nonisolated init(coreResult: iTunesArtworkCoreResult) {
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
