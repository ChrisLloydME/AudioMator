import SwiftUI

struct LRCLIBLyricsBrowserView: View {
    @ObservedObject var store: LRCLIBLyricsBrowserStore
    @ObservedObject var viewModel: AudioViewModel
    let onBackToSources: () -> Void

    @State private var isApplyingLyrics = false
    @State private var isAutoApplyingLyrics = false
    @State private var autoApplyProgress: MetadataSaveProgress?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 920, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(platformColor: .audiomatorWindowBackground))
        .audiomatorMacTitlebarScrollEdgeBar()
        .onAppear {
            if store.hasFiles {
                store.searchCurrentFile()
            }
        }
        .onChange(of: store.navigationResetToken) { _, _ in
            if store.hasFiles {
                store.searchCurrentFile()
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    onBackToSources()
                } label: {
                    Label("Sources", systemImage: "chevron.left")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if store.searchState == .searching && !isAutoApplyingLyrics {
                    Button("Cancel") {
                        store.cancelSearch()
                    }
                } else {
                    Button("Search") {
                        store.searchCurrentFile()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.hasFiles || isAutoApplyingLyrics)
                }
            }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LRCLIB Lyrics")
                        .font(.title3.weight(.semibold))
                    Text(store.sourceDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(store.queuePositionText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            if let currentFile = store.currentFile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentFile.displayTitle)
                        .font(.headline)
                    Text([currentFile.artist, currentFile.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(currentFile.fileName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasFiles {
            ContentUnavailableView(
                "No Files Selected",
                systemImage: "music.note.list",
                description: Text("Select one or more audio files in AudioMator, then open LRCLIB from Online Metadata.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isAutoApplyingLyrics {
            autoApplyProgressView
        } else {
            HStack(spacing: 0) {
                resultsPane
                    .frame(minWidth: 340, idealWidth: 390, maxWidth: 460)
                Divider()
                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var autoApplyProgressView: some View {
        let progress = viewModel.metadataSaveProgress ?? autoApplyProgress

        return VStack(spacing: 16) {
            ProgressView()

            VStack(spacing: 4) {
                Text(progress?.title ?? "Finding LRCLIB Best Matches")
                    .font(.headline)
                Text(progress?.subtitle ?? "Preparing selected files...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let progress {
                VStack(alignment: .trailing, spacing: 7) {
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    Text(progress.progressLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 360, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Candidates")
                    .font(.headline)
                Spacer()
                if store.searchState == .loaded {
                    Text("\(store.rankedCandidates.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            resultsStateContent
        }
        .padding(16)
    }

    @ViewBuilder
    private var resultsStateContent: some View {
        switch store.searchState {
        case .idle:
            ContentUnavailableView(
                "Search LRCLIB",
                systemImage: "text.magnifyingglass",
                description: Text("Search uses this file's title, artist, album, and duration when available.")
            )
        case .searching:
            VStack(spacing: 10) {
                Spacer()
                ProgressView("Searching LRCLIB…")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .cancelled:
            ContentUnavailableView(
                "Search Cancelled",
                systemImage: "xmark.circle",
                description: Text("Start a new search when you are ready.")
            )
        case .failed(let message):
            ContentUnavailableView(
                "Unable to Search LRCLIB",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded:
            if store.rankedCandidates.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "text.magnifyingglass",
                    description: Text("LRCLIB did not return lyrics candidates for this track.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !store.hasSyncedCandidate {
                            Label("No synced lyrics found in these results.", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                        }

                        ForEach(store.rankedCandidates) { rankedCandidate in
                            LRCLIBCandidateRow(
                                rankedCandidate: rankedCandidate,
                                isSelected: store.selectedCandidateID == rankedCandidate.id,
                                isApplied: store.appliedCandidateID == rankedCandidate.id
                            ) {
                                store.selectCandidate(rankedCandidate.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview")
                    .font(.headline)

                Spacer()

                if let candidate = store.selectedCandidate {
                    Text(candidate.lyricsAvailabilityLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(candidate.hasSyncedLyrics ? Color.green : Color.secondary)
                }
            }

            if let candidate = store.selectedCandidate {
                selectedCandidatePreview(candidate)
            } else {
                ContentUnavailableView(
                    "No Candidate Selected",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    description: Text("Choose a result to preview the lyrics before applying.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    private func selectedCandidatePreview(_ candidate: LRCLIBLyricsCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LRCLIBCandidateMetadataView(candidate: candidate)

            if candidate.hasSyncedLyrics, let syncedLyrics = candidate.syncedLyrics {
                lyricsPreview(text: syncedLyrics)
            } else if candidate.hasPlainLyrics, let plainLyrics = candidate.plainLyrics {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This result has plain lyrics only. It will not be applied as synced lyrics.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    lyricsPreview(text: plainLyrics)
                }
            } else {
                ContentUnavailableView(
                    candidate.instrumental ? "Instrumental Result" : "No Lyrics Text",
                    systemImage: "music.note",
                    description: Text("Choose another candidate with synced lyrics.")
                )
            }
        }
    }

    private func lyricsPreview(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                store.movePrevious()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!store.canMovePrevious || isApplyingLyrics || isAutoApplyingLyrics)

            Button {
                store.moveNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!store.canMoveNext || isApplyingLyrics || isAutoApplyingLyrics)

            Spacer()

            if isApplyingLyrics || isAutoApplyingLyrics {
                ProgressView()
                    .controlSize(.small)
            }

            if store.hasMultipleFiles {
                Button("Auto Apply Best Matches") {
                    Task {
                        await autoApplyBestSyncedLyrics()
                    }
                }
                .disabled(isApplyingLyrics || isAutoApplyingLyrics || store.searchState == .searching)
            }

            Button("Apply Synced Lyrics") {
                Task {
                    await applySelectedLyrics()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!store.canApplySelectedCandidate || isApplyingLyrics || isAutoApplyingLyrics)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func applySelectedLyrics() async {
        guard
            !isApplyingLyrics,
            let currentFile = store.currentFile,
            let candidate = store.selectedCandidate,
            let syncedLyrics = candidate.syncedLyrics,
            candidate.hasSyncedLyrics
        else {
            return
        }

        isApplyingLyrics = true
        let didApply = await viewModel.applyLRCLIBSyncedLyrics(syncedLyrics, to: currentFile.id)
        if didApply {
            store.markCurrentFileApplied(candidateID: candidate.id)
        }
        isApplyingLyrics = false
    }

    private func autoApplyBestSyncedLyrics() async {
        guard !isApplyingLyrics, !isAutoApplyingLyrics else { return }

        isAutoApplyingLyrics = true
        autoApplyProgress = MetadataSaveProgress(
            title: "Finding LRCLIB Best Matches",
            subtitle: "Preparing selected files...",
            completedUnitCount: 0,
            totalUnitCount: max(store.fileInputs.count, 1)
        )
        let matches = await store.autoSyncedLyricsMatchesForAllFiles { completedCount, totalCount, currentFileName in
            autoApplyProgress = MetadataSaveProgress(
                title: "Finding LRCLIB Best Matches",
                subtitle: currentFileName.isEmpty ? "Preparing selected files..." : currentFileName,
                completedUnitCount: completedCount,
                totalUnitCount: max(totalCount, 1)
            )
        }
        let appliedFileIDs = await viewModel.applyLRCLIBSyncedLyricsAutoMatches(matches)
        store.markFilesApplied(matches, appliedFileIDs: appliedFileIDs)
        autoApplyProgress = nil
        isAutoApplyingLyrics = false
    }
}

private struct LRCLIBCandidateRow: View {
    let rankedCandidate: LRCLIBRankedCandidate
    let isSelected: Bool
    let isApplied: Bool
    let onSelect: () -> Void

    private var candidate: LRCLIBLyricsCandidate {
        rankedCandidate.candidate
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(candidate.trackName.isEmpty ? "Untitled Track" : candidate.trackName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(rankedCandidate.score)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text([candidate.artistName, candidate.albumName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(candidate.lyricsAvailabilityLabel, systemImage: candidate.hasSyncedLyrics ? "waveform" : "text.alignleft")
                        .foregroundStyle(candidate.hasSyncedLyrics ? Color.green : Color.secondary)

                    if let duration = candidate.durationSeconds {
                        Text(durationLabel(duration))
                    }

                    if isApplied {
                        Label("Applied", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption.weight(.medium))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func durationLabel(_ duration: Int) -> String {
        let minutes = duration / 60
        let seconds = duration % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct LRCLIBCandidateMetadataView: View {
    let candidate: LRCLIBLyricsCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.trackName.isEmpty ? "Untitled Track" : candidate.trackName)
                .font(.title3.weight(.semibold))
            Text([candidate.artistName, candidate.albumName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("LRCLIB ID \(candidate.id)")
                if let duration = candidate.durationSeconds {
                    Text("\(duration)s")
                }
                if candidate.instrumental {
                    Text("Instrumental")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}
