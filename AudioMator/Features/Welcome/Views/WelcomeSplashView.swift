import SwiftUI

struct WelcomeSplashView: View {
    let onQuit: () -> Void
    let onContinue: () -> Void

    @State private var currentPage: WelcomeSplashPage = .welcome
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            HStack {
                if currentPage == .welcome {
                    Button(platformCancelTitle) {
                        platformCancelAction()
                    }
                    .buttonStyle(GlassActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("Back") {
                        retreat()
                    }
                    .buttonStyle(GlassActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }

                Spacer()

                Button(currentPage.next == nil ? "Get Started" : "Continue") {
                    advance()
                }
                .buttonStyle(GlassActionButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 30)
        .frame(
            minWidth: minimumWidth,
            idealWidth: 750,
            maxWidth: maximumWidth,
            minHeight: minimumHeight,
            idealHeight: 700,
            maxHeight: maximumHeight
        )
        #if os(iOS)
        .background(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        #endif
        .animation(.easeInOut(duration: 0.18), value: currentPage)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .welcome:
            WelcomePage()
        case .features:
            FeaturesPage()
        case .musicBrainz:
            MusicBrainzPage()
        case .artwork:
            ArtworkPage()
        case .privacy:
            NetworkPrivacyPage()
        }
    }

    private func advance() {
        guard let nextPage = currentPage.next else {
            onContinue()
            return
        }

        currentPage = nextPage
    }

    private func retreat() {
        guard let previousPage = currentPage.previous else { return }
        currentPage = previousPage
    }

    private var platformCancelTitle: String {
        #if os(macOS)
        "Quit"
        #else
        "Skip"
        #endif
    }

    private func platformCancelAction() {
        #if os(macOS)
        onQuit()
        #else
        onContinue()
        #endif
    }

    private var minimumWidth: CGFloat? {
        #if os(macOS)
        750
        #else
        nil
        #endif
    }

    private var maximumWidth: CGFloat? {
        #if os(macOS)
        750
        #else
        horizontalSizeClass == .compact ? .infinity : 750
        #endif
    }

    private var minimumHeight: CGFloat? {
        #if os(macOS)
        700
        #else
        nil
        #endif
    }

    private var maximumHeight: CGFloat? {
        #if os(macOS)
        700
        #else
        .infinity
        #endif
    }
}

private enum WelcomeSplashPage: Int {
    case welcome
    case features
    case musicBrainz
    case artwork
    case privacy

    var next: WelcomeSplashPage? {
        switch self {
        case .welcome:
            .features
        case .features:
            .musicBrainz
        case .musicBrainz:
            .artwork
        case .artwork:
            .privacy
        case .privacy:
            nil
        }
    }

    var previous: WelcomeSplashPage? {
        switch self {
        case .welcome:
            nil
        case .features:
            .welcome
        case .musicBrainz:
            .features
        case .artwork:
            .musicBrainz
        case .privacy:
            .artwork
        }
    }
}

private struct AppIconHero: View {
    var body: some View {
        if let image = PlatformApplication.appIconImage {
            Image(platformImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 104, height: 104)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageHeader(
                title: "Welcome to AudioMator",
                subtitle: "Inspect, clean up, and rewrite audio metadata on \(platformDeviceName)."
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 24) {
                    WelcomeIntroRow(
                        symbol: "music.note",
                        title: "Edit metadata on \(platformDeviceName)",
                        description: "Open the tracks you want and work locally."
                    )
                    WelcomeIntroRow(
                        symbol: "wand.and.stars",
                        title: "Review tags quickly",
                        description: "Spot important fields fast and make precise fixes."
                    )
                    WelcomeIntroRow(
                        symbol: platformNativeSymbol,
                        title: "Feels native on \(platformName)",
                        description: "Uses familiar windows, sheets, and inspectors."
                    )
                }
                .padding(.vertical, 22)
            }
        }
    }

    private var platformDeviceName: String {
        #if os(macOS)
        "your Mac"
        #else
        "your iPad"
        #endif
    }

    private var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iPadOS"
        #endif
    }

    private var platformNativeSymbol: String {
        #if os(macOS)
        "macwindow"
        #else
        "ipad"
        #endif
    }
}

private struct WelcomeIntroRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
    }
}

private struct FeaturesPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageHeader(
                title: "What You Can Do",
                subtitle: "Bring in tracks, inspect tags, make precise changes, and save when you're ready."
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 23) {
                    WelcomeFeatureRow(
                        symbol: "music.note.list",
                        title: "Choose one-time or watched sources",
                        description: "Use Current Session for one-off work, or add watched folders for later."
                    )

                    WelcomeFeatureRow(
                        symbol: "slider.horizontal.3",
                        title: "Inspect and edit metadata",
                        description: "Review tags, compare selections, and check raw metadata before saving."
                    )

                    WelcomeFeatureRow(
                        symbol: "square.stack.3d.down.right",
                        title: "Use batch utilities",
                        description: "Reorder files, renumber tracks, copy paths, reveal files, or clear tags."
                    )

                    WelcomeFeatureRow(
                        symbol: "photo.on.rectangle.angled",
                        title: "Work with artwork",
                        description: "Replace, remove, preview, and apply album artwork from the inspector."
                    )
                }
                .padding(.vertical, 20)
            }
        }
        .padding(.top, 8)
    }
}

private struct MusicBrainzPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageHeader(
                title: "Match Metadata with MusicBrainz",
                subtitle: "Search releases and tracks, compare the candidates, and apply the details you choose."
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 24) {
                    WelcomeFeatureRow(
                        symbol: "magnifyingglass",
                        title: "Search from selected files",
                        description: "Start with existing track metadata, or enter a MusicBrainz search manually."
                    )

                    WelcomeFeatureRow(
                        symbol: "list.bullet.rectangle",
                        title: "Review before applying",
                        description: "Check candidate release and track information before it changes your files."
                    )

                    WelcomeFeatureRow(
                        symbol: "square.and.arrow.down",
                        title: "Apply metadata when ready",
                        description: "Write matched titles, artists, album details, dates, and identifiers."
                    )
                }
                .padding(.vertical, 22)
            }
        }
        .padding(.top, 8)
    }
}

private struct ArtworkPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageHeader(
                title: "Find Album Artwork",
                subtitle: "Use iTunes artwork lookup to find covers, preview them, and apply the selected image."
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 24) {
                    WelcomeFeatureRow(
                        symbol: "magnifyingglass.circle",
                        title: "Find covers online",
                        description: "Search from album details, an iTunes Album ID, or your own artwork search terms."
                    )

                    WelcomeFeatureRow(
                        symbol: "rectangle.on.rectangle",
                        title: "Preview the result",
                        description: "Compare available artwork before choosing what to use."
                    )

                    WelcomeFeatureRow(
                        symbol: "checkmark.rectangle.stack",
                        title: "Apply to selected files",
                        description: "Save selected artwork into supported audio files with your metadata edits."
                    )
                }
                .padding(.vertical, 22)
            }
        }
        .padding(.top, 8)
    }
}

private struct NetworkPrivacyPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                title: "Privacy & Network Access",
                subtitle: "AudioMator edits files locally. Online services are contacted only when you use lookup features."
            )

            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    PrivacyRow(
                        symbol: "internaldrive",
                        title: "Your audio stays local",
                        description: "AudioMator reads and writes the files you choose. Lookup features do not upload audio file contents."
                    )

                    PrivacyRow(
                        symbol: "text.magnifyingglass",
                        title: "Lookup sends search details",
                        description: "MusicBrainz and iTunes searches may use metadata such as title, artist, album, track number, duration, identifiers, links, or text you enter."
                    )

                    PrivacyRow(
                        symbol: "network",
                        title: "External services",
                        description: "Lookups may contact MusicBrainz, Apple iTunes Search API, Apple artwork CDN, or related services."
                    )

                    Text(domainSummary)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 66)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 20)
            }
        }
        .padding(.top, 8)
    }

    private var domainSummary: String {
        (NetworkServiceDisclosure.MusicBrainz.domains +
            NetworkServiceDisclosure.ITunesArtwork.domains)
            .joined(separator: "  ")
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppIconHero()
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 35, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WelcomeFeatureRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))

                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
    }
}

private struct GlassActionButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(minWidth: 108)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(background(configuration: configuration))
            .overlay(border(configuration: configuration))
            .clipShape(Capsule(style: .continuous))
            .shadow(color: shadowColor(configuration: configuration), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        isProminent ? .white : Color.primary.opacity(0.82)
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        if isProminent {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(configuration.isPressed ? 0.82 : 0.94),
                            Color.accentColor.opacity(configuration.isPressed ? 0.66 : 0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .opacity(configuration.isPressed ? 0.88 : 1)
        }
    }

    @ViewBuilder
    private func border(configuration: Configuration) -> some View {
        Capsule(style: .continuous)
            .strokeBorder(
                isProminent
                    ? Color.white.opacity(configuration.isPressed ? 0.18 : 0.26)
                    : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.14),
                lineWidth: 1
            )
    }

    private func shadowColor(configuration: Configuration) -> Color {
        isProminent
            ? Color.accentColor.opacity(configuration.isPressed ? 0.14 : 0.22)
            : Color.black.opacity(configuration.isPressed ? 0.04 : 0.08)
    }
}
