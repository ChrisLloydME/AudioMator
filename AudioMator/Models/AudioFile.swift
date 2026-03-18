//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
// import SFBAudioEngine
import AVFoundation
import CoreMedia
import AppKit

struct AudioFile: Identifiable {
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
        if let durationTime = try? await asset.load(.duration) {
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

        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
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

        let metadataItems = (try? await asset.load(.commonMetadata)) ?? []
        let commonArtwork = AVMetadataItem.metadataItems(
            from: metadataItems,
            withKey: AVMetadataKey.commonKeyArtwork,
            keySpace: .common
        )

        if let item = commonArtwork.first {
            if let data = try? await item.load(.dataValue) {
                self.artwork = NSImage(data: data)
            } else if let value = try? await item.load(.value),
                      let data = value as? Data {
                self.artwork = NSImage(data: data)
            } else if let data = tag.artworkData {
                self.artwork = NSImage(data: data)
            } else {
                self.artwork = nil
            }
        } else if let data = tag.artworkData {
            self.artwork = NSImage(data: data)
        } else {
            self.artwork = nil
        }
    }
}
