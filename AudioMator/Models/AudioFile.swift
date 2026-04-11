//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import Combine
// import SFBAudioEngine
import AVFoundation
import CoreMedia
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
    let musicBrainzArtistID: String
    let musicBrainzAlbumID: String
    let musicBrainzTrackID: String
    let musicBrainzReleaseGroupID: String
    let publisher: String
    let copyright: String
    let credits: String
    let isExplicit: Bool

    // MARK: – Technical
    let duration: Double
    let bitrate: Int
    let sampleRate: Double
    let channels: Int
    let format: String

    // MARK: – Artwork
    let artwork: NSImage?
    let artworkFingerprint: Int?

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
        hasher.combine(publisher)
        hasher.combine(copyright)
        hasher.combine(credits)
        hasher.combine(isExplicit)
        hasher.combine(duration)
        hasher.combine(bitrate)
        hasher.combine(sampleRate)
        hasher.combine(channels)
        hasher.combine(format)
        return hasher.finalize()
    }

    init(
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
        musicBrainzArtistID: String,
        musicBrainzAlbumID: String,
        musicBrainzTrackID: String,
        musicBrainzReleaseGroupID: String,
        publisher: String,
        copyright: String,
        credits: String,
        isExplicit: Bool,
        duration: Double,
        bitrate: Int,
        sampleRate: Double,
        channels: Int,
        format: String,
        artwork: NSImage?,
        artworkFingerprint: Int?
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
        self.musicBrainzArtistID = musicBrainzArtistID
        self.musicBrainzAlbumID = musicBrainzAlbumID
        self.musicBrainzTrackID = musicBrainzTrackID
        self.musicBrainzReleaseGroupID = musicBrainzReleaseGroupID
        self.publisher = publisher
        self.copyright = copyright
        self.credits = credits
        self.isExplicit = isExplicit
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.format = format
        self.artwork = artwork
        self.artworkFingerprint = artworkFingerprint
    }

    func withUpdatedURL(_ url: URL) -> AudioFile {
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
            musicBrainzArtistID: musicBrainzArtistID,
            musicBrainzAlbumID: musicBrainzAlbumID,
            musicBrainzTrackID: musicBrainzTrackID,
            musicBrainzReleaseGroupID: musicBrainzReleaseGroupID,
            publisher: publisher,
            copyright: copyright,
            credits: credits,
            isExplicit: isExplicit,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            artwork: artwork,
            artworkFingerprint: artworkFingerprint
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
            musicBrainzArtistID: musicBrainzArtistID,
            musicBrainzAlbumID: musicBrainzAlbumID,
            musicBrainzTrackID: musicBrainzTrackID,
            musicBrainzReleaseGroupID: musicBrainzReleaseGroupID,
            publisher: publisher,
            copyright: copyright,
            credits: credits,
            isExplicit: isExplicit,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            format: format,
            artwork: artwork,
            artworkFingerprint: artworkFingerprint
        )
    }

    private static func artworkFingerprint(for data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)

        if data.count <= 128 {
            hasher.combine(data)
        } else {
            hasher.combine(data.prefix(64))
            hasher.combine(data.suffix(64))
        }

        return hasher.finalize()
    }

    private static func parseNumberText(_ rawText: String) -> (number: Int, total: Int) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }

        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let number = parts.first.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let total = parts.count > 1
            ? Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            : 0

        return (max(0, number), max(0, total))
    }

    // Shared helper for reading metadata values.
    private static func normalizedNumberText(
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

    private static func readMetadata(from metadata: [AVMetadataItem],
                                     commonKeys: [AVMetadataKey],
                                     id3Keys: [String] = [],
                                     itunesKeys: [String] = []) async -> String {

        // 1. Common metadata
        for key in commonKeys {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key,
                keySpace: .common
            )
            for item in items {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value
                }
            }
        }

        // 2. ID3 metadata
        for key in id3Keys {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key as (NSCopying & NSSecureCoding),
                keySpace: .id3
            )
            for item in items {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value
                }
            }
        }

        // 3. iTunes metadata
        for key in itunesKeys {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key as (NSCopying & NSSecureCoding),
                keySpace: .iTunes
            )
            for item in items {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value
                }
            }
        }

        return ""
    }

    private static func readArtworkData(from metadata: [AVMetadataItem]) async -> Data? {
        let commonArtwork = AVMetadataItem.metadataItems(
            from: metadata,
            withKey: AVMetadataKey.commonKeyArtwork,
            keySpace: .common
        )

        guard let item = commonArtwork.first else { return nil }

        if let data = try? await item.load(.dataValue) {
            return data
        }

        if let value = try? await item.load(.value),
           let data = value as? Data {
            return data
        }

        return nil
    }

    init(url: URL, id: UUID = UUID()) async throws {
        self.id = id
        self.url = url

        // MARK: – Basic tags via TagLib
        //
        // Fall back to `BasicMetadata.empty` when TagLib parsing fails to avoid repeated optional handling.
        let tag = TagLibMetadataManager.readMetadata(from: url) ?? .empty

        self.title       = tag.title
        self.artist      = tag.artist
        self.album       = tag.album
        self.composer    = tag.composer
        self.genre       = tag.genre
        self.comment     = tag.comment
        self.track       = tag.track
        self.trackTotal  = tag.trackTotal
        self.disc        = tag.disc
        self.discTotal   = tag.discTotal
        self.trackNumberText = AudioFile.normalizedNumberText(
            rawText: tag.trackNumberText,
            number: tag.track,
            total: tag.trackTotal
        )
        self.discNumberText = AudioFile.normalizedNumberText(
            rawText: tag.discNumberText,
            number: tag.disc,
            total: tag.discTotal
        )

        // Treat Year and Release Date as separate fields:
        // - `year`: plain year provided by TagLib, if available
        // - `releaseDate`: full release date string provided by TagLib, if available
        self.year        = tag.year
        self.albumArtist = tag.albumArtist
        self.releaseDate = tag.releaseDate
        self.isrc        = tag.isrc
        self.barcode     = tag.barcode
        self.itunesAlbumID = tag.itunesAlbumID
        self.musicBrainzArtistID = tag.musicBrainzArtistID
        self.musicBrainzAlbumID = tag.musicBrainzAlbumID
        self.musicBrainzTrackID = tag.musicBrainzTrackID
        self.musicBrainzReleaseGroupID = tag.musicBrainzReleaseGroupID
        self.isExplicit  = tag.isExplicit

        let asset = AVURLAsset(url: url)

        // MARK: – Publisher / Copyright / Credits via AVFoundation (best effort)

        let allMetadataItems = (try? await asset.load(.metadata)) ?? []

        let publisherFromAV = await AudioFile.readMetadata(
            from: allMetadataItems,
            commonKeys: [.commonKeyPublisher],
            id3Keys: ["TPUB"]
        )
        self.publisher = publisherFromAV.isEmpty ? tag.publisher : publisherFromAV

        let copyrightFromAV = await AudioFile.readMetadata(
            from: allMetadataItems,
            commonKeys: [.commonKeyCopyrights],
            id3Keys: ["TCOP"]
        )
        self.copyright = copyrightFromAV.isEmpty ? tag.copyright : copyrightFromAV

        self.credits = await AudioFile.readMetadata(
            from: allMetadataItems,
            commonKeys: [],
            id3Keys: ["TEXT"]
        )

        // MARK: – Technical info with TagLib fallback

        var durationSeconds = tag.duration
        if durationSeconds <= 0,
           let durationTime = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(durationTime)
            if seconds.isFinite && seconds >= 0 {
                durationSeconds = seconds
            }
        }
        self.duration = durationSeconds

        var bitrateKbps = tag.bitrate
        var sampleRateHz = tag.sampleRate
        var channelsCount = tag.channels
        var formatName = tag.format

        let needsAudioTrackFallback =
            bitrateKbps <= 0 ||
            sampleRateHz <= 0 ||
            channelsCount <= 0

        if needsAudioTrackFallback,
           let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let track = audioTracks.first {
            if let estimatedRate = try? await track.load(.estimatedDataRate) {
                let avBitrate = Int(estimatedRate / 1000)
                if avBitrate > 0 {
                    bitrateKbps = avBitrate
                }
            }

            if let descriptions = try? await track.load(.formatDescriptions),
               let formatDesc = descriptions.first,
               let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {

                let asbd = asbdPtr.pointee
                if asbd.mSampleRate > 0 {
                    sampleRateHz = asbd.mSampleRate
                }
                if asbd.mChannelsPerFrame > 0 {
                    channelsCount = Int(asbd.mChannelsPerFrame)
                }

                switch asbd.mFormatID {
                case kAudioFormatMPEGLayer3:
                    formatName = "MP3"
                case kAudioFormatMPEG4AAC:
                    formatName = "AAC"
                default:
                    break
                }
            }
        }

        self.bitrate = bitrateKbps
        self.sampleRate = sampleRateHz
        self.channels = channelsCount
        self.format = formatName.isEmpty ? url.pathExtension.uppercased() : formatName

        // MARK: – Artwork with TagLib fallback

        let artworkData = await AudioFile.readArtworkData(from: allMetadataItems) ?? tag.artworkData
        if let artworkData {
            self.artwork = NSImage(data: artworkData)
            self.artworkFingerprint = AudioFile.artworkFingerprint(for: artworkData)
        } else {
            self.artwork = nil
            self.artworkFingerprint = nil
        }
    }
}
