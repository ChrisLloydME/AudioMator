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
        // 1. 按扩展名快速过滤
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }

        if !TagLibMetadataExtractor.isSupportedFormat(ext) {
            // 不支持的格式，让调用方回退到 AVFoundation
            return nil
        }

        do {
            // ObjC++ 提供的接口（Swift 里是 throws 形式）
            let meta = try TagLibMetadataExtractor.extractMetadata(from: url)
            let obj = meta as NSObject

            // KVC 读取前先判断 selector 是否存在，避免 unknown key 直接崩溃
            func string(_ key: String) -> String {
                let sel = NSSelectorFromString(key)
                guard obj.responds(to: sel) else { return "" }
                return (obj.value(forKey: key) as? String) ?? ""
            }

            func int(_ key: String) -> Int {
                let sel = NSSelectorFromString(key)
                guard obj.responds(to: sel) else { return 0 }
                if let n = obj.value(forKey: key) as? NSNumber { return n.intValue }
                if let i = obj.value(forKey: key) as? Int { return i }
                return 0
            }

            func bool(_ key: String) -> Bool {
                let sel = NSSelectorFromString(key)
                guard obj.responds(to: sel) else { return false }
                if let n = obj.value(forKey: key) as? NSNumber { return n.boolValue }
                if let b = obj.value(forKey: key) as? Bool { return b }
                return false
            }

            // 兼容不同实现里可能存在的别名字段（例如 label/publisher）
            func firstNonEmpty(_ keys: [String]) -> String {
                for k in keys {
                    let v = string(k)
                    if !v.isEmpty { return v }
                }
                return ""
            }

            func firstInt(_ keys: [String]) -> Int {
                for k in keys {
                    let v = int(k)
                    if v != 0 { return v }
                }
                return 0
            }

            func firstBool(_ keys: [String]) -> Bool {
                for k in keys {
                    let v = bool(k)
                    if v { return true }
                }
                return false
            }

            // TagLibAudioMetadata -> BasicMetadata
            return BasicMetadata(
                title:       firstNonEmpty(["title"]),
                artist:      firstNonEmpty(["artist"]),
                album:       firstNonEmpty(["album"]),
                composer:    firstNonEmpty(["composer"]),
                genre:       firstNonEmpty(["genre"]),
                comment:     firstNonEmpty(["comment"]),
                track:       firstInt(["trackNumber", "track"]),
                trackTotal:  firstInt(["totalTracks", "trackTotal"]),
                disc:        firstInt(["discNumber", "disc"]),
                discTotal:   firstInt(["totalDiscs", "discTotal"]),
                year:        firstNonEmpty(["year"]),
                albumArtist: firstNonEmpty(["albumArtist"]),
                // Release Date 字段：如果桥接层不提供，这里会是空字符串；AudioFile 可继续用 AVFoundation 兜底
                releaseDate: firstNonEmpty(["releaseDate", "originalReleaseDate"]),
                publisher:   firstNonEmpty(["publisher", "label"]),
                copyright:   firstNonEmpty(["copyright"]),
                isExplicit:  firstBool(["explicitContent", "isExplicit", "explicit"])
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
    /// - This is intended for formats supported by our TagLib bridge (currently MP3-first).
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

        // Dates
        m.year = nilIfEmpty(meta.year)
        m.releaseDate = nilIfEmpty(meta.releaseDate)

        // Legal / publisher
        m.label = nilIfEmpty(meta.publisher)
        m.copyright = nilIfEmpty(meta.copyright)

        // Explicit
        m.explicitContent = meta.isExplicit

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
