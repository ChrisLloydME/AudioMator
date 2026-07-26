import Foundation

enum NetworkServiceDisclosure {
    enum iTunesArtwork {
        static let searchHost = "itunes.apple.com"
        static let highResolutionArtworkHost = "is5-ssl.mzstatic.com"
        static let uncompressedArtworkHost = "a5.mzstatic.com"

        static let domains = [
            searchHost,
            highResolutionArtworkHost,
            uncompressedArtworkHost
        ]

        static let sentDataSummary = "iTunes lookup may send search terms derived from metadata or user input, such as title, artist, album, album artist, track number, duration, UPC/barcode, iTunes store IDs, pasted Apple Music or iTunes links, and manually entered searches."
    }

    enum MusicBrainz {
        nonisolated static let host = "musicbrainz.org"
        static let webHost = "www.musicbrainz.org"
        nonisolated static let webBaseURLString = "https://\(host)"

        static let domains = [
            host
        ]

        nonisolated static let acceptedLinkDomains = [
            host,
            webHost
        ]

        static let sentDataSummary = "MusicBrainz lookup may send metadata-derived queries or identifiers, including title, artist, album, album artist, track number, duration, release identifiers, ISRC, barcode, and manually entered search terms or links."

        nonisolated static func webURL(path: String) -> URL? {
            URL(string: "\(webBaseURLString)\(path)")
        }
    }

    enum LRCLIB {
        static let host = "lrclib.net"

        static let domains = [
            host
        ]

        static let sentDataSummary = "LRCLIB lookup may send metadata-derived queries, including title, artist, album, and duration, to search for synced lyrics."
    }

    enum ReleaseNotes {
        static let host = "api.github.com"
    }

    enum SoftwareUpdates {
        static let host = "api.github.com"
        static let releasesPageHost = "github.com"

        static let domains = [
            host,
            releasesPageHost
        ]

        static let sentDataSummary = "Update checks request AudioMator release/version metadata from GitHub Releases. No audio file content is sent."
    }
}
