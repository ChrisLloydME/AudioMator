import SwiftUI

#if os(macOS)
import AppKit

struct MacWelcomeSplashView: View {
    let onQuit: () -> Void
    let onContinue: () -> Void

    @State private var currentPage: WelcomeSplashPage = .welcome

    var body: some View {
        ScrollView(.vertical) {
            MacWelcomeSplashPageView(content: currentPage.content)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 30)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 18)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            MacWelcomeSplashButtonBar(
                currentPage: currentPage,
                onQuit: onQuit,
                onBack: retreat,
                onContinue: advance
            )
            .padding(.horizontal, 30)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(width: 750, height: 700)
        .background(MacWelcomeWindowConfigurator())
        .animation(.easeInOut(duration: 0.18), value: currentPage)
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
}

private struct MacWelcomeSplashPageView: View {
    let content: WelcomeSplashPageContent

    var body: some View {
        VStack(alignment: .leading, spacing: content.page == .welcome ? 28 : 26) {
            MacWelcomeSplashHeader(title: content.title, subtitle: content.subtitle)

            GroupBox {
                VStack(alignment: .leading, spacing: content.page == .features ? 23 : 24) {
                    ForEach(content.rows) { row in
                        MacWelcomeSplashRow(row: row)
                    }

                    if content.page == .privacy {
                        Text(WelcomeSplashPage.domainSummary)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 66)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, content.page == .features || content.page == .privacy ? 20 : 22)
            }
        }
        .padding(.top, content.topPadding)
    }
}

private struct MacWelcomeSplashHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = PlatformApplication.appIconImage {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .padding(.top, 4)
            }

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

private struct MacWelcomeSplashRow: View {
    let row: WelcomeSplashRowContent

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: row.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.system(size: 18, weight: .semibold))

                Text(row.description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
    }
}

private struct MacWelcomeSplashButtonBar: View {
    let currentPage: WelcomeSplashPage
    let onQuit: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack {
            if currentPage == .welcome {
                Button("Quit", action: onQuit)
                    .buttonStyle(MacWelcomeGlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Back", action: onBack)
                    .buttonStyle(MacWelcomeGlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()

            Button(currentPage.next == nil ? "Get Started" : "Continue", action: onContinue)
                .buttonStyle(MacWelcomeGlassButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct MacWelcomeGlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary.opacity(0.86))
            .frame(minWidth: 108)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(prominentFill(configuration: configuration))
            .glassEffect(.regular, in: .capsule)
            .shadow(color: shadowColor(configuration: configuration), radius: 11, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func prominentFill(configuration: Configuration) -> some View {
        if isProminent {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(configuration.isPressed ? 0.76 : 0.92),
                            Color.accentColor.opacity(configuration.isPressed ? 0.58 : 0.76)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            Color.clear
        }
    }

    private func shadowColor(configuration: Configuration) -> Color {
        isProminent
            ? Color.accentColor.opacity(configuration.isPressed ? 0.12 : 0.20)
            : Color.black.opacity(configuration.isPressed ? 0.03 : 0.07)
    }
}

private struct MacWelcomeWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MacWelcomeWindowObserverView {
        MacWelcomeWindowObserverView()
    }

    func updateNSView(_ nsView: MacWelcomeWindowObserverView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.minSize = NSSize(width: 750, height: 700)
        window.maxSize = NSSize(width: 750, height: 700)
    }
}

private final class MacWelcomeWindowObserverView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.minSize = NSSize(width: 750, height: 700)
        window.maxSize = NSSize(width: 750, height: 700)
    }
}
#endif
