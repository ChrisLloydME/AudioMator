//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation

// Loaded off the main actor and then treated as an immutable snapshot in the UI.
struct AudioFile: Identifiable, @unchecked Sendable {
    let id: UUID

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
    var isExplicit: Bool { contentAdvisory?.isExplicit ?? false }

    // MARK: – Technical
    let duration: Double
    let bitrate: Int
    let sampleRate: Double
    let channels: Int
    let format: String

    // MARK: – Artwork
    let artwork: PlatformImage?
    let artworkFingerprint: Int?
    let fileFingerprint: AudioFileFingerprint?

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
        hasher.combine(duration)
        hasher.combine(bitrate)
        hasher.combine(sampleRate)
        hasher.combine(channels)
        hasher.combine(format)
        hasher.combine(fileFingerprint)
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
        artwork: PlatformImage?,
        artworkFingerprint: Int?,
        fileFingerprint: AudioFileFingerprint? = nil
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
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
        self.artwork = artwork
        self.artworkFingerprint = artworkFingerprint
        self.fileFingerprint = fileFingerprint
    }

    nonisolated func withUpdatedURL(_ url: URL) -> AudioFile {
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
            artwork: artwork,
            artworkFingerprint: artworkFingerprint,
            fileFingerprint: try? AudioFileFingerprint.capture(at: url)
        )
    }

    func withUpdatedTrackNumberText(_ rawText: String) -> AudioFile {
        let normalizedRawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = AudioFile.parseNumberText(normalizedRawText)

        return AudioFile(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            composer: composer,
            genre: genre,
            comment: comment,
            track: parsed.number,
            trackTotal: parsed.total,
            disc: disc,
            discTotal: discTotal,
            trackNumberText: AudioFile.normalizedNumberText(
                rawText: normalizedRawText,
                number: parsed.number,
                total: parsed.total
            ),
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
            artwork: artwork,
            artworkFingerprint: artworkFingerprint,
            fileFingerprint: try? AudioFileFingerprint.capture(at: url)
        )
    }

    nonisolated private static func parseNumberText(_ rawText: String) -> (number: Int, total: Int) {
        AudioTagNumberText.parsedPair(from: rawText)
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
