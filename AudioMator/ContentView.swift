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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.metadataWriteSuccessHUD?.id)
    }

    private func openTrackRenumberSheet() {
        // Seed defaults each time the sheet opens
        trackRenumberStartText = String(max(1, trackRenumberOptions.startNumber))
        trackRenumberResult = .empty
        isTrackRenumberPresented = true
    }
}

private struct MetadataWriteSuccessHUDView: View {
    let hud: MetadataWriteSuccessHUD

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.38, green: 0.86, blue: 0.50),
                                Color(red: 0.16, green: 0.72, blue: 0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)

                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 3) {
                Text(hud.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text(hud.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 220)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
        .allowsHitTesting(false)
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
