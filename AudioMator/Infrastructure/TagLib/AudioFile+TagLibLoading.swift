import AVFoundation
import CoreMedia
import Foundation
import TagLibAudioMetadata

extension AudioFile {
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

    nonisolated init(url: URL, id: UUID = UUID()) async throws {
        self.id = id
        self.url = url

        // MARK: – Basic tags via TagLib
        //
        // A failed source read must remain a load failure so import and rescan recovery can react.
        let snapshot = try TagLibMetadataManager.readSnapshot(from: url)
        let tag = snapshot.basic
        self.metadataFileVersion = snapshot.fileVersion
        self.requiresMetadataRefreshBeforeWriting = false

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
        self.contentAdvisory = switch tag.explicitAdvisory {
        case .unspecified: nil
        case .notExplicit: .notExplicit
        case .clean: .clean
        case .explicit: .explicit
        }

        let asset = AVURLAsset(url: url)

        // MARK: – Editable tags remain TagLib-authoritative; credits are display-only AVFoundation data.

        let allMetadataItems = (try? await asset.load(.metadata)) ?? []

        self.publisher = tag.publisher
        self.copyright = tag.copyright

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

        // MARK: – Artwork via the same authoritative editable metadata source

        let artworkData = tag.artworkData
        if let artworkData {
            self.artworkData = artworkData
        } else {
            self.artworkData = nil
        }

        self.fileFingerprint = try AudioFileFingerprint.capture(at: url)
    }
}
