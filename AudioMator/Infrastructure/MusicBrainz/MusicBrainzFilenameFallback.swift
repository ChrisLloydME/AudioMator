import Foundation

struct MusicBrainzFilenameFallback {
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let trackNumber: String
    let discNumber: String
}

enum MusicBrainzFilenameFallbackResolver {
    private static let discDirectoryPattern = #"\b(?:CD|DVD|Disc)\s*(\d+)\b"#
    private static let explicitTrackPrefixPattern = #"(?i)^track[\s_-]*(?:(?:no|nr)\.?)?[\s_-]*0*(\d+)(?:[\s._-]+(.+))?$"#
    private static let leadingTrackPattern = #"^(?:\d+[\s_-]+)?0*(\d{1,3})(?:\.(?=[^0-9])|[)\]]|[\s_-])+\s*(.+)$"#

    static func makeSearchInput(for file: AudioFile) -> MusicBrainzFileSearchInput {
        let fallback = resolve(for: file)

        return MusicBrainzFileSearchInput(
            id: file.id.uuidString,
            displayTitle: file.title.isEmpty ? file.url.lastPathComponent : file.title,
            title: fallback.title,
            artist: fallback.artist,
            albumArtist: fallback.albumArtist,
            album: fallback.album,
            trackNumber: fallback.trackNumber,
            discNumber: fallback.discNumber,
            trackTotal: file.trackTotal,
            durationMilliseconds: file.duration.isFinite && file.duration > 0
                ? Int((file.duration * 1000).rounded())
                : nil,
            releaseDate: file.releaseDate.isEmpty ? file.year : file.releaseDate,
            isrc: file.isrc,
            barcode: file.barcode,
            musicBrainzAlbumID: file.musicBrainzAlbumID,
            musicBrainzTrackID: file.musicBrainzTrackID
        )
    }

    static func resolve(for file: AudioFile) -> MusicBrainzFilenameFallback {
        let guessedTrackAndTitle = guessedTrackAndTitle(from: file.url)
        let pathFallback = guessedAlbumArtistAndDisc(from: file.url)

        let albumArtist = preferredValue(file.albumArtist, fallback: pathFallback.albumArtist)
        let artist = preferredValue(file.artist, fallback: albumArtist)

        return MusicBrainzFilenameFallback(
            title: preferredValue(file.title, fallback: guessedTrackAndTitle.title),
            artist: artist,
            albumArtist: albumArtist,
            album: preferredValue(file.album, fallback: pathFallback.album),
            trackNumber: preferredValue(file.trackNumberText, fallback: guessedTrackAndTitle.trackNumber),
            discNumber: preferredValue(file.discNumberText, fallback: pathFallback.discNumber)
        )
    }

    private static func guessedTrackAndTitle(from url: URL) -> (trackNumber: String, title: String) {
        let baseName = url.deletingPathExtension().lastPathComponent
        let normalizedBaseName = normalizedFilenameComponent(baseName)

        if let match = firstMatch(
            in: normalizedBaseName,
            patterns: [explicitTrackPrefixPattern, leadingTrackPattern]
        ) {
            let trackNumber = normalizedTrackNumber(match.number)
            let title = cleanedTitle(match.title.isEmpty ? normalizedBaseName : match.title)

            if !trackNumber.isEmpty || !title.isEmpty {
                return (
                    trackNumber,
                    title.isEmpty ? normalizedBaseName : title
                )
            }
        }

        return ("", normalizedBaseName)
    }

    private static func guessedAlbumArtistAndDisc(from url: URL) -> (album: String, albumArtist: String, discNumber: String) {
        var directories = url
            .deletingLastPathComponent()
            .pathComponents
            .filter { $0 != "/" }

        var discNumber = ""
        if let lastDirectory = directories.last,
           let discMatch = firstCapturedGroup(in: lastDirectory, pattern: discDirectoryPattern) {
            discNumber = normalizedTrackNumber(discMatch)
            directories.removeLast()
        }

        guard let lastDirectory = directories.last else {
            return ("", "", discNumber)
        }

        let cleanedAlbumCandidate = cleanedTitle(lastDirectory)
        if let separatorRange = cleanedAlbumCandidate.range(of: " - ") {
            let artist = cleanedTitle(String(cleanedAlbumCandidate[..<separatorRange.lowerBound]))
            let album = cleanedTitle(String(cleanedAlbumCandidate[separatorRange.upperBound...]))
            return (album, artist, discNumber)
        }

        let artist = directories.count >= 2 ? cleanedTitle(directories[directories.count - 2]) : ""
        return (cleanedAlbumCandidate, artist, discNumber)
    }

    private static func preferredValue(_ primary: String, fallback: String) -> String {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrimary.isEmpty {
            return trimmedPrimary
        }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedFilenameComponent(_ value: String) -> String {
        cleanedTitle(
            value.replacingOccurrences(of: "_", with: " ")
        )
    }

    private static func cleanedTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTrackNumber(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let stripped = trimmed.drop { $0 == "0" }
        let candidate = stripped.isEmpty ? "0" : String(stripped)

        guard let value = Int(candidate), value > 0, value < 1900 else {
            return ""
        }

        return String(value)
    }

    private static func firstMatch(
        in value: String,
        patterns: [String]
    ) -> (number: String, title: String)? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, range: range) else { continue }

            let number = string(from: value, match: match, group: 1)
            let title = string(from: value, match: match, group: 2)
            return (number, title)
        }

        return nil
    }

    private static func firstCapturedGroup(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range) else {
            return nil
        }

        let result = string(from: value, match: match, group: 1)
        return result.isEmpty ? nil : result
    }

    private static func string(from value: String, match: NSTextCheckingResult, group: Int) -> String {
        guard group < match.numberOfRanges else { return "" }
        let nsRange = match.range(at: group)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: value) else {
            return ""
        }
        return String(value[range])
    }
}
