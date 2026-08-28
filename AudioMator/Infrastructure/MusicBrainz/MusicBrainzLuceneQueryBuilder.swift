import Foundation

nonisolated enum MusicBrainzLuceneQueryBuilder {
    static func combinedSearchQuery(
        from queries: [String],
        maximumClauseCount: Int
    ) -> String? {
        MusicBrainzProviderLuceneQueryBuilder.combinedSearchQuery(
            from: queries,
            maximumClauseCount: maximumClauseCount
        )
    }

    static func recordingSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        MusicBrainzProviderLuceneQueryBuilder.recordingSearchQueries(from: query.providerSearchQuery)
    }

    static func releaseSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        MusicBrainzProviderLuceneQueryBuilder.releaseSearchQueries(from: query.providerSearchQuery)
    }

    static func fileSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        MusicBrainzProviderLuceneQueryBuilder.fileSearchQueries(from: query.providerSearchQuery)
    }

    static func fileClusterStrongReleaseSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        MusicBrainzProviderLuceneQueryBuilder.fileClusterStrongReleaseSearchQueries(from: query.providerSearchQuery)
    }

    static func fileClusterBroadReleaseSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        MusicBrainzProviderLuceneQueryBuilder.fileClusterBroadReleaseSearchQueries(from: query.providerSearchQuery)
    }

    static func fileStrongSearchQueries(from query: MusicBrainzSearchQuery) -> [String] {
        MusicBrainzProviderLuceneQueryBuilder.fileStrongSearchQueries(from: query.providerSearchQuery)
    }
}

private extension MusicBrainzSearchQuery {
    nonisolated var providerSearchQuery: MusicBrainzProviderSearchQuery {
        MusicBrainzProviderSearchQuery(
            mode: providerMode,
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
            albumID: musicBrainzAlbumID,
            trackID: musicBrainzTrackID,
            fileInputs: fileInputs.map(\.providerFileInput),
            link: link,
            releaseFilters: releaseFilters.providerReleaseFilters
        )
    }

    nonisolated var providerMode: MusicBrainzProviderSearchMode {
        switch mode {
        case .track:
            return .track
        case .album:
            return .album
        case .file:
            return .file
        case .link:
            return .link
        }
    }
}

private extension MusicBrainzFileSearchInput {
    nonisolated var providerFileInput: MusicBrainzProviderFileInput {
        MusicBrainzProviderFileInput(
            id: id,
            displayTitle: displayTitle,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            trackNumber: trackNumber,
            discNumber: discNumber,
            trackTotal: trackTotal,
            durationMilliseconds: durationMilliseconds,
            releaseDate: releaseDate,
            isrc: isrc,
            barcode: barcode,
            albumID: musicBrainzAlbumID,
            trackID: musicBrainzTrackID
        )
    }
}

private extension MusicBrainzReleaseFilters {
    nonisolated var providerReleaseFilters: MusicBrainzProviderReleaseFilters {
        MusicBrainzProviderReleaseFilters(
            mediaFormats: Set(mediaFormats.compactMap { MusicBrainzProviderMediaFormat(rawValue: $0.rawValue) }),
            releaseYear: releaseYear,
            countries: countries,
            statuses: Set(statuses.compactMap { MusicBrainzProviderReleaseStatus(rawValue: $0.rawValue) })
        )
    }
}
