import AppKit

struct PendingArtwork {
    var image: NSImage
    var data: Data
    var mimeType: String
}

enum ArtworkEditAction {
    case unchanged
    case replace(PendingArtwork)
    case remove
}

struct SingleFileEditModel {
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
    var trackNumberText: String   // e.g. "1" / "01" / "01/10" (TRCK)
    var discNumberText: String    // e.g. "1" / "1/2" (TPOS)
    var albumArtist: String
    var releaseDate: String
    var publisher: String
    var copyright: String
    var isExplicit: Bool
    var artworkEditAction: ArtworkEditAction

    init(
        title: String = "",
        artist: String = "",
        album: String = "",
        composer: String = "",
        genre: String = "",
        comment: String = "",
        track: Int = 0,
        trackTotal: Int = 0,
        disc: Int = 0,
        discTotal: Int = 0,
        year: String = "",
        trackNumberText: String = "",
        discNumberText: String = "",
        albumArtist: String = "",
        releaseDate: String = "",
        publisher: String = "",
        copyright: String = "",
        isExplicit: Bool = false,
        artworkEditAction: ArtworkEditAction = .unchanged
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.composer = composer
        self.genre = genre
        self.comment = comment
        self.track = track
        self.trackTotal = trackTotal
        self.disc = disc
        self.discTotal = discTotal
        self.year = year
        self.trackNumberText = trackNumberText
        self.discNumberText = discNumberText
        self.albumArtist = albumArtist
        self.releaseDate = releaseDate
        self.publisher = publisher
        self.copyright = copyright
        self.isExplicit = isExplicit
        self.artworkEditAction = artworkEditAction
    }

    init(from file: AudioFile) {
        self.init(
            title: file.title,
            artist: file.artist,
            album: file.album,
            composer: file.composer,
            genre: file.genre,
            comment: file.comment,
            track: file.track,
            trackTotal: file.trackTotal,
            disc: file.disc,
            discTotal: file.discTotal,
            year: file.year,
            trackNumberText: file.track > 0 ? (file.trackTotal > 0 ? "\(file.track)/\(file.trackTotal)" : "\(file.track)") : "",
            discNumberText: file.disc > 0 ? (file.discTotal > 0 ? "\(file.disc)/\(file.discTotal)" : "\(file.disc)") : "",
            albumArtist: file.albumArtist,
            releaseDate: file.releaseDate,
            publisher: file.publisher,
            copyright: file.copyright,
            isExplicit: file.isExplicit
        )
    }
}
