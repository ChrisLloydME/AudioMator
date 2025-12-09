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
        albumArtist: ""
    )
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
                albumArtist: meta.albumArtist ?? ""
            )
        } catch {
            print("TagLib read error for \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
