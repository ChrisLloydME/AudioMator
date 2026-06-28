import Foundation

enum iTunesProviderSearchMode: String {
    case track
    case album
    case file
    case link
    case upc
}

struct iTunesProviderFileInput: Equatable, Hashable {
    let id: String
    let displayTitle: String
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let trackNumber: String
    let discNumber: String
    let trackTotal: Int
    let durationMilliseconds: Int?
    let releaseDate: String
    let barcode: String
    let albumID: String

    var preferredDisplayTitle: String {
        if !title.isEmpty { return title }
        if !displayTitle.isEmpty { return displayTitle }
        return "Selected File"
    }

    var normalizedTrackNumber: Int? {
        OnlineMetadataSelectionCore.normalizedPositiveIndex(trackNumber)
    }

    var normalizedDiscNumber: Int? {
        OnlineMetadataSelectionCore.normalizedPositiveIndex(discNumber)
    }

    var normalizedReleaseYear: String {
        OnlineMetadataSelectionCore.normalizedReleaseYear(releaseDate)
    }

    var artistCandidates: [String] {
        OnlineMetadataSelectionCore.deduplicatedTrimmedValues([artist, albumArtist])
    }
}

struct iTunesProviderSearchQuery: Equatable {
    var mode: iTunesProviderSearchMode = .track
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var upc: String = ""
    var link: String = ""
    var country: String = "us"
    var fileInputs: [iTunesProviderFileInput] = []

    var isEmpty: Bool {
        switch mode {
        case .track:
            return title.trimmediTunesCore.isEmpty && artist.trimmediTunesCore.isEmpty && album.trimmediTunesCore.isEmpty
        case .album:
            return album.trimmediTunesCore.isEmpty && artist.trimmediTunesCore.isEmpty
        case .file:
            return fileInputs.isEmpty
        case .link:
            return link.trimmediTunesCore.isEmpty
        case .upc:
            return upc.trimmediTunesCore.isEmpty
        }
    }

    var selectionSummary: OnlineMetadataFileSelectionSummary? {
        guard !fileInputs.isEmpty else { return nil }
        return OnlineMetadataSelectionCore.summary(
            albums: fileInputs.map(\.album),
            albumArtists: fileInputs.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist },
            primaryArtists: fileInputs.map(\.artist),
            trackTotals: fileInputs.map(\.trackTotal),
            releaseDates: fileInputs.map(\.releaseDate),
            barcodes: fileInputs.map(\.barcode),
            providerAlbumIDs: fileInputs.map(\.albumID)
        )
    }

    var searchTerm: String {
        switch mode {
        case .track:
            return [title, artist, album].map(\.trimmediTunesCore).filter { !$0.isEmpty }.joined(separator: " ")
        case .album:
            return [album, artist].map(\.trimmediTunesCore).filter { !$0.isEmpty }.joined(separator: " ")
        case .file:
            guard let summary = selectionSummary else { return "" }
            if summary.isMultiFile {
                return [summary.albumCandidate, summary.albumArtistCandidate].filter { !$0.isEmpty }.joined(separator: " ")
            }
            guard let file = fileInputs.first else { return "" }
            return [file.title, file.artist, file.album].filter { !$0.isEmpty }.joined(separator: " ")
        case .link:
            return link
        case .upc:
            return upc
        }
    }

    func searchURL(entity: String, limit: Int) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: searchTerm),
            URLQueryItem(name: "country", value: try normalizedCountry(country)),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))
        ]
        guard let url = components.url else { throw CoreProviderRequestError.failedToBuildURL }
        return url
    }

    func lookupURL(idName: String, idValue: String, country: String, includeSongs: Bool) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        var queryItems = [
            URLQueryItem(name: idName, value: idValue),
            URLQueryItem(name: "country", value: try normalizedCountry(country))
        ]
        if includeSongs {
            queryItems.append(URLQueryItem(name: "entity", value: "song"))
            queryItems.append(URLQueryItem(name: "limit", value: "200"))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw CoreProviderRequestError.failedToBuildURL }
        return url
    }

    private func normalizedCountry(_ country: String) throws -> String {
        let normalized = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 2 else { throw CoreProviderRequestError.invalidCountry }
        return normalized
    }
}

enum iTunesProviderLinkTarget: Equatable {
    case album(Int)
    case track(Int)
}

enum iTunesProviderLinkParser {
    static func parse(_ rawValue: String) throws -> iTunesProviderLinkTarget {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoreProviderRequestError.invalidLink }
        if let id = Int(trimmed) {
            return .album(id)
        }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: normalized) else {
            throw CoreProviderRequestError.invalidLink
        }

        let queryItems = components.queryItems ?? []
        if let trackID = queryItems.first(where: { $0.name == "i" })?.value.flatMap(Int.init) {
            return .track(trackID)
        }

        if let albumID = queryItems.first(where: { $0.name == "id" })?.value.flatMap(Int.init) {
            return .album(albumID)
        }

        let pathParts = components.path.split(separator: "/").map(String.init)
        if let idPart = pathParts.last(where: { $0.hasPrefix("id") }) {
            let digits = String(idPart.dropFirst(2))
            if let id = Int(digits) {
                return .album(id)
            }
        }

        throw CoreProviderRequestError.unsupportedLink
    }
}

enum CoreProviderRequestError: Error, Equatable {
    case invalidCountry
    case invalidLink
    case unsupportedLink
    case failedToBuildURL
}

private extension String {
    var trimmediTunesCore: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
