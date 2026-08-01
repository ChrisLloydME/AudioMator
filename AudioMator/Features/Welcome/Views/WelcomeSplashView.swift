import SwiftUI

struct WelcomeSplashView: View {
    let onQuit: () -> Void
    let onContinue: () -> Void
    let initialFileAccessGrantPath: String?
    let onAuthorizeFileAccess: () -> FileAccessAuthorizationOutcome

    var body: some View {
        #if os(macOS)
        MacWelcomeSplashView(
            onQuit: onQuit,
            onContinue: onContinue,
            initialFileAccessGrantPath: initialFileAccessGrantPath,
            onAuthorizeFileAccess: onAuthorizeFileAccess
        )
            .frame(width: 750, height: 700)
        #else
        SwiftUIWelcomeSplashView(onQuit: onQuit, onContinue: onContinue)
        #endif
    }
}

struct WelcomeSplashPageContent: Identifiable {
    let page: WelcomeSplashPage
    let title: String
    let subtitle: String
    let rows: [WelcomeSplashRowContent]
    var topPadding: CGFloat = 8

    var id: WelcomeSplashPage { page }
}

struct WelcomeSplashRowContent: Identifiable {
    let symbol: String
    let title: String
    let description: String

    var id: String { "\(symbol)-\(title)" }
}

enum WelcomeSplashPage: Int, CaseIterable {
    case welcome
    case features
    #if os(macOS)
    case fileAccess
    #endif
    case onlineMetadata
    case artwork
    case privacy

    var next: WelcomeSplashPage? {
        WelcomeSplashPage(rawValue: rawValue + 1)
    }

    var previous: WelcomeSplashPage? {
        WelcomeSplashPage(rawValue: rawValue - 1)
    }

    var content: WelcomeSplashPageContent {
        switch self {
        case .welcome:
            WelcomeSplashPageContent(
                page: self,
                title: "Welcome to AudioMator",
                subtitle: "Inspect, clean up, and rewrite audio metadata on \(Self.platformDeviceName).",
                rows: [
                    WelcomeSplashRowContent(
                        symbol: "music.note",
                        title: "Edit metadata on \(Self.platformDeviceName)",
                        description: "Open the tracks you want and work locally."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "wand.and.stars",
                        title: "Review tags quickly",
                        description: "Spot important fields fast and make precise fixes."
                    ),
                    WelcomeSplashRowContent(
                        symbol: Self.platformNativeSymbol,
                        title: "Feels native on \(Self.platformName)",
                        description: "Uses familiar windows, sheets, and inspectors."
                    )
                ],
                topPadding: 0
            )
        case .features:
            WelcomeSplashPageContent(
                page: self,
                title: "What You Can Do",
                subtitle: "Bring in tracks, inspect tags, make precise changes, and save when you're ready.",
                rows: [
                    WelcomeSplashRowContent(
                        symbol: "music.note.list",
                        title: "Choose one-time or watched sources",
                        description: "Use Current Session for one-off work, or add watched folders for later."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "slider.horizontal.3",
                        title: "Inspect and edit metadata",
                        description: "Review tags, compare selections, and check raw metadata before saving."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "square.stack.3d.down.right",
                        title: "Use batch utilities",
                        description: "Reorder files, renumber tracks, copy paths, reveal files, or clear tags."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "photo.on.rectangle.angled",
                        title: "Work with artwork",
                        description: "Replace, remove, preview, and apply album artwork from the inspector."
                    )
                ]
            )
        #if os(macOS)
        case .fileAccess:
            WelcomeSplashPageContent(
                page: self,
                title: String(localized: "Protect Your Files While Saving"),
                subtitle: String(
                    localized: "AudioMator uses transactional saves to reduce the chance that a failed operation leaves an audio file partially written."
                ),
                rows: []
            )
        #endif
        case .onlineMetadata:
            WelcomeSplashPageContent(
                page: self,
                title: "Match Online Metadata",
                subtitle: "Search MusicBrainz, iTunes, and LRCLIB, compare candidates, and apply only the details you choose.",
                rows: [
                    WelcomeSplashRowContent(
                        symbol: "magnifyingglass",
                        title: "Search from selected files",
                        description: "Start with existing track metadata, IDs, links, filenames, or your own search terms."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "list.bullet.rectangle",
                        title: "Review before applying",
                        description: "Check MusicBrainz releases, iTunes catalog matches, and LRCLIB synced lyrics before they change your files."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "square.and.arrow.down",
                        title: "Apply metadata when ready",
                        description: "Write matched titles, artists, album details, dates, identifiers, artwork, and lyrics."
                    )
                ]
            )
        case .artwork:
            WelcomeSplashPageContent(
                page: self,
                title: "Find Album Artwork",
                subtitle: "Use iTunes artwork lookup to find covers, preview them, and apply the selected image.",
                rows: [
                    WelcomeSplashRowContent(
                        symbol: "magnifyingglass.circle",
                        title: "Find covers online",
                        description: "Search from album details, an iTunes Album ID, or your own artwork search terms."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "rectangle.on.rectangle",
                        title: "Preview the result",
                        description: "Compare available artwork before choosing what to use."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "checkmark.rectangle.stack",
                        title: "Apply to selected files",
                        description: "Save selected artwork into supported audio files with your metadata edits."
                    )
                ]
            )
        case .privacy:
            WelcomeSplashPageContent(
                page: self,
                title: "Privacy & Network Access",
                subtitle: "AudioMator edits files locally. Online services are contacted only when you use lookup or update-checking features.",
                rows: [
                    WelcomeSplashRowContent(
                        symbol: "internaldrive",
                        title: "Your audio stays local",
                        description: "AudioMator reads and writes the files you choose. Lookup features do not upload audio file contents."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "text.magnifyingglass",
                        title: "Lookup sends search details",
                        description: "MusicBrainz, iTunes, and LRCLIB searches may use metadata such as title, artist, album, track number, duration, identifiers, links, lyrics, or text you enter."
                    ),
                    WelcomeSplashRowContent(
                        symbol: "network",
                        title: "External services",
                        description: "Lookups may contact MusicBrainz, Apple iTunes Search API, Apple artwork CDN, LRCLIB, or related services. Manual update checks may contact GitHub Releases for AudioMator release/version information."
                    )
                ]
            )
        }
    }

    private static var platformDeviceName: String {
        #if os(macOS)
        "your Mac"
        #else
        "your iPad"
        #endif
    }

    private static var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iPadOS"
        #endif
    }

    private static var platformNativeSymbol: String {
        #if os(macOS)
        "macwindow"
        #else
        "ipad"
        #endif
    }
}
