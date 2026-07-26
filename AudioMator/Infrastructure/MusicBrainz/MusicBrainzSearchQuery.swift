import Foundation

nonisolated struct MusicBrainzSearchQuery: Equatable, Sendable {
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
