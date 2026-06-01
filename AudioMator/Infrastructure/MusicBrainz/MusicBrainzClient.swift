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
        Self.normalizedIndex(trackNumber)
    }

    var normalizedDiscNumber: Int? {
        Self.normalizedIndex(discNumber)
    }

    var normalizedReleaseYear: String {
        let digits = releaseDate.filter(\.isNumber)
        guard digits.count >= 4 else { return "" }
        return String(digits.prefix(4))
    }

    private static func normalizedIndex(_ rawValue: String) -> Int? {
        AudioTagNumberText.positiveIndex(from: rawValue)
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
        self.totalSelectedFiles = normalizedFiles.count
        self.albumCandidate = Self.majorityValue(from: normalizedFiles.map(\.album))
        self.albumArtistCandidate = Self.majorityValue(
            from: normalizedFiles.map { file in
                file.albumArtist.isEmpty ? file.artist : file.albumArtist
            }
        )
        self.primaryArtistCandidate = Self.majorityValue(from: normalizedFiles.map(\.artist))

        let explicitTrackTotal = Self.majorityInt(
            from: normalizedFiles.map(\.trackTotal).filter { $0 > 0 }
        )
        self.releaseTrackCountCandidate = max(explicitTrackTotal ?? 0, normalizedFiles.count)
        self.releaseYearCandidate = Self.majorityValue(from: normalizedFiles.map(\.normalizedReleaseYear))
        self.barcodeCandidate = Self.majorityValue(from: normalizedFiles.map(\.barcode))
        self.musicBrainzAlbumIDCandidate = Self.majorityValue(from: normalizedFiles.map(\.musicBrainzAlbumID))
        self.distinctAlbumCount = Self.distinctValueCount(normalizedFiles.map(\.album))
        self.distinctArtistCount = Self.distinctValueCount(
            normalizedFiles.map { file in
                file.albumArtist.isEmpty ? file.artist : file.albumArtist
            }
        )
    }

    var isMultiFile: Bool {
        files.count > 1
    }

    var selectionLooksMixed: Bool {
        distinctAlbumCount > 1 || distinctArtistCount > 1
    }

    private static func majorityValue(from values: [String]) -> String {
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedValues.isEmpty else { return "" }

        var counts: [String: Int] = [:]
        var bestValue = cleanedValues[0]
        var bestCount = 0

        for value in cleanedValues {
            let count = (counts[value] ?? 0) + 1
            counts[value] = count

            if count > bestCount {
                bestValue = value
                bestCount = count
            }
        }

        return bestValue
    }

    private static func majorityInt(from values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        var bestValue = values[0]
        var bestCount = 0

        for value in values {
            let count = (counts[value] ?? 0) + 1
            counts[value] = count

            if count > bestCount {
                bestValue = value
                bestCount = count
            }
        }

        return bestValue
    }

    private static func distinctValueCount(_ values: [String]) -> Int {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count
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

struct MusicBrainzSearchQuery: Equatable {
    var mode: MusicBrainzSearchMode
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var trackNumber: String
    var trackTotal: Int
    var durationMilliseconds: Int?
    var releaseDate: String
    var isrc: String
    var barcode: String
    var musicBrainzAlbumID: String
    var musicBrainzTrackID: String
    var fileInputs: [MusicBrainzFileSearchInput]
    var link: String
    var releaseFilters: MusicBrainzReleaseFilters

    init(
        mode: MusicBrainzSearchMode = .track,
        title: String = "",
        artist: String = "",
        albumArtist: String = "",
        album: String = "",
        trackNumber: String = "",
        trackTotal: Int = 0,
        durationMilliseconds: Int? = nil,
        releaseDate: String = "",
        isrc: String = "",
        barcode: String = "",
        musicBrainzAlbumID: String = "",
        musicBrainzTrackID: String = "",
        fileInputs: [MusicBrainzFileSearchInput] = [],
        link: String = "",
        releaseFilters: MusicBrainzReleaseFilters = MusicBrainzReleaseFilters()
    ) {
        self.mode = mode
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.albumArtist = albumArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackNumber = trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackTotal = max(0, trackTotal)
        self.durationMilliseconds = durationMilliseconds.flatMap { $0 > 0 ? $0 : nil }
        self.releaseDate = releaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isrc = isrc.trimmingCharacters(in: .whitespacesAndNewlines)
        self.barcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.musicBrainzAlbumID = musicBrainzAlbumID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.musicBrainzTrackID = musicBrainzTrackID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fileInputs = fileInputs
        self.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.releaseFilters = releaseFilters
    }

    var isEmpty: Bool {
        switch mode {
        case .track:
            title.isEmpty && artist.isEmpty && album.isEmpty
        case .album:
            title.isEmpty && artist.isEmpty && album.isEmpty
        case .file:
            effectiveFileInputs.isEmpty &&
            title.isEmpty &&
            artist.isEmpty &&
            albumArtist.isEmpty &&
            album.isEmpty &&
            trackNumber.isEmpty &&
            trackTotal == 0 &&
            durationMilliseconds == nil &&
            releaseDate.isEmpty &&
            isrc.isEmpty &&
            musicBrainzAlbumID.isEmpty &&
            musicBrainzTrackID.isEmpty
        case .link:
            link.isEmpty
        }
    }

    var artistCandidates: [String] {
        switch mode {
        case .file:
            if let fileSelectionSummary {
                return deduplicatedValues([
                    fileSelectionSummary.albumArtistCandidate,
                    fileSelectionSummary.primaryArtistCandidate
                ])
            }

            return deduplicatedValues([artist, albumArtist])
        case .track, .album:
            return deduplicatedValues([artist])
        case .link:
            return []
        }
    }

    var summaryText: String {
        var parts: [String] = ["mode: \(mode.displayName.lowercased())"]

        if !title.isEmpty {
            parts.append("title: \(title)")
        }

        if !artist.isEmpty {
            parts.append("artist: \(artist)")
        }

        if !albumArtist.isEmpty {
            parts.append("album artist: \(albumArtist)")
        }

        if !album.isEmpty {
            parts.append("album: \(album)")
        }

        if !trackNumber.isEmpty {
            parts.append("track: \(trackNumber)")
        }

        if trackTotal > 0 {
            parts.append("track total: \(trackTotal)")
        }

        if !releaseDate.isEmpty {
            parts.append("release date: \(releaseDate)")
        }

        if !isrc.isEmpty {
            parts.append("isrc: \(isrc)")
        }

        if !musicBrainzAlbumID.isEmpty {
            parts.append("release id: \(musicBrainzAlbumID)")
        }

        if !musicBrainzTrackID.isEmpty {
            parts.append("track id: \(musicBrainzTrackID)")
        }

        if !effectiveFileInputs.isEmpty {
            parts.append("selected files: \(effectiveFileInputs.count)")
        }

        if !link.isEmpty {
            parts.append("link: \(link)")
        }

        if !releaseFilters.isEmpty {
            parts.append("filters: \(releaseFilters.summaryText)")
        }

        return parts.joined(separator: " • ")
    }

    var normalizedTrackNumber: Int? {
        let normalized = trackNumber
            .split(separator: "/")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trackNumber

        guard !normalized.isEmpty else { return nil }

        let stripped = String(normalized.drop(while: { $0 == "0" }))
        if let value = Int(stripped), value > 0 {
            return value
        }

        if let value = Int(normalized), value > 0 {
            return value
        }

        return nil
    }

    var quantizedDuration: Int? {
        guard let durationMilliseconds, durationMilliseconds > 0 else { return nil }
        return max(1, durationMilliseconds / 2_000)
    }

    var normalizedReleaseYear: String {
        let digits = releaseDate.filter(\.isNumber)
        guard digits.count >= 4 else { return "" }
        return String(digits.prefix(4))
    }

    var effectiveFileInputs: [MusicBrainzFileSearchInput] {
        if !fileInputs.isEmpty {
            return fileInputs
        }

        guard mode == .file else { return [] }
        guard
            !title.isEmpty ||
            !artist.isEmpty ||
            !albumArtist.isEmpty ||
            !album.isEmpty ||
            !trackNumber.isEmpty ||
            !releaseDate.isEmpty ||
            !isrc.isEmpty ||
            !musicBrainzAlbumID.isEmpty ||
            !musicBrainzTrackID.isEmpty
        else {
            return []
        }

        return [
            MusicBrainzFileSearchInput(
                id: UUID().uuidString,
                displayTitle: title,
                title: title,
                artist: artist,
                albumArtist: albumArtist,
                album: album,
                trackNumber: trackNumber,
                trackTotal: trackTotal,
                durationMilliseconds: durationMilliseconds,
                releaseDate: releaseDate,
                isrc: isrc,
                barcode: barcode,
                musicBrainzAlbumID: musicBrainzAlbumID,
                musicBrainzTrackID: musicBrainzTrackID
            )
        ]
    }

    var fileSelectionSummary: MusicBrainzFileSelectionSummary? {
        let inputs = effectiveFileInputs
        guard !inputs.isEmpty else { return nil }
        return MusicBrainzFileSelectionSummary(files: inputs)
    }

    var isMultiFileSelection: Bool {
        effectiveFileInputs.count > 1
    }

    var selectionReleaseQuery: MusicBrainzSearchQuery {
        let summary = fileSelectionSummary
        return MusicBrainzSearchQuery(
            mode: .album,
            title: "",
            artist: summary?.albumArtistCandidate ?? summary?.primaryArtistCandidate ?? "",
            albumArtist: "",
            album: summary?.albumCandidate ?? "",
            trackNumber: "",
            trackTotal: summary?.releaseTrackCountCandidate ?? 0,
            durationMilliseconds: nil,
            releaseDate: summary?.releaseYearCandidate ?? "",
            isrc: "",
            barcode: summary?.barcodeCandidate ?? "",
            musicBrainzAlbumID: summary?.musicBrainzAlbumIDCandidate ?? "",
            musicBrainzTrackID: "",
            fileInputs: effectiveFileInputs,
            link: "",
            releaseFilters: releaseFilters
        )
    }

    private func deduplicatedValues(_ values: [String]) -> [String] {
        let trimmedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (Array(NSOrderedSet(array: trimmedValues)) as? [String]) ?? trimmedValues
    }
}

struct MusicBrainzReleaseSearchResult: Identifiable, Equatable, Hashable {
    struct ReleaseGroup: Equatable, Hashable {
        let id: String
        let primaryType: String
        let secondaryTypes: [String]
    }

    let id: String
    let title: String
    let artistCredit: String
    let score: Int
    let date: String
    let country: String
    let status: String
    let mediaFormats: [String]
    let releaseGroup: ReleaseGroup?
    let selectionMatchPreview: MusicBrainzReleaseMatchPreview?
    let selectionMatchScore: Double?

    var mediaFormatSummary: String {
        mediaFormats.joined(separator: " • ")
    }

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/release/\(id)")
    }
}

extension MusicBrainzReleaseSearchResult {
    init(recordingRelease release: MusicBrainzRecordingResult.Release) {
        self.init(
            id: release.id,
            title: release.title,
            artistCredit: "",
            score: 0,
            date: release.date,
            country: release.country,
            status: release.status,
            mediaFormats: [],
            releaseGroup: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }
}

enum MusicBrainzSearchResults: Equatable {
    case recordings([MusicBrainzRecordingResult])
    case releases([MusicBrainzReleaseSearchResult])

    var count: Int {
        switch self {
        case .recordings(let items): return items.count
        case .releases(let items): return items.count
        }
    }

    var isEmpty: Bool { count == 0 }
}

struct MusicBrainzRecordingResult: Identifiable, Equatable, Hashable {
    struct Release: Identifiable, Equatable, Hashable {
        let id: String
        let title: String
        let date: String
        let country: String
        let status: String

        var musicBrainzURL: URL? {
            NetworkServiceDisclosure.MusicBrainz.webURL(path: "/release/\(id)")
        }
    }

    let id: String
    let title: String
    let artistCredit: String
    let score: Int
    let disambiguation: String
    let firstReleaseDate: String
    let durationMilliseconds: Int?
    let releases: [Release]

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/recording/\(id)")
    }

    var primaryRelease: Release? {
        releases.first
    }
}

struct MusicBrainzRecordingDetail: Equatable {
    let id: String
    let title: String
    let artistCredit: String
    let disambiguation: String
    let firstReleaseDate: String
    let durationMilliseconds: Int?
    let annotation: String
    let isrcs: [String]
    let genres: [MusicBrainzTerm]
    let tags: [MusicBrainzTerm]
    let rating: MusicBrainzRating?
    let releases: [MusicBrainzRecordingResult.Release]
    let relationshipGroups: [MusicBrainzRelationshipGroup]

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/recording/\(id)")
    }
}

struct MusicBrainzRelationshipGroup: Equatable, Identifiable {
    let title: String
    var values: [String]

    var id: String { title }
}

struct MusicBrainzTerm: Equatable {
    let name: String
    let count: Int?

    nonisolated init(name: String, count: Int?) {
        self.name = name
        self.count = count
    }
}

struct MusicBrainzRating: Equatable {
    let value: Double?
    let voteCount: Int

    nonisolated init(value: Double?, voteCount: Int) {
        self.value = value
        self.voteCount = voteCount
    }
}

struct MusicBrainzReleaseDetail: Equatable {
    struct LabelInfo: Identifiable, Equatable, Hashable {
        let id: String
        let labelName: String
        let catalogNumber: String
    }

    struct Medium: Identifiable, Equatable, Hashable {
        struct Track: Identifiable, Equatable, Hashable {
            let id: String
            let number: String
            let title: String
            let artistCredit: String
            let durationMilliseconds: Int?
            let recordingID: String
            let isrcs: [String]
        }

        let id: String
        let title: String
        let format: String
        let trackCount: Int
        let discIDs: [String]
        let tracks: [Track]
    }

    let id: String
    let title: String
    let artistCredit: String
    let date: String
    let country: String
    let status: String
    let barcode: String
    let packaging: String
    let asin: String
    let quality: String
    let language: String
    let script: String
    let annotation: String
    let genres: [MusicBrainzTerm]
    let tags: [MusicBrainzTerm]
    let releaseGroupTitle: String
    let releaseGroupID: String
    let releaseGroupPrimaryType: String
    let releaseGroupSecondaryTypes: [String]
    let labels: [LabelInfo]
    let media: [Medium]
    var selectionMatchPreview: MusicBrainzReleaseMatchPreview?

    var musicBrainzURL: URL? {
        NetworkServiceDisclosure.MusicBrainz.webURL(path: "/release/\(id)")
    }
}

struct MusicBrainzTrackDetail: Equatable {
    let track: MusicBrainzReleaseDetail.Medium.Track
    let recordingDetail: MusicBrainzRecordingDetail?
}

enum MusicBrainzMetadataDetail: Equatable {
    case recording(MusicBrainzRecordingDetail)
    case release(MusicBrainzReleaseDetail)
    case track(MusicBrainzTrackDetail)
}

enum MusicBrainzClientError: LocalizedError {
    case emptyQuery
    case invalidLink
    case unsupportedLink
    case invalidRequest
    case requestFailed(statusCode: Int)
    case invalidResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter at least one search field."
        case .invalidLink:
            return "Paste a valid MusicBrainz link."
        case .unsupportedLink:
            return "Only MusicBrainz release and recording links are supported."
        case .invalidRequest:
            return "Couldn't create the MusicBrainz request."
        case .requestFailed(let statusCode):
            return "MusicBrainz returned HTTP \(statusCode)."
        case .invalidResponse:
            return "MusicBrainz returned an unexpected response."
        case .decodingFailed(let detail):
            return "MusicBrainz returned data AudioMator couldn't read. \(detail)"
        }
    }
}

private extension MusicBrainzClientError {
    var isRecoverableServerFailure: Bool {
        guard case .requestFailed(let statusCode) = self else { return false }
        return (500...599).contains(statusCode)
    }
}

actor MusicBrainzRateLimiter {
    private let minimumIntervalNanoseconds: UInt64
    private var lastRequestUptimeNanoseconds: UInt64?

    init(minimumIntervalNanoseconds: UInt64 = 1_100_000_000) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
    }

    func waitIfNeeded() async throws {
        let now = DispatchTime.now().uptimeNanoseconds

        if let lastRequestUptimeNanoseconds {
            let elapsed = now &- lastRequestUptimeNanoseconds
            if elapsed < minimumIntervalNanoseconds {
                try await Task.sleep(nanoseconds: minimumIntervalNanoseconds - elapsed)
            }
        }

        lastRequestUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
    }
}

struct MusicBrainzClient {
    private static let baseURL = URL(string: "https://\(NetworkServiceDisclosure.MusicBrainz.host)/ws/2")!

    private let session: URLSession
    private let decoder: JSONDecoder
    private let rateLimiter: MusicBrainzRateLimiter
    private let userAgent: String

    init(
        session: URLSession = .shared,
        rateLimiter: MusicBrainzRateLimiter = MusicBrainzRateLimiter()
    ) {
        self.session = session
        self.rateLimiter = rateLimiter

        let decoder = JSONDecoder()
        self.decoder = decoder

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.chrislloydme.AudioMator"
        let contactURL = "https://github.com/ChrisLloydME/AudioMator"
        // MusicBrainz asks clients to identify themselves clearly in the User-Agent.
        self.userAgent = "AudioMator/\(version) (\(contactURL); \(bundleIdentifier))"
    }

    func search(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> MusicBrainzSearchResults {
        switch query.mode {
        case .track:
            return .recordings(try await searchRecordings(matching: query, limit: limit))
        case .album:
            return .releases(try await searchReleases(matching: query, limit: limit))
        case .file:
            if query.isMultiFileSelection {
                return .releases(try await searchFileSelections(matching: query, limit: max(limit, 8)))
            }
            return .recordings(try await searchFiles(matching: query, limit: max(limit, 50)))
        case .link:
            return try await searchByLink(matching: query)
        }
    }

    func searchByLink(matching query: MusicBrainzSearchQuery) async throws -> MusicBrainzSearchResults {
        guard !query.link.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let parsedLink = try MusicBrainzLinkParser.parse(query.link)

        switch parsedLink {
        case .recording(let id):
            return .recordings([try await recordingSummary(id: id)])
        case .release(let id):
            return .releases([try await releaseSummary(id: id)])
        }
    }

    func searchRecordings(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> [MusicBrainzRecordingResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let luceneQueries = MusicBrainzLuceneQueryBuilder.recordingSearchQueries(from: query)
        let results = try await searchRecordings(luceneQueries: luceneQueries, limit: limit)
        return MusicBrainzResultRanker.rerankRecordings(results, query: query)
    }

    func searchReleases(matching query: MusicBrainzSearchQuery, limit: Int = 25) async throws -> [MusicBrainzReleaseSearchResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        let luceneQueries = MusicBrainzLuceneQueryBuilder.releaseSearchQueries(from: query)
        let releases = try await searchReleases(luceneQueries: luceneQueries, limit: limit)
        return MusicBrainzResultRanker.rerankReleases(releases, query: query)
    }

    func searchFileSelections(
        matching query: MusicBrainzSearchQuery,
        limit: Int = 8
    ) async throws -> [MusicBrainzReleaseSearchResult] {
        guard let selectionSummary = query.fileSelectionSummary, selectionSummary.isMultiFile else {
            throw MusicBrainzClientError.emptyQuery
        }

        var candidates: [MusicBrainzReleaseSearchResult] = []
        var filenameEvidenceByReleaseID: [String: Double] = [:]
        let selectionQuery = query.selectionReleaseQuery

        if let releaseID = selectionSummary.musicBrainzAlbumIDCandidate.validMBID {
            let release = try await releaseSummary(id: releaseID)
            if query.releaseFilters.isEmpty || query.releaseFilters.matches(
                date: release.date,
                country: release.country,
                status: release.status,
                candidateMediaFormats: release.mediaFormats
            ) {
                candidates.append(release)
            }
            filenameEvidenceByReleaseID[releaseID, default: 0] += 1.0
        }

        let strongQueries = MusicBrainzLuceneQueryBuilder.fileClusterStrongReleaseSearchQueries(from: query)
        if !strongQueries.isEmpty {
            candidates.append(contentsOf: try await searchReleases(luceneQueries: strongQueries, limit: 12))
        }

        let broadQueries = MusicBrainzLuceneQueryBuilder.fileClusterBroadReleaseSearchQueries(from: query)
        if !broadQueries.isEmpty {
            candidates.append(contentsOf: try await searchReleases(luceneQueries: broadQueries, limit: 20))
        }

        for candidate in try await releaseCandidatesFromRepresentativeFiles(selectionSummary, filters: query.releaseFilters) {
            candidates.append(candidate.release)
            filenameEvidenceByReleaseID[candidate.release.id, default: 0] += candidate.evidence
        }

        let deduplicatedCandidates = Self.deduplicatedReleases(candidates)
        let rerankedCandidates = MusicBrainzResultRanker.rerankReleases(
            deduplicatedCandidates,
            query: selectionQuery
        )
        let rerankedPositions = Dictionary(
            uniqueKeysWithValues: rerankedCandidates.enumerated().map { ($1.id, $0) }
        )
        let orderedCandidates = deduplicatedCandidates.sorted { lhs, rhs in
            let lhsEvidence = filenameEvidenceByReleaseID[lhs.id] ?? 0
            let rhsEvidence = filenameEvidenceByReleaseID[rhs.id] ?? 0

            if lhsEvidence != rhsEvidence {
                return lhsEvidence > rhsEvidence
            }

            let lhsPosition = rerankedPositions[lhs.id] ?? Int.max
            let rhsPosition = rerankedPositions[rhs.id] ?? Int.max
            if lhsPosition != rhsPosition {
                return lhsPosition < rhsPosition
            }

            return lhs.score > rhs.score
        }

        var matchedResults: [MusicBrainzReleaseSearchResult] = []
        for candidate in orderedCandidates.prefix(6) {
            do {
                let detail = try await releaseDetail(id: candidate.id)
                let preview = MusicBrainzFileSelectionMatcher.match(
                    selection: selectionSummary,
                    release: detail
                )
                matchedResults.append(
                    candidate.withSelectionMatchPreview(
                        preview,
                        selectionMatchScore: preview.overallScore
                    )
                )
            } catch {
                matchedResults.append(candidate)
            }
        }

        return matchedResults
            .sorted { lhs, rhs in
                let lhsScore = lhs.selectionMatchScore ?? Double(lhs.score)
                let rhsScore = rhs.selectionMatchScore ?? Double(rhs.score)

                if lhsScore == rhsScore {
                    let lhsEvidence = filenameEvidenceByReleaseID[lhs.id] ?? 0
                    let rhsEvidence = filenameEvidenceByReleaseID[rhs.id] ?? 0

                    if lhsEvidence == rhsEvidence {
                        return lhs.score > rhs.score
                    }

                    return lhsEvidence > rhsEvidence
                }

                return lhsScore > rhsScore
            }
            .prefix(limit)
            .map { $0 }
    }

    private func releaseCandidatesFromRepresentativeFiles(
        _ summary: MusicBrainzFileSelectionSummary,
        filters: MusicBrainzReleaseFilters
    ) async throws -> [(release: MusicBrainzReleaseSearchResult, evidence: Double)] {
        let representativeFiles = Self.representativeFilesForReleaseLookup(from: summary.files)
        guard !representativeFiles.isEmpty else { return [] }

        var evidenceByReleaseID: [String: Double] = [:]

        for (fileIndex, file) in representativeFiles.enumerated() {
            let title = file.title.isEmpty ? file.preferredDisplayTitle : file.title
            guard !title.isEmpty else { continue }

            let query = MusicBrainzSearchQuery(
                mode: .file,
                title: title,
                artist: file.artist,
                albumArtist: file.albumArtist,
                album: file.album,
                trackNumber: file.trackNumber,
                trackTotal: file.trackTotal,
                durationMilliseconds: file.durationMilliseconds,
                releaseDate: file.releaseDate,
                isrc: file.isrc,
                barcode: file.barcode,
                musicBrainzAlbumID: file.musicBrainzAlbumID,
                musicBrainzTrackID: file.musicBrainzTrackID,
                fileInputs: [file],
                link: "",
                releaseFilters: filters
            )

            let recordings = try await searchFiles(matching: query, limit: 6)
            let fileWeight = max(0.45, 1.0 - (Double(fileIndex) * 0.2))

            for (recordingIndex, recording) in recordings.prefix(4).enumerated() {
                let recordingWeight = fileWeight * max(0.25, Double(recording.score) / 100.0) * max(0.4, 1.0 - (Double(recordingIndex) * 0.18))

                for release in recording.releases.prefix(3) {
                    evidenceByReleaseID[release.id, default: 0] += recordingWeight
                }
            }
        }

        guard !evidenceByReleaseID.isEmpty else { return [] }

        var candidates: [(release: MusicBrainzReleaseSearchResult, evidence: Double)] = []
        for releaseID in evidenceByReleaseID.keys
            .sorted(by: { (evidenceByReleaseID[$0] ?? 0) > (evidenceByReleaseID[$1] ?? 0) })
            .prefix(6) {
            let release = try await releaseSummary(id: releaseID)
            guard filters.isEmpty || filters.matches(
                date: release.date,
                country: release.country,
                status: release.status,
                candidateMediaFormats: release.mediaFormats
            ) else {
                continue
            }

            candidates.append(
                (
                    release: release,
                    evidence: evidenceByReleaseID[releaseID] ?? 0
                )
            )
        }

        return candidates
    }

    func searchFiles(matching query: MusicBrainzSearchQuery, limit: Int = 50) async throws -> [MusicBrainzRecordingResult] {
        guard !query.isEmpty else {
            throw MusicBrainzClientError.emptyQuery
        }

        var candidates: [MusicBrainzRecordingResult] = []
        var preferredRecordingIDs: Set<String> = []

        let strongQueries = MusicBrainzLuceneQueryBuilder.fileStrongSearchQueries(from: query)
        if !strongQueries.isEmpty {
            let exactMatches = try await searchRecordings(luceneQueries: strongQueries, limit: 15)
            candidates.append(contentsOf: exactMatches)
            preferredRecordingIDs.formUnion(exactMatches.map(\.id))
        }

        let broadQueries = MusicBrainzLuceneQueryBuilder.fileSearchQueries(from: query)
        if !broadQueries.isEmpty {
            candidates.append(contentsOf: try await searchRecordings(luceneQueries: broadQueries, limit: limit))
        }

        let deduplicatedCandidates = Self.deduplicatedRecordings(candidates)
        return MusicBrainzResultRanker.rerankRecordings(
            deduplicatedCandidates,
            query: query,
            preferredRecordingIDs: preferredRecordingIDs
        )
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release] = []
    ) async throws -> MusicBrainzRecordingDetail {
        let data = try await performRequest(
            resource: "recording",
            id: id,
            queryItems: [
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(
                    name: "inc",
                    value: "artist-credits+isrcs+genres+tags+ratings+annotation+releases+artist-rels+label-rels+place-rels+recording-rels+release-rels+release-group-rels+series-rels+url-rels+work-rels+work-level-rels"
                )
            ]
        )

        let payload: MusicBrainzRecordingLookupDTO
        do {
            payload = try decoder.decode(MusicBrainzRecordingLookupDTO.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return MusicBrainzRecordingDetail(dto: payload, releases: fallbackReleases)
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        let data = try await performRequest(
            resource: "release",
            id: id,
            queryItems: [
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "inc", value: "artist-credits+genres+tags+annotation+labels+recordings+release-groups+media+discids+isrcs")
            ]
        )

        let payload: MusicBrainzReleaseLookupDTO
        do {
            payload = try decoder.decode(MusicBrainzReleaseLookupDTO.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return MusicBrainzReleaseDetail(dto: payload)
    }

    private func recordingSummary(id: String) async throws -> MusicBrainzRecordingResult {
        let detail = try await recordingDetail(id: id, fallbackReleases: [])
        return MusicBrainzRecordingResult(
            id: detail.id,
            title: detail.title,
            artistCredit: detail.artistCredit,
            score: 100,
            disambiguation: detail.disambiguation,
            firstReleaseDate: detail.firstReleaseDate,
            durationMilliseconds: detail.durationMilliseconds,
            releases: detail.releases
        )
    }

    private func releaseSummary(id: String) async throws -> MusicBrainzReleaseSearchResult {
        let detail = try await releaseDetail(id: id)
        let mediaFormats = Array(NSOrderedSet(array: detail.media.map(\.format).filter { !$0.isEmpty })) as? [String] ?? []

        let releaseGroup: MusicBrainzReleaseSearchResult.ReleaseGroup?
        if !detail.releaseGroupID.isEmpty {
            releaseGroup = .init(
                id: detail.releaseGroupID,
                primaryType: detail.releaseGroupPrimaryType,
                secondaryTypes: detail.releaseGroupSecondaryTypes
            )
        } else {
            releaseGroup = nil
        }

        return MusicBrainzReleaseSearchResult(
            id: detail.id,
            title: detail.title,
            artistCredit: detail.artistCredit,
            score: 100,
            date: detail.date,
            country: detail.country,
            status: detail.status,
            mediaFormats: mediaFormats,
            releaseGroup: releaseGroup,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
    }

    private func searchRecordings(luceneQuery: String, limit: Int) async throws -> [MusicBrainzRecordingResult] {
        guard !luceneQuery.isEmpty else {
            return []
        }

        let data = try await performRequest(
            resource: "recording",
            queryItems: [
                URLQueryItem(name: "query", value: luceneQuery),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
            ]
        )

        let payload: MusicBrainzRecordingSearchResponse
        do {
            payload = try decoder.decode(MusicBrainzRecordingSearchResponse.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return payload.recordings.map(MusicBrainzRecordingResult.init)
    }

    private func searchRecordings(luceneQueries: [String], limit: Int) async throws -> [MusicBrainzRecordingResult] {
        let normalizedQueries = luceneQueries.filter { !$0.isEmpty }
        guard !normalizedQueries.isEmpty else { return [] }

        var mergedResults: [MusicBrainzRecordingResult] = []
        var seenIDs: Set<String> = []
        var lastRecoverableError: MusicBrainzClientError?

        for luceneQuery in normalizedQueries {
            do {
                let results = try await searchRecordings(
                    luceneQuery: luceneQuery,
                    limit: max(8, min(limit, 25))
                )

                for result in results where seenIDs.insert(result.id).inserted {
                    mergedResults.append(result)
                }

                if mergedResults.count >= limit {
                    break
                }
            } catch let error as MusicBrainzClientError {
                if error.isRecoverableServerFailure {
                    lastRecoverableError = error
                    continue
                }
                throw error
            }
        }

        if !mergedResults.isEmpty {
            return Array(mergedResults.prefix(limit))
        }

        if let lastRecoverableError {
            throw lastRecoverableError
        }

        return []
    }

    private func searchReleases(luceneQuery: String, limit: Int) async throws -> [MusicBrainzReleaseSearchResult] {
        guard !luceneQuery.isEmpty else {
            return []
        }

        let data = try await performRequest(
            resource: "release",
            queryItems: [
                URLQueryItem(name: "query", value: luceneQuery),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
            ]
        )

        let payload: MusicBrainzReleaseSearchResponse
        do {
            payload = try decoder.decode(MusicBrainzReleaseSearchResponse.self, from: data)
        } catch let error as DecodingError {
            throw MusicBrainzClientError.decodingFailed(Self.describeDecodingError(error))
        }

        return payload.releases.map(MusicBrainzReleaseSearchResult.init)
    }

    private func searchReleases(luceneQueries: [String], limit: Int) async throws -> [MusicBrainzReleaseSearchResult] {
        let normalizedQueries = luceneQueries.filter { !$0.isEmpty }
        guard !normalizedQueries.isEmpty else { return [] }

        var mergedResults: [MusicBrainzReleaseSearchResult] = []
        var seenIDs: Set<String> = []
        var lastRecoverableError: MusicBrainzClientError?

        for luceneQuery in normalizedQueries {
            do {
                let results = try await searchReleases(
                    luceneQuery: luceneQuery,
                    limit: max(8, min(limit, 25))
                )

                for result in results where seenIDs.insert(result.id).inserted {
                    mergedResults.append(result)
                }

                if mergedResults.count >= limit {
                    break
                }
            } catch let error as MusicBrainzClientError {
                if error.isRecoverableServerFailure {
                    lastRecoverableError = error
                    continue
                }
                throw error
            }
        }

        if !mergedResults.isEmpty {
            return Array(mergedResults.prefix(limit))
        }

        if let lastRecoverableError {
            throw lastRecoverableError
        }

        return []
    }

    private static func deduplicatedRecordings(_ recordings: [MusicBrainzRecordingResult]) -> [MusicBrainzRecordingResult] {
        var seenIDs: Set<String> = []
        var orderedResults: [MusicBrainzRecordingResult] = []

        for recording in recordings where seenIDs.insert(recording.id).inserted {
            orderedResults.append(recording)
        }

        return orderedResults
    }

    private static func deduplicatedReleases(_ releases: [MusicBrainzReleaseSearchResult]) -> [MusicBrainzReleaseSearchResult] {
        var seenIDs: Set<String> = []
        var orderedResults: [MusicBrainzReleaseSearchResult] = []

        for release in releases where seenIDs.insert(release.id).inserted {
            orderedResults.append(release)
        }

        return orderedResults
    }

    private static func representativeFilesForReleaseLookup(
        from files: [MusicBrainzFileSearchInput]
    ) -> [MusicBrainzFileSearchInput] {
        let orderedFiles = files
            .filter { !$0.preferredDisplayTitle.isEmpty }
            .sorted {
                ($0.normalizedDiscNumber ?? 0, $0.normalizedTrackNumber ?? 0, $0.preferredDisplayTitle)
                    < ($1.normalizedDiscNumber ?? 0, $1.normalizedTrackNumber ?? 0, $1.preferredDisplayTitle)
            }

        guard orderedFiles.count > 3 else {
            return orderedFiles
        }

        let positions = [0, orderedFiles.count / 2, orderedFiles.count - 1]
        let uniquePositions = Array(NSOrderedSet(array: positions)) as? [Int] ?? positions
        return uniquePositions.map { orderedFiles[$0] }
    }

    private func performRequest(
        resource: String,
        id: String? = nil,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        let baseURL: URL
        if let id {
            baseURL = Self.baseURL
                .appending(path: resource)
                .appending(path: id)
        } else {
            baseURL = Self.baseURL.appending(path: resource)
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw MusicBrainzClientError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        try await rateLimiter.waitIfNeeded()
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MusicBrainzClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        func codingPathDescription(_ path: [CodingKey]) -> String {
            let parts = path.map(\.stringValue).filter { !$0.isEmpty }
            return parts.isEmpty ? "(root)" : parts.joined(separator: ".")
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPathDescription(context.codingPath))."
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(codingPathDescription(context.codingPath))."
        case .valueNotFound(let type, let context):
            return "Missing value for \(type) at \(codingPathDescription(context.codingPath))."
        case .dataCorrupted(let context):
            return "Corrupted data at \(codingPathDescription(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error."
        }
    }
}

enum MusicBrainzLuceneQueryBuilder {
    nonisolated private static let reservedCharacters: Set<Character> = Set(#"+-&|!(){}[]^"~*?:\/"#)
    nonisolated private static let maxPreferredClauseCount = 6
    nonisolated private static let maxPreferredClauseLength = 420

    static func recordingSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        finalizedPreferredClauses(
            applyingFilters(to: recordingSearchClauses(from: query), filters: query.releaseFilters)
        )
    }

    static func releaseSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        var clauses: [String] = []

        if !query.album.isEmpty, !query.artist.isEmpty {
            clauses.append(allOf([
                fieldClause(name: "release", value: query.album),
                fieldClause(name: "artist", value: query.artist)
            ]))
        }

        if !query.album.isEmpty {
            clauses.append(fieldClause(name: "release", value: query.album))
            clauses.append(generalClause(query.album))
        } else if !query.title.isEmpty {
            clauses.append(fieldClause(name: "release", value: query.title))
            clauses.append(generalClause(query.title))
        }

        if !query.artist.isEmpty {
            clauses.append(fieldClause(name: "artist", value: query.artist))
            clauses.append(generalClause(query.artist))
        }

        return finalizedPreferredClauses(applyingFilters(to: clauses, filters: query.releaseFilters))
    }

    static func fileSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        finalizedPreferredClauses(
            applyingFilters(to: recordingSearchClauses(from: query), filters: query.releaseFilters)
        )
    }

    static func fileClusterStrongReleaseSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        guard let summary = query.fileSelectionSummary else { return [] }

        var clauses: [String] = []
        let releaseClause = summary.albumCandidate.isEmpty ? "" : fieldClause(name: "release", value: summary.albumCandidate)
        let artistClauses = [summary.albumArtistCandidate, summary.primaryArtistCandidate]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { fieldClause(name: "artist", value: $0) }
        let trackCountClause = summary.releaseTrackCountCandidate > 0
            ? numericClause(name: "tracks", value: summary.releaseTrackCountCandidate)
            : ""
        let yearClause = summary.releaseYearCandidate.isEmpty
            ? ""
            : fieldClause(name: "date", value: summary.releaseYearCandidate)

        if let releaseIDClause = validMBIDClause(name: "reid", value: summary.musicBrainzAlbumIDCandidate) {
            clauses.append(releaseIDClause)
        }

        if !summary.barcodeCandidate.isEmpty {
            clauses.append(fieldClause(name: "barcode", value: summary.barcodeCandidate))
        }

        if !releaseClause.isEmpty && !artistClauses.isEmpty && !trackCountClause.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([releaseClause, artistClause, trackCountClause]))
            }
        }

        if !releaseClause.isEmpty && !artistClauses.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([releaseClause, artistClause]))
            }
        }

        if !releaseClause.isEmpty && !trackCountClause.isEmpty {
            clauses.append(allOf([releaseClause, trackCountClause]))
        }

        if !releaseClause.isEmpty && !yearClause.isEmpty {
            clauses.append(allOf([releaseClause, yearClause]))
        }

        return finalizedPreferredClauses(applyingFilters(to: clauses, filters: query.releaseFilters))
    }

    static func fileClusterBroadReleaseSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        guard let summary = query.fileSelectionSummary else { return [] }

        var clauses: [String] = []

        if !summary.albumCandidate.isEmpty {
            clauses.append(fieldClause(name: "release", value: summary.albumCandidate))
            clauses.append(generalClause(summary.albumCandidate))
        }

        if !summary.albumArtistCandidate.isEmpty {
            clauses.append(fieldClause(name: "artist", value: summary.albumArtistCandidate))
            clauses.append(generalClause(summary.albumArtistCandidate))
        } else if !summary.primaryArtistCandidate.isEmpty {
            clauses.append(fieldClause(name: "artist", value: summary.primaryArtistCandidate))
            clauses.append(generalClause(summary.primaryArtistCandidate))
        }

        if summary.releaseTrackCountCandidate > 0 {
            clauses.append(numericClause(name: "tracks", value: summary.releaseTrackCountCandidate))
        }

        if !summary.releaseYearCandidate.isEmpty {
            clauses.append(fieldClause(name: "date", value: summary.releaseYearCandidate))
        }

        return finalizedPreferredClauses(applyingFilters(to: clauses, filters: query.releaseFilters))
    }

    static func fileStrongSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        var queries: [String] = []
        let titleClause = query.title.isEmpty ? "" : fieldClause(name: "recording", value: query.title)
        let releaseIDClause = validMBIDClause(name: "reid", value: query.musicBrainzAlbumID)
        let artistClauses = query.artistCandidates.map { fieldClause(name: "artist", value: $0) }
        let trackClauses = trackNumberClauses(query.trackNumber)
        let trackTotalClauses = trackTotalClauses(query.trackTotal)
        let durationClauses = durationClauses(query.quantizedDuration)

        if let trackIDClause = validMBIDClause(name: "tid", value: query.musicBrainzTrackID) {
            queries.append(trackIDClause)
        }

        if !query.isrc.isEmpty {
            queries.append(fieldClause(name: "isrc", value: query.isrc))
        }

        if let releaseIDClause {
            var releaseScopedQueries: [String] = []

            if !titleClause.isEmpty && !artistClauses.isEmpty && !trackClauses.isEmpty {
                for artistClause in artistClauses {
                    for trackClause in trackClauses {
                        releaseScopedQueries.append(allOf([releaseIDClause, titleClause, artistClause, trackClause]))
                    }
                }
            }

            for trackClause in trackClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, trackClause]))
            }

            if !titleClause.isEmpty {
                releaseScopedQueries.append(allOf([releaseIDClause, titleClause]))
            }

            for artistClause in artistClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, artistClause]))

                if !titleClause.isEmpty {
                    releaseScopedQueries.append(allOf([releaseIDClause, titleClause, artistClause]))
                }
            }

            for durationClause in durationClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, durationClause]))
            }

            for trackTotalClause in trackTotalClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, trackTotalClause]))
            }

            if releaseScopedQueries.isEmpty {
                releaseScopedQueries.append(releaseIDClause)
            }

            queries.append(contentsOf: releaseScopedQueries)
        }

        return finalizedPreferredClauses(applyingFilters(to: queries, filters: query.releaseFilters))
    }

    nonisolated private static func fieldClause(name: String, value: String) -> String {
        let escaped = escapeLucene(value)
        return "\(name):\"\(escaped)\""
    }

    nonisolated private static func generalClause(_ value: String) -> String {
        let tokens = searchTokens(in: value)
        guard !tokens.isEmpty else { return "" }

        if tokens.count == 1 {
            return escapeLucene(tokens[0])
        }

        return allOf(tokens.map(escapeLucene))
    }

    nonisolated private static func allOf(_ clauses: [String]) -> String {
        "(" + clauses.joined(separator: " AND ") + ")"
    }

    nonisolated private static func anyOf(_ clauses: [String]) -> String {
        "(" + clauses.joined(separator: " OR ") + ")"
    }

    nonisolated private static func numericClause(name: String, value: Int) -> String {
        "\(name):\(value)"
    }

    nonisolated private static func validMBIDClause(name: String, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return fieldClause(name: name, value: trimmed)
    }

    nonisolated private static func joinPreferredClauses(_ clauses: [String]) -> String {
        let deduplicated = deduplicatedClauses(clauses)
        return deduplicated.joined(separator: " OR ")
    }

    nonisolated private static func finalizedPreferredClauses(_ clauses: [String]) -> [String] {
        deduplicatedClauses(clauses)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= maxPreferredClauseLength }
            .prefix(maxPreferredClauseCount)
            .map { $0 }
    }

    nonisolated private static func applyingFilters(
        to clauses: [String],
        filters: MusicBrainzReleaseFilters
    ) -> [String] {
        let filterClauses = releaseFilterClauses(from: filters)
        guard !filterClauses.isEmpty else { return clauses }

        let baseClauses = clauses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !baseClauses.isEmpty else {
            return [allOf(filterClauses)]
        }

        return baseClauses.map { allOf([$0] + filterClauses) }
    }

    nonisolated private static func releaseFilterClauses(from filters: MusicBrainzReleaseFilters) -> [String] {
        var clauses: [String] = []

        if !filters.mediaFormats.isEmpty {
            clauses.append(
                anyOf(
                    filters.mediaFormats
                        .sorted { $0.displayName < $1.displayName }
                        .map { fieldClause(name: "format", value: $0.rawValue) }
                )
            )
        }

        let releaseYear = MusicBrainzReleaseFilters.normalizedYear(filters.releaseYear)
        if !releaseYear.isEmpty {
            clauses.append(fieldClause(name: "date", value: releaseYear))
        }

        if !filters.countries.isEmpty {
            clauses.append(
                anyOf(
                    filters.normalizedCountries
                        .map { fieldClause(name: "country", value: $0.lowercased()) }
                )
            )
        }

        if !filters.statuses.isEmpty {
            clauses.append(
                anyOf(
                    filters.statuses
                        .sorted { $0.displayName < $1.displayName }
                        .map { fieldClause(name: "status", value: $0.rawValue) }
                )
            )
        }

        return clauses
    }

    nonisolated private static func deduplicatedClauses(_ clauses: [String]) -> [String] {
        (Array(NSOrderedSet(array: clauses.filter { !$0.isEmpty })) as? [String]) ?? []
    }

    nonisolated private static func escapeLucene(_ raw: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(raw.count)

        for character in raw {
            if reservedCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        return escaped
    }

    nonisolated private static func searchTokens(in raw: String) -> [String] {
        raw
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func recordingSearchClauses(from query: MusicBrainzSearchQuery) -> [String] {
        let titleClause = query.title.isEmpty ? "" : fieldClause(name: "recording", value: query.title)
        let releaseClause = query.album.isEmpty ? "" : fieldClause(name: "release", value: query.album)
        let artistClauses = query.artistCandidates.map { fieldClause(name: "artist", value: $0) }
        let trackClauses = trackNumberClauses(query.trackNumber)
        let trackTotalClauses = trackTotalClauses(query.trackTotal)
        let durationClauses = durationClauses(query.quantizedDuration)

        var clauses: [String] = []

        if !titleClause.isEmpty && !artistClauses.isEmpty && !releaseClause.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([titleClause, artistClause, releaseClause]))
            }
        }

        if !titleClause.isEmpty && !artistClauses.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([titleClause, artistClause]))
            }
        }

        if !titleClause.isEmpty && !releaseClause.isEmpty {
            clauses.append(allOf([titleClause, releaseClause]))
        }

        if !releaseClause.isEmpty && !artistClauses.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([releaseClause, artistClause]))
            }
        }

        if !titleClause.isEmpty && !trackClauses.isEmpty {
            for trackClause in trackClauses {
                clauses.append(allOf([titleClause, trackClause]))
            }
        }

        if !releaseClause.isEmpty && !trackClauses.isEmpty {
            for trackClause in trackClauses {
                clauses.append(allOf([releaseClause, trackClause]))
            }
        }

        if !titleClause.isEmpty {
            for durationClause in durationClauses {
                clauses.append(allOf([titleClause, durationClause]))
            }
        }

        if !releaseClause.isEmpty {
            for totalTrackClause in trackTotalClauses {
                clauses.append(allOf([releaseClause, totalTrackClause]))
            }
        }

        if !titleClause.isEmpty && !releaseClause.isEmpty {
            for durationClause in durationClauses {
                clauses.append(allOf([titleClause, releaseClause, durationClause]))
            }

            for totalTrackClause in trackTotalClauses {
                clauses.append(allOf([titleClause, releaseClause, totalTrackClause]))
            }
        }

        if !trackClauses.isEmpty {
            for trackClause in trackClauses {
                for durationClause in durationClauses {
                    clauses.append(allOf([trackClause, durationClause]))
                }
            }
        }

        if !titleClause.isEmpty {
            clauses.append(titleClause)
            clauses.append(generalClause(query.title))
        }

        if !releaseClause.isEmpty {
            clauses.append(releaseClause)
            clauses.append(generalClause(query.album))
        }

        clauses.append(contentsOf: artistClauses)
        clauses.append(contentsOf: trackClauses)
        clauses.append(contentsOf: trackTotalClauses)
        clauses.append(contentsOf: durationClauses)

        return clauses
    }

    nonisolated private static func trackNumberClauses(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = trimmed
            .split(separator: "/")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        var clauses: [String] = []

        let numericToken = String(normalized.drop(while: { $0 == "0" }))

        if let numericValue = Int(numericToken), numericValue > 0 {
            clauses.append(numericClause(name: "tnum", value: numericValue))
        } else if let numericValue = Int(normalized), numericValue > 0 {
            clauses.append(numericClause(name: "tnum", value: numericValue))
        }

        if !normalized.isEmpty {
            clauses.append(fieldClause(name: "number", value: normalized))
        }

        return (Array(NSOrderedSet(array: clauses)) as? [String]) ?? clauses
    }

    nonisolated private static func trackTotalClauses(_ trackTotal: Int) -> [String] {
        guard trackTotal > 0 else { return [] }
        return [numericClause(name: "tracks", value: trackTotal)]
    }

    nonisolated private static func durationClauses(_ quantizedDuration: Int?) -> [String] {
        guard let quantizedDuration, quantizedDuration > 0 else { return [] }
        return [numericClause(name: "qdur", value: quantizedDuration)]
    }
}

private enum MusicBrainzLinkTarget {
    case recording(String)
    case release(String)
}

private extension String {
    var validMBID: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return trimmed
    }
}

private enum MusicBrainzLinkParser {
    private static let supportedHosts = Set(NetworkServiceDisclosure.MusicBrainz.acceptedLinkDomains)

    static func parse(_ rawValue: String) throws -> MusicBrainzLinkTarget {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MusicBrainzClientError.invalidLink
        }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: normalized),
              let host = components.host?.lowercased(),
              supportedHosts.contains(host) else {
            throw MusicBrainzClientError.invalidLink
        }

        let pathComponents = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard pathComponents.count >= 2 else {
            throw MusicBrainzClientError.invalidLink
        }

        let entity = pathComponents[0].lowercased()
        let id = pathComponents[1]

        guard UUID(uuidString: id) != nil else {
            throw MusicBrainzClientError.invalidLink
        }

        switch entity {
        case "recording":
            return .recording(id)
        case "release":
            return .release(id)
        default:
            throw MusicBrainzClientError.unsupportedLink
        }
    }
}

private struct MusicBrainzRecordingSearchResponse: Decodable {
    let recordings: [MusicBrainzRecordingDTO]
}

private struct MusicBrainzReleaseSearchResponse: Decodable {
    let releases: [MusicBrainzReleaseSearchDTO]
}

private struct MusicBrainzRecordingDTO: Decodable {
    let id: String
    let title: String
    let score: Int
    let disambiguation: String
    let firstReleaseDate: String
    let length: Int?
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let releases: [MusicBrainzReleaseDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case disambiguation
        case length
        case releases
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        firstReleaseDate = try container.decodeIfPresent(String.self, forKey: .firstReleaseDate) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        releases = try container.decodeIfPresent([MusicBrainzReleaseDTO].self, forKey: .releases) ?? []

        if let score = try container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = score
        } else if
            let scoreString = try container.decodeIfPresent(String.self, forKey: .score),
            let score = Int(scoreString)
        {
            self.score = score
        } else {
            self.score = 0
        }
    }
}

private struct MusicBrainzArtistCreditDTO: Decodable {
    let name: String?
    let joinPhrase: String
    let artist: MusicBrainzArtistDTO?

    enum CodingKeys: String, CodingKey {
        case name
        case artist
        case joinPhrase = "joinphrase"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        joinPhrase = try container.decodeIfPresent(String.self, forKey: .joinPhrase) ?? ""
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
    }
}

private struct MusicBrainzArtistDTO: Decodable {
    let id: String
    let name: String?
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private struct MusicBrainzReleaseDTO: Decodable {
    let id: String
    let title: String
    let date: String
    let country: String
    let status: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case status
    }
}

private struct MusicBrainzReleaseSearchDTO: Decodable {
    let id: String
    let title: String
    let score: Int
    let date: String
    let country: String
    let status: String
    let media: [MusicBrainzMediumDTO]
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let releaseGroup: MusicBrainzReleaseGroupDTO?

    enum CodingKeys: String, CodingKey {
        case id, title, score, date, country, status
        case media
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        media = try container.decodeIfPresent([MusicBrainzMediumDTO].self, forKey: .media) ?? []
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupDTO.self, forKey: .releaseGroup)

        if let score = try container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = score
        } else if
            let scoreString = try container.decodeIfPresent(String.self, forKey: .score),
            let score = Int(scoreString)
        {
            self.score = score
        } else {
            self.score = 0
        }
    }
}

private struct MusicBrainzReleaseGroupDTO: Decodable {
    let id: String
    let primaryType: String
    let secondaryTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        primaryType = try container.decodeIfPresent(String.self, forKey: .primaryType) ?? ""
        secondaryTypes = try container.decodeIfPresent([String].self, forKey: .secondaryTypes) ?? []
    }
}

private struct MusicBrainzTermDTO: Decodable {
    let name: String
    let count: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            name = value
            count = nil
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        name = try keyed.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let count = try keyed.decodeIfPresent(Int.self, forKey: .count) {
            self.count = count
        } else if
            let countString = try keyed.decodeIfPresent(String.self, forKey: .count),
            let count = Int(countString)
        {
            self.count = count
        } else {
            self.count = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case count
    }
}

private struct MusicBrainzRatingDTO: Decodable {
    let value: Double?
    let voteCount: Int

    enum CodingKeys: String, CodingKey {
        case value
        case voteCount = "votes-count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try container.decodeIfPresent(Double.self, forKey: .value) {
            self.value = value
        } else if
            let valueString = try container.decodeIfPresent(String.self, forKey: .value),
            let value = Double(valueString)
        {
            self.value = value
        } else {
            self.value = nil
        }

        if let voteCount = try container.decodeIfPresent(Int.self, forKey: .voteCount) {
            self.voteCount = voteCount
        } else if
            let voteCountString = try container.decodeIfPresent(String.self, forKey: .voteCount),
            let voteCount = Int(voteCountString)
        {
            self.voteCount = voteCount
        } else {
            self.voteCount = 0
        }
    }
}

private struct MusicBrainzTextRepresentationDTO: Decodable {
    let language: String
    let script: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case script
    }
}

private struct MusicBrainzRecordingLookupDTO: Decodable {
    let id: String
    let title: String
    let disambiguation: String
    let firstReleaseDate: String
    let length: Int?
    let annotation: String
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let isrcs: [String]
    let genres: [MusicBrainzTermDTO]
    let tags: [MusicBrainzTermDTO]
    let rating: MusicBrainzRatingDTO?
    let releases: [MusicBrainzReleaseDTO]
    let relations: [MusicBrainzRelationDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case disambiguation
        case length
        case annotation
        case isrcs
        case genres
        case tags
        case rating
        case releases
        case relations
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        firstReleaseDate = try container.decodeIfPresent(String.self, forKey: .firstReleaseDate) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
        genres = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .tags) ?? []
        rating = try container.decodeIfPresent(MusicBrainzRatingDTO.self, forKey: .rating)
        releases = try container.decodeIfPresent([MusicBrainzReleaseDTO].self, forKey: .releases) ?? []
        relations = try container.decodeIfPresent([MusicBrainzRelationDTO].self, forKey: .relations) ?? []
    }
}

private struct MusicBrainzReleaseLookupDTO: Decodable {
    let id: String
    let title: String
    let date: String
    let country: String
    let status: String
    let barcode: String
    let packaging: String
    let asin: String
    let quality: String
    let annotation: String
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let genres: [MusicBrainzTermDTO]
    let tags: [MusicBrainzTermDTO]
    let textRepresentation: MusicBrainzTextRepresentationDTO?
    let releaseGroup: MusicBrainzReleaseGroupLookupDTO?
    let labelInfo: [MusicBrainzLabelInfoDTO]
    let media: [MusicBrainzMediumDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case country
        case status
        case barcode
        case packaging
        case asin
        case quality
        case annotation
        case genres
        case tags
        case media
        case textRepresentation = "text-representation"
        case artistCredit = "artist-credit"
        case releaseGroup = "release-group"
        case labelInfo = "label-info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode) ?? ""
        packaging = try container.decodeIfPresent(String.self, forKey: .packaging) ?? ""
        asin = try container.decodeIfPresent(String.self, forKey: .asin) ?? ""
        quality = try container.decodeIfPresent(String.self, forKey: .quality) ?? ""
        annotation = try container.decodeIfPresent(String.self, forKey: .annotation) ?? ""
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        genres = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent([MusicBrainzTermDTO].self, forKey: .tags) ?? []
        textRepresentation = try container.decodeIfPresent(MusicBrainzTextRepresentationDTO.self, forKey: .textRepresentation)
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupLookupDTO.self, forKey: .releaseGroup)
        labelInfo = try container.decodeIfPresent([MusicBrainzLabelInfoDTO].self, forKey: .labelInfo) ?? []
        media = try container.decodeIfPresent([MusicBrainzMediumDTO].self, forKey: .media) ?? []
    }
}

private struct MusicBrainzReleaseGroupLookupDTO: Decodable {
    let id: String
    let title: String
    let primaryType: String
    let secondaryTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        primaryType = try container.decodeIfPresent(String.self, forKey: .primaryType) ?? ""
        secondaryTypes = try container.decodeIfPresent([String].self, forKey: .secondaryTypes) ?? []
    }
}

private struct MusicBrainzLabelInfoDTO: Decodable {
    let catalogNumber: String
    let label: MusicBrainzLabelDTO?

    enum CodingKeys: String, CodingKey {
        case catalogNumber = "catalog-number"
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogNumber = try container.decodeIfPresent(String.self, forKey: .catalogNumber) ?? ""
        label = try container.decodeIfPresent(MusicBrainzLabelDTO.self, forKey: .label)
    }
}

private struct MusicBrainzLabelDTO: Decodable {
    let id: String
    let name: String
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private struct MusicBrainzPlaceDTO: Decodable {
    let id: String
    let name: String
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private struct MusicBrainzSeriesDTO: Decodable {
    let id: String
    let name: String
    let disambiguation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case disambiguation
    }
}

private struct MusicBrainzURLDTO: Decodable {
    let id: String
    let resource: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        resource = try container.decodeIfPresent(String.self, forKey: .resource) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case resource
    }
}

private struct MusicBrainzRelatedRecordingDTO: Decodable {
    let id: String
    let title: String
    let disambiguation: String
    let artistCredit: [MusicBrainzArtistCreditDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case disambiguation
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
    }
}

private struct MusicBrainzWorkDTO: Decodable {
    let id: String
    let title: String
    let disambiguation: String
    let relations: [MusicBrainzNestedRelationDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        disambiguation = try container.decodeIfPresent(String.self, forKey: .disambiguation) ?? ""
        relations = try container.decodeIfPresent([MusicBrainzNestedRelationDTO].self, forKey: .relations) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case disambiguation
        case relations
    }
}

private struct MusicBrainzRelationDTO: Decodable {
    let type: String
    let direction: String
    let targetType: String
    let begin: String
    let end: String
    let ended: Bool
    let attributes: [String]
    let attributeValues: [String: String]
    let artist: MusicBrainzArtistDTO?
    let label: MusicBrainzLabelDTO?
    let place: MusicBrainzPlaceDTO?
    let recording: MusicBrainzRelatedRecordingDTO?
    let release: MusicBrainzReleaseDTO?
    let releaseGroup: MusicBrainzReleaseGroupLookupDTO?
    let series: MusicBrainzSeriesDTO?
    let work: MusicBrainzWorkDTO?
    let url: MusicBrainzURLDTO?
    let targetCredit: String
    let sourceCredit: String

    enum CodingKeys: String, CodingKey {
        case type
        case direction
        case targetType = "target-type"
        case begin
        case end
        case ended
        case attributes
        case attributeValues = "attribute-values"
        case artist
        case label
        case place
        case recording
        case release
        case releaseGroup = "release-group"
        case series
        case work
        case url
        case targetCredit = "target-credit"
        case sourceCredit = "source-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType) ?? ""
        begin = try container.decodeIfPresent(String.self, forKey: .begin) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        ended = try container.decodeIfPresent(Bool.self, forKey: .ended) ?? false
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        attributeValues = try container.decodeIfPresent([String: String].self, forKey: .attributeValues) ?? [:]
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
        label = try container.decodeIfPresent(MusicBrainzLabelDTO.self, forKey: .label)
        place = try container.decodeIfPresent(MusicBrainzPlaceDTO.self, forKey: .place)
        recording = try container.decodeIfPresent(MusicBrainzRelatedRecordingDTO.self, forKey: .recording)
        release = try container.decodeIfPresent(MusicBrainzReleaseDTO.self, forKey: .release)
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupLookupDTO.self, forKey: .releaseGroup)
        series = try container.decodeIfPresent(MusicBrainzSeriesDTO.self, forKey: .series)
        work = try container.decodeIfPresent(MusicBrainzWorkDTO.self, forKey: .work)
        url = try container.decodeIfPresent(MusicBrainzURLDTO.self, forKey: .url)
        targetCredit = try container.decodeIfPresent(String.self, forKey: .targetCredit) ?? ""
        sourceCredit = try container.decodeIfPresent(String.self, forKey: .sourceCredit) ?? ""
    }
}

private struct MusicBrainzNestedRelationDTO: Decodable {
    let type: String
    let direction: String
    let targetType: String
    let begin: String
    let end: String
    let ended: Bool
    let attributes: [String]
    let attributeValues: [String: String]
    let artist: MusicBrainzArtistDTO?
    let label: MusicBrainzLabelDTO?
    let place: MusicBrainzPlaceDTO?
    let recording: MusicBrainzRelatedRecordingDTO?
    let release: MusicBrainzReleaseDTO?
    let releaseGroup: MusicBrainzReleaseGroupLookupDTO?
    let series: MusicBrainzSeriesDTO?
    let url: MusicBrainzURLDTO?
    let targetCredit: String
    let sourceCredit: String

    enum CodingKeys: String, CodingKey {
        case type
        case direction
        case targetType = "target-type"
        case begin
        case end
        case ended
        case attributes
        case attributeValues = "attribute-values"
        case artist
        case label
        case place
        case recording
        case release
        case releaseGroup = "release-group"
        case series
        case url
        case targetCredit = "target-credit"
        case sourceCredit = "source-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType) ?? ""
        begin = try container.decodeIfPresent(String.self, forKey: .begin) ?? ""
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        ended = try container.decodeIfPresent(Bool.self, forKey: .ended) ?? false
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        attributeValues = try container.decodeIfPresent([String: String].self, forKey: .attributeValues) ?? [:]
        artist = try container.decodeIfPresent(MusicBrainzArtistDTO.self, forKey: .artist)
        label = try container.decodeIfPresent(MusicBrainzLabelDTO.self, forKey: .label)
        place = try container.decodeIfPresent(MusicBrainzPlaceDTO.self, forKey: .place)
        recording = try container.decodeIfPresent(MusicBrainzRelatedRecordingDTO.self, forKey: .recording)
        release = try container.decodeIfPresent(MusicBrainzReleaseDTO.self, forKey: .release)
        releaseGroup = try container.decodeIfPresent(MusicBrainzReleaseGroupLookupDTO.self, forKey: .releaseGroup)
        series = try container.decodeIfPresent(MusicBrainzSeriesDTO.self, forKey: .series)
        url = try container.decodeIfPresent(MusicBrainzURLDTO.self, forKey: .url)
        targetCredit = try container.decodeIfPresent(String.self, forKey: .targetCredit) ?? ""
        sourceCredit = try container.decodeIfPresent(String.self, forKey: .sourceCredit) ?? ""
    }
}

private struct MusicBrainzMediumDTO: Decodable {
    let id: String
    let title: String
    let format: String
    let trackCount: Int
    let discs: [MusicBrainzDiscDTO]
    let tracks: [MusicBrainzTrackDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case format
        case discs
        case tracks
        case trackCount = "track-count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? ""
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        discs = try container.decodeIfPresent([MusicBrainzDiscDTO].self, forKey: .discs) ?? []
        tracks = try container.decodeIfPresent([MusicBrainzTrackDTO].self, forKey: .tracks) ?? []
    }
}

private struct MusicBrainzDiscDTO: Decodable {
    let id: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }
}

private struct MusicBrainzTrackDTO: Decodable {
    let id: String
    let number: String
    let title: String
    let length: Int?
    let artistCredit: [MusicBrainzArtistCreditDTO]
    let recording: MusicBrainzTrackRecordingDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case length
        case recording
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        number = try container.decodeIfPresent(String.self, forKey: .number) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
        recording = try container.decodeIfPresent(MusicBrainzTrackRecordingDTO.self, forKey: .recording)
    }
}

private struct MusicBrainzTrackRecordingDTO: Decodable {
    let id: String
    let title: String
    let length: Int?
    let isrcs: [String]
    let artistCredit: [MusicBrainzArtistCreditDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case length
        case isrcs
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
        artistCredit = try container.decodeIfPresent([MusicBrainzArtistCreditDTO].self, forKey: .artistCredit) ?? []
    }
}

private extension MusicBrainzRecordingResult {
    init(dto: MusicBrainzRecordingDTO) {
        id = dto.id
        title = dto.title
        score = dto.score
        disambiguation = dto.disambiguation
        firstReleaseDate = dto.firstReleaseDate
        durationMilliseconds = dto.length
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        releases = dto.releases.compactMap {
            guard !$0.id.isEmpty, !$0.title.isEmpty else { return nil }
            return Release(
                id: $0.id,
                title: $0.title,
                date: $0.date,
                country: $0.country,
                status: $0.status
            )
        }
    }
}

private extension MusicBrainzReleaseSearchResult {
    init(dto: MusicBrainzReleaseSearchDTO) {
        id = dto.id
        title = dto.title
        score = dto.score
        date = dto.date
        country = dto.country
        status = dto.status
        mediaFormats = Array(
            NSOrderedSet(
                array: dto.media
                    .map(\.format)
                    .filter { !$0.isEmpty }
            )
        ) as? [String] ?? []
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let group = dto.releaseGroup, !group.id.isEmpty {
            releaseGroup = ReleaseGroup(
                id: group.id,
                primaryType: group.primaryType,
                secondaryTypes: group.secondaryTypes
            )
        } else {
            releaseGroup = nil
        }

        selectionMatchPreview = nil
        selectionMatchScore = nil
    }
}

private extension MusicBrainzRecordingDetail {
    init(dto: MusicBrainzRecordingLookupDTO, releases: [MusicBrainzRecordingResult.Release]) {
        id = dto.id
        title = dto.title
        disambiguation = dto.disambiguation
        firstReleaseDate = dto.firstReleaseDate
        durationMilliseconds = dto.length
        annotation = dto.annotation
        isrcs = dto.isrcs.filter { !$0.isEmpty }
        genres = dto.genres.compactMap { MusicBrainzTerm($0) }
        tags = dto.tags.compactMap { MusicBrainzTerm($0) }
        rating = dto.rating.map { MusicBrainzRating(value: $0.value, voteCount: $0.voteCount) }
        relationshipGroups = MusicBrainzRelationshipBuilder.makeGroups(from: dto.relations)
        let lookupReleases = dto.releases.compactMap { dtoRelease -> MusicBrainzRecordingResult.Release? in
            guard !dtoRelease.id.isEmpty, !dtoRelease.title.isEmpty else { return nil }
            return MusicBrainzRecordingResult.Release(
                id: dtoRelease.id,
                title: dtoRelease.title,
                date: dtoRelease.date,
                country: dtoRelease.country,
                status: dtoRelease.status
            )
        }
        self.releases = lookupReleases.isEmpty ? releases : lookupReleases
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MusicBrainzReleaseDetail {
    init(dto: MusicBrainzReleaseLookupDTO) {
        id = dto.id
        title = dto.title
        date = dto.date
        country = dto.country
        status = dto.status
        barcode = dto.barcode
        packaging = dto.packaging
        asin = dto.asin
        quality = dto.quality
        language = dto.textRepresentation?.language ?? ""
        script = dto.textRepresentation?.script ?? ""
        annotation = dto.annotation
        genres = dto.genres.compactMap { MusicBrainzTerm($0) }
        tags = dto.tags.compactMap { MusicBrainzTerm($0) }
        releaseGroupTitle = dto.releaseGroup?.title ?? ""
        releaseGroupID = dto.releaseGroup?.id ?? ""
        releaseGroupPrimaryType = dto.releaseGroup?.primaryType ?? ""
        releaseGroupSecondaryTypes = dto.releaseGroup?.secondaryTypes ?? []
        labels = dto.labelInfo.compactMap { info in
            let labelName = info.label?.name ?? ""
            guard !labelName.isEmpty || !info.catalogNumber.isEmpty else { return nil }
            let id = info.label?.id ?? "\(labelName)-\(info.catalogNumber)"
            return LabelInfo(
                id: id,
                labelName: labelName,
                catalogNumber: info.catalogNumber
            )
        }
        media = dto.media.map { medium in
            Medium(
                id: medium.id,
                title: medium.title,
                format: medium.format,
                trackCount: medium.trackCount,
                discIDs: medium.discs.map(\.id).filter { !$0.isEmpty },
                tracks: medium.tracks.map { track in
                    Medium.Track(
                        id: track.id,
                        number: track.number,
                        title: track.title.isEmpty ? (track.recording?.title ?? "") : track.title,
                        artistCredit: musicBrainzJoinedArtistCredit(
                            track.artistCredit.isEmpty ? (track.recording?.artistCredit ?? []) : track.artistCredit
                        ),
                        durationMilliseconds: track.length ?? track.recording?.length,
                        recordingID: track.recording?.id ?? "",
                        isrcs: track.recording?.isrcs.filter { !$0.isEmpty } ?? []
                    )
                }
            )
        }
        selectionMatchPreview = nil
        artistCredit = dto.artistCredit
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MusicBrainzReleaseSearchResult {
    func withSelectionMatchPreview(
        _ preview: MusicBrainzReleaseMatchPreview,
        selectionMatchScore: Double
    ) -> MusicBrainzReleaseSearchResult {
        MusicBrainzReleaseSearchResult(
            id: id,
            title: title,
            artistCredit: artistCredit,
            score: score,
            date: date,
            country: country,
            status: status,
            mediaFormats: mediaFormats,
            releaseGroup: releaseGroup,
            selectionMatchPreview: preview,
            selectionMatchScore: selectionMatchScore
        )
    }
}

enum MusicBrainzTaggingPreviewBuilder {
    static func makePreview(
        files: [MusicBrainzFileSearchInput],
        release: MusicBrainzReleaseDetail
    ) -> MusicBrainzReleaseMatchPreview? {
        guard !files.isEmpty else { return nil }
        let selection = MusicBrainzFileSelectionSummary(files: files)
        return MusicBrainzFileSelectionMatcher.match(
            selection: selection,
            release: release
        )
    }
}

private extension MusicBrainzTerm {
    nonisolated init?(_ dto: MusicBrainzTermDTO) {
        guard !dto.name.isEmpty else { return nil }
        self.init(name: dto.name, count: dto.count)
    }
}

private func musicBrainzJoinedArtistCredit(_ credits: [MusicBrainzArtistCreditDTO]) -> String {
    credits
        .map { credit in
            let baseName = credit.name ?? credit.artist?.name ?? ""
            return baseName + credit.joinPhrase
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private enum MusicBrainzFileSelectionMatcher {
    static func match(
        selection: MusicBrainzFileSelectionSummary,
        release: MusicBrainzReleaseDetail
    ) -> MusicBrainzReleaseMatchPreview {
        let releaseTracks = flattenedTracks(from: release)
        let exactCandidates = buildCandidates(
            files: selection.files,
            tracks: releaseTracks,
            releaseArtistCredit: release.artistCredit,
            exactOnly: true
        )
        let exactAssignments = greedyAssignments(from: exactCandidates)

        let assignedFileIDs = Set(exactAssignments.map(\.file.id))
        let assignedTrackIDs = Set(exactAssignments.map(\.track.id))

        let remainingFiles = selection.files.filter { !assignedFileIDs.contains($0.id) }
        let remainingTracks = releaseTracks.filter { !assignedTrackIDs.contains($0.id) }

        let similarityCandidates = buildCandidates(
            files: remainingFiles,
            tracks: remainingTracks,
            releaseArtistCredit: release.artistCredit,
            exactOnly: false
        )
        let similarityAssignments = greedyAssignments(from: similarityCandidates)

        let allAssignments = (exactAssignments + similarityAssignments)
            .sorted {
                ($0.file.normalizedDiscNumber ?? 0, $0.file.normalizedTrackNumber ?? 0, $0.file.preferredDisplayTitle)
                    < ($1.file.normalizedDiscNumber ?? 0, $1.file.normalizedTrackNumber ?? 0, $1.file.preferredDisplayTitle)
            }

        let finalAssignedFileIDs = Set(allAssignments.map(\.file.id))
        let finalAssignedTrackIDs = Set(allAssignments.map(\.track.id))
        let unmatchedFiles = selection.files.filter { !finalAssignedFileIDs.contains($0.id) }
        let unassignedTracks = releaseTracks.filter { !finalAssignedTrackIDs.contains($0.id) }

        let averageTrackScore: Double
        if allAssignments.isEmpty {
            averageTrackScore = 0
        } else {
            averageTrackScore = allAssignments.map(\.score).reduce(0, +) / Double(allAssignments.count)
        }

        let releaseMetadataScore = releaseScore(selection: selection, release: release)
        let coverage = selection.files.isEmpty ? 0 : Double(allAssignments.count) / Double(selection.files.count)
        var overallScore = releaseMetadataScore
        overallScore += coverage * 420
        overallScore += averageTrackScore * 340
        overallScore -= Double(unmatchedFiles.count) * 90
        overallScore -= Double(unassignedTracks.count) * 15

        if selection.selectionLooksMixed {
            overallScore -= 60
        }

        return MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: selection.totalSelectedFiles,
            matchedAssignments: allAssignments,
            unmatchedFiles: unmatchedFiles,
            unassignedTracks: unassignedTracks,
            averageTrackScore: averageTrackScore,
            overallScore: max(0, overallScore),
            selectionLooksMixed: selection.selectionLooksMixed
        )
    }

    private static func flattenedTracks(from release: MusicBrainzReleaseDetail) -> [MusicBrainzReleaseMatchTrack] {
        release.media.enumerated().flatMap { mediumIndex, medium in
            medium.tracks.map { track in
                MusicBrainzReleaseMatchTrack(
                    id: track.id,
                    mediumTitle: medium.title,
                    mediumFormat: medium.format,
                    mediumPosition: mediumIndex + 1,
                    mediumTrackCount: max(medium.trackCount, medium.tracks.count),
                    releaseMediumCount: max(release.media.count, 1),
                    number: track.number,
                    title: track.title,
                    artistCredit: track.artistCredit,
                    durationMilliseconds: track.durationMilliseconds,
                    recordingID: track.recordingID,
                    isrcs: track.isrcs,
                    )
            }
        }
    }

    private static func buildCandidates(
        files: [MusicBrainzFileSearchInput],
        tracks: [MusicBrainzReleaseMatchTrack],
        releaseArtistCredit: String,
        exactOnly: Bool
    ) -> [MusicBrainzReleaseMatchAssignment] {
        var candidates: [MusicBrainzReleaseMatchAssignment] = []

        for file in files {
            for track in tracks {
                let candidate = candidateAssignment(
                    file: file,
                    track: track,
                    releaseArtistCredit: releaseArtistCredit,
                    exactOnly: exactOnly
                )

                if let candidate {
                    candidates.append(candidate)
                }
            }
        }

        return candidates.sorted {
            if $0.score == $1.score {
                return $0.file.preferredDisplayTitle < $1.file.preferredDisplayTitle
            }
            return $0.score > $1.score
        }
    }

    private static func greedyAssignments(
        from candidates: [MusicBrainzReleaseMatchAssignment]
    ) -> [MusicBrainzReleaseMatchAssignment] {
        var assignedFileIDs: Set<String> = []
        var assignedTrackIDs: Set<String> = []
        var assignments: [MusicBrainzReleaseMatchAssignment] = []

        for candidate in candidates {
            guard !assignedFileIDs.contains(candidate.file.id) else { continue }
            guard !assignedTrackIDs.contains(candidate.track.id) else { continue }

            assignedFileIDs.insert(candidate.file.id)
            assignedTrackIDs.insert(candidate.track.id)
            assignments.append(candidate)
        }

        return assignments
    }

    private static func candidateAssignment(
        file: MusicBrainzFileSearchInput,
        track: MusicBrainzReleaseMatchTrack,
        releaseArtistCredit: String,
        exactOnly: Bool
    ) -> MusicBrainzReleaseMatchAssignment? {
        if let exactReason = exactMatchReason(file: file, track: track) {
            return MusicBrainzReleaseMatchAssignment(
                id: "\(file.id)::\(track.id)",
                file: file,
                track: track,
                score: exactReason.score,
                reason: exactReason.reason
            )
        }

        guard !exactOnly else { return nil }

        let titleScore = weightedSimilarity(file.title, track.title)
        let artistTargets = [track.artistCredit, releaseArtistCredit].filter { !$0.isEmpty }
        let artistScore = bestSimilarity(file.artistCandidates, candidates: artistTargets)
        let durationScore = durationSimilarity(file.durationMilliseconds, track.durationMilliseconds)
        let trackNumberScore = trackIndexSimilarity(file.normalizedTrackNumber, candidateValue: track.number)
        let discNumberScore = discIndexSimilarity(file.normalizedDiscNumber, candidateValue: track.mediumPosition)
        let albumScore = weightedSimilarity(file.album, track.mediumTitle.isEmpty ? "" : track.mediumTitle)

        let similarity =
            (titleScore * 0.42) +
            (artistScore * 0.18) +
            (durationScore * 0.16) +
            (trackNumberScore * 0.14) +
            (discNumberScore * 0.05) +
            (albumScore * 0.05)

        guard similarity >= 0.48 else { return nil }

        return MusicBrainzReleaseMatchAssignment(
            id: "\(file.id)::\(track.id)",
            file: file,
            track: track,
            score: similarity,
            reason: trackNumberScore >= 1 ? "Track number + metadata" : "Metadata similarity"
        )
    }

    private static func exactMatchReason(
        file: MusicBrainzFileSearchInput,
        track: MusicBrainzReleaseMatchTrack
    ) -> (score: Double, reason: String)? {
        if let trackID = file.musicBrainzTrackID.validMBID,
           trackID == track.id || trackID == track.recordingID {
            return (1.0, "MusicBrainz ID")
        }

        if !file.isrc.isEmpty, track.isrcs.contains(file.isrc) {
            return (0.99, "ISRC")
        }

        let sameTrackNumber = trackIndexSimilarity(file.normalizedTrackNumber, candidateValue: track.number) >= 1
        let sameDiscNumber = file.normalizedDiscNumber == nil || discIndexSimilarity(file.normalizedDiscNumber, candidateValue: track.mediumPosition) >= 1
        let titleSimilarity = weightedSimilarity(file.title, track.title)

        if sameTrackNumber, sameDiscNumber, titleSimilarity >= 0.88 {
            return (0.94, "Track number + title")
        }

        return nil
    }

    private static func releaseScore(
        selection: MusicBrainzFileSelectionSummary,
        release: MusicBrainzReleaseDetail
    ) -> Double {
        let albumScore = weightedSimilarity(selection.albumCandidate, release.title) * 260
        let artistScore = bestSimilarity(
            [selection.albumArtistCandidate, selection.primaryArtistCandidate].filter { !$0.isEmpty },
            candidates: [release.artistCredit]
        ) * 170
        let yearScore = yearSimilarity(selection.releaseYearCandidate, candidateDate: release.date) * 70
        let trackCountScore = releaseTrackCountSimilarity(
            selectedCount: selection.totalSelectedFiles,
            releaseTrackCount: totalTrackCount(in: release)
        ) * 110

        var total = albumScore + artistScore + yearScore + trackCountScore

        if !selection.barcodeCandidate.isEmpty, selection.barcodeCandidate == release.barcode {
            total += 260
        }

        if let releaseID = selection.musicBrainzAlbumIDCandidate.validMBID, releaseID == release.id {
            total += 420
        }

        return total
    }

    private static func totalTrackCount(in release: MusicBrainzReleaseDetail) -> Int {
        let summed = release.media.reduce(0) { partialResult, medium in
            partialResult + max(medium.trackCount, medium.tracks.count)
        }
        return max(summed, release.media.flatMap(\.tracks).count)
    }

    private static func releaseTrackCountSimilarity(selectedCount: Int, releaseTrackCount: Int) -> Double {
        guard selectedCount > 0, releaseTrackCount > 0 else { return 0 }
        if selectedCount == releaseTrackCount {
            return 1
        }
        if selectedCount < releaseTrackCount {
            return 0.3
        }
        return 0
    }

    private static func trackIndexSimilarity(_ expected: Int?, candidateValue: String) -> Double {
        guard let expected else { return 0 }
        let candidate = normalizedIndex(candidateValue)
        guard let candidate else { return 0 }
        if expected == candidate {
            return 1
        }
        if abs(expected - candidate) == 1 {
            return 0.35
        }
        return 0
    }

    private static func discIndexSimilarity(_ expected: Int?, candidateValue: Int) -> Double {
        guard let expected else { return 0 }
        return expected == candidateValue ? 1 : 0
    }

    private static func durationSimilarity(_ lhs: Int?, _ rhs: Int?) -> Double {
        guard let lhs, let rhs else { return 0 }
        let difference = abs(lhs - rhs)
        guard difference < 30_000 else { return 0 }
        return 1 - (Double(difference) / 30_000)
    }

    private static func yearSimilarity(_ queryYear: String, candidateDate: String) -> Double {
        let digits = candidateDate.filter(\.isNumber)
        guard digits.count >= 4, !queryYear.isEmpty else { return 0 }
        let candidateYear = String(digits.prefix(4))
        guard let queryValue = Int(queryYear), let candidateValue = Int(candidateYear) else { return 0 }
        let difference = abs(queryValue - candidateValue)
        switch difference {
        case 0:
            return 1
        case 1:
            return 0.65
        case 2:
            return 0.3
        default:
            return 0
        }
    }

    private static func bestSimilarity(_ queries: [String], candidates: [String]) -> Double {
        var best = 0.0
        for query in queries {
            for candidate in candidates {
                best = max(best, weightedSimilarity(query, candidate))
            }
        }
        return best
    }

    private static func weightedSimilarity(_ lhs: String, _ rhs: String) -> Double {
        FuzzyStringSimilarity.score(lhs, rhs)
    }

    private static func normalizedIndex(_ rawValue: String) -> Int? {
        AudioTagNumberText.positiveIndex(from: rawValue)
    }
}

private enum MusicBrainzResultRanker {
    static func rerankRecordings(
        _ results: [MusicBrainzRecordingResult],
        query: MusicBrainzSearchQuery,
        preferredRecordingIDs: Set<String> = []
    ) -> [MusicBrainzRecordingResult] {
        results.sorted { lhs, rhs in
            let lhsScore = recordingScore(lhs, query: query, preferredRecordingIDs: preferredRecordingIDs)
            let rhsScore = recordingScore(rhs, query: query, preferredRecordingIDs: preferredRecordingIDs)
            if lhsScore == rhsScore {
                return lhs.score > rhs.score
            }
            return lhsScore > rhsScore
        }
    }

    static func rerankReleases(_ results: [MusicBrainzReleaseSearchResult], query: MusicBrainzSearchQuery) -> [MusicBrainzReleaseSearchResult] {
        results.sorted { lhs, rhs in
            let lhsScore = releaseScore(lhs, query: query)
            let rhsScore = releaseScore(rhs, query: query)
            if lhsScore == rhsScore {
                return lhs.score > rhs.score
            }
            return lhsScore > rhsScore
        }
    }

    private static func recordingScore(
        _ result: MusicBrainzRecordingResult,
        query: MusicBrainzSearchQuery,
        preferredRecordingIDs: Set<String>
    ) -> Double {
        var score = Double(result.score) * 1.8

        if preferredRecordingIDs.contains(result.id) {
            score += 700
        }

        if !query.musicBrainzAlbumID.isEmpty,
           result.releases.contains(where: { $0.id == query.musicBrainzAlbumID }) {
            score += 280
        }

        score += weightedSimilarityScore(
            query: query.title,
            candidates: [result.title],
            weight: 360
        )
        score += weightedSimilarityScore(
            queries: query.artistCandidates,
            candidates: [result.artistCredit],
            weight: 230
        )
        score += weightedSimilarityScore(
            queries: query.album.isEmpty ? [] : [query.album],
            candidates: result.releases.map(\.title),
            weight: 180
        )

        if let queryDuration = query.durationMilliseconds,
           let candidateDuration = result.durationMilliseconds {
            score += durationScore(queryDuration, candidateDuration) * 150
        }

        if !query.normalizedReleaseYear.isEmpty {
            score += yearScore(query.normalizedReleaseYear, candidateDate: result.firstReleaseDate) * 70
        }

        return score
    }

    private static func releaseScore(_ result: MusicBrainzReleaseSearchResult, query: MusicBrainzSearchQuery) -> Double {
        var score = Double(result.score) * 1.8

        score += weightedSimilarityScore(
            query: query.album.isEmpty ? query.title : query.album,
            candidates: [result.title],
            weight: 360
        )
        score += weightedSimilarityScore(
            queries: query.artistCandidates,
            candidates: [result.artistCredit],
            weight: 230
        )

        if !query.normalizedReleaseYear.isEmpty {
            score += yearScore(query.normalizedReleaseYear, candidateDate: result.date) * 90
        }

        return score
    }

    private static func weightedSimilarityScore(
        query: String,
        candidates: [String],
        weight: Double
    ) -> Double {
        weightedSimilarityScore(queries: query.isEmpty ? [] : [query], candidates: candidates, weight: weight)
    }

    private static func weightedSimilarityScore(
        queries: [String],
        candidates: [String],
        weight: Double
    ) -> Double {
        guard weight > 0 else { return 0 }

        var bestSimilarity = 0.0

        for query in queries {
            for candidate in candidates {
                bestSimilarity = max(bestSimilarity, FuzzyStringSimilarity.score(query, candidate))
            }
        }

        return bestSimilarity * weight
    }

    private static func durationScore(_ lhs: Int, _ rhs: Int) -> Double {
        let difference = abs(lhs - rhs)
        guard difference < 30_000 else { return 0 }
        return 1 - (Double(difference) / 30_000)
    }

    private static func yearScore(_ queryYear: String, candidateDate: String) -> Double {
        let candidateYearDigits = candidateDate.filter(\.isNumber)
        guard candidateYearDigits.count >= 4 else { return 0 }
        let candidateYear = String(candidateYearDigits.prefix(4))
        guard let queryValue = Int(queryYear), let candidateValue = Int(candidateYear) else { return 0 }

        let difference = abs(queryValue - candidateValue)
        switch difference {
        case 0:
            return 1
        case 1:
            return 0.65
        case 2:
            return 0.3
        default:
            return 0
        }
    }
}

private enum MusicBrainzRelationshipBuilder {
    static func makeGroups(from relations: [MusicBrainzRelationDTO]) -> [MusicBrainzRelationshipGroup] {
        var groups: [MusicBrainzRelationshipGroup] = []

        for relation in relations {
            append(relation: relation, to: &groups)

            if let work = relation.work {
                for nestedRelation in work.relations {
                    append(nestedRelation: nestedRelation, to: &groups)
                }
            }
        }

        return groups
    }

    private static func append(relation: MusicBrainzRelationDTO, to groups: inout [MusicBrainzRelationshipGroup]) {
        let title = relationTitle(
            type: relation.type,
            attributes: relation.attributes,
            attributeValues: relation.attributeValues,
            targetType: relation.targetType
        )
        let value = relationValue(from: relation)
        appendGroup(title: title, value: value, to: &groups)
    }

    private static func append(nestedRelation: MusicBrainzNestedRelationDTO, to groups: inout [MusicBrainzRelationshipGroup]) {
        let title = relationTitle(
            type: nestedRelation.type,
            attributes: nestedRelation.attributes,
            attributeValues: nestedRelation.attributeValues,
            targetType: nestedRelation.targetType
        )
        let value = relationValue(from: nestedRelation)
        appendGroup(title: title, value: value, to: &groups)
    }

    private static func appendGroup(title: String, value: String, to groups: inout [MusicBrainzRelationshipGroup]) {
        guard !title.isEmpty, !value.isEmpty else { return }

        if let index = groups.firstIndex(where: { $0.title == title }) {
            if !groups[index].values.contains(value) {
                groups[index].values.append(value)
            }
        } else {
            groups.append(MusicBrainzRelationshipGroup(title: title, values: [value]))
        }
    }

    private static func relationTitle(
        type: String,
        attributes: [String],
        attributeValues: [String: String],
        targetType: String
    ) -> String {
        if type == "performance", targetType == "work" {
            return "recording of"
        }

        if type == "phonographic copyright" {
            return "phonographic copyright (℗) by"
        }

        let loweredType = type.lowercased()
        if loweredType == "instrument" || loweredType == "vocal" || loweredType == "performer" {
            let attributeTitle = instrumentTitle(attributes: attributes, attributeValues: attributeValues)
            return attributeTitle.isEmpty ? loweredType : attributeTitle
        }

        if !attributes.isEmpty, shouldPrefixAttributes(to: loweredType) {
            return (attributes + [loweredType]).joined(separator: " ").lowercased()
        }

        return loweredType
    }

    private static func shouldPrefixAttributes(to relationType: String) -> Bool {
        switch relationType {
        case "engineer", "mix", "producer", "miscellaneous support":
            return true
        default:
            return false
        }
    }

    private static func instrumentTitle(attributes: [String], attributeValues: [String: String]) -> String {
        guard !attributes.isEmpty else { return "" }

        var title = joinList(attributes)
        if let creditedAs = attributeValues["credited-as"], !creditedAs.isEmpty, !title.contains("[\(creditedAs)]") {
            title += " [\(creditedAs)]"
        }
        return title
    }

    private static func relationValue(from relation: MusicBrainzRelationDTO) -> String {
        relationValue(
            artist: relation.artist,
            label: relation.label,
            place: relation.place,
            recording: relation.recording,
            release: relation.release,
            releaseGroup: relation.releaseGroup,
            series: relation.series,
            work: relation.work,
            url: relation.url,
            targetCredit: relation.targetCredit,
            sourceCredit: relation.sourceCredit,
            attributeValues: relation.attributeValues,
            begin: relation.begin,
            end: relation.end
        )
    }

    private static func relationValue(from relation: MusicBrainzNestedRelationDTO) -> String {
        relationValue(
            artist: relation.artist,
            label: relation.label,
            place: relation.place,
            recording: relation.recording,
            release: relation.release,
            releaseGroup: relation.releaseGroup,
            series: relation.series,
            work: nil,
            url: relation.url,
            targetCredit: relation.targetCredit,
            sourceCredit: relation.sourceCredit,
            attributeValues: relation.attributeValues,
            begin: relation.begin,
            end: relation.end
        )
    }

    private static func relationValue(
        artist: MusicBrainzArtistDTO?,
        label: MusicBrainzLabelDTO?,
        place: MusicBrainzPlaceDTO?,
        recording: MusicBrainzRelatedRecordingDTO?,
        release: MusicBrainzReleaseDTO?,
        releaseGroup: MusicBrainzReleaseGroupLookupDTO?,
        series: MusicBrainzSeriesDTO?,
        work: MusicBrainzWorkDTO?,
        url: MusicBrainzURLDTO?,
        targetCredit: String,
        sourceCredit: String,
        attributeValues: [String: String],
        begin: String,
        end: String
    ) -> String {
        var base = ""

        if let artist {
            base = creditedName(
                credit: targetCredit.isEmpty ? sourceCredit : targetCredit,
                fallback: artist.name ?? "",
                disambiguation: artist.disambiguation
            )
        } else if let label {
            base = appendDisambiguation(to: label.name, disambiguation: label.disambiguation)
        } else if let place {
            base = appendDisambiguation(to: place.name, disambiguation: place.disambiguation)
        } else if let recording {
            var recordingTitle = recording.title
            let artistCredit = joinedArtistCredit(recording.artistCredit)
            if !artistCredit.isEmpty {
                recordingTitle += " by \(artistCredit)"
            }
            base = appendDisambiguation(to: recordingTitle, disambiguation: recording.disambiguation)
        } else if let release, !release.title.isEmpty {
            base = release.title
        } else if let releaseGroup, !releaseGroup.title.isEmpty {
            base = releaseGroup.title
        } else if let series {
            base = appendDisambiguation(to: series.name, disambiguation: series.disambiguation)
        } else if let work {
            base = appendDisambiguation(to: work.title, disambiguation: work.disambiguation)
        } else if let url, !url.resource.isEmpty {
            base = url.resource
        }

        guard !base.isEmpty else { return "" }

        var extras: [String] = []
        for key in attributeValues.keys.sorted() {
            let value = attributeValues[key] ?? ""
            guard !value.isEmpty, key != "credited-as" else { continue }
            extras.append("\(key): \(value)")
        }

        if let dateText = relationDateText(begin: begin, end: end) {
            extras.append(dateText)
        }

        if !extras.isEmpty {
            base += " (" + extras.joined(separator: "; ") + ")"
        }

        return base
    }

    private static func relationDateText(begin: String, end: String) -> String? {
        if !begin.isEmpty && begin == end {
            return "in \(begin)"
        }

        if !begin.isEmpty && end.isEmpty {
            return "from \(begin)"
        }

        if begin.isEmpty && !end.isEmpty {
            return "until \(end)"
        }

        if !begin.isEmpty && !end.isEmpty {
            return "\(begin) to \(end)"
        }

        return nil
    }

    private static func creditedName(credit: String, fallback: String, disambiguation: String) -> String {
        let name = credit.isEmpty ? fallback : credit
        return appendDisambiguation(to: name, disambiguation: disambiguation)
    }

    private static func appendDisambiguation(to value: String, disambiguation: String) -> String {
        guard !value.isEmpty else { return "" }
        guard !disambiguation.isEmpty else { return value }
        return "\(value) (\(disambiguation))"
    }

    private static func joinedArtistCredit(_ credits: [MusicBrainzArtistCreditDTO]) -> String {
        credits
            .map { credit in
                let baseName = credit.name ?? credit.artist?.name ?? ""
                return baseName + credit.joinPhrase
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func joinList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            let prefix = values.dropLast().joined(separator: ", ")
            return "\(prefix) and \(values.last ?? "")"
        }
    }
}
