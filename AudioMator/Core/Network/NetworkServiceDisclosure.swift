import Foundation

enum NetworkServiceDisclosure {
    struct Entry: Identifiable, Equatable {
        enum ID: String, CaseIterable {
            case iTunesArtwork
            case musicBrainz
            case lrclib
            case releaseNotes
            case softwareUpdates
        }

        let id: ID
        let title: String
        let domains: [String]
        let sentDataSummary: String
        let purpose: String
        var hostLabel: String {
            "Target host\(domains.count == 1 ? "" : "s"): \(domains.joined(separator: ", "))"
        }
    }

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
        static let sentDataSummary = "Release-note requests send standard request headers and request the published release list. No audio file content is sent."
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

    static let allDisclosures: [Entry] = [
        Entry(
            id: .iTunesArtwork,
            title: "iTunes Search API and artwork lookup",
            domains: iTunesArtwork.domains,
            sentDataSummary: iTunesArtwork.sentDataSummary,
            purpose: "Searching Apple catalog metadata, reviewing album and track results, preparing selected metadata writes, previewing artwork, downloading selected artwork, and applying chosen values locally."
        ),
        Entry(
            id: .musicBrainz,
            title: "MusicBrainz browser and search",
            domains: MusicBrainz.domains,
            sentDataSummary: MusicBrainz.sentDataSummary,
            purpose: "Searching, reviewing, and applying MusicBrainz metadata."
        ),
        Entry(
            id: .lrclib,
            title: "LRCLIB lyrics search",
            domains: LRCLIB.domains,
            sentDataSummary: LRCLIB.sentDataSummary,
            purpose: "Searching for synced lyrics, reviewing matches, and applying selected lyrics locally."
        ),
        Entry(
            id: .releaseNotes,
            title: "Release notes",
            domains: [ReleaseNotes.host],
            sentDataSummary: ReleaseNotes.sentDataSummary,
            purpose: "Loading published AudioMator release notes."
        ),
        Entry(
            id: .softwareUpdates,
            title: "Software update checks",
            domains: SoftwareUpdates.domains,
            sentDataSummary: SoftwareUpdates.sentDataSummary,
            purpose: "Detecting whether a newer AudioMator release exists and opening GitHub Releases when you choose to download it manually. AudioMator does not silently install updates in this lightweight update flow."
        ),
    ]
}
