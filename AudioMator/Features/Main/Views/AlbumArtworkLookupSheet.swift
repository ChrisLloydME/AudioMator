import SwiftUI

struct AlbumArtworkLookupSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    @Environment(\.dismiss) private var dismiss

    private var session: ArtworkLookupSession? {
        viewModel.artworkLookupSession
    }

    private var selectedResult: iTunesArtworkSearchResult? {
        session?.selectedResult
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)
    ]

    var body: some View {
        Group {
            if let session {
                VStack(alignment: .leading, spacing: 18) {
                    header(session: session)

                    Divider()

                    HStack(alignment: .top, spacing: 20) {
                        resultsPane(session: session)
                        previewPane(session: session)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Divider()

                    footer(session: session)
                }
                .padding(20)
                .frame(minWidth: 860, minHeight: 620)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear { dismiss() }
            }
        }
    }

    private func header(session: ArtworkLookupSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Online Album Artwork")
                .font(.title2)
                .fontWeight(.semibold)

            Text(session.selectionTitle)
                .font(.headline)

            Text("Search source: \(session.request.summary)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func resultsPane(session: ArtworkLookupSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Results", systemImage: "photo.stack")
                    .font(.headline)

                Spacer()

                if session.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(session.results.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if session.isLoading {
                    ContentUnavailableView(
                        "Searching iTunes Artwork",
                        systemImage: "icloud.and.arrow.down",
                        description: Text("Results will appear here when the search completes.")
                    )
                } else if !session.results.isEmpty {
                    // A download fault never replaces the settled result grid.
                    resultGrid(session: session)
                } else if let message = session.searchFailureMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            String(localized: "Artwork Lookup Couldn’t Be Completed"),
                            systemImage: "exclamationmark.triangle",
                            description: Text(message)
                        )

                        Button(String(localized: "Search Again")) {
                            viewModel.retryArtworkSearch()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else if let message = session.searchCancellationMessage {
                    ContentUnavailableView(
                        String(localized: "Search Was Cancelled"),
                        systemImage: "magnifyingglass",
                        description: Text(message)
                    )
                } else if let emptyMessage = session.emptyMessage {
                    ContentUnavailableView(
                        String(localized: "No Matching Artwork"),
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(emptyMessage)
                    )
                } else {
                    resultGrid(session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resultGrid(session: ArtworkLookupSession) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(session.results) { result in
                    ArtworkLookupResultTile(
                        result: result,
                        isSelected: result.id == session.selectedResultID
                    ) {
                        viewModel.selectArtworkLookupResult(id: result.id)
                    }
                    .disabled(!session.canSelectCandidate)
                }
            }
            .padding(.vertical, 2)
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
    }

    private func previewPane(session: ArtworkLookupSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Selection", systemImage: "checkmark.circle")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                if let selectedResult {
                    // The preview state is owned by the candidate identity:
                    // switching candidates recreates the fallback at URL 0.
                    RemoteArtworkImage(
                        urls: selectedResult.preferredPreviewURLs,
                        identity: selectedResult.id,
                        padding: 14
                    )
                    .id(selectedResult.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("Choose one artwork result.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 250, height: 250)

            if let selectedResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedResult.title)
                        .font(.headline)

                    if let subtitle = selectedResult.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(selectedResult.pixelWidth) × \(selectedResult.pixelHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(
                        session.isMultiSelection
                            ? "The selected artwork will be applied to all selected files."
                            : "The selected artwork will replace the current file artwork."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let fault = session.downloadFault {
                downloadFaultView(fault: fault, session: session)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func downloadFaultView(
        fault: ArtworkLookupDownloadFault,
        session: ArtworkLookupSession
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                fault.isCancellation
                    ? String(localized: "Artwork Download Cancelled")
                    : String(localized: "Artwork Download Failed"),
                systemImage: fault.isCancellation ? "stop.circle" : "exclamationmark.triangle"
            )
            .font(.subheadline)
            .fontWeight(.medium)

            if let candidateTitle = session.downloadFaultCandidateTitle {
                Text(candidateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(fault.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footer(session: ArtworkLookupSession) -> some View {
        HStack {
            Button("Cancel") {
                viewModel.dismissArtworkLookup()
                dismiss()
            }

            Spacer()

            if session.isApplying {
                ProgressView()
                    .controlSize(.small)

                Button(String(localized: "Stop Download")) {
                    viewModel.cancelSelectedArtworkDownload()
                }
            }

            Button(session.applyActionTitle) {
                viewModel.applySelectedArtworkLookupResult()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!session.canApplySelectedResult)
        }
    }
}

private struct ArtworkLookupResultTile: View {
    let result: iTunesArtworkSearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let outerCornerRadius: CGFloat = 16
        let innerCornerRadius: CGFloat = 10

        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))

                    RemoteArtworkImage(
                        urls: result.preferredPreviewURLs,
                        identity: result.id,
                        padding: 10
                    )
                }
                .frame(height: 150)

                Text(result.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .audiomatorWindowBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RemoteArtworkImage: View {
    let urls: [URL]
    let identity: String?
    let padding: CGFloat

    @State private var fallback: ArtworkPreviewFallback

    init(urls: [URL], identity: String? = nil, padding: CGFloat) {
        self.urls = urls
        self.identity = identity
        self.padding = padding
        _fallback = State(initialValue: ArtworkPreviewFallback(urls: urls))
    }

    var body: some View {
        Group {
            if let currentURL = fallback.currentURL {
                AsyncImage(url: currentURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(padding)
                    case .failure:
                        if fallback.hasSuccessor {
                            Color.clear
                                .onAppear {
                                    // Only the URL that is actually showing may
                                    // advance the fallback; delayed failures of a
                                    // previous candidate are ignored.
                                    fallback.advance(afterFailedURL: currentURL)
                                }
                        } else {
                            failurePlaceholder
                        }
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                failurePlaceholder
            }
        }
        .onChange(of: identity) { _, _ in
            fallback = ArtworkPreviewFallback(urls: urls)
        }
        .onChange(of: urls) { _, newURLs in
            fallback = ArtworkPreviewFallback(urls: newURLs)
        }
    }

    private var failurePlaceholder: some View {
        Image(systemName: "photo.badge.exclamationmark")
            .font(.system(size: 40))
            .foregroundStyle(.secondary)
    }
}
