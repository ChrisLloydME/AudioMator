import Foundation

enum NetworkServiceDisclosure {
    struct Entry: Identifiable, Equatable {
        enum ID: String, CaseIterable {
            case iTunesArtwork
            case musicBrainz
            case lrclib
            case releaseNotes
            case softwareUpdates
            case providerWebPages
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

        static let sentDataSummary = "iTunes lookup may send search terms derived from tags, filenames, parent folder names, or user input, such as title, artist, album, album artist, UPC/barcode, an iTunes album or track ID, a pasted Apple Music or iTunes link, storefront country, or a manually entered search. Artwork downloads use Apple-returned artwork URLs, so Apple may direct the app to an Apple artwork host beyond the hosts listed here."
    }

    enum MusicBrainz {
        nonisolated static let host = "musicbrainz.org"
        nonisolated static let webHost = "www.musicbrainz.org"
        nonisolated static let webBaseURLString = "https://\(host)"

        static let domains = [
            host
        ]

        nonisolated static let acceptedLinkDomains = [
            host,
            webHost
        ]

        static let sentDataSummary = "MusicBrainz lookup may send queries or identifiers derived from tags, filenames, parent folder names, or user input, including title, artist, album, album artist, track number, duration, release identifiers, ISRC, barcode, MusicBrainz IDs, and manually entered search terms or links."

        nonisolated static func webURL(path: String) -> URL? {
            URL(string: "\(webBaseURLString)\(path)")
        }
    }

    enum LRCLIB {
        static let host = "lrclib.net"

        static let domains = [
            host
        ]

        static let sentDataSummary = "LRCLIB lookup may send queries derived from tags, filenames, or user input, including title, artist, album, and duration, to search for synced lyrics."
    }

    enum ProviderWebPages {
        nonisolated static let allowedHostSuffixes = ["apple.com", "musicbrainz.org"]
        static let sentDataSummary = String(localized: "Opening a provider page sends its URL and standard browser requests to Apple or MusicBrainz, including their subdomains. Embedded pages use non-persistent browser storage. Their images, scripts, and other subresources may contact additional hosts; the page navigation allow-list does not filter subresources.")
    }

    enum ReleaseNotes {
        static let host = "api.github.com"
        static let sentDataSummary = "Release-note requests send standard request headers and request the published release list. No audio file content is sent."
    }

    enum SoftwareUpdates {
        static let host = "api.github.com"
        static let releasesPageHost = "github.com"

        // github.com is opened in the user's browser, not requested by the app.
        static let domains = [
            host
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
            id: .providerWebPages,
            title: String(localized: "Embedded provider pages"),
            domains: ProviderWebPages.allowedHostSuffixes,
            sentDataSummary: ProviderWebPages.sentDataSummary,
            purpose: String(localized: "Viewing selected Apple Music, iTunes, and MusicBrainz pages. HTTPS page navigation is limited to these domains and their subdomains.")
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
