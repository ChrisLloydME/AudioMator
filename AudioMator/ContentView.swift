//
//  ContentView.swift
//  AudioMator
//
//  Created by Christopher Lloyd on 2025.11.22.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AudioViewModel()
    @StateObject private var state = SharedState()
    @State private var isInspectorVisible: Bool = true

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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isInspectorVisible.toggle()
                    }
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
        .overlay(alignment: .bottom) {
            if let hud = viewModel.metadataWriteSuccessHUD {
                MetadataWriteSuccessHUDView(hud: hud)
                    .id(hud.id)
                    .padding(.bottom, 40)
            }
        }
    }

    private func openTrackRenumberSheet() {
        // Seed defaults each time the sheet opens
        trackRenumberStartText = String(max(1, trackRenumberOptions.startNumber))
        trackRenumberResult = .empty
        isTrackRenumberPresented = true
    }
}

private struct MetadataWriteSuccessHUDView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hud: MetadataWriteSuccessHUD

    var body: some View {
        VStack(spacing: 10) {
            AnimatedCheckmarkBadge(colorScheme: colorScheme)

            VStack(spacing: 3) {
                Text(hud.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Text(hud.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 220)
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
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
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

private struct AnimatedCheckmarkBadge: View {
    let colorScheme: ColorScheme

    @State private var ringScale: CGFloat = 0.9
    @State private var ringOpacity: CGFloat = 0.0
    @State private var checkProgress: CGFloat = 0.0
    @State private var checkScale: CGFloat = 0.92

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeFillColor)
                .frame(width: 54, height: 54)

            Circle()
                .stroke(ringStrokeColor, lineWidth: 1)
                .frame(width: 54, height: 54)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            CheckmarkShape()
                .trim(from: 0, to: checkProgress)
                .stroke(
                    checkColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 24, height: 18)
                .scaleEffect(checkScale)
        }
        .onAppear {
            ringScale = 0.9
            ringOpacity = 0.0
            checkProgress = 0.0
            checkScale = 0.92

            withAnimation(.easeOut(duration: 0.18)) {
                ringScale = 1.0
                ringOpacity = 1.0
            }

            withAnimation(.timingCurve(0.22, 0.9, 0.24, 1.0, duration: 0.32).delay(0.04)) {
                checkProgress = 1.0
            }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.68).delay(0.08)) {
                checkScale = 1.0
            }
        }
    }

    private var badgeFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private var ringStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.12)
    }

    private var checkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.84)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.12))
        return path
    }
}

#Preview {
    ContentView()
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
