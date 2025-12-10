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
    let id = UUID()

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
    let year: String
    let albumArtist: String
    let releaseDate: String    // ✅ 用 releaseDate，替代原来的 releasingTime
    let publisher: String
    let copyright: String
    let credits: String

    // MARK: – Technical
    let duration: Double
    let bitrate: Int
    let sampleRate: Double
    let channels: Int
    let format: String

    // MARK: – Artwork
    let artwork: NSImage?

    // 统一的元数据读取帮助函数
    private static func readMetadata(from asset: AVAsset,
                                     commonKeys: [AVMetadataKey],
                                     id3Keys: [String] = [],
                                     itunesKeys: [String] = []) -> String {
        let metadata = asset.metadata

        // 1. Common metadata
        for key in commonKeys {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key,
                keySpace: .common
            )
            if let value = items.first?.stringValue, !value.isEmpty {
                return value
            }
        }

        // 2. ID3 metadata
        for key in id3Keys {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key as (NSCopying & NSSecureCoding),
                keySpace: .id3
            )
            if let value = items.first?.stringValue, !value.isEmpty {
                return value
            }
        }

        // 3. iTunes metadata
        for key in itunesKeys {
            let items = AVMetadataItem.metadataItems(
                from: metadata,
                withKey: key as (NSCopying & NSSecureCoding),
                keySpace: .iTunes
            )
            if let value = items.first?.stringValue, !value.isEmpty {
                return value
            }
        }

        return ""
    }

    init(url: URL) async throws {
        self.url = url

        // MARK: – Basic tags via TagLib
        //
        // TagLib 解析失败时，用 BasicMetadata.empty 兜底，避免到处写 if let
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
        self.year        = tag.year
        self.albumArtist = tag.albumArtist
        // 目前 TagLib 这层没有单独的发布日期字段，就先用 year 填充；
        // 之后如果你在 TagLibMetadataExtractor/Manager 里加了 releaseDate 字段，再把这里改成 tag.releaseDate
        self.releaseDate = tag.year

        // MARK: – Publisher / Copyright / Credits via AVFoundation

        let asset = AVURLAsset(url: url)

        self.publisher = AudioFile.readMetadata(
            from: asset,
            commonKeys: [.commonKeyPublisher],
            id3Keys: ["TPUB"]
        )

        self.copyright = AudioFile.readMetadata(
            from: asset,
            commonKeys: [.commonKeyCopyrights],
            id3Keys: ["TCOP"]
        )

        self.credits = AudioFile.readMetadata(
            from: asset,
            commonKeys: [],
            id3Keys: ["TEXT"]
        )

        // MARK: – Technical info via AVFoundation

        let durationTime = try await asset.load(.duration)
        self.duration = CMTimeGetSeconds(durationTime)

        var bitrateKbps = 0
        var sampleRateHz = 0.0
        var channelsCount = 0
        var formatName = ""

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let track = audioTracks.first {
            let estimatedRate = try await track.load(.estimatedDataRate)
            bitrateKbps = Int(estimatedRate / 1000)

            let descriptions = try await track.load(.formatDescriptions)
            if let formatDescAny = descriptions.first,
               CFGetTypeID(formatDescAny as CFTypeRef) == CMFormatDescriptionGetTypeID(),
               let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescAny as! CMAudioFormatDescription) {

                let asbd = asbdPtr.pointee
                sampleRateHz = asbd.mSampleRate
                channelsCount = Int(asbd.mChannelsPerFrame)

                switch asbd.mFormatID {
                case kAudioFormatMPEGLayer3:
                    formatName = "MP3"
                case kAudioFormatMPEG4AAC:
                    formatName = "AAC"
                default:
                    formatName = "Audio"
                }
            }
        }

        self.bitrate    = bitrateKbps
        self.sampleRate = sampleRateHz
        self.channels   = channelsCount
        self.format     = formatName

        // MARK: – Artwork via AVFoundation

        let metadataItems = try await asset.load(.commonMetadata)
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
            } else {
                self.artwork = nil
            }
        } else {
            self.artwork = nil
        }
    }
}
