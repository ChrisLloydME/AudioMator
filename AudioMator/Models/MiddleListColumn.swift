import Foundation

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
        case .filename:
            return "Filename"
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .album:
            return "Album"
        case .albumArtist:
            return "Album Artist"
        case .composer:
            return "Composer"
        case .genre:
            return "Genre"
        case .year:
            return "Year"
        case .track:
            return "Track"
        case .disc:
            return "Disc"
        case .comment:
            return "Comment"
        case .releaseDate:
            return "Release Date"
        case .publisher:
            return "Publisher"
        case .copyright:
            return "Copyright"
        case .credits:
            return "Credits"
        case .explicit:
            return "Explicit"
        case .duration:
            return "Duration"
        case .bitrate:
            return "Bitrate"
        case .sampleRate:
            return "Sample Rate"
        case .channels:
            return "Channels"
        case .format:
            return "Format"
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
            return file.isExplicit ? "Yes" : "No"
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
}
