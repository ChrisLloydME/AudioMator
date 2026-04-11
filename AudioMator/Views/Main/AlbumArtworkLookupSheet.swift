import SwiftUI
import AppKit

struct AlbumArtworkLookupSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    @Environment(\.dismiss) private var dismiss

    private var session: ArtworkLookupSession? {
        viewModel.artworkLookupSession
    }

    private var selectedResult: ITunesArtworkSearchResult? {
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
                .interactiveDismissDisabled(session.isApplying)
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
                } else if let errorMessage = session.errorMessage {
                    ContentUnavailableView(
                        "Artwork Lookup Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if let emptyMessage = session.emptyMessage {
                    ContentUnavailableView(
                        "No Artwork Found",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(emptyMessage)
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(session.results) { result in
                                ArtworkLookupResultTile(
                                    result: result,
                                    isSelected: result.id == session.selectedResultID
                                ) {
                                    viewModel.selectArtworkLookupResult(id: result.id)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func previewPane(session: ArtworkLookupSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Selection", systemImage: "checkmark.circle")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                if let selectedResult {
                    RemoteArtworkImage(
                        urls: selectedResult.preferredPreviewURLs,
                        padding: 14
                    )
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

            Spacer(minLength: 0)
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func footer(session: ArtworkLookupSession) -> some View {
        HStack {
            Button("Cancel") {
                viewModel.dismissArtworkLookup()
                dismiss()
            }
            .disabled(session.isApplying)

            Spacer()

            if session.isApplying {
                ProgressView()
                    .controlSize(.small)
            }

            Button(session.isMultiSelection ? "Apply to Selected Files" : "Use Selected Artwork") {
                viewModel.applySelectedArtworkLookupResult()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                session.isLoading ||
                session.isApplying ||
                session.selectedResult == nil ||
                session.errorMessage != nil
            )
        }
    }
}

private struct ArtworkLookupResultTile: View {
    let result: ITunesArtworkSearchResult
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
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
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
    let padding: CGFloat

    @State private var currentIndex: Int = 0

    private var currentURL: URL? {
        guard currentIndex >= 0, currentIndex < urls.count else { return nil }
        return urls[currentIndex]
    }

    var body: some View {
        Group {
            if let currentURL {
                AsyncImage(url: currentURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(padding)
                    case .failure:
                        if currentIndex < urls.count - 1 {
                            Color.clear
                                .onAppear {
                                    currentIndex += 1
                                }
                        } else {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
