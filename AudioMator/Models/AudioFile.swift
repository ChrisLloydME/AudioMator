//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import AVFoundation
import CoreMedia
import AppKit

struct AudioFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    let title: String?
    let artist: String?
    let album: String?
    let composer: String?
    let genre: String?
    let comments: String?
    let year: Int?
    let trackNumber: Int?
    let discNumber: Int?

    let duration: Double?
    let bitrate: Int?
    let sampleRate: Double?
    let channels: Int?
    let fileFormat: String?
    let fileSize: Int?

    let artwork: NSImage?

    static func load(from url: URL) async throws -> AudioFile {
        let asset = AVURLAsset(url: url)

        let common = try await asset.load(.commonMetadata)
        let base = try await asset.load(.metadata)
        let id3 = try await asset.loadMetadata(for: .id3Metadata)
        let itunes = try await asset.loadMetadata(for: .iTunesMetadata)
        let quick = try await asset.loadMetadata(for: .quickTimeMetadata)

        let metadata = common + base + id3 + itunes + quick

        func firstString(_ ids: [AVMetadataIdentifier]) async -> String? {
            for id in ids {
                let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id)
                if let item = items.first {
                    return try? await item.load(.stringValue)
                }
            }
            return nil
        }

        func firstNumber(_ ids: [AVMetadataIdentifier]) async -> Int? {
            for id in ids {
                let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id)
                if let item = items.first {
                    if let num = try? await item.load(.numberValue) {
                        return num.intValue
                    }
                }
            }
            return nil
        }

        let title = await firstString([.commonIdentifierTitle])
        let artist = await firstString([.commonIdentifierArtist])
        let album = await firstString([.commonIdentifierAlbumName])
        let composer = await firstString([
            .id3MetadataComposer,
            .iTunesMetadataComposer,
            .quickTimeMetadataAuthor
        ])
        let genre = await firstString([
            .id3MetadataContentType,
            .iTunesMetadataUserGenre,
            .iTunesMetadataPredefinedGenre,
            .quickTimeMetadataGenre
        ])
        let comments = await firstString([
            .commonIdentifierDescription,
            .id3MetadataComments,
            .quickTimeMetadataInformation
        ])

        var year: Int? = nil
        if let y = await firstString([.id3MetadataYear, .iTunesMetadataReleaseDate]) {
            year = Int(y.prefix(4))
        }

        let trackNumber = await firstNumber([.iTunesMetadataTrackNumber, .id3MetadataTrackNumber])
        let discNumber = await firstNumber([.iTunesMetadataDiscNumber, .id3MetadataPartOfASet])

        var artwork: NSImage? = nil
        if let artItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
           let data = try? await artItem.load(.dataValue) {
            artwork = NSImage(data: data)
        }

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        var duration: Double? = nil
        var bitrate: Int? = nil
        var sampleRate: Double? = nil
        var channels: Int? = nil

        if let t = tracks.first {
            let range = try await t.load(.timeRange)
            let seconds = CMTimeGetSeconds(range.duration)
            duration = seconds.isFinite ? seconds : nil

            let rate = try await t.load(.estimatedDataRate)
            bitrate = rate > 0 ? Int(rate / 1000) : nil

            let desc = try await t.load(.formatDescriptions)
            if let raw = desc.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(raw as! CMFormatDescription)?.pointee {
                sampleRate = asbd.mSampleRate
                channels = Int(asbd.mChannelsPerFrame)
            }
        }

        let ext = url.pathExtension
        let fileFormat = ext.isEmpty ? nil : ext.uppercased()

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize

        return AudioFile(
            url: url,
            title: title,
            artist: artist,
            album: album,
            composer: composer,
            genre: genre,
            comments: comments,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: duration,
            bitrate: bitrate,
            sampleRate: sampleRate,
            channels: channels,
            fileFormat: fileFormat,
            fileSize: size,
            artwork: artwork
        )
    }

    private init(
        url: URL,
        title: String?,
        artist: String?,
        album: String?,
        composer: String?,
        genre: String?,
        comments: String?,
        year: Int?,
        trackNumber: Int?,
        discNumber: Int?,
        duration: Double?,
        bitrate: Int?,
        sampleRate: Double?,
        channels: Int?,
        fileFormat: String?,
        fileSize: Int?,
        artwork: NSImage?
    ) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.composer = composer
        self.genre = genre
        self.comments = comments
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.fileFormat = fileFormat
        self.fileSize = fileSize
        self.artwork = artwork
    }
}
