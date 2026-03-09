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
    }

    private func openTrackRenumberSheet() {
        // Seed defaults each time the sheet opens
        trackRenumberStartText = String(max(1, trackRenumberOptions.startNumber))
        trackRenumberResult = .empty
        isTrackRenumberPresented = true
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
