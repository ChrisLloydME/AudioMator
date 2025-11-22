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

    init(url: URL) {
        self.url = url

        let asset = AVURLAsset(url: url)
        let metadata = asset.metadata + asset.commonMetadata

        func firstString(_ identifiers: [AVMetadataIdentifier]) -> String? {
            for id in identifiers {
                if let value = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first?.stringValue {
                    return value
                }
            }
            return nil
        }

        func firstNumber(_ identifiers: [AVMetadataIdentifier]) -> Int? {
            for id in identifiers {
                if let value = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first?.numberValue {
                    return value.intValue
                }
            }
            return nil
        }

        self.title = firstString([.commonIdentifierTitle])
        self.artist = firstString([.commonIdentifierArtist])
        self.album = firstString([.commonIdentifierAlbumName])
        self.composer = firstString([
            .id3MetadataComposer,
            .iTunesMetadataComposer,
            .quickTimeMetadataAuthor
        ])
        self.genre = firstString([
            .id3MetadataContentType,
            .iTunesMetadataPredefinedGenre,
            .iTunesMetadataUserGenre
        ])
        self.comments = firstString([
            .commonIdentifierDescription,
            .id3MetadataComments,
            .quickTimeMetadataInformation
        ])

        if let yearString = firstString([
            .id3MetadataYear,
            .iTunesMetadataReleaseDate
        ]) {
            self.year = Int(yearString.prefix(4))
        } else {
            self.year = nil
        }

        self.trackNumber = firstNumber([.iTunesMetadataTrackNumber])
        self.discNumber = firstNumber([.iTunesMetadataDiscNumber])

        if let artItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
           let data = artItem.dataValue,
           let image = NSImage(data: data) {
            self.artwork = image
        } else {
            self.artwork = nil
        }

        if let track = asset.tracks(withMediaType: .audio).first {
            let seconds = CMTimeGetSeconds(track.timeRange.duration)
            self.duration = seconds.isFinite ? seconds : nil

            let estimatedRate = track.estimatedDataRate
            self.bitrate = estimatedRate > 0 ? Int(estimatedRate / 1000) : nil

            if let rawFormat = track.formatDescriptions.first {
                let format = rawFormat as! CMAudioFormatDescription
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    self.sampleRate = asbd.mSampleRate
                    self.channels = Int(asbd.mChannelsPerFrame)
                } else {
                    self.sampleRate = nil
                    self.channels = nil
                }
            } else {
                self.sampleRate = nil
                self.channels = nil
            }
        } else {
            let seconds = CMTimeGetSeconds(asset.duration)
            self.duration = seconds.isFinite ? seconds : nil
            self.bitrate = nil
            self.sampleRate = nil
            self.channels = nil
        }

        let ext = url.pathExtension
        self.fileFormat = ext.isEmpty ? nil : ext.uppercased()

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            self.fileSize = values.fileSize
        } else {
            self.fileSize = nil
        }
    }
}
