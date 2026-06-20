import Foundation

enum MusicBrainzSearchMode: String, CaseIterable, Identifiable {
    case track
    case album
    case file
    case link

    var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .track: return "Track"
        case .album: return "Album"
        case .file: return "File"
        case .link: return "Link"
        }
    }
}

struct MusicBrainzFileSearchInput: Identifiable, Equatable, Hashable {
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
    let musicBrainzAlbumID: String
    let musicBrainzTrackID: String

    init(
        id: String,
        displayTitle: String,
        title: String,
        artist: String,
        albumArtist: String,
        album: String,
        trackNumber: String,
        discNumber: String = "",
        trackTotal: Int = 0,
        durationMilliseconds: Int? = nil,
        releaseDate: String = "",
        isrc: String = "",
        barcode: String = "",
        musicBrainzAlbumID: String = "",
        musicBrainzTrackID: String = ""
    ) {
        self.id = id
        self.displayTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.albumArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackNumber = trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.discNumber = discNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackTotal = max(0, trackTotal)
        self.durationMilliseconds = durationMilliseconds.flatMap { $0 > 0 ? $0 : nil }
        self.releaseDate = releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isrc = isrc.trimmingCharacters(in: .whitespacesAndNewlines)
        self.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.musicBrainzAlbumID = musicBrainzAlbumID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.musicBrainzTrackID = musicBrainzTrackID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var preferredDisplayTitle: String {
        if !title.isEmpty {
            return title
        }

        if !displayTitle.isEmpty {
            return displayTitle
        }

        return "Selected File"
    }

    var artistCandidates: [String] {
        let values = [artist, albumArtist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (Array(NSOrderedSet(array: values)) as? [String]) ?? values
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
}

struct MusicBrainzFileSelectionSummary: Equatable, Hashable {
    let files: [MusicBrainzFileSearchInput]
    let albumCandidate: String
    let albumArtistCandidate: String
    let primaryArtistCandidate: String
    let totalSelectedFiles: Int
    let releaseTrackCountCandidate: Int
    let releaseYearCandidate: String
    let barcodeCandidate: String
    let musicBrainzAlbumIDCandidate: String
    let distinctAlbumCount: Int
    let distinctArtistCount: Int

    init(files: [MusicBrainzFileSearchInput]) {
        let normalizedFiles = files
        self.files = normalizedFiles
        let summary = OnlineMetadataSelectionCore.summary(
            albums: normalizedFiles.map(\.album),
            albumArtists: normalizedFiles.map { file in
                file.albumArtist.isEmpty ? file.artist : file.albumArtist
            },
            primaryArtists: normalizedFiles.map(\.artist),
            trackTotals: normalizedFiles.map(\.trackTotal),
            releaseDates: normalizedFiles.map(\.releaseDate),
            barcodes: normalizedFiles.map(\.barcode),
            providerAlbumIDs: normalizedFiles.map(\.musicBrainzAlbumID)
        )
        self.totalSelectedFiles = summary.totalSelectedFiles
        self.albumCandidate = summary.albumCandidate
        self.albumArtistCandidate = summary.albumArtistCandidate
        self.primaryArtistCandidate = summary.primaryArtistCandidate
        self.releaseTrackCountCandidate = summary.trackCountCandidate
        self.releaseYearCandidate = summary.releaseYearCandidate
        self.barcodeCandidate = summary.barcodeCandidate
        self.musicBrainzAlbumIDCandidate = summary.providerAlbumIDCandidate
        self.distinctAlbumCount = summary.distinctAlbumCount
        self.distinctArtistCount = summary.distinctArtistCount
    }

    var isMultiFile: Bool {
        files.count > 1
    }

    var selectionLooksMixed: Bool {
        distinctAlbumCount > 1 || distinctArtistCount > 1
    }
}

struct MusicBrainzReleaseMatchTrack: Identifiable, Equatable, Hashable {
    let id: String
    let mediumTitle: String
    let mediumFormat: String
    let mediumPosition: Int
    let mediumTrackCount: Int
    let releaseMediumCount: Int
    let number: String
    let title: String
    let artistCredit: String
    let durationMilliseconds: Int?
    let recordingID: String
    let isrcs: [String]
}

struct MusicBrainzReleaseMatchAssignment: Identifiable, Equatable, Hashable {
    let id: String
    let file: MusicBrainzFileSearchInput
    let track: MusicBrainzReleaseMatchTrack
    let score: Double
    let reason: String
}

struct MusicBrainzReleaseMatchPreview: Equatable, Hashable {
    let totalSelectedFiles: Int
    let matchedAssignments: [MusicBrainzReleaseMatchAssignment]
    let unmatchedFiles: [MusicBrainzFileSearchInput]
    let unassignedTracks: [MusicBrainzReleaseMatchTrack]
    let averageTrackScore: Double
    let overallScore: Double
    let selectionLooksMixed: Bool

    var matchedFileCount: Int {
        matchedAssignments.count
    }
}

enum MusicBrainzReleaseStatus: String, CaseIterable, Identifiable, Hashable {
    case official
    case promotion
    case bootleg
    case pseudoRelease = "pseudo-release"
    case withdrawn
    case expunged
    case cancelled

    var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .official: return "Official"
        case .promotion: return "Promotion"
        case .bootleg: return "Bootleg"
        case .pseudoRelease: return "Pseudo-release"
        case .withdrawn: return "Withdrawn"
        case .expunged: return "Expunged"
        case .cancelled: return "Cancelled"
        }
    }
}

enum MusicBrainzReleaseMediaFormat: String, CaseIterable, Identifiable, Hashable {
    case digitalMedia = "Digital Media"
    case cd = "CD"
    case vinyl = "Vinyl"
    case cassette = "Cassette"
    case dvd = "DVD"
    case bluRay = "Blu-ray"
    case sacd = "SACD"
    case minidisc = "MiniDisc"

    var id: String { rawValue }

    nonisolated var displayName: String { rawValue }
}

struct MusicBrainzReleaseFilters: Equatable, Hashable {
    var mediaFormats: Set<MusicBrainzReleaseMediaFormat>
    var releaseYear: String
    var countries: Set<String>
    var statuses: Set<MusicBrainzReleaseStatus>

    init(
        mediaFormats: Set<MusicBrainzReleaseMediaFormat> = [],
        releaseYear: String = "",
        countries: Set<String> = [],
        statuses: Set<MusicBrainzReleaseStatus> = []
    ) {
        self.mediaFormats = mediaFormats
        self.releaseYear = Self.normalizedYear(releaseYear)
        self.countries = Set(countries.compactMap(Self.normalizedCountryCode))
        self.statuses = statuses
    }

    nonisolated var isEmpty: Bool {
        mediaFormats.isEmpty &&
            releaseYear.isEmpty &&
            countries.isEmpty &&
            statuses.isEmpty
    }

    nonisolated var normalizedCountries: [String] {
        countries.sorted()
    }

    nonisolated var summaryParts: [String] {
        var parts: [String] = []
        parts.append(contentsOf: mediaFormats.sorted { $0.displayName < $1.displayName }.map(\.displayName))

        if !releaseYear.isEmpty {
            parts.append(releaseYear)
        }

        parts.append(contentsOf: normalizedCountries)
        parts.append(contentsOf: statuses.sorted { $0.displayName < $1.displayName }.map(\.displayName))
        return parts
    }

    nonisolated var summaryText: String {
        summaryParts.joined(separator: " • ")
    }

    nonisolated func matches(date: String, country: String, status: String, candidateMediaFormats: [String]) -> Bool {
        if !releaseYear.isEmpty {
            let candidateYear = Self.normalizedYear(date)
            guard candidateYear == releaseYear else { return false }
        }

        if !countries.isEmpty {
            guard countries.contains(country.uppercased()) else { return false }
        }

        if !statuses.isEmpty {
            let normalizedStatus = status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
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
        let digits = rawValue.filter(\.isNumber)
        guard digits.count >= 4 else { return "" }
        return String(digits.prefix(4))
    }

    nonisolated static func normalizedCountryCode(_ rawValue: String) -> String? {
        let letters = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter(\.isLetter)
            .uppercased()

        guard letters.count == 2 else { return nil }
        return letters
    }

    nonisolated private static func normalizedFormat(_ rawValue: String) -> String {
        rawValue
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
