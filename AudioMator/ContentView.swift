//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    @AppStorage("hasCompletedWelcomeSplash") private var hasCompletedWelcomeSplash: Bool = false
    @State private var isInspectorVisible: Bool = true
    @State private var isWelcomeSplashPresented: Bool = false

    // Full metadata dump (user-facing feature)
    @State private var isMetadataDumpPresented: Bool = false
    @State private var metadataDumpText: String = ""

    // Track renumbering (by middle-list order)
    @State private var isTrackRenumberPresented: Bool = false
    @State private var trackRenumberOptions: TrackRenumberOptions = .init()
    @State private var trackRenumberStartText: String = "1"
    @State private var isTrackRenumberRunning: Bool = false
    @State private var trackRenumberResult: TrackRenumberResult = .empty

    var body: some View {
        NavigationSplitView {
            SidebarPane(state: state)
        } content: {
            ContentPane(
                viewModel: viewModel,
                state: state,
                onAddFiles: viewModel.addFiles,
                onShowMetadataDump: presentMetadataDump,
                onOpenTrackRenumber: openTrackRenumberSheet,
                onCancelEdits: viewModel.cancelEditing,
                onSaveEdits: viewModel.saveSingleEdits
            )
        } detail: {
            Group {
                if isInspectorVisible {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()

                        InspectorPane(
                            viewModel: viewModel,
                            state: state,
                            isInspectorVisible: $isInspectorVisible
                        )
                    }
                    .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 480)
                } else {
                    Color.clear
                        .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
            }
        }
        .sheet(isPresented: $isMetadataDumpPresented) {
            MetadataDumpSheet(
                metadataDumpText: metadataDumpText,
                onClose: { isMetadataDumpPresented = false }
            )
        }
        .sheet(isPresented: $isTrackRenumberPresented) {
            TrackRenumberSheet(
                viewModel: viewModel,
                state: state,
                isPresented: $isTrackRenumberPresented,
                trackRenumberOptions: $trackRenumberOptions,
                trackRenumberStartText: $trackRenumberStartText,
                isTrackRenumberRunning: $isTrackRenumberRunning,
                trackRenumberResult: $trackRenumberResult
            )
        }
        .sheet(isPresented: $isWelcomeSplashPresented) {
            WelcomeSplashView(
                onQuit: quitApplication,
                onContinue: dismissWelcomeSplash
            )
        }
        .overlay(alignment: .bottom) {
            if let hud = viewModel.metadataWriteHUD {
                MetadataWriteHUDView(hud: hud)
                    .id(hud.id)
                    .padding(.bottom, 40)
            }
        }
        .task {
            guard !hasCompletedWelcomeSplash, !isWelcomeSplashPresented else { return }
            isWelcomeSplashPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWelcomeSplash)) { _ in
            guard !isWelcomeSplashPresented else { return }
            isWelcomeSplashPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestMetadataDump)) { _ in
            guard !state.selectedAudioIDs.isEmpty else { return }
            presentMetadataDump()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestTrackRenumber)) { _ in
            guard !viewModel.files.isEmpty else { return }
            openTrackRenumberSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestToggleInspector)) { _ in
            toggleInspector()
        }
    }

    private func openTrackRenumberSheet() {
        // Seed defaults each time the sheet opens
        trackRenumberStartText = String(max(1, trackRenumberOptions.startNumber))
        trackRenumberResult = .empty
        isTrackRenumberPresented = true
    }

    private func dismissWelcomeSplash() {
        hasCompletedWelcomeSplash = true
        isWelcomeSplashPresented = false
    }

    private func quitApplication() {
        isWelcomeSplashPresented = false

        Task { @MainActor in
            await Task.yield()
            NSApplication.shared.terminate(nil)
        }
    }

    private func toggleInspector() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isInspectorVisible.toggle()
        }
    }
}

private struct MetadataWriteHUDView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hud: MetadataWriteHUD

    var body: some View {
        VStack(spacing: 10) {
            MetadataWriteHUDIcon(style: hud.style, colorScheme: colorScheme)

            VStack(spacing: 3) {
                Text(hud.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Text(hud.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 320)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 18, x: 0, y: 12)
        .allowsHitTesting(false)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11).opacity(0.94)
            : Color.white.opacity(0.96)
    }

    private var borderColor: Color {
        switch hud.style {
        case .success:
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.08)
        case .warning:
            return Color.orange.opacity(colorScheme == .dark ? 0.55 : 0.35)
        case .failure:
            return Color.red.opacity(colorScheme == .dark ? 0.58 : 0.38)
        }
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.30)
            : Color.black.opacity(0.14)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.66)
            : Color.black.opacity(0.56)
    }
}

private struct MetadataWriteHUDIcon: View {
    let style: MetadataWriteHUDStyle
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeFillColor)
                .frame(width: 54, height: 54)

            Circle()
                .stroke(ringStrokeColor, lineWidth: 1)
                .frame(width: 54, height: 54)

            Image(systemName: symbolName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(symbolColor)
        }
    }

    private var badgeFillColor: Color {
        switch style {
        case .success:
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.06)
        case .warning:
            return Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.14)
        case .failure:
            return Color.red.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }
    }

    private var ringStrokeColor: Color {
        switch style {
        case .success:
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.12)
        case .warning:
            return Color.orange.opacity(colorScheme == .dark ? 0.42 : 0.28)
        case .failure:
            return Color.red.opacity(colorScheme == .dark ? 0.44 : 0.30)
        }
    }

    private var symbolColor: Color {
        switch style {
        case .success:
            return colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.84)
        case .warning:
            return colorScheme == .dark ? Color.orange.opacity(0.92) : Color.orange.opacity(0.86)
        case .failure:
            return colorScheme == .dark ? Color.red.opacity(0.92) : Color.red.opacity(0.86)
        }
    }

    private var symbolName: String {
        switch style {
        case .success:
            return "checkmark"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark"
        }
    }
}

#Preview {
    ContentView(viewModel: AudioViewModel(), state: SharedState())
}

// MARK: - Full metadata dump (user-facing)
extension ContentView {
    private func presentMetadataDump() {
        let selected = viewModel.files.filter { state.selectedAudioIDs.contains($0.id) }
        metadataDumpText = buildTagLibDump(for: selected)
        isMetadataDumpPresented = true
    }

    /// Produces a best-effort *raw* metadata dump using the TagLib bridge.
    ///
    /// This intentionally does **not** re-print the already-normalized fields shown in the right inspector.
    private func buildTagLibDump(for files: [AudioFile]) -> String {
        guard !files.isEmpty else { return "(No selection)" }

        // Single selection: show only the raw dump.
        if files.count == 1, let file = files.first {
            return buildTagLibDump(for: file.url)
        }

        // Multiple selection: concatenate per-file dumps.
        return files.map { buildTagLibDump(for: $0.url) }
            .joined(separator: "\n\n")
    }

    /// Produces a best-effort *raw* metadata dump using the TagLib bridge.
    private func buildTagLibDump(for url: URL) -> String {
        if let text = TagLibMetadataManager.rawMetadataText(from: url),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        return [
            "File: \(url.lastPathComponent)",
            "Path: \(url.path)",
            "",
            "(No TagLib metadata to display. The file may contain no readable tags, or the TagLib bridge returned an empty result.)"
        ].joined(separator: "\n")
    }
}
