import Foundation
import TagLibAudioMetadata

enum MiddleListColumn: String, CaseIterable, Identifiable {
    case filename
    case title
    case artist
    case album
    case albumArtist
    case composer
    case genre
    case year
    case track
    case disc
    case comment
    case releaseDate
    case publisher
    case copyright
    case credits
    case explicit
    case duration
    case bitrate
    case sampleRate
    case channels
    case format

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filename: return L10n.string("Filename")
        case .title: return MetadataFieldGuide.displayName(for: .title)
        case .artist: return MetadataFieldGuide.displayName(for: .artist)
        case .album: return MetadataFieldGuide.displayName(for: .album)
        case .albumArtist: return MetadataFieldGuide.displayName(for: .albumArtist)
        case .composer: return MetadataFieldGuide.displayName(for: .composer)
        case .genre: return MetadataFieldGuide.displayName(for: .genre)
        case .year: return MetadataFieldGuide.displayName(for: .year)
        case .track: return MetadataFieldGuide.displayName(for: .track)
        case .disc: return MetadataFieldGuide.displayName(for: .disc)
        case .comment: return MetadataFieldGuide.displayName(for: .comment)
        case .releaseDate: return MetadataFieldGuide.displayName(for: .releaseDate)
        case .publisher: return MetadataFieldGuide.displayName(for: .publisher)
        case .copyright: return MetadataFieldGuide.displayName(for: .copyright)
        case .explicit: return MetadataFieldGuide.displayName(for: .explicitContent)
        case .credits: return MetadataFieldGuide.displayName(forReadOnlyField: "credits")
        case .duration: return MetadataFieldGuide.displayName(forReadOnlyField: "duration")
        case .bitrate: return MetadataFieldGuide.displayName(forReadOnlyField: "bitrate")
        case .sampleRate: return MetadataFieldGuide.displayName(forReadOnlyField: "sampleRate")
        case .channels: return MetadataFieldGuide.displayName(forReadOnlyField: "channels")
        case .format: return MetadataFieldGuide.displayName(forReadOnlyField: "format")
        }
    }

    static let defaultVisibleColumns: [MiddleListColumn] = [
        .filename,
        .title,
        .artist,
        .album,
        .duration
    ]

    func text(for file: AudioFile) -> String {
        switch self {
        case .filename:
            return file.url.lastPathComponent
        case .title:
            return file.title
        case .artist:
            return file.artist
        case .album:
            return file.album
        case .albumArtist:
            return file.albumArtist
        case .composer:
            return file.composer
        case .genre:
            return file.genre
        case .year:
            return file.year
        case .track:
            return file.trackNumberText.isEmpty
                ? formatTrackIndex(file.track, total: file.trackTotal)
                : file.trackNumberText
        case .disc:
            return file.discNumberText.isEmpty
                ? formatTrackIndex(file.disc, total: file.discTotal)
                : file.discNumberText
        case .comment:
            return file.comment
        case .releaseDate:
            return file.releaseDate
        case .publisher:
            return file.publisher
        case .copyright:
            return file.copyright
        case .credits:
            return file.credits
        case .explicit:
            return file.contentAdvisory?.displayName ?? ""
        case .duration:
            return formatDuration(file.duration)
        case .bitrate:
            return formatBitrate(file.bitrate)
        case .sampleRate:
            return formatSampleRate(file.sampleRate)
        case .channels:
            return formatChannelCount(file.channels)
        case .format:
            return file.format
        }
    }

    func compare(_ lhs: AudioFile, _ rhs: AudioFile) -> ComparisonResult {
        switch self {
        case .filename:
            return compareText(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
        case .title:
            return compareText(lhs.title, rhs.title)
        case .artist:
            return compareText(lhs.artist, rhs.artist)
        case .album:
            return compareText(lhs.album, rhs.album)
        case .albumArtist:
            return compareText(lhs.albumArtist, rhs.albumArtist)
        case .composer:
            return compareText(lhs.composer, rhs.composer)
        case .genre:
            return compareText(lhs.genre, rhs.genre)
        case .year:
            return compareText(lhs.year, rhs.year)
        case .track:
            return compareTrackIndex(
                number: lhs.track,
                total: lhs.trackTotal,
                rawText: lhs.trackNumberText,
                againstNumber: rhs.track,
                againstTotal: rhs.trackTotal,
                againstRawText: rhs.trackNumberText
            )
        case .disc:
            return compareTrackIndex(
                number: lhs.disc,
                total: lhs.discTotal,
                rawText: lhs.discNumberText,
                againstNumber: rhs.disc,
                againstTotal: rhs.discTotal,
                againstRawText: rhs.discNumberText
            )
        case .comment:
            return compareText(lhs.comment, rhs.comment)
        case .releaseDate:
            return compareText(lhs.releaseDate, rhs.releaseDate)
        case .publisher:
            return compareText(lhs.publisher, rhs.publisher)
        case .copyright:
            return compareText(lhs.copyright, rhs.copyright)
        case .credits:
            return compareText(lhs.credits, rhs.credits)
        case .explicit:
            return compareInt(lhs.contentAdvisory?.rawValue ?? -1, rhs.contentAdvisory?.rawValue ?? -1)
        case .duration:
            return compareDouble(lhs.duration, rhs.duration)
        case .bitrate:
            return compareInt(lhs.bitrate, rhs.bitrate)
        case .sampleRate:
            return compareDouble(lhs.sampleRate, rhs.sampleRate)
        case .channels:
            return compareInt(lhs.channels, rhs.channels)
        case .format:
            return compareText(lhs.format, rhs.format)
        }
    }

    private func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }

    private func compareInt(_ lhs: Int, _ rhs: Int) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private func compareDouble(_ lhs: Double, _ rhs: Double) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private func compareBool(_ lhs: Bool, _ rhs: Bool) -> ComparisonResult {
        compareInt(lhs ? 1 : 0, rhs ? 1 : 0)
    }

    private func compareTrackIndex(
        number lhsNumber: Int,
        total lhsTotal: Int,
        rawText lhsRawText: String,
        againstNumber rhsNumber: Int,
        againstTotal rhsTotal: Int,
        againstRawText rhsRawText: String
    ) -> ComparisonResult {
        let numberResult = compareInt(lhsNumber, rhsNumber)
        if numberResult != .orderedSame {
            return numberResult
        }

        let totalResult = compareInt(lhsTotal, rhsTotal)
        if totalResult != .orderedSame {
            return totalResult
        }

        return compareText(lhsRawText, rhsRawText)
    }
}
