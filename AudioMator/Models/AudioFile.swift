//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import SFBAudioEngine
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

    // MARK: – Technical
    let duration: Double
    let bitrate: Int
    let sampleRate: Double
    let channels: Int
    let format: String

    // MARK: – Artwork
    let artwork: NSImage?

    init(url: URL) throws {
        self.url = url

        // ⭐ 使用正确的初始化方法，自动读取 metadata
        let file = try SFBAudioEngine.AudioFile(readingPropertiesAndMetadataFrom: url)
        let meta = file.metadata

        self.title = meta.title ?? ""
        self.artist = meta.artist ?? ""
        self.album = meta.albumTitle ?? ""
        self.composer = meta.composer ?? ""
        self.genre = meta.genre ?? ""
        self.comment = meta.comment ?? ""

        self.track = meta.trackNumber ?? 0
        self.trackTotal = meta.trackTotal ?? 0
        self.disc = meta.discNumber ?? 0
        self.discTotal = meta.discTotal ?? 0

        self.year = meta.releaseDate ?? ""

        // MARK: – Technical info via AVFoundation
        let asset = AVURLAsset(url: url)

        var durationSeconds: Double = 0
        var bitrateKbps: Int = 0
        var sampleRateHz: Double = 0
        var channelsCount: Int = 0
        var formatName: String = ""

        // Duration
        durationSeconds = CMTimeGetSeconds(asset.duration)

        // Use first audio track for technical details
        if let track = asset.tracks(withMediaType: .audio).first {
            // estimatedDataRate is in bits per second
            bitrateKbps = Int(track.estimatedDataRate / 1000)

            if let formatDescAny = track.formatDescriptions.first,
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

        self.duration = durationSeconds
        self.bitrate = bitrateKbps
        self.sampleRate = sampleRateHz
        self.channels = channelsCount
        self.format = formatName

        // MARK: – Artwork via AVFoundation
        var artworkImage: NSImage? = nil

        let commonArtwork = AVMetadataItem.metadataItems(
            from: asset.commonMetadata,
            withKey: AVMetadataKey.commonKeyArtwork,
            keySpace: .common
        )

        if let item = commonArtwork.first {
            if let data = item.dataValue {
                artworkImage = NSImage(data: data)
            } else if let value = item.value as? Data {
                artworkImage = NSImage(data: value)
            }
        }

        self.artwork = artworkImage
    }
}
