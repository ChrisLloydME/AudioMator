//
//  TagLibMetadataManager.swift
//  AudioMator
//

import Foundation

/// 和 AudioFile.swift 中使用的字段一一对应
struct BasicMetadata {
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var comment: String
    var track: Int
    var trackTotal: Int
    var disc: Int
    var discTotal: Int
    var year: String
    var albumArtist: String
    var releaseDate: String
    var publisher: String
    var copyright: String
    var isExplicit: Bool

    static let empty = BasicMetadata(
        title: "",
        artist: "",
        album: "",
        composer: "",
        genre: "",
        comment: "",
        track: 0,
        trackTotal: 0,
        disc: 0,
        discTotal: 0,
        year: "",
        albumArtist: "",
        releaseDate: "",
        publisher: "",
        copyright: "",
        isExplicit: false
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

/// 包一层，负责调用 Objective-C++ 的 TagLibMetadataExtractor
struct TagLibMetadataManager {

    static func readMetadata(from url: URL) -> BasicMetadata? {
        // 1. 按扩展名快速过滤
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        if !TagLibMetadataExtractor.isSupportedFormat(ext) {
            // 不支持的格式，让调用方回退到 AVFoundation
            return nil
        }

        // 2. 调用 ObjC++ 提供的接口（Swift 里是 throws 形式）
        do {
            // 注意这里是 extractMetadata(from:)，没有 error: 这个参数
            let meta = try TagLibMetadataExtractor.extractMetadata(from: url)

            // 3. 把 TagLibAudioMetadata -> BasicMetadata
            return BasicMetadata(
                title:       meta.title       ?? "",
                artist:      meta.artist      ?? "",
                album:       meta.album       ?? "",
                composer:    meta.composer    ?? "",
                genre:       meta.genre       ?? "",
                comment:     meta.comment     ?? "",
                track:       Int(meta.trackNumber),
                trackTotal:  Int(meta.totalTracks),
                disc:        Int(meta.discNumber),
                discTotal:   Int(meta.totalDiscs),
                year:        meta.year        ?? "",
                albumArtist: meta.albumArtist ?? "",
                releaseDate: meta.releaseDate ?? "",
                publisher:   meta.label       ?? "",
                copyright:   meta.copyright   ?? "",
                isExplicit:  meta.explicitContent
            )
        } catch {
            print("TagLib read error for \(url.lastPathComponent): \(error)")
            return nil
        }
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
        guard TagLibMetadataExtractor.isSupportedFormat(ext) else { return nil }

        // ObjC++ returns a Foundation dictionary for display; normalize it into Swift models.
        let dictObj = TagLibMetadataExtractor.rawMetadata(for: url)
        let dict = dictObj as NSDictionary

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
}
