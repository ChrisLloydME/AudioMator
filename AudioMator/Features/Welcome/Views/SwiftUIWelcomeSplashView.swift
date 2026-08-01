import SwiftUI

#if os(iOS)
struct SwiftUIWelcomeSplashView: View {
    let onQuit: () -> Void
    let onContinue: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentPage: WelcomeSplashPage = .welcome

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            WelcomeSplashPageView(content: currentPage.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            WelcomeSplashButtonBar(
                currentPage: currentPage,
                onCancel: platformCancelAction,
                onBack: retreat,
                onContinue: advance
            )
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 30)
        .frame(
            minWidth: nil,
            idealWidth: 750,
            maxWidth: horizontalSizeClass == .compact ? .infinity : 750,
            minHeight: nil,
            idealHeight: 700,
            maxHeight: .infinity
        )
        .background(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
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

    private func platformCancelAction() {
        onContinue()
    }
}

private struct WelcomeSplashButtonBar: View {
    let currentPage: WelcomeSplashPage
    let onCancel: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack {
            if currentPage == .welcome {
                Button("Skip", action: onCancel)
                    .buttonStyle(GlassActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Back", action: onBack)
                    .buttonStyle(GlassActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()

            Button(currentPage.next == nil ? "Get Started" : "Continue", action: onContinue)
                .buttonStyle(GlassActionButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct WelcomeSplashPageView: View {
    let content: WelcomeSplashPageContent

    var body: some View {
        VStack(alignment: .leading, spacing: content.page == .welcome ? 28 : 26) {
            WelcomeSplashHeader(title: content.title, subtitle: content.subtitle)

            GroupBox {
                VStack(alignment: .leading, spacing: content.page == .features ? 23 : 24) {
                    ForEach(content.rows) { row in
                        WelcomeSplashRow(row: row)
                    }
                }
                .padding(.vertical, content.page == .features || content.page == .privacy ? 20 : 22)
            }
        }
        .padding(.top, content.topPadding)
    }
}

private struct WelcomeSplashHeader: View {
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

private struct WelcomeSplashRow: View {
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
#endif
