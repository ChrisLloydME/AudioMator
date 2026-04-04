import Foundation
import SwiftUI

struct MusicBrainzMetadataDetailView: View {
    let store: MusicBrainzBrowserStore
    let destination: MusicBrainzBrowserDestination

    @State private var loadState: LoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading metadata…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                ContentUnavailableView(
                    "Unable to Load Metadata",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )

            case .loaded(let detail):
                metadataList(detail)
            }
        }
        .navigationTitle(navigationTitle)
        .task(id: destination.id) {
            await loadMetadata()
        }
    }

    @ViewBuilder
    private func metadataList(_ detail: MusicBrainzMetadataDetail) -> some View {
        List {
            switch detail {
            case .recording(let detail):
                recordingSections(detail)
            case .release(let detail):
                releaseSections(detail)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func recordingSections(_ detail: MusicBrainzRecordingDetail) -> some View {
        Section("Overview") {
            MetadataValueRow(title: "Title", value: detail.title)
            MetadataValueRow(title: "Artist", value: detail.artistCredit)
            MetadataValueRow(title: "Disambiguation", value: detail.disambiguation)
            MetadataValueRow(title: "First Release", value: detail.firstReleaseDate)
            MetadataValueRow(title: "Length", value: formattedDuration(detail.durationMilliseconds))
            MetadataValueRow(title: "Genres", value: detail.genres.joined(separator: ", "))
            MetadataValueRow(title: "ISRC", value: detail.isrcs.joined(separator: ", "))
            MetadataValueRow(title: "MBID", value: detail.id)
            ExternalLinkRow(title: "MusicBrainz", url: detail.musicBrainzURL)
        }

        if !detail.releases.isEmpty {
            Section("Releases") {
                ForEach(detail.releases) { release in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(release.title)
                            .font(.system(size: 13, weight: .semibold))

                        Text(releaseMetadataLine(release))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if let url = release.musicBrainzURL {
                            Link(destination: url) {
                                Label("Open Release", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func releaseSections(_ detail: MusicBrainzReleaseDetail) -> some View {
        Section("Overview") {
            MetadataValueRow(title: "Title", value: detail.title)
            MetadataValueRow(title: "Artist", value: detail.artistCredit)
            MetadataValueRow(title: "Release Date", value: detail.date)
            MetadataValueRow(title: "Country", value: detail.country)
            MetadataValueRow(title: "Status", value: detail.status)
            MetadataValueRow(title: "Barcode", value: detail.barcode)
            MetadataValueRow(title: "Packaging", value: detail.packaging)
            MetadataValueRow(title: "Genres", value: detail.genres.joined(separator: ", "))
            MetadataValueRow(title: "MBID", value: detail.id)
            ExternalLinkRow(title: "MusicBrainz", url: detail.musicBrainzURL)
        }

        if !detail.releaseGroupTitle.isEmpty || !detail.releaseGroupPrimaryType.isEmpty || !detail.releaseGroupSecondaryTypes.isEmpty {
            Section("Release Group") {
                MetadataValueRow(title: "Title", value: detail.releaseGroupTitle)
                MetadataValueRow(title: "Primary Type", value: detail.releaseGroupPrimaryType)
                MetadataValueRow(title: "Secondary Types", value: detail.releaseGroupSecondaryTypes.joined(separator: ", "))
            }
        }

        if !detail.labels.isEmpty {
            Section("Labels") {
                ForEach(detail.labels) { label in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label.labelName.isEmpty ? "Unknown Label" : label.labelName)
                            .font(.system(size: 13, weight: .semibold))

                        if !label.catalogNumber.isEmpty {
                            Text("Catalog No. \(label.catalogNumber)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        ForEach(detail.media) { medium in
            Section(mediumSectionTitle(medium)) {
                if !medium.title.isEmpty {
                    MetadataValueRow(title: "Title", value: medium.title)
                }

                MetadataValueRow(title: "Format", value: medium.format)
                MetadataValueRow(title: "Track Count", value: medium.trackCount > 0 ? String(medium.trackCount) : "")

                if !medium.tracks.isEmpty {
                    ForEach(medium.tracks) { track in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(track.number.isEmpty ? "•" : track.number)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)

                            Text(track.title)

                            Spacer()

                            let duration = formattedDuration(track.durationMilliseconds)
                            if !duration.isEmpty {
                                Text(duration)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch destination {
        case .recording(let result):
            return result.title
        case .release(let result):
            return result.title
        }
    }

    private func loadMetadata() async {
        loadState = .loading

        do {
            let detail = try await store.metadataDetail(for: destination)
            guard !Task.isCancelled else { return }
            loadState = .loaded(detail)
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func formattedDuration(_ milliseconds: Int?) -> String {
        guard let milliseconds, milliseconds > 0 else { return "" }

        let totalSeconds = milliseconds / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }

    private func mediumSectionTitle(_ medium: MusicBrainzReleaseDetail.Medium) -> String {
        let base = medium.format.isEmpty ? "Medium" : medium.format
        if medium.trackCount > 0 {
            return "\(base) • \(medium.trackCount) tracks"
        }
        return base
    }

    private func releaseMetadataLine(_ release: MusicBrainzRecordingResult.Release) -> String {
        [release.date, release.country, release.status]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private extension MusicBrainzMetadataDetailView {
    enum LoadState {
        case loading
        case loaded(MusicBrainzMetadataDetail)
        case failed(String)
    }
}

private struct MetadataValueRow: View {
    let title: String
    let value: String

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)

                Text(value)
                    .textSelection(.enabled)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
        }
    }
}

private struct ExternalLinkRow: View {
    let title: String
    let url: URL?

    var body: some View {
        if let url {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)

                Link(destination: url) {
                    Label(url.absoluteString, systemImage: "arrow.up.right.square")
                        .lineLimit(1)
                }
                .buttonStyle(.link)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 1)
        }
    }
}
