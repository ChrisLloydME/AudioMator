//
//  AudioFile.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import Foundation
import SFBAudioEngine

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
    }
}
