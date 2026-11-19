//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import TagLibAudioMetadata

// Loaded off the main actor and then treated as an immutable snapshot in the UI.
struct AudioFile: Identifiable, Sendable {
    let id: UUID
    // A new token for each immutable load/transformation; copies retain it.
    let snapshotID = UUID()

    /// The single coherent observation that authorizes metadata writes for this
    /// snapshot. It is produced only by a validated full read; a display or move
    /// projection carries `nil`. Version is nonoptional, so "write authority
    /// without a revision" is unrepresentable.
    nonisolated struct Observation: Sendable {
        let fileID: UUID
        let url: URL
        let fingerprint: AudioFileFingerprint
        let version: MetadataFileVersion
        let conflictBaseline: MetadataConflictBaseline
    }

    // MARK: – Basic Tags
    let url: URL
    let title: String
    let artist: String
    let album: String
    let composer: String
    let genre: String
    let comment: String
    let track: Int
    let trackTotal: Int
    let disc: Int
    let discTotal: Int
    let trackNumberText: String
    let discNumberText: String
    let year: String
    let albumArtist: String
    let releaseDate: String
    let isrc: String
    let barcode: String
    let itunesAlbumID: String
    let itunesArtistID: String
    let itunesCatalogID: String
    let musicBrainzArtistID: String
    let musicBrainzAlbumID: String
    let musicBrainzTrackID: String
    let musicBrainzReleaseGroupID: String
    let publisher: String
    let copyright: String
    let credits: String
    let lyricist: String
    let remixer: String
    let producer: String
    let engineer: String
    let language: String
    let mediaType: String
    let releaseType: String
    let catalogNumber: String
    let releaseCountry: String
    let contentAdvisory: ContentAdvisory?

    // MARK: – Independent dates and container-exclusive semantics
    //
    // YEAR, DATE, RELEASEDATE and ORIGINALDATE are independent stored fields.
    // `year` is the complete stored YEAR text, never a four-character projection.
    let date: String
    let originalReleaseDate: String
    let advisoryRawValue: String?
    let contentGroup: String
    let grouping: String
    let work: String
    /// Typed MP4-exclusive values. Presence in the dictionary is significant:
    /// `.boolean(false)` and `.integer(0)` are present values, not absence.
    let containerValues: [MetadataFieldKey: ContainerFieldValue]
    // MARK: – Technical
    let duration: Double
    let bitrate: Int
    let sampleRate: Double
    let channels: Int
    let format: String

    // MARK: – Artwork
    let artworkData: Data?
    // The only write-authorizing value. Nil means this snapshot carries no
    // authority (display projection, failed readback, or recovery block).
    let observation: Observation?

    // A recovery block is separate from "no write authority": display-only and
    // preview projections have no authority but are not recovery-blocked. Move
    // and recovery projections set this flag; a successful coherent reload
    // produces a fresh observation with the flag false.
    let requiresMetadataRefreshBeforeWriting: Bool

    // Read-only projections retained for display, previews and conflict-aware
    // drafts. They cannot compose a new token pair with retained metadata.
    nonisolated var fileFingerprint: AudioFileFingerprint? { observation?.fingerprint }
    nonisolated var metadataFileVersion: MetadataFileVersion? { observation?.version }
    nonisolated var metadataConflictBaseline: MetadataConflictBaseline? { observation?.conflictBaseline }

    // Stable content fingerprint for middle-list row refresh decisions.
    var middleListContentFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(url.lastPathComponent)
        hasher.combine(title)
        hasher.combine(artist)
        hasher.combine(album)
        hasher.combine(albumArtist)
        hasher.combine(composer)
        hasher.combine(genre)
        hasher.combine(year)
        hasher.combine(track)
        hasher.combine(trackTotal)
        hasher.combine(disc)
        hasher.combine(discTotal)
        hasher.combine(trackNumberText)
        hasher.combine(discNumberText)
        hasher.combine(comment)
        hasher.combine(releaseDate)
        hasher.combine(itunesAlbumID)
        hasher.combine(itunesArtistID)
        hasher.combine(itunesCatalogID)
        hasher.combine(publisher)
        hasher.combine(copyright)
        hasher.combine(credits)
        hasher.combine(lyricist)
        hasher.combine(remixer)
        hasher.combine(producer)
        hasher.combine(engineer)
        hasher.combine(language)
        hasher.combine(mediaType)
        hasher.combine(releaseType)
        hasher.combine(catalogNumber)
        hasher.combine(releaseCountry)
        hasher.combine(contentAdvisory)
        hasher.combine(date)
        hasher.combine(originalReleaseDate)
        hasher.combine(advisoryRawValue)
        hasher.combine(contentGroup)
        hasher.combine(grouping)
        hasher.combine(work)
        hasher.combine(containerValues)
        hasher.combine(duration)
        hasher.combine(bitrate)
        hasher.combine(sampleRate)
        hasher.combine(channels)
        hasher.combine(format)
        hasher.combine(fileFingerprint)
        hasher.combine(requiresMetadataRefreshBeforeWriting)
        return hasher.finalize()
    }

    nonisolated init(
        id: UUID,
        url: URL,
        title: String,
        artist: String,
        album: String,
        composer: String,
        genre: String,
        comment: String,
        track: Int,
        trackTotal: Int,
        disc: Int,
        discTotal: Int,
        trackNumberText: String,
        discNumberText: String,
        year: String,
        albumArtist: String,
        releaseDate: String,
        isrc: String,
        barcode: String,
        itunesAlbumID: String,
        itunesArtistID: String,
        itunesCatalogID: String,
        musicBrainzArtistID: String,
        musicBrainzAlbumID: String,
        musicBrainzTrackID: String,
        musicBrainzReleaseGroupID: String,
        publisher: String,
        copyright: String,
        credits: String,
        lyricist: String,
        remixer: String,
        producer: String,
        engineer: String,
        language: String,
        mediaType: String,
        releaseType: String,
        catalogNumber: String,
        releaseCountry: String,
        contentAdvisory: ContentAdvisory?,
        duration: Double,
        bitrate: Int,
        sampleRate: Double,
        channels: Int,
        format: String,
        artworkData: Data?,
        date: String = "",
        originalReleaseDate: String = "",
        advisoryRawValue: String? = nil,
        contentGroup: String = "",
        grouping: String = "",
        work: String = "",
        containerValues: [MetadataFieldKey: ContainerFieldValue] = [:],
        observation: Observation? = nil,
        requiresMetadataRefreshBeforeWriting: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.composer = composer
        self.genre = genre
        self.comment = comment
        self.track = track
        self.trackTotal = trackTotal
        self.disc = disc
        self.discTotal = discTotal
        self.trackNumberText = trackNumberText
        self.discNumberText = discNumberText
        self.year = year
        self.albumArtist = albumArtist
        self.releaseDate = releaseDate
        self.isrc = isrc
        self.barcode = barcode
        self.itunesAlbumID = itunesAlbumID
        self.itunesArtistID = itunesArtistID
        self.itunesCatalogID = itunesCatalogID
        self.musicBrainzArtistID = musicBrainzArtistID
        self.musicBrainzAlbumID = musicBrainzAlbumID
        self.musicBrainzTrackID = musicBrainzTrackID
        self.musicBrainzReleaseGroupID = musicBrainzReleaseGroupID
        self.publisher = publisher
        self.copyright = copyright
        self.credits = credits
        self.lyricist = lyricist
        self.remixer = remixer
        self.producer = producer
        self.engineer = engineer
        self.language = language
        self.mediaType = mediaType
        self.releaseType = releaseType
        self.catalogNumber = catalogNumber
        self.releaseCountry = releaseCountry
        self.contentAdvisory = contentAdvisory
        self.date = date
        self.originalReleaseDate = originalReleaseDate
        self.advisoryRawValue = advisoryRawValue
        self.contentGroup = contentGroup
        self.grouping = grouping
        self.work = work
        self.containerValues = containerValues
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
        self.artworkData = artworkData
        self.observation = observation
        self.requiresMetadataRefreshBeforeWriting = requiresMetadataRefreshBeforeWriting
    }

    /// Display-only projection to a new URL. Always clears write authority, so a
    /// moved or recovery-projected snapshot can never authorize a metadata write.
    nonisolated func projectingDisplay(to url: URL) -> AudioFile {
        AudioFile(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            composer: composer,
            genre: genre,
            comment: comment,
            track: track,
            trackTotal: trackTotal,
            disc: disc,
            discTotal: discTotal,
            trackNumberText: trackNumberText,
            discNumberText: discNumberText,
            year: year,
            albumArtist: albumArtist,
            releaseDate: releaseDate,
            isrc: isrc,
            barcode: barcode,
            itunesAlbumID: itunesAlbumID,
            itunesArtistID: itunesArtistID,
            itunesCatalogID: itunesCatalogID,
            musicBrainzArtistID: musicBrainzArtistID,
            musicBrainzAlbumID: musicBrainzAlbumID,
            musicBrainzTrackID: musicBrainzTrackID,
            musicBrainzReleaseGroupID: musicBrainzReleaseGroupID,
            publisher: publisher,
            copyright: copyright,
            credits: credits,
            lyricist: lyricist,
            remixer: remixer,
            producer: producer,
            engineer: engineer,
            language: language,
            mediaType: mediaType,
            releaseType: releaseType,
            catalogNumber: catalogNumber,
            releaseCountry: releaseCountry,
            contentAdvisory: contentAdvisory,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            artworkData: artworkData,
            date: date,
            originalReleaseDate: originalReleaseDate,
            advisoryRawValue: advisoryRawValue,
            contentGroup: contentGroup,
            grouping: grouping,
            work: work,
            containerValues: containerValues,
            observation: nil,
            requiresMetadataRefreshBeforeWriting: true
        )
    }

    /// Display-only projection that keeps the URL. Used to apply a recovery
    /// decision without discarding the last known labels.
    nonisolated func projectingRecoveryState() -> AudioFile {
        projectingDisplay(to: url)
    }

    // Shared helper for reading metadata values.
    nonisolated static func normalizedNumberText(
        rawText: String,
        number: Int,
        total: Int
    ) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if trimmed.contains("/") || total == 0 {
                return trimmed
            }

            return "\(trimmed)/\(total)"
        }

        guard number > 0 else { return "" }
        return total > 0 ? "\(number)/\(total)" : "\(number)"
    }
}


extension AudioFile {
    /// The package exposes legacy combined ID3v2.3 date projections read-only.
    /// Do not reinterpret them as verified independent canonical date values.
    nonisolated var hasUnverifiedIndependentDateProjection: Bool {
        metadataConflictBaseline?.structured.id3v2MajorVersion == 3
    }
}
