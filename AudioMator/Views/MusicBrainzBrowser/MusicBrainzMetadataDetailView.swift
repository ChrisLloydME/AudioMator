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
            case .track(let detail):
                trackSections(detail)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func recordingSections(_ detail: MusicBrainzRecordingDetail) -> some View {
        recordingMetadataSections(detail, overviewTitle: "Overview")
    }

    @ViewBuilder
    private func recordingMetadataSections(_ detail: MusicBrainzRecordingDetail, overviewTitle: String) -> some View {
        Section(overviewTitle) {
            MetadataValueRow(title: "Title", value: detail.title)
            MetadataValueRow(title: "Artist", value: detail.artistCredit)
            MetadataValueRow(title: "Disambiguation", value: detail.disambiguation)
            MetadataValueRow(title: "First Release", value: detail.firstReleaseDate)
            MetadataValueRow(title: "Length", value: formattedDuration(detail.durationMilliseconds))
            MetadataValueRow(title: "Genres", value: formattedTerms(detail.genres))
            MetadataValueRow(title: "Tags", value: formattedTerms(detail.tags))
            MetadataValueRow(title: "Rating", value: formattedRating(detail.rating))
            MetadataValueRow(title: "ISRC", value: detail.isrcs.joined(separator: ", "))
            MetadataValueRow(title: "MBID", value: detail.id)
            ExternalLinkRow(title: "MusicBrainz", url: detail.musicBrainzURL)
        }

        if !detail.relationshipGroups.isEmpty {
            Section("Relationships") {
                ForEach(detail.relationshipGroups) { group in
                    MetadataValueRow(title: group.title, value: joinedValues(group.values))
                }
            }
        }

        if !detail.annotation.isEmpty {
            Section("Annotation") {
                Text(detail.annotation)
                    .textSelection(.enabled)
            }
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
    private func trackSections(_ detail: MusicBrainzTrackDetail) -> some View {
        Section("Track") {
            MetadataValueRow(title: "Title", value: detail.track.title)
            MetadataValueRow(title: "Number", value: detail.track.number)
            MetadataValueRow(title: "Length", value: formattedDuration(detail.track.durationMilliseconds))
            MetadataValueRow(title: "Recording MBID", value: detail.track.recordingID)
            MetadataValueRow(title: "ISRC", value: detail.track.isrcs.joined(separator: ", "))
        }

        if let recordingDetail = detail.recordingDetail {
            recordingMetadataSections(recordingDetail, overviewTitle: "Recording")
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
            MetadataValueRow(title: "ASIN", value: detail.asin)
            MetadataValueRow(title: "Quality", value: detail.quality)
            MetadataValueRow(title: "Language", value: detail.language)
            MetadataValueRow(title: "Script", value: detail.script)
            MetadataValueRow(title: "Genres", value: formattedTerms(detail.genres))
            MetadataValueRow(title: "Tags", value: formattedTerms(detail.tags))
            MetadataValueRow(title: "MBID", value: detail.id)
            ExternalLinkRow(title: "MusicBrainz", url: detail.musicBrainzURL)
        }

        if !detail.annotation.isEmpty {
            Section("Annotation") {
                Text(detail.annotation)
                    .textSelection(.enabled)
            }
        }

        if !detail.releaseGroupTitle.isEmpty || !detail.releaseGroupPrimaryType.isEmpty || !detail.releaseGroupSecondaryTypes.isEmpty || !detail.releaseGroupID.isEmpty {
            Section("Release Group") {
                MetadataValueRow(title: "Title", value: detail.releaseGroupTitle)
                MetadataValueRow(title: "MBID", value: detail.releaseGroupID)
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

                        if !label.id.isEmpty {
                            Text(label.id)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
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
                MetadataValueRow(title: "Disc IDs", value: medium.discIDs.joined(separator: ", "))

                if !medium.tracks.isEmpty {
                    ForEach(medium.tracks) { track in
                        NavigationLink(value: MusicBrainzBrowserDestination.track(track)) {
                            VStack(alignment: .leading, spacing: 4) {
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
                            .padding(.vertical, 1)
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
        case .track(let track):
            return track.title
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

    private func formattedTerms(_ terms: [MusicBrainzTerm]) -> String {
        terms
            .map { term in
                if let count = term.count {
                    return "\(term.name) (\(count))"
                }
                return term.name
            }
            .joined(separator: ", ")
    }

    private func formattedRating(_ rating: MusicBrainzRating?) -> String {
        guard let rating else { return "" }
        var parts: [String] = []

        if let value = rating.value {
            parts.append(String(format: "%.1f", value))
        }

        if rating.voteCount > 0 {
            parts.append("\(rating.voteCount) vote\(rating.voteCount == 1 ? "" : "s")")
        }

        return parts.joined(separator: " • ")
    }

    private func joinedValues(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            let prefix = values.dropLast().joined(separator: ", ")
            return "\(prefix) and \(values.last ?? "")"
        }
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
