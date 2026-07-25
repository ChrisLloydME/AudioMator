import AVFoundation
import CoreMedia
import Foundation
import TagLibAudioMetadata
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension AudioFile {
    nonisolated private static func artworkFingerprint(for data: Data) -> Int {
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

    nonisolated private static func readMetadata(from metadata: [AVMetadataItem],
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

    nonisolated private static func readArtworkData(from metadata: [AVMetadataItem]) async -> Data? {
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

    nonisolated private static func contentAdvisory(from url: URL, fallbackExplicit: Bool) -> ContentAdvisory? {
        guard let dump = try? TagLibMetadataManager.rawMetadataResult(from: url) else {
            return fallbackExplicit ? .explicit : nil
        }

        for property in dump.properties {
            let key = property.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let values = property.values.isEmpty ? [property.value] : property.values
            for value in values {
                if let advisory = contentAdvisory(rawValue: value, key: key) {
                    return advisory
                }
            }
        }

        for frame in dump.id3v2Frames {
            let frameID = frame.frameID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let description = frame.description?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            guard frameID == "TXXX", description == "ITUNESADVISORY" || description == "EXPLICIT" else { continue }
            if let advisory = contentAdvisory(rawValue: frame.value, key: "ITUNESADVISORY") {
                return advisory
            }
        }

        return fallbackExplicit ? .explicit : nil
    }

    nonisolated private static func contentAdvisory(rawValue: String, key: String) -> ContentAdvisory? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let advisoryKey: String?
        switch normalizedKey {
        case "ITUNESADVISORY", "ADVISORY", "EXPLICITCONTENT", "EXPLICIT", "RTNG":
            advisoryKey = normalizedKey
        case let key where key.hasSuffix(":ITUNESADVISORY") || key.hasSuffix(".ITUNESADVISORY"):
            advisoryKey = "ITUNESADVISORY"
        default:
            advisoryKey = nil
        }

        guard let advisoryKey else { return nil }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if advisoryKey == "RTNG" {
            switch normalized {
            case "0", "none", "not explicit", "notexplicit":
                return .notExplicit
            case "2", "clean":
                return .clean
            case "1", "explicit", "true", "yes":
                return .explicit
            default:
                return nil
            }
        }

        switch normalized {
        case "0", "none", "not explicit", "notexplicit", "false", "no":
            return .notExplicit
        case "1", "explicit", "true", "yes":
            return .explicit
        case "2", "clean":
            return .clean
        default:
            return nil
        }
    }

    nonisolated init(url: URL, id: UUID = UUID()) async throws {
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
        self.itunesArtistID = tag.itunesArtistID
        self.itunesCatalogID = tag.itunesCatalogID
        self.musicBrainzArtistID = tag.musicBrainzArtistID
        self.musicBrainzAlbumID = tag.musicBrainzAlbumID
        self.musicBrainzTrackID = tag.musicBrainzTrackID
        self.musicBrainzReleaseGroupID = tag.musicBrainzReleaseGroupID
        self.lyricist = tag.lyricist
        self.remixer = tag.remixer
        self.producer = tag.producer
        self.engineer = tag.engineer
        self.language = tag.language
        self.mediaType = tag.mediaType
        self.releaseType = tag.releaseType
        self.catalogNumber = tag.catalogNumber
        self.releaseCountry = tag.releaseCountry
        self.contentAdvisory = AudioFile.contentAdvisory(from: url, fallbackExplicit: tag.isExplicit)

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
            self.artwork = PlatformImage(data: artworkData)
            self.artworkFingerprint = AudioFile.artworkFingerprint(for: artworkData)
        } else {
            self.artwork = nil
            self.artworkFingerprint = nil
        }

        self.fileFingerprint = try? AudioFileFingerprint.capture(at: url)
    }
}
