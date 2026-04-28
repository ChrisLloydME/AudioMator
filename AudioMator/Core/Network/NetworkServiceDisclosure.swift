import Foundation

enum NetworkServiceDisclosure {
    enum ITunesArtwork {
        static let searchHost = "itunes.apple.com"
        static let highResolutionArtworkHost = "is5-ssl.mzstatic.com"
        static let uncompressedArtworkHost = "a5.mzstatic.com"

        static let domains = [
            searchHost,
            highResolutionArtworkHost,
            uncompressedArtworkHost
        ]

        static let sentDataSummary = "Artwork lookup may send search terms derived from metadata or user input, such as iTunes Album ID, album, artist, title, and manually entered searches."
    }

    enum MusicBrainz {
        static let host = "musicbrainz.org"
        static let webHost = "www.musicbrainz.org"
        static let webBaseURLString = "https://\(host)"

        static let domains = [
            host
        ]

        static let acceptedLinkDomains = [
            host,
            webHost
        ]

        static let sentDataSummary = "MusicBrainz lookup may send metadata-derived queries or identifiers, including title, artist, album, album artist, track number, duration, release identifiers, ISRC, barcode, and manually entered search terms or links."

        static func webURL(path: String) -> URL? {
            URL(string: "\(webBaseURLString)\(path)")
        }
    }

    enum ReleaseNotes {
        static let host = "api.github.com"
    }
}
