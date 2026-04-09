//
//  TagLibMetadataManager.swift
//  AudioMator
//

import Foundation

/// Mirrors the metadata fields used in `AudioFile.swift`.
struct BasicMetadata {
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var comment: String
    var lyrics: String
    var track: Int
    var trackTotal: Int
    var disc: Int
    var discTotal: Int
    var trackNumberText: String
    var discNumberText: String
    var year: String
    var albumArtist: String
    var releaseDate: String
    var originalReleaseDate: String
    var isrc: String
    var barcode: String
    var musicBrainzArtistID: String
    var musicBrainzAlbumID: String
    var musicBrainzTrackID: String
    var musicBrainzReleaseGroupID: String
    var publisher: String
    var copyright: String
    var encodedBy: String
    var encoderSettings: String
    var sortTitle: String
    var sortArtist: String
    var sortAlbum: String
    var sortAlbumArtist: String
    var sortComposer: String
    var conductor: String
    var remixer: String
    var producer: String
    var engineer: String
    var lyricist: String
    var subtitle: String
    var grouping: String
    var movement: String
    var mood: String
    var language: String
    var musicalKey: String
    var replayGainTrack: String
    var replayGainAlbum: String
    var mediaType: String
    var releaseType: String
    var catalogNumber: String
    var releaseCountry: String
    var artistType: String
    var bpm: Int
    var isCompilation: Bool
    var isExplicit: Bool
    var duration: Double
    var bitrate: Int
    var sampleRate: Double
    var channels: Int
    var bitDepth: Int
    var format: String
    var artworkData: Data?
    var customFields: [String: String]

    static let empty = BasicMetadata(
        title: "",
        artist: "",
        album: "",
        composer: "",
        genre: "",
        comment: "",
        lyrics: "",
        track: 0,
        trackTotal: 0,
        disc: 0,
        discTotal: 0,
        trackNumberText: "",
        discNumberText: "",
        year: "",
        albumArtist: "",
        releaseDate: "",
        originalReleaseDate: "",
        isrc: "",
        barcode: "",
        musicBrainzArtistID: "",
        musicBrainzAlbumID: "",
        musicBrainzTrackID: "",
        musicBrainzReleaseGroupID: "",
        publisher: "",
        copyright: "",
        encodedBy: "",
        encoderSettings: "",
        sortTitle: "",
        sortArtist: "",
        sortAlbum: "",
        sortAlbumArtist: "",
        sortComposer: "",
        conductor: "",
        remixer: "",
        producer: "",
        engineer: "",
        lyricist: "",
        subtitle: "",
        grouping: "",
        movement: "",
        mood: "",
        language: "",
        musicalKey: "",
        replayGainTrack: "",
        replayGainAlbum: "",
        mediaType: "",
        releaseType: "",
        catalogNumber: "",
        releaseCountry: "",
        artistType: "",
        bpm: 0,
        isCompilation: false,
        isExplicit: false,
        duration: 0,
        bitrate: 0,
        sampleRate: 0,
        channels: 0,
        bitDepth: 0,
        format: "",
        artworkData: nil,
        customFields: [:]
    )
}

private func preferredRawNumberText(_ currentValue: String, _ candidateValue: String) -> String {
    func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func score(_ value: String) -> Int {
        let trimmed = normalized(value)
        guard !trimmed.isEmpty else { return .min }

        let leftPart = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
        let hasLeadingZeros = leftPart.count > 1 && leftPart.hasPrefix("0")
        let hasExplicitTotal = trimmed.contains("/")
        return (hasLeadingZeros ? 1000 : 0) + (hasExplicitTotal ? 100 : 0) + trimmed.count
    }

    let trimmedCurrent = normalized(currentValue)
    let trimmedCandidate = normalized(candidateValue)

    guard !trimmedCandidate.isEmpty else { return trimmedCurrent }
    guard !trimmedCurrent.isEmpty else { return trimmedCandidate }
    return score(trimmedCandidate) > score(trimmedCurrent) ? trimmedCandidate : trimmedCurrent
}

private func rawNumberTexts(from dump: RawMetadataDump) -> (track: String, disc: String) {
    let trackFromProperties = dump.properties
        .filter { ["TRACKNUMBER", "TRACK"].contains($0.key.uppercased()) }
        .reduce(into: "") { bestValue, entry in
            for value in entry.values {
                bestValue = preferredRawNumberText(bestValue, value)
            }
            bestValue = preferredRawNumberText(bestValue, entry.value)
        }

    let discFromProperties = dump.properties
        .filter { ["DISCNUMBER", "DISC"].contains($0.key.uppercased()) }
        .reduce(into: "") { bestValue, entry in
            for value in entry.values {
                bestValue = preferredRawNumberText(bestValue, value)
            }
            bestValue = preferredRawNumberText(bestValue, entry.value)
        }

    let trackFromFrames = dump.id3v2Frames
        .filter { $0.frameID.uppercased() == "TRCK" }
        .reduce(into: "") { bestValue, entry in
            bestValue = preferredRawNumberText(bestValue, entry.value)
        }

    let discFromFrames = dump.id3v2Frames
        .filter { $0.frameID.uppercased() == "TPOS" }
        .reduce(into: "") { bestValue, entry in
            bestValue = preferredRawNumberText(bestValue, entry.value)
        }

    return (
        track: preferredRawNumberText(trackFromProperties, trackFromFrames),
        disc: preferredRawNumberText(discFromProperties, discFromFrames)
    )
}

// MARK: - Raw Metadata Dump Models (for GUI display)

struct RawMetadataDump: Hashable {
    var properties: [RawPropertyEntry]
    var id3v2Frames: [RawID3v2FrameEntry]

    static let empty = RawMetadataDump(properties: [], id3v2Frames: [])
}

struct RawPropertyEntry: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
    var values: [String]
    var count: Int
}

struct RawID3v2FrameEntry: Identifiable, Hashable {
    let id = UUID()
    var frameID: String
    var value: String
    var description: String?
    var language: String?
}

enum TagLibManagerError: Error {
    case unsupportedFormat
    case failedToRead
}

/// Thin wrapper around the Objective-C++ `TagLibMetadataExtractor`.
struct TagLibMetadataManager {

    // MARK: - Bridge Dump API

    /// Return a single plain-text dump of metadata as TagLib sees it.
    ///
    /// Preferred path: call the ObjC++ bridge API directly (Swift `throws`).
    /// Fallback path: attempt older single-argument selector names via `perform` for compatibility.
    private static func bridgeTextDumpIfAvailable(for url: URL) -> String? {
        // Newer bridge (preferred): `dumpMetadataText(from:)` is exposed as a Swift-throwing method.
        if let text = try? TagLibMetadataExtractor.dumpMetadataText(from: url) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        // Older bridge variants: try a small set of single-argument selector names at runtime.
        let candidates = [
            "rawMetadataTextFor:",
            "rawMetadataTextForURL:",
            "dumpMetadataTextFor:",
            "dumpMetadataTextFrom:",
            "dumpMetadataTextFromURL:",
            "dumpMetadataTextForURL:"
        ]

        for name in candidates {
            let sel = NSSelectorFromString(name)
            guard TagLibMetadataExtractor.responds(to: sel) else { continue }

            // perform(_:with:) only supports single-argument selectors.
            if let unmanaged = TagLibMetadataExtractor.perform(sel, with: url) {
                let any = unmanaged.takeUnretainedValue()
                if let s = any as? String {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let s = any as? NSString {
                    let trimmed = (s as String).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }

        return nil
    }

    static func readMetadata(from url: URL) -> BasicMetadata? {
        // 1. Quickly filter by file extension.
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        if !TagLibMetadataExtractor.isSupportedFormat(ext) {
            // Unsupported formats fall back to the AVFoundation path.
            return nil
        }

        do {
            // ObjC++ bridge API imported into Swift as `throws`.
            let meta = try TagLibMetadataExtractor.extractMetadata(from: url)
            let trackNumberText = meta.trackNumberText ?? ""
            let discNumberText = meta.discNumberText ?? ""
            let needsTrackTextFallback =
                trackNumberText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                meta.trackNumber > 0
            let needsDiscTextFallback =
                discNumberText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                meta.discNumber > 0

            let rawNumberText: (track: String, disc: String)
            if needsTrackTextFallback || needsDiscTextFallback {
                rawNumberText = rawMetadata(from: url).map(rawNumberTexts(from:)) ?? (track: "", disc: "")
            } else {
                rawNumberText = (track: "", disc: "")
            }

            return BasicMetadata(
                title: meta.title ?? "",
                artist: meta.artist ?? "",
                album: meta.album ?? "",
                composer: meta.composer ?? "",
                genre: meta.genre ?? "",
                comment: meta.comment ?? "",
                lyrics: meta.lyrics ?? "",
                track: Int(meta.trackNumber),
                trackTotal: Int(meta.totalTracks),
                disc: Int(meta.discNumber),
                discTotal: Int(meta.totalDiscs),
                trackNumberText: needsTrackTextFallback
                    ? preferredRawNumberText(trackNumberText, rawNumberText.track)
                    : trackNumberText,
                discNumberText: needsDiscTextFallback
                    ? preferredRawNumberText(discNumberText, rawNumberText.disc)
                    : discNumberText,
                year: meta.year ?? "",
                albumArtist: meta.albumArtist ?? "",
                releaseDate: meta.releaseDate ?? meta.originalReleaseDate ?? "",
                originalReleaseDate: meta.originalReleaseDate ?? "",
                isrc: meta.isrc ?? "",
                barcode: meta.barcode ?? "",
                musicBrainzArtistID: meta.musicBrainzArtistId ?? "",
                musicBrainzAlbumID: meta.musicBrainzAlbumId ?? "",
                musicBrainzTrackID: meta.musicBrainzTrackId ?? "",
                musicBrainzReleaseGroupID: meta.musicBrainzReleaseGroupId ?? "",
                publisher: meta.label ?? "",
                copyright: meta.copyright ?? "",
                encodedBy: meta.encodedBy ?? "",
                encoderSettings: meta.encoderSettings ?? "",
                sortTitle: meta.sortTitle ?? "",
                sortArtist: meta.sortArtist ?? "",
                sortAlbum: meta.sortAlbum ?? "",
                sortAlbumArtist: meta.sortAlbumArtist ?? "",
                sortComposer: meta.sortComposer ?? "",
                conductor: meta.conductor ?? "",
                remixer: meta.remixer ?? "",
                producer: meta.producer ?? "",
                engineer: meta.engineer ?? "",
                lyricist: meta.lyricist ?? "",
                subtitle: meta.subtitle ?? "",
                grouping: meta.grouping ?? "",
                movement: meta.movement ?? "",
                mood: meta.mood ?? "",
                language: meta.language ?? "",
                musicalKey: meta.musicalKey ?? "",
                replayGainTrack: meta.replayGainTrack ?? "",
                replayGainAlbum: meta.replayGainAlbum ?? "",
                mediaType: meta.mediaType ?? "",
                releaseType: meta.releaseType ?? "",
                catalogNumber: meta.catalogNumber ?? "",
                releaseCountry: meta.releaseCountry ?? "",
                artistType: meta.artistType ?? "",
                bpm: Int(meta.bpm),
                isCompilation: meta.compilation,
                isExplicit: meta.explicitContent,
                duration: meta.duration,
                bitrate: Int(meta.bitrate),
                sampleRate: Double(meta.sampleRate),
                channels: Int(meta.channels),
                bitDepth: Int(meta.bitDepth),
                format: meta.codec ?? "",
                artworkData: meta.artworkData as Data?,
                customFields: meta.customFields ?? [:]
            )
        } catch {
            print("TagLib read error for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Write / Erase

    /// Write `BasicMetadata` back to the file using TagLib.
    ///
    /// Notes:
    /// - This is intended for formats supported by our TagLib bridge's write paths.
    /// - Fields that are empty strings are written as `nil` (i.e. removed/cleared).
    /// - `publisher` is mapped to TagLib's `label` field.
    @discardableResult
    static func writeMetadata(_ meta: BasicMetadata, to url: URL) throws -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, TagLibMetadataExtractor.isSupportedFormat(ext) else {
            throw TagLibManagerError.unsupportedFormat
        }

        let m = TagLibAudioMetadata()

        func nilIfEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        // Core tags
        m.title = nilIfEmpty(meta.title)
        m.artist = nilIfEmpty(meta.artist)
        m.album = nilIfEmpty(meta.album)
        m.albumArtist = nilIfEmpty(meta.albumArtist)
        m.composer = nilIfEmpty(meta.composer)
        m.genre = nilIfEmpty(meta.genre)
        m.comment = nilIfEmpty(meta.comment)

        // Numbers
        // TagLib bridge uses `Int` for these fields; use 0 to represent “not set/clear”.
        m.trackNumber = meta.track
        m.totalTracks = meta.trackTotal
        m.discNumber = meta.disc
        m.totalDiscs = meta.discTotal
        m.trackNumberText = nilIfEmpty(meta.trackNumberText)
        m.discNumberText = nilIfEmpty(meta.discNumberText)

        // Dates
        m.year = nilIfEmpty(meta.year)
        m.releaseDate = nilIfEmpty(meta.releaseDate)
        m.originalReleaseDate = nilIfEmpty(meta.originalReleaseDate)

        // Legal / publisher
        m.label = nilIfEmpty(meta.publisher)
        m.copyright = nilIfEmpty(meta.copyright)
        m.lyrics = nilIfEmpty(meta.lyrics)
        m.encodedBy = nilIfEmpty(meta.encodedBy)
        m.encoderSettings = nilIfEmpty(meta.encoderSettings)
        m.sortTitle = nilIfEmpty(meta.sortTitle)
        m.sortArtist = nilIfEmpty(meta.sortArtist)
        m.sortAlbum = nilIfEmpty(meta.sortAlbum)
        m.sortAlbumArtist = nilIfEmpty(meta.sortAlbumArtist)
        m.sortComposer = nilIfEmpty(meta.sortComposer)
        m.conductor = nilIfEmpty(meta.conductor)
        m.remixer = nilIfEmpty(meta.remixer)
        m.producer = nilIfEmpty(meta.producer)
        m.engineer = nilIfEmpty(meta.engineer)
        m.lyricist = nilIfEmpty(meta.lyricist)
        m.subtitle = nilIfEmpty(meta.subtitle)
        m.grouping = nilIfEmpty(meta.grouping)
        m.movement = nilIfEmpty(meta.movement)
        m.mood = nilIfEmpty(meta.mood)
        m.language = nilIfEmpty(meta.language)
        m.musicalKey = nilIfEmpty(meta.musicalKey)
        m.replayGainTrack = nilIfEmpty(meta.replayGainTrack)
        m.replayGainAlbum = nilIfEmpty(meta.replayGainAlbum)
        m.mediaType = nilIfEmpty(meta.mediaType)
        m.releaseType = nilIfEmpty(meta.releaseType)
        m.catalogNumber = nilIfEmpty(meta.catalogNumber)
        m.releaseCountry = nilIfEmpty(meta.releaseCountry)
        m.artistType = nilIfEmpty(meta.artistType)

        // Explicit
        m.bpm = meta.bpm
        m.compilation = meta.isCompilation
        m.explicitContent = meta.isExplicit
        m.isrc = nilIfEmpty(meta.isrc)
        m.barcode = nilIfEmpty(meta.barcode)
        m.musicBrainzArtistId = nilIfEmpty(meta.musicBrainzArtistID)
        m.musicBrainzAlbumId = nilIfEmpty(meta.musicBrainzAlbumID)
        m.musicBrainzTrackId = nilIfEmpty(meta.musicBrainzTrackID)
        m.musicBrainzReleaseGroupId = nilIfEmpty(meta.musicBrainzReleaseGroupID)
        m.customFields = meta.customFields.isEmpty ? nil : meta.customFields

        // Persist
        try TagLibMetadataExtractor.writeMetadata(m, to: url)
        return true
    }

    /// Remove (as much as TagLib allows) all metadata from a file.
    ///
    /// Implementation strategy: write an empty `TagLibAudioMetadata` object.
    /// This should clear the common tag fields and reset numeric fields to 0.
    @discardableResult
    static func eraseAllMetadata(from url: URL) throws -> Bool {
        return try writeMetadata(.empty, to: url)
    }

    /// Raw metadata dump for GUI inspection ("show me everything TagLib sees").
    ///
    /// The extractor returns a dictionary with stable keys:
    /// - "properties": unified TagLib PropertyMap entries
    /// - "id3v2Frames": ID3v2 frames (MP3 only)
    ///
    /// Returns `nil` if format is not supported by TagLib in this app.
    static func rawMetadata(from url: URL) -> RawMetadataDump? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        guard TagLibMetadataExtractor.isSupportedFormat(ext) else {
            return nil
        }

        // ObjC++ returns a Foundation dictionary for display; normalize it into Swift models.
        let dictAny: Any
        do {
            dictAny = try TagLibMetadataExtractor.rawMetadata(for: url)
        } catch {
            print("TagLib rawMetadata error for \(url.lastPathComponent): \(error)")
            return .empty
        }
        let dict: NSDictionary
        if let d = dictAny as? NSDictionary {
            dict = d
        } else if let d = dictAny as? [String: Any] {
            dict = d as NSDictionary
        } else {
            return .empty
        }

        let propsAny = dict["properties"] as? [Any] ?? []
        let framesAny = dict["id3v2Frames"] as? [Any] ?? []

        let properties: [RawPropertyEntry] = propsAny.compactMap { item in
            guard let d = item as? NSDictionary else { return nil }

            let key = d["key"] as? String ?? ""
            let value = d["value"] as? String ?? ""

            let values: [String]
            if let arr = d["values"] as? [String] {
                values = arr
            } else if let arr = d["values"] as? [Any] {
                values = arr.compactMap { $0 as? String }
            } else {
                values = []
            }

            let count: Int
            if let n = d["count"] as? Int {
                count = n
            } else if let n = d["count"] as? NSNumber {
                count = n.intValue
            } else {
                count = values.count
            }

            return RawPropertyEntry(key: key, value: value, values: values, count: count)
        }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }

        let id3v2Frames: [RawID3v2FrameEntry] = framesAny.compactMap { item in
            guard let d = item as? NSDictionary else { return nil }

            let frameID = d["id"] as? String ?? ""
            let value = d["value"] as? String ?? ""
            let desc = d["description"] as? String
            let lang = d["language"] as? String

            return RawID3v2FrameEntry(frameID: frameID, value: value, description: desc, language: lang)
        }

        return RawMetadataDump(properties: properties, id3v2Frames: id3v2Frames)
    }

    /// Formats *raw* metadata (as seen by TagLib) into a single text blob for GUI display.
    ///
    /// This is intentionally **not** the same as the structured fields shown in the right inspector.
    /// It surfaces:
    /// - TagLib `PropertyMap` entries (including multi-value fields)
    /// - ID3v2 frames (MP3 only), including TXXX/COMM details when available
    static func rawMetadataText(from url: URL) -> String? {
        // Prefer a direct text dump from the bridge if available.
        if let text = bridgeTextDumpIfAvailable(for: url) {
            return text
        }

        // Otherwise, build a readable text representation from the normalized dump models.
        guard let dump = rawMetadata(from: url) else { return nil }

        var lines: [String] = []
        lines.append("File: \(url.lastPathComponent)")
        lines.append("Path: \(url.path)")
        lines.append("")

        lines.append("[TagLib Properties]")
        if dump.properties.isEmpty {
            lines.append("(none)")
        } else {
            for p in dump.properties {
                // Prefer showing the full values array when present.
                if !p.values.isEmpty {
                    if p.values.count == 1 {
                        lines.append("\(p.key): \(p.values[0])")
                    } else {
                        lines.append("\(p.key):")
                        for v in p.values {
                            lines.append("  - \(v)")
                        }
                    }
                } else if !p.value.isEmpty {
                    lines.append("\(p.key): \(p.value)")
                } else {
                    lines.append("\(p.key):")
                }
            }
        }

        lines.append("")
        lines.append("[ID3v2 Frames]")
        if dump.id3v2Frames.isEmpty {
            lines.append("(none)")
        } else {
            for f in dump.id3v2Frames {
                let trimmedValue = f.value.trimmingCharacters(in: .whitespacesAndNewlines)

                // Provide richer labeling for common “multi-field” frames.
                if let desc = f.description, !desc.isEmpty {
                    // Typically TXXX / COMM
                    if let lang = f.language, !lang.isEmpty {
                        lines.append("\(f.frameID) [\(lang)] (\(desc)): \(trimmedValue)")
                    } else {
                        lines.append("\(f.frameID) (\(desc)): \(trimmedValue)")
                    }
                } else {
                    lines.append("\(f.frameID): \(trimmedValue)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
