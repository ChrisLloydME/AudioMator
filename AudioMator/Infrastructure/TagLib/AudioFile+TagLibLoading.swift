import AVFoundation
import CoreMedia
import Foundation
import TagLibAudioMetadata

extension AudioFile {
    /// Only ID3 TEXT contributes to the display-only Credits column. The full
    /// TagLib snapshot already tells us whether it exists in these containers.
    /// Retain AVFoundation fallback for formats whose ID3 frames are not exposed
    /// by the snapshot (including FLAC and ADTS).
    nonisolated static func needsAVFoundationCreditsRead(
        fileExtension: String, rawMetadata: RawMetadataDump
    ) -> Bool {        switch fileExtension.lowercased() {
        case "mp3", "mp2", "wav", "aiff", "aif", "tta":
            rawMetadata.id3v2Frames.contains { $0.frameID == "TEXT" }
        case "m4a", "mp4", "ogg", "oga", "opus", "spx":
            false
        default:
            true
        }
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

    nonisolated init(url: URL, id: UUID = UUID()) async throws {
        self.id = id
        self.url = url

        // MARK: – Basic tags via TagLib
        //
        // A failed source read must remain a load failure so import and rescan recovery can react.
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let snapshot = try TagLibMetadataManager.readSnapshot(from: url, includingAudioContent: true)
        let tag = snapshot.basic
        self.metadataConflictBaseline = MetadataConflictBaseline(snapshot)
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

        // Year, Date, Release Date and Original Release Date are independent.
        // `year` is the complete stored YEAR text and is never truncated.
        self.year        = tag.year
        self.date        = tag.date
        self.albumArtist = tag.albumArtist
        self.releaseDate = tag.releaseDate
        self.originalReleaseDate = tag.originalReleaseDate
        self.contentGroup = tag.contentGroup
        self.grouping = tag.grouping
        self.work = tag.work
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
        self.advisoryRawValue = tag.explicitAdvisoryRawValue
        self.containerValues = Self.containerValues(from: tag, atoms: snapshot.structured.mp4Atoms)

        let numberingInventory = try? TagLibMetadataManager.numberingInventory(at: url)
        if let numberingInventory {
            // The inventory must describe the same revision as the snapshot.
            if let inventoryVersion = numberingInventory.fileVersion,
               inventoryVersion != snapshot.fileVersion {
                throw TagLibManagerError.fileChanged
            }
            self.trackNumberInventory = numberingInventory.track
            self.discNumberInventory = numberingInventory.disc
        } else {
            self.trackNumberInventory = nil
            self.discNumberInventory = nil
        }

        let asset = AVURLAsset(url: url)

        // MARK: – Editable tags remain TagLib-authoritative; credits are display-only AVFoundation data.

        self.publisher = tag.publisher
        self.copyright = tag.copyright

        if Self.needsAVFoundationCreditsRead(fileExtension: url.pathExtension, rawMetadata: snapshot.raw) {
            let allMetadataItems = (try? await asset.load(.metadata)) ?? []
            self.credits = await AudioFile.readMetadata(
                from: allMetadataItems,
                commonKeys: [],
                id3Keys: ["TEXT"]
            )
        } else {
            self.credits = ""
        }

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

        // AVFoundation reads above can suspend. Never publish metadata from one
        // revision paired with the fingerprint of a later revision.
        guard fingerprint == (try AudioFileFingerprint.capture(at: url)),
              snapshot.fileVersion == (try TagLibMetadataManager.fileVersion(at: url)) else {
            throw TagLibManagerError.fileChanged
        }
        self.fileFingerprint = fingerprint
    }

    /// Reads typed container-exclusive values. Absence is represented by a
    /// missing dictionary entry; present zero/false values are retained.
    nonisolated static func containerValues(
        from tag: BasicMetadata,
        atoms: [StructuredMP4Atom]
    ) -> [MetadataFieldKey: ContainerFieldValue] {
        var values: [MetadataFieldKey: ContainerFieldValue] = [:]

        for key in ContainerMetadataFieldCatalog.readKeys {
            let accepted = ContainerMetadataFieldCatalog.acceptedKinds(for: key)
            let atomKey = ContainerMetadataFieldCatalog.atomKey(for: key)
            let atom = atoms.last {
                !$0.remove && $0.key == atomKey
            }

            if let atom {
                if accepted.contains(.boolean) && !accepted.contains(.text) {
                    let flag = atom.first.map { $0 != 0 } ?? parsedBoolean(atom.value)
                    if let flag {
                        values[key] = .boolean(flag)
                    }
                    continue
                }
                if accepted.contains(.integer) && !accepted.contains(.text) || accepted.isEmpty {
                    if let integer = atom.first ?? Int(atom.value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        values[key] = .integer(integer)
                    }
                    continue
                }
                let text = atom.value.isEmpty
                    ? atom.values.joined(separator: "; ")
                    : atom.value
                if !text.isEmpty {
                    values[key] = .text(text)
                }
                continue
            }

            // Text projections are available through BasicMetadata. Integer and
            // Boolean projections use structured atoms so absence stays distinct
            // from a present zero/false value.
            guard !accepted.contains(.integer) && !accepted.contains(.boolean),
                  let text = textValue(for: key, in: tag),
                  !text.isEmpty else {
                continue
            }
            values[key] = .text(text)
        }

        return values
    }

    nonisolated private static func textValue(
        for key: MetadataFieldKey,
        in tag: BasicMetadata
    ) -> String? {
        switch key {
        case .director: return tag.director
        case .itunesAccount: return tag.itunesAccount
        case .itunesOwner: return tag.itunesOwner
        case .storeDescription: return tag.storeDescription
        case .tvEpisodeID: return tag.tvEpisodeID
        case .tvNetwork: return tag.tvNetwork
        case .tvShow: return tag.tvShow
        case .tvShowSort: return tag.tvShowSort
        default: return nil
        }
    }

    nonisolated private static func parsedBoolean(_ text: String) -> Bool? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true": return true
        case "0", "false": return false
        default: return nil
        }
    }
}
