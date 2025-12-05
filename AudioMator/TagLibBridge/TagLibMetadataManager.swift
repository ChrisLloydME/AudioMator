//
//  TagLibMetadataManager.swift
//  AudioMator
//
//  Lightweight Swift wrapper around TagLibMetadataExtractor
//  Used by AudioFile to read basic tags via TagLib.
//
//  NOTE: This is a trimmed-down version of the HiFidelity helper.
//  All HiFidelity-specific types such as TrackMetadata, ExtendedMetadata,
//  Track, and Logger have been removed.
//

import Foundation

/// Swift wrapper for TagLib-based metadata extraction, simplified for AudioMator.
struct TagLibMetadataManager {

    // MARK: - AudioMator Basic Metadata

    /// Lightweight metadata container for AudioMator
    struct BasicMetadata {
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var albumArtist: String = ""
        var composer: String = ""
        var genre: String = ""
        var comment: String = ""
        var track: Int = 0
        var trackTotal: Int = 0
        var disc: Int = 0
        var discTotal: Int = 0
        var year: String = ""
        var artwork: Data? = nil
    }

    // MARK: - Public API

    /// Read simplified metadata for a single file.
    ///
    /// This is the only API that `AudioFile` needs. It is intentionally
    /// decoupled from HiFidelity's `TrackMetadata` and related types.
    ///
    /// - Parameter url: File URL of the audio file.
    /// - Returns: A `BasicMetadata` value with TagLib data. If TagLib fails,
    ///            title will fall back to the filename and other fields remain default.
    static func readMetadata(from url: URL) -> BasicMetadata {
        var meta = BasicMetadata()

        do {
            // TagLibMetadataExtractor comes from the Objective‑C++ bridge
            // imported via AudioMator-Bridging-Header.h.
            let tag = try TagLibMetadataExtractor.extractMetadata(from: url)

            meta.title       = tag.title ?? ""
            meta.artist      = tag.artist ?? ""
            meta.album       = tag.album ?? ""
            meta.albumArtist = tag.albumArtist ?? ""
            meta.composer    = tag.composer ?? ""
            meta.genre       = tag.genre ?? ""
            meta.comment     = tag.comment ?? ""
            meta.year        = tag.year ?? ""

            if tag.trackNumber > 0 {
                meta.track = Int(tag.trackNumber)
            }
            if tag.totalTracks > 0 {
                meta.trackTotal = Int(tag.totalTracks)
            }
            if tag.discNumber > 0 {
                meta.disc = Int(tag.discNumber)
            }
            if tag.totalDiscs > 0 {
                meta.discTotal = Int(tag.totalDiscs)
            }

            meta.artwork = tag.artworkData
        } catch {
            // TagLib failed → use filename as fallback title
            meta.title = url.deletingPathExtension().lastPathComponent
        }

        return meta
    }

    /// Optional: expose supported extensions if you ever need them.
    static func supportedExtensions() -> [String] {
        return TagLibMetadataExtractor.supportedExtensions()
    }

    /// Optional: quick check if a file extension is supported by TagLib.
    static func isSupportedFormat(_ fileExtension: String) -> Bool {
        return TagLibMetadataExtractor.isSupportedFormat(fileExtension)
    }
}
