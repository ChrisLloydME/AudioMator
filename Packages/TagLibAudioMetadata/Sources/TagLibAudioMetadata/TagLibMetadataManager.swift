//
//  TagLibMetadataManager.swift
//  AudioMator
//

import Foundation
@_exported import CTagLibBridge

public enum MetadataValueSource: String, Hashable, Sendable {
    case nativeTag
    case propertyMap
    case id3v2Frame
    case rawFallback
    case derivedNumeric
    case none
}

public struct MetadataFieldProvenance: Hashable, Sendable {
    public var trackNumberText: MetadataValueSource
    public var discNumberText: MetadataValueSource
    public var explicitContent: MetadataValueSource
    public var artwork: MetadataValueSource

    public init(
        trackNumberText: MetadataValueSource,
        discNumberText: MetadataValueSource,
        explicitContent: MetadataValueSource,
        artwork: MetadataValueSource
    ) {
        self.trackNumberText = trackNumberText
        self.discNumberText = discNumberText
        self.explicitContent = explicitContent
        self.artwork = artwork
    }

    public nonisolated static let unknown = MetadataFieldProvenance(
        trackNumberText: .none,
        discNumberText: .none,
        explicitContent: .none,
        artwork: .none
    )
}

/// Mirrors the metadata fields used in `AudioFile.swift`.
public struct BasicMetadata: Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var composer: String
    public var genre: String
    public var comment: String
    public var lyrics: String
    public var track: Int
    public var trackTotal: Int
    public var disc: Int
    public var discTotal: Int
    public var trackNumberText: String
    public var discNumberText: String
    public var year: String
    public var albumArtist: String
    public var releaseDate: String
    public var originalReleaseDate: String
    public var isrc: String
    public var barcode: String
    public var musicBrainzArtistID: String
    public var musicBrainzAlbumID: String
    public var musicBrainzTrackID: String
    public var musicBrainzReleaseGroupID: String
    public var publisher: String
    public var copyright: String
    public var encodedBy: String
    public var encoderSettings: String
    public var sortTitle: String
    public var sortArtist: String
    public var sortAlbum: String
    public var sortAlbumArtist: String
    public var sortComposer: String
    public var conductor: String
    public var remixer: String
    public var producer: String
    public var engineer: String
    public var lyricist: String
    public var subtitle: String
    public var grouping: String
    public var movement: String
    public var mood: String
    public var language: String
    public var musicalKey: String
    public var replayGainTrack: String
    public var replayGainAlbum: String
    public var mediaType: String
    public var itunesAlbumID: String
    public var itunesArtistID: String
    public var itunesCatalogID: String
    public var itunesGenreID: String
    public var itunesMediaType: String
    public var itunesPurchaseDate: String
    public var itunesNorm: String
    public var itunesSMPB: String
    public var releaseType: String
    public var catalogNumber: String
    public var releaseCountry: String
    public var artistType: String
    public var bpm: Int
    public var isCompilation: Bool
    public var isExplicit: Bool
    public var duration: Double
    public var bitrate: Int
    public var sampleRate: Double
    public var channels: Int
    public var bitDepth: Int
    public var format: String
    public var artworkData: Data?
    public var customFields: [String: String]
    public var provenance: MetadataFieldProvenance

    public nonisolated static let empty = BasicMetadata(
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
        itunesAlbumID: "",
        itunesArtistID: "",
        itunesCatalogID: "",
        itunesGenreID: "",
        itunesMediaType: "",
        itunesPurchaseDate: "",
        itunesNorm: "",
        itunesSMPB: "",
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
        customFields: [:],
        provenance: .unknown
    )
}

nonisolated private func preferredRawNumberText(_ currentValue: String, _ candidateValue: String) -> String {
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

nonisolated private func rawNumberTexts(from dump: RawMetadataDump) -> (track: String, disc: String) {
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

public struct RawMetadataDump: Hashable, Sendable {
    public var properties: [RawPropertyEntry]
    public var id3v2Frames: [RawID3v2FrameEntry]

    public init(properties: [RawPropertyEntry], id3v2Frames: [RawID3v2FrameEntry]) {
        self.properties = properties
        self.id3v2Frames = id3v2Frames
    }

    public nonisolated static let empty = RawMetadataDump(properties: [], id3v2Frames: [])
}

public struct RawPropertyEntry: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var key: String
    public var value: String
    public var values: [String]
    public var count: Int

    public init(key: String, value: String, values: [String], count: Int) {
        self.key = key
        self.value = value
        self.values = values
        self.count = count
    }
}

public struct RawID3v2FrameEntry: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var frameID: String
    public var value: String
    public var description: String?
    public var language: String?

    public init(frameID: String, value: String, description: String?, language: String?) {
        self.frameID = frameID
        self.value = value
        self.description = description
        self.language = language
    }
}

public enum TagLibManagerError: Error, Sendable {
    case unsupportedFormat
    case failedToRead
}

/// Thin wrapper around the Objective-C++ `TagLibMetadataExtractor`.
public struct TagLibMetadataManager {

    nonisolated private static let hiddenInternalRawFieldKeys: Set<String> = [
        "AUDIOMATOR_TRACKNUMBER_TEXT",
        "AUDIOMATOR_DISCNUMBER_TEXT",
        "----:COM.APPLE.ITUNES:AUDIOMATOR_TRACKNUMBER_TEXT",
        "----:COM.APPLE.ITUNES:AUDIOMATOR_DISCNUMBER_TEXT",
    ]

    public enum ArtworkVerificationExpectation: Sendable {
        case unchanged
        case present
        case absent
    }

    public struct MetadataWriteVerificationContext: Equatable, Sendable {
        public var expectedTrackNumber: Int?
        public var expectedTrackTotal: Int?
        public var expectedTrackNumberText: String?
        public var expectedDiscNumber: Int?
        public var expectedDiscTotal: Int?
        public var expectedDiscNumberText: String?
        public var expectedExplicitContent: Bool?
        public var artworkExpectation: ArtworkVerificationExpectation
        public var customFieldKeys: [String]

        public init(
            expectedTrackNumber: Int?,
            expectedTrackTotal: Int?,
            expectedTrackNumberText: String?,
            expectedDiscNumber: Int?,
            expectedDiscTotal: Int?,
            expectedDiscNumberText: String?,
            expectedExplicitContent: Bool?,
            artworkExpectation: ArtworkVerificationExpectation,
            customFieldKeys: [String]
        ) {
            self.expectedTrackNumber = expectedTrackNumber
            self.expectedTrackTotal = expectedTrackTotal
            self.expectedTrackNumberText = expectedTrackNumberText
            self.expectedDiscNumber = expectedDiscNumber
            self.expectedDiscTotal = expectedDiscTotal
            self.expectedDiscNumberText = expectedDiscNumberText
            self.expectedExplicitContent = expectedExplicitContent
            self.artworkExpectation = artworkExpectation
            self.customFieldKeys = customFieldKeys
        }

        public nonisolated static let none = MetadataWriteVerificationContext(
            expectedTrackNumber: nil,
            expectedTrackTotal: nil,
            expectedTrackNumberText: nil,
            expectedDiscNumber: nil,
            expectedDiscTotal: nil,
            expectedDiscNumberText: nil,
            expectedExplicitContent: nil,
            artworkExpectation: .unchanged,
            customFieldKeys: []
        )
    }

    public struct MetadataWriteResult: Sendable {
        public var warnings: [String]

        public init(warnings: [String]) {
            self.warnings = warnings
        }
    }

    nonisolated private static func isHiddenInternalRawFieldKey(_ key: String) -> Bool {
        hiddenInternalRawFieldKeys.contains(
            key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        )
    }

    nonisolated private static func normalizedTrimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func parseNumberPair(_ value: String) -> (number: Int, total: Int) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }

        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let number = parts.first.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        let total = parts.count > 1
            ? Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            : 0
        return (max(0, number), max(0, total))
    }

    nonisolated private static func numberPairEquivalent(_ lhs: String?, _ rhs: String?) -> Bool {
        parseNumberPair(normalizedTrimmed(lhs)) == parseNumberPair(normalizedTrimmed(rhs))
    }

    nonisolated private static func rawPropertiesLookup(_ dump: RawMetadataDump) -> [String: [String]] {
        dump.properties.reduce(into: [:]) { result, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !key.isEmpty else { return }

            let mergedValues = (entry.values + [entry.value])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !mergedValues.isEmpty else { return }

            var existing = result[key] ?? []
            existing.append(contentsOf: mergedValues)
            result[key] = Array(Set(existing))
        }
    }

    nonisolated private static func rawContainsCustomKey(_ key: String, dump: RawMetadataDump) -> Bool {
        let expected = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !expected.isEmpty else { return true }

        for property in dump.properties {
            let candidate = property.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if candidate == expected || candidate.hasSuffix(":\(expected)") || candidate.contains(expected) {
                return true
            }
        }

        return false
    }

    nonisolated private static func explicitValueSource(from dump: RawMetadataDump, fallback: Bool) -> MetadataValueSource {
        let explicitKeys = Set(["ITUNESADVISORY", "ADVISORY", "EXPLICITCONTENT", "EXPLICIT", "RTNG"])
        if dump.properties.contains(where: { entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return explicitKeys.contains(key) || key.hasSuffix(":ITUNESADVISORY")
        }) {
            return .propertyMap
        }

        if dump.id3v2Frames.contains(where: { frame in
            if frame.frameID.uppercased() == "TXXX" {
                let description = frame.description?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
                return description == "ITUNESADVISORY" || description == "EXPLICIT"
            }
            return false
        }) {
            return .id3v2Frame
        }

        return fallback ? .nativeTag : .none
    }

    nonisolated private static func hasVerificationExpectations(_ verification: MetadataWriteVerificationContext) -> Bool {
        if verification.expectedTrackNumber != nil || verification.expectedTrackTotal != nil {
            return true
        }

        if let expectedTrack = verification.expectedTrackNumberText,
           !normalizedTrimmed(expectedTrack).isEmpty {
            return true
        }

        if verification.expectedDiscNumber != nil || verification.expectedDiscTotal != nil {
            return true
        }

        if let expectedDisc = verification.expectedDiscNumberText,
           !normalizedTrimmed(expectedDisc).isEmpty {
            return true
        }

        if verification.expectedExplicitContent != nil {
            return true
        }

        switch verification.artworkExpectation {
        case .unchanged:
            break
        case .present, .absent:
            return true
        }

        return !verification.customFieldKeys.isEmpty
    }

    nonisolated private static func metadataWriteWarnings(
        for url: URL,
        verification: MetadataWriteVerificationContext
    ) -> [String] {
        guard hasVerificationExpectations(verification) else { return [] }

        var warnings: [String] = []
        let afterWrite = readMetadata(from: url)
        let rawDump = rawMetadata(from: url)

        if let afterWrite {
            if let expectedTrackNumber = verification.expectedTrackNumber,
               afterWrite.track != expectedTrackNumber {
                warnings.append(
                    "Track number differs after save (expected \(expectedTrackNumber), got \(afterWrite.track))."
                )
            }

            if let expectedTrackTotal = verification.expectedTrackTotal,
               afterWrite.trackTotal != expectedTrackTotal {
                warnings.append(
                    "Total tracks differs after save (expected \(expectedTrackTotal), got \(afterWrite.trackTotal))."
                )
            }
        }

        if let expectedTrack = verification.expectedTrackNumberText,
           !normalizedTrimmed(expectedTrack).isEmpty,
           let afterWrite {
            if !numberPairEquivalent(expectedTrack, afterWrite.trackNumberText) {
                warnings.append(
                    "Track number text differs after save (expected \(expectedTrack), got \(afterWrite.trackNumberText))."
                )
            } else if normalizedTrimmed(expectedTrack) != normalizedTrimmed(afterWrite.trackNumberText) {
                warnings.append(
                    "Track number formatting was normalized by the container (\(expectedTrack) -> \(afterWrite.trackNumberText))."
                )
            }
        }

        if let afterWrite {
            if let expectedDiscNumber = verification.expectedDiscNumber,
               afterWrite.disc != expectedDiscNumber {
                warnings.append(
                    "Disc number differs after save (expected \(expectedDiscNumber), got \(afterWrite.disc))."
                )
            }

            if let expectedDiscTotal = verification.expectedDiscTotal,
               afterWrite.discTotal != expectedDiscTotal {
                warnings.append(
                    "Total discs differs after save (expected \(expectedDiscTotal), got \(afterWrite.discTotal))."
                )
            }
        }

        if let expectedDisc = verification.expectedDiscNumberText,
           !normalizedTrimmed(expectedDisc).isEmpty,
           let afterWrite {
            if !numberPairEquivalent(expectedDisc, afterWrite.discNumberText) {
                warnings.append(
                    "Disc number text differs after save (expected \(expectedDisc), got \(afterWrite.discNumberText))."
                )
            } else if normalizedTrimmed(expectedDisc) != normalizedTrimmed(afterWrite.discNumberText) {
                warnings.append(
                    "Disc number formatting was normalized by the container (\(expectedDisc) -> \(afterWrite.discNumberText))."
                )
            }
        }

        if let expectedExplicit = verification.expectedExplicitContent, let afterWrite {
            if expectedExplicit != afterWrite.isExplicit {
                warnings.append(
                    "Explicit flag differs after save (expected \(expectedExplicit ? "explicit" : "clean"), got \(afterWrite.isExplicit ? "explicit" : "clean"))."
                )
            }
        }

        if let afterWrite {
            switch verification.artworkExpectation {
            case .unchanged:
                break
            case .present:
                if afterWrite.artworkData == nil {
                    warnings.append("Artwork was expected to be present after save but no embedded artwork was found.")
                }
            case .absent:
                if afterWrite.artworkData != nil {
                    warnings.append("Artwork was expected to be removed but embedded artwork is still present.")
                }
            }
        }

        if !verification.customFieldKeys.isEmpty {
            guard let rawDump else {
                warnings.append("Could not verify custom field preservation after save.")
                return warnings
            }

            for key in verification.customFieldKeys where !rawContainsCustomKey(key, dump: rawDump) {
                warnings.append("Custom field \"\(key)\" could not be confirmed after save.")
            }
        }

        return warnings
    }

    nonisolated private static func rawPropertyMapWriteWarnings(
        requestedProperties: [String: String],
        for url: URL
    ) -> [String] {
        guard !requestedProperties.isEmpty else { return [] }
        guard let rawDump = rawMetadata(from: url) else {
            return ["Could not verify raw metadata write after save."]
        }

        var warnings: [String] = []
        let lookup = rawPropertiesLookup(rawDump)
        let riskyNumberKeys = Set([
            "TRACKNUMBER", "TRACK", "TRACKTOTAL", "TOTALTRACKS",
            "DISCNUMBER", "DISC", "DISCTOTAL", "TOTALDISCS"
        ])
        let riskyExplicitKeys = Set(["ITUNESADVISORY", "ADVISORY", "EXPLICITCONTENT", "EXPLICIT"])

        for (rawKey, rawValue) in requestedProperties {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            guard let persistedValues = lookup[key], !persistedValues.isEmpty else {
                warnings.append("Raw key \"\(rawKey)\" was not found after save.")
                continue
            }

            if riskyNumberKeys.contains(key) {
                let expectedPair = parseNumberPair(value)
                let pairMatched = persistedValues.contains { parseNumberPair($0) == expectedPair }
                if !pairMatched {
                    warnings.append("Raw number key \"\(rawKey)\" differs after save.")
                }
                continue
            }

            if riskyExplicitKeys.contains(key) {
                let normalizedPersisted = persistedValues.map { $0.uppercased() }
                if !normalizedPersisted.contains(value.uppercased()) {
                    warnings.append("Raw explicit key \"\(rawKey)\" differs after save.")
                }
                continue
            }

            if !persistedValues.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                warnings.append("Raw key \"\(rawKey)\" value changed after save.")
            }
        }

        return warnings
    }

    nonisolated private static func parsedPropertyEntries(fromDumpText text: String) -> [RawPropertyEntry] {
        var isInPropertiesSection = false
        var properties: [RawPropertyEntry] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") {
                if isInPropertiesSection {
                    break
                }

                isInPropertiesSection = (trimmedLine == "[TagLib Properties]")
                continue
            }

            guard isInPropertiesSection else { continue }
            guard !trimmedLine.isEmpty else { continue }

            if trimmedLine == "(none)" || trimmedLine.hasPrefix("(unable to open") {
                break
            }

            guard let separatorRange = trimmedLine.range(of: " = ") else { continue }

            let key = String(trimmedLine[..<separatorRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmedLine[separatorRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !isHiddenInternalRawFieldKey(key) else { continue }
            guard !key.isEmpty, !value.isEmpty else { continue }

            let values = value
                .components(separatedBy: "; ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            properties.append(
                RawPropertyEntry(
                    key: key,
                    value: value,
                    values: values,
                    count: values.count
                )
            )
        }

        return properties.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    // MARK: - Bridge Dump API

    /// Return a single plain-text dump of metadata as TagLib sees it.
    ///
    /// Preferred path: call the ObjC++ bridge API directly (Swift `throws`).
    /// Fallback path: attempt older single-argument selector names via `perform` for compatibility.
    nonisolated private static func bridgeTextDumpIfAvailable(for url: URL) -> String? {
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

    public nonisolated static func readMetadata(from url: URL) -> BasicMetadata? {
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

            var rawDump: RawMetadataDump?
            let rawNumberText: (track: String, disc: String)
            if needsTrackTextFallback || needsDiscTextFallback {
                rawDump = rawMetadata(from: url)
                rawNumberText = rawDump.map(rawNumberTexts(from:)) ?? (track: "", disc: "")
            } else {
                rawNumberText = (track: "", disc: "")
            }

            if case nil = rawDump {
                rawDump = rawMetadata(from: url)
            }

            var trackSource: MetadataValueSource =
                trackNumberText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (meta.trackNumber > 0 ? .derivedNumeric : .none)
                : .nativeTag

            var discSource: MetadataValueSource =
                discNumberText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (meta.discNumber > 0 ? .derivedNumeric : .none)
                : .nativeTag

            if needsTrackTextFallback,
               !rawNumberText.track.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                trackSource = .rawFallback
            }

            if needsDiscTextFallback,
               !rawNumberText.disc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                discSource = .rawFallback
            }

            let explicitSource = rawDump.map {
                explicitValueSource(from: $0, fallback: meta.explicitContent)
            } ?? (meta.explicitContent ? .nativeTag : .none)
            let artworkSource: MetadataValueSource = (meta.artworkData as Data?) == nil ? .none : .nativeTag

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
                itunesAlbumID: meta.itunesAlbumId ?? "",
                itunesArtistID: meta.itunesArtistId ?? "",
                itunesCatalogID: meta.itunesCatalogId ?? "",
                itunesGenreID: meta.itunesGenreId ?? "",
                itunesMediaType: meta.itunesMediaType ?? "",
                itunesPurchaseDate: meta.itunesPurchaseDate ?? "",
                itunesNorm: meta.itunesNorm ?? "",
                itunesSMPB: meta.itunesSmpb ?? "",
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
                customFields: meta.customFields ?? [:],
                provenance: MetadataFieldProvenance(
                    trackNumberText: trackSource,
                    discNumberText: discSource,
                    explicitContent: explicitSource,
                    artwork: artworkSource
                )
            )
        } catch {
            print("TagLib read error for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Write / Erase

    @discardableResult
    public nonisolated static func writeTagMetadata(
        _ metadata: TagLibAudioMetadata,
        to url: URL,
        verification: MetadataWriteVerificationContext = .none
    ) throws -> MetadataWriteResult {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, TagLibMetadataExtractor.isSupportedFormat(ext) else {
            throw TagLibManagerError.unsupportedFormat
        }

        try TagLibMetadataExtractor.writeMetadata(metadata, to: url)
        return MetadataWriteResult(
            warnings: metadataWriteWarnings(for: url, verification: verification)
        )
    }

    @discardableResult
    public nonisolated static func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool = true
    ) throws -> MetadataWriteResult {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, TagLibMetadataExtractor.isSupportedFormat(ext) else {
            throw TagLibManagerError.unsupportedFormat
        }

        try TagLibMetadataExtractor.writeTrackNumberText(
            trackNumberText,
            discNumberText: discNumberText,
            to: url
        )

        if !verifyAfterWrite {
            return MetadataWriteResult(warnings: [])
        }

        let expectedTrackPair = parseNumberPair(trackNumberText)
        let expectedDiscPair = parseNumberPair(normalizedTrimmed(discNumberText))

        return MetadataWriteResult(
            warnings: metadataWriteWarnings(
                for: url,
                verification: MetadataWriteVerificationContext(
                    expectedTrackNumber: expectedTrackPair.number > 0 ? expectedTrackPair.number : nil,
                    expectedTrackTotal: expectedTrackPair.total > 0 ? expectedTrackPair.total : nil,
                    expectedTrackNumberText: trackNumberText,
                    expectedDiscNumber: expectedDiscPair.number > 0 ? expectedDiscPair.number : nil,
                    expectedDiscTotal: expectedDiscPair.total > 0 ? expectedDiscPair.total : nil,
                    expectedDiscNumberText: discNumberText,
                    expectedExplicitContent: nil,
                    artworkExpectation: .unchanged,
                    customFieldKeys: []
                )
            )
        )
    }

    @discardableResult
    public nonisolated static func writeRawMetadataPropertyMapWithVerification(
        _ properties: [String: String],
        to url: URL,
        verifyAfterWrite: Bool = true
    ) throws -> MetadataWriteResult {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, TagLibMetadataExtractor.isSupportedFormat(ext) else {
            throw TagLibManagerError.unsupportedFormat
        }

        try TagLibMetadataExtractor.writeRawPropertyMap(properties, to: url)
        return MetadataWriteResult(
            warnings: verifyAfterWrite
                ? rawPropertyMapWriteWarnings(requestedProperties: properties, for: url)
                : []
        )
    }

    nonisolated private static func residualWarningsAfterErase(for url: URL) -> [String] {
        var warnings: [String] = []

        if let metadata = readMetadata(from: url) {
            var residualFields: [String] = []
            if !metadata.title.isEmpty { residualFields.append("TITLE") }
            if !metadata.artist.isEmpty { residualFields.append("ARTIST") }
            if !metadata.album.isEmpty { residualFields.append("ALBUM") }
            if !metadata.comment.isEmpty { residualFields.append("COMMENT") }
            if !metadata.genre.isEmpty { residualFields.append("GENRE") }
            if metadata.track > 0 || metadata.trackTotal > 0 { residualFields.append("TRACK") }
            if metadata.disc > 0 || metadata.discTotal > 0 { residualFields.append("DISC") }
            if metadata.artworkData != nil { residualFields.append("ARTWORK") }
            if !metadata.customFields.isEmpty { residualFields.append("CUSTOM") }

            if !residualFields.isEmpty {
                warnings.append(
                    "Some metadata fields still remain after erase: \(residualFields.joined(separator: ", "))."
                )
            }
        } else {
            warnings.append("Could not verify erase result by re-reading metadata.")
        }

        if let rawDump = rawMetadata(from: url) {
            let remainingKeys = rawDump.properties
                .map(\.key)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !isHiddenInternalRawFieldKey($0) && !$0.isEmpty }
                .sorted()

            if !remainingKeys.isEmpty {
                let preview = remainingKeys.prefix(8).joined(separator: ", ")
                warnings.append(
                    "Raw metadata still contains \(remainingKeys.count) key(s) after erase (\(preview)\(remainingKeys.count > 8 ? ", ..." : ""))."
                )
            }
        }

        return warnings
    }

    @discardableResult
    public nonisolated static func eraseAllMetadataWithVerification(from url: URL) throws -> MetadataWriteResult {
        let meta = TagLibAudioMetadata()
        meta.title = ""
        meta.artist = ""
        meta.album = ""
        meta.composer = ""
        meta.genre = ""
        meta.comment = ""
        meta.albumArtist = ""
        meta.year = ""
        meta.releaseDate = ""
        meta.originalReleaseDate = ""
        meta.label = ""
        meta.isrc = ""
        meta.barcode = ""
        meta.musicBrainzArtistId = ""
        meta.musicBrainzAlbumId = ""
        meta.musicBrainzTrackId = ""
        meta.musicBrainzReleaseGroupId = ""
        meta.lyricist = ""
        meta.remixer = ""
        meta.producer = ""
        meta.engineer = ""
        meta.language = ""
        meta.mediaType = ""
        meta.releaseType = ""
        meta.catalogNumber = ""
        meta.releaseCountry = ""
        meta.copyright = ""
        meta.trackNumber = 0
        meta.totalTracks = 0
        meta.discNumber = 0
        meta.totalDiscs = 0
        meta.trackNumberText = nil
        meta.discNumberText = nil
        meta.explicitContent = false
        meta.removeArtwork = true
        meta.customFields = nil

        var warnings: [String] = []
        warnings.append(
            contentsOf: try writeTagMetadata(
                meta,
                to: url,
                verification: MetadataWriteVerificationContext(
                    expectedTrackNumber: nil,
                    expectedTrackTotal: nil,
                    expectedTrackNumberText: nil,
                    expectedDiscNumber: nil,
                    expectedDiscTotal: nil,
                    expectedDiscNumberText: nil,
                    expectedExplicitContent: false,
                    artworkExpectation: .absent,
                    customFieldKeys: []
                )
            ).warnings
        )

        warnings.append(
            contentsOf: try writeRawMetadataPropertyMapWithVerification(
                [:],
                to: url,
                verifyAfterWrite: false
            ).warnings
        )

        warnings.append(contentsOf: residualWarningsAfterErase(for: url))
        return MetadataWriteResult(warnings: warnings)
    }

    /// Write `BasicMetadata` back to the file using TagLib.
    ///
    /// Notes:
    /// - This is intended for formats supported by our TagLib bridge's write paths.
    /// - Fields that are empty strings are written as `nil` (i.e. removed/cleared).
    /// - `publisher` is mapped to TagLib's `label` field.
    @discardableResult
    public nonisolated static func writeMetadata(_ meta: BasicMetadata, to url: URL) throws -> Bool {
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
        m.itunesAlbumId = nilIfEmpty(meta.itunesAlbumID)
        m.itunesArtistId = nilIfEmpty(meta.itunesArtistID)
        m.itunesCatalogId = nilIfEmpty(meta.itunesCatalogID)
        m.itunesGenreId = nilIfEmpty(meta.itunesGenreID)
        m.itunesMediaType = nilIfEmpty(meta.itunesMediaType)
        m.itunesPurchaseDate = nilIfEmpty(meta.itunesPurchaseDate)
        m.itunesNorm = nilIfEmpty(meta.itunesNorm)
        m.itunesSmpb = nilIfEmpty(meta.itunesSMPB)
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

        // Persist through the write coordinator so all metadata entry points
        // share post-write verification policy.
        let result = try writeTagMetadata(
            m,
            to: url,
            verification: MetadataWriteVerificationContext(
                expectedTrackNumber: meta.track,
                expectedTrackTotal: meta.trackTotal,
                expectedTrackNumberText: meta.trackNumberText,
                expectedDiscNumber: meta.disc,
                expectedDiscTotal: meta.discTotal,
                expectedDiscNumberText: meta.discNumberText,
                expectedExplicitContent: meta.isExplicit,
                artworkExpectation: .unchanged,
                customFieldKeys: Array(meta.customFields.keys)
            )
        )
        if !result.warnings.isEmpty {
            print("[AudioMator] Metadata write warnings for \(url.lastPathComponent): \(result.warnings.joined(separator: " | "))")
        }
        return true
    }

    @discardableResult
    public nonisolated static func writeRawMetadataPropertyMap(_ properties: [String: String], to url: URL) throws -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, TagLibMetadataExtractor.isSupportedFormat(ext) else {
            throw TagLibManagerError.unsupportedFormat
        }

        let result = try writeRawMetadataPropertyMapWithVerification(properties, to: url)
        if !result.warnings.isEmpty {
            print("[AudioMator] Raw metadata write warnings for \(url.lastPathComponent): \(result.warnings.joined(separator: " | "))")
        }
        return true
    }

    /// Remove (as much as TagLib allows) all metadata from a file.
    ///
    /// Implementation strategy: write an empty `TagLibAudioMetadata` object.
    /// This should clear the common tag fields and reset numeric fields to 0.
    @discardableResult
    public nonisolated static func eraseAllMetadata(from url: URL) throws -> Bool {
        let result = try eraseAllMetadataWithVerification(from: url)
        if !result.warnings.isEmpty {
            print("[AudioMator] Erase warnings for \(url.lastPathComponent): \(result.warnings.joined(separator: " | "))")
        }
        return true
    }

    /// Raw metadata dump for GUI inspection ("show me everything TagLib sees").
    ///
    /// The extractor returns a dictionary with stable keys:
    /// - "properties": unified TagLib PropertyMap entries
    /// - "id3v2Frames": ID3v2 frames (MP3 only)
    ///
    /// Returns `nil` if format is not supported by TagLib in this app.
    public nonisolated static func rawMetadata(from url: URL) -> RawMetadataDump? {
        try? rawMetadataResult(from: url)
    }

    public nonisolated static func rawMetadataResult(from url: URL) throws -> RawMetadataDump {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else {
            throw TagLibManagerError.unsupportedFormat
        }

        guard TagLibMetadataExtractor.isSupportedFormat(ext) else {
            throw TagLibManagerError.unsupportedFormat
        }

        // ObjC++ returns a Foundation dictionary for display; normalize it into Swift models.
        let dict = try TagLibMetadataExtractor.rawMetadata(for: url)

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

            guard !isHiddenInternalRawFieldKey(key) else { return nil }

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

        if !properties.isEmpty {
            return RawMetadataDump(properties: properties, id3v2Frames: id3v2Frames)
        }

        if let dumpText = try? TagLibMetadataExtractor.dumpMetadataText(from: url) {
            let fallbackProperties = parsedPropertyEntries(fromDumpText: dumpText)
            if !fallbackProperties.isEmpty {
                return RawMetadataDump(properties: fallbackProperties, id3v2Frames: id3v2Frames)
            }
        }

        return RawMetadataDump(properties: properties, id3v2Frames: id3v2Frames)
    }

    /// Formats *raw* metadata (as seen by TagLib) into a single text blob for GUI display.
    ///
    /// This is intentionally **not** the same as the structured fields shown in the right inspector.
    /// It surfaces:
    /// - TagLib `PropertyMap` entries (including multi-value fields)
    /// - ID3v2 frames (MP3 only), including TXXX/COMM details when available
    public nonisolated static func rawMetadataText(from url: URL) -> String? {
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
