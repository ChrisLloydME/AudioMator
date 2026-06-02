import Foundation

enum MusicBrainzProviderSearchMode: String {
    case track
    case album
    case file
    case link
}

enum MusicBrainzProviderReleaseStatus: String, CaseIterable, Hashable {
    case official
    case promotion
    case bootleg
    case pseudoRelease = "pseudo-release"
    case withdrawn
    case expunged
    case cancelled
}

enum MusicBrainzProviderMediaFormat: String, CaseIterable, Hashable {
    case digitalMedia = "Digital Media"
    case cd = "CD"
    case vinyl = "Vinyl"
    case cassette = "Cassette"
    case dvd = "DVD"
    case bluRay = "Blu-ray"
    case sacd = "SACD"
    case minidisc = "MiniDisc"
}

struct MusicBrainzProviderReleaseFilters: Equatable, Hashable {
    var mediaFormats: Set<MusicBrainzProviderMediaFormat>
    var releaseYear: String
    var countries: Set<String>
    var statuses: Set<MusicBrainzProviderReleaseStatus>

    init(
        mediaFormats: Set<MusicBrainzProviderMediaFormat> = [],
        releaseYear: String = "",
        countries: Set<String> = [],
        statuses: Set<MusicBrainzProviderReleaseStatus> = []
    ) {
        self.mediaFormats = mediaFormats
        self.releaseYear = Self.normalizedYear(releaseYear)
        self.countries = Set(countries.compactMap(Self.normalizedCountryCode))
        self.statuses = statuses
    }

    nonisolated var isEmpty: Bool {
        mediaFormats.isEmpty && releaseYear.isEmpty && countries.isEmpty && statuses.isEmpty
    }

    nonisolated func matches(date: String, country: String, status: String, candidateMediaFormats: [String]) -> Bool {
        if !releaseYear.isEmpty {
            guard Self.normalizedYear(date) == releaseYear else { return false }
        }

        if !countries.isEmpty {
            guard countries.contains(country.uppercased()) else { return false }
        }

        if !statuses.isEmpty {
            let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard statuses.contains(where: { $0.rawValue == normalizedStatus }) else { return false }
        }

        if !mediaFormats.isEmpty {
            let normalizedCandidateFormats = Set(candidateMediaFormats.map(Self.normalizedFormat))
            guard mediaFormats.contains(where: { normalizedCandidateFormats.contains(Self.normalizedFormat($0.rawValue)) }) else {
                return false
            }
        }

        return true
    }

    nonisolated static func normalizedYear(_ rawValue: String) -> String {
        OnlineMetadataSelectionCore.normalizedReleaseYear(rawValue)
    }

    nonisolated static func normalizedCountryCode(_ rawValue: String) -> String? {
        let letters = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isLetter).uppercased()
        guard letters.count == 2 else { return nil }
        return letters
    }

    nonisolated private static func normalizedFormat(_ rawValue: String) -> String {
        rawValue.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

struct MusicBrainzProviderFileInput: Equatable, Hashable {
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
    let isrc: String
    let barcode: String
    let albumID: String
    let trackID: String

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

struct MusicBrainzProviderSearchQuery: Equatable {
    var mode: MusicBrainzProviderSearchMode = .track
    var title: String = ""
    var artist: String = ""
    var albumArtist: String = ""
    var album: String = ""
    var trackNumber: String = ""
    var trackTotal: Int = 0
    var durationMilliseconds: Int?
    var releaseDate: String = ""
    var isrc: String = ""
    var barcode: String = ""
    var albumID: String = ""
    var trackID: String = ""
    var fileInputs: [MusicBrainzProviderFileInput] = []
    var link: String = ""
    var releaseFilters = MusicBrainzProviderReleaseFilters()

    var isEmpty: Bool {
        switch mode {
        case .track, .album:
            return title.isEmpty && artist.isEmpty && album.isEmpty
        case .file:
            return effectiveFileInputs.isEmpty &&
                title.isEmpty && artist.isEmpty && albumArtist.isEmpty && album.isEmpty &&
                trackNumber.isEmpty && trackTotal == 0 && durationMilliseconds == nil &&
                releaseDate.isEmpty && isrc.isEmpty && albumID.isEmpty && trackID.isEmpty
        case .link:
            return link.isEmpty
        }
    }

    var normalizedTrackNumber: Int? {
        OnlineMetadataSelectionCore.normalizedPositiveIndex(trackNumber)
    }

    var quantizedDuration: Int? {
        guard let durationMilliseconds, durationMilliseconds > 0 else { return nil }
        return max(1, durationMilliseconds / 2_000)
    }

    var normalizedReleaseYear: String {
        OnlineMetadataSelectionCore.normalizedReleaseYear(releaseDate)
    }

    var effectiveFileInputs: [MusicBrainzProviderFileInput] {
        if !fileInputs.isEmpty { return fileInputs }
        guard mode == .file else { return [] }
        guard !title.isEmpty || !artist.isEmpty || !albumArtist.isEmpty || !album.isEmpty ||
            !trackNumber.isEmpty || !releaseDate.isEmpty || !isrc.isEmpty || !albumID.isEmpty || !trackID.isEmpty
        else { return [] }

        return [
            MusicBrainzProviderFileInput(
                id: "synthetic",
                displayTitle: title,
                title: title,
                artist: artist,
                albumArtist: albumArtist,
                album: album,
                trackNumber: trackNumber,
                discNumber: "",
                trackTotal: trackTotal,
                durationMilliseconds: durationMilliseconds,
                releaseDate: releaseDate,
                isrc: isrc,
                barcode: barcode,
                albumID: albumID,
                trackID: trackID
            )
        ]
    }

    var selectionSummary: OnlineMetadataFileSelectionSummary? {
        let inputs = effectiveFileInputs
        guard !inputs.isEmpty else { return nil }
        return OnlineMetadataSelectionCore.summary(
            albums: inputs.map(\.album),
            albumArtists: inputs.map { $0.albumArtist.isEmpty ? $0.artist : $0.albumArtist },
            primaryArtists: inputs.map(\.artist),
            trackTotals: inputs.map(\.trackTotal),
            releaseDates: inputs.map(\.releaseDate),
            barcodes: inputs.map(\.barcode),
            providerAlbumIDs: inputs.map(\.albumID)
        )
    }

    var selectionReleaseQuery: MusicBrainzProviderSearchQuery {
        let summary = selectionSummary
        return MusicBrainzProviderSearchQuery(
            mode: .album,
            title: "",
            artist: summary?.albumArtistCandidate.isEmpty == false ? summary?.albumArtistCandidate ?? "" : summary?.primaryArtistCandidate ?? "",
            albumArtist: "",
            album: summary?.albumCandidate ?? "",
            trackNumber: "",
            trackTotal: summary?.trackCountCandidate ?? 0,
            durationMilliseconds: nil,
            releaseDate: summary?.releaseYearCandidate ?? "",
            isrc: "",
            barcode: summary?.barcodeCandidate ?? "",
            albumID: summary?.providerAlbumIDCandidate ?? "",
            trackID: "",
            fileInputs: effectiveFileInputs,
            link: "",
            releaseFilters: releaseFilters
        )
    }

    var artistCandidates: [String] {
        switch mode {
        case .file:
            if let summary = selectionSummary {
                return OnlineMetadataSelectionCore.deduplicatedTrimmedValues([
                    summary.albumArtistCandidate,
                    summary.primaryArtistCandidate
                ])
            }
            return OnlineMetadataSelectionCore.deduplicatedTrimmedValues([artist, albumArtist])
        case .track, .album:
            return OnlineMetadataSelectionCore.deduplicatedTrimmedValues([artist])
        case .link:
            return []
        }
    }
}

enum MusicBrainzProviderLinkTarget: Equatable {
    case recording(String)
    case release(String)
}

enum MusicBrainzProviderLinkParser {
    static let supportedHosts = Set(["musicbrainz.org", "www.musicbrainz.org"])

    static func parse(_ rawValue: String) throws -> MusicBrainzProviderLinkTarget {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CoreProviderRequestError.invalidLink }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard
            let components = URLComponents(string: normalized),
            let host = components.host?.lowercased(),
            supportedHosts.contains(host)
        else {
            throw CoreProviderRequestError.invalidLink
        }

        let pathComponents = components.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard pathComponents.count >= 2 else { throw CoreProviderRequestError.invalidLink }
        let entity = pathComponents[0].lowercased()
        let id = pathComponents[1]
        guard UUID(uuidString: id) != nil else { throw CoreProviderRequestError.invalidLink }

        switch entity {
        case "recording":
            return .recording(id)
        case "release":
            return .release(id)
        default:
            throw CoreProviderRequestError.unsupportedLink
        }
    }
}

enum MusicBrainzProviderCore {
    static func representativeFilesForReleaseLookup(
        from files: [MusicBrainzProviderFileInput]
    ) -> [MusicBrainzProviderFileInput] {
        OnlineMetadataSelectionCore.representativeFiles(
            files,
            title: \.preferredDisplayTitle,
            discNumber: \.normalizedDiscNumber,
            trackNumber: \.normalizedTrackNumber,
            limit: 3
        )
    }

    static func deduplicatedIDs<T>(_ values: [T], id: (T) -> String) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        for value in values where seen.insert(id(value)).inserted {
            result.append(value)
        }
        return result
    }
}
