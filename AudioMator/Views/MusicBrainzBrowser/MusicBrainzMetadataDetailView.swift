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
                detailContent(detail)
            }
        }
        .navigationTitle(navigationTitle)
        .task(id: destination.id) {
            await loadMetadata()
        }
    }

    private func detailContent(_ detail: MusicBrainzMetadataDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                switch detail {
                case .recording(let recording):
                    recordingSections(recording, overviewTitle: "Overview")
                case .release(let release):
                    releaseSections(release)
                case .track(let track):
                    trackSections(track)
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func recordingSections(_ detail: MusicBrainzRecordingDetail, overviewTitle: String) -> some View {
        let overviewItems = [
            infoItem("title", "Title", detail.title),
            infoItem("artist", "Artist", detail.artistCredit),
            infoItem("disambiguation", "Disambiguation", detail.disambiguation),
            infoItem("first-release", "First Release", detail.firstReleaseDate),
            infoItem("length", "Length", formattedDuration(detail.durationMilliseconds)),
            infoItem("genres", "Genres", formattedTerms(detail.genres)),
            infoItem("tags", "Tags", formattedTerms(detail.tags)),
            infoItem("rating", "Rating", formattedRating(detail.rating)),
            infoItem("isrc", "ISRC", detail.isrcs.joined(separator: ", "), monospaced: true),
            infoItem("mbid", "MBID", detail.id, monospaced: true)
        ].compactMap { $0 }

        MetadataSectionCard(title: overviewTitle, symbolName: "info.circle") {
            MetadataInfoRows(items: overviewItems)

            if let url = detail.musicBrainzURL {
                if !overviewItems.isEmpty {
                    MetadataCardDivider()
                }

                MetadataActionRow(
                    title: "MusicBrainz",
                    buttonTitle: "Open",
                    destination: url
                )
            }
        }

        if !detail.relationshipGroups.isEmpty {
            MetadataSectionCard(title: "Relationships", symbolName: "link") {
                MetadataInfoRows(
                    items: detail.relationshipGroups.compactMap { group in
                        infoItem(
                            group.title,
                            prettifiedRelationshipTitle(group.title),
                            joinedValues(group.values)
                        )
                    }
                )
            }
        }

        if !detail.annotation.isEmpty {
            MetadataSectionCard(title: "Annotation", symbolName: "text.alignleft") {
                MetadataBodyRow(text: detail.annotation)
            }
        }

        if !detail.releases.isEmpty {
            MetadataSectionCard(title: "Releases", symbolName: "opticaldisc") {
                ForEach(Array(detail.releases.enumerated()), id: \.element.id) { index, release in
                    MetadataSummaryRow(
                        title: release.title,
                        subtitle: releaseMetadataLine(release),
                        buttonTitle: release.musicBrainzURL == nil ? nil : "Open",
                        destination: release.musicBrainzURL
                    )

                    if index < detail.releases.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trackSections(_ detail: MusicBrainzTrackDetail) -> some View {
        let trackItems = [
            infoItem("title", "Title", detail.track.title),
            infoItem("number", "Number", detail.track.number, monospaced: true),
            infoItem("length", "Length", formattedDuration(detail.track.durationMilliseconds), monospaced: true),
            infoItem("recording-id", "Recording MBID", detail.track.recordingID, monospaced: true),
            infoItem("isrc", "ISRC", detail.track.isrcs.joined(separator: ", "), monospaced: true)
        ].compactMap { $0 }

        MetadataSectionCard(title: "Track", symbolName: "music.note") {
            MetadataInfoRows(items: trackItems)
        }

        if let recordingDetail = detail.recordingDetail {
            recordingSections(recordingDetail, overviewTitle: "Recording")
        }
    }

    @ViewBuilder
    private func releaseSections(_ detail: MusicBrainzReleaseDetail) -> some View {
        if let preview = detail.selectionMatchPreview {
            let comparisonGroups = preview.matchedAssignments.map { assignment in
                MetadataComparisonGroup(
                    id: assignment.id,
                    assignment: assignment,
                    rows: comparisonRows(for: assignment, release: detail)
                )
            }
            let overviewItems = [
                infoItem("matched", "Matched Files", "\(preview.matchedFileCount)/\(preview.totalSelectedFiles)", monospaced: true),
                infoItem("unmatched", "Unmatched Files", preview.unmatchedFiles.isEmpty ? "" : "\(preview.unmatchedFiles.count)", monospaced: true),
                infoItem("missing", "Unassigned Tracks", preview.unassignedTracks.isEmpty ? "" : "\(preview.unassignedTracks.count)", monospaced: true),
                infoItem("avg-score", "Average Track Score", String(format: "%.0f%%", preview.averageTrackScore * 100), monospaced: true),
                infoItem("mixed", "Selection", preview.selectionLooksMixed ? "Mixed" : "Coherent")
            ].compactMap { $0 }

            MetadataSectionCard(title: "Match Preview", symbolName: "checklist") {
                MetadataInfoRows(items: overviewItems)

                if !preview.matchedAssignments.isEmpty {
                    MetadataCardDivider()

                    NavigationLink {
                        MatchedFilesDetailView(assignments: preview.matchedAssignments)
                    } label: {
                        MetadataDetailNavigationRow(
                            title: "Matched Files",
                            subtitle: "\(preview.matchedFileCount) file-to-track assignment\(preview.matchedFileCount == 1 ? "" : "s")",
                            symbolName: "link"
                        )
                    }
                    .buttonStyle(.plain)

                    MetadataCardDivider()

                    NavigationLink {
                        MetadataComparisonDetailView(groups: comparisonGroups)
                    } label: {
                        MetadataDetailNavigationRow(
                            title: "Metadata Comparison",
                            subtitle: "Compare local file tags with MusicBrainz metadata",
                            symbolName: "arrow.left.arrow.right"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !preview.unmatchedFiles.isEmpty {
                MetadataSectionCard(title: "Unmatched Files", symbolName: "questionmark.circle") {
                    ForEach(Array(preview.unmatchedFiles.enumerated()), id: \.element.id) { index, file in
                        MetadataFileSummaryRow(file: file)

                        if index < preview.unmatchedFiles.count - 1 {
                            MetadataCardDivider()
                        }
                    }
                }
            }

            if !preview.unassignedTracks.isEmpty {
                MetadataSectionCard(title: "Unassigned Release Tracks", symbolName: "music.note.list") {
                    ForEach(Array(preview.unassignedTracks.enumerated()), id: \.element.id) { index, track in
                        MetadataReleaseTrackSummaryRow(track: track)

                        if index < preview.unassignedTracks.count - 1 {
                            MetadataCardDivider()
                        }
                    }
                }
            }
        }

        let overviewItems = [
            infoItem("title", "Title", detail.title),
            infoItem("artist", "Artist", detail.artistCredit),
            infoItem("release-date", "Release Date", detail.date),
            infoItem("country", "Country", detail.country),
            infoItem("status", "Status", detail.status),
            infoItem("barcode", "Barcode", detail.barcode, monospaced: true),
            infoItem("packaging", "Packaging", detail.packaging),
            infoItem("asin", "ASIN", detail.asin, monospaced: true),
            infoItem("quality", "Quality", detail.quality),
            infoItem("language", "Language", detail.language),
            infoItem("script", "Script", detail.script),
            infoItem("genres", "Genres", formattedTerms(detail.genres)),
            infoItem("tags", "Tags", formattedTerms(detail.tags)),
            infoItem("mbid", "MBID", detail.id, monospaced: true)
        ].compactMap { $0 }

        MetadataSectionCard(title: "Overview", symbolName: "info.circle") {
            MetadataInfoRows(items: overviewItems)

            if let url = detail.musicBrainzURL {
                if !overviewItems.isEmpty {
                    MetadataCardDivider()
                }

                MetadataActionRow(
                    title: "MusicBrainz",
                    buttonTitle: "Open",
                    destination: url
                )
            }
        }

        if !detail.annotation.isEmpty {
            MetadataSectionCard(title: "Annotation", symbolName: "text.alignleft") {
                MetadataBodyRow(text: detail.annotation)
            }
        }

        let releaseGroupItems = [
            infoItem("title", "Title", detail.releaseGroupTitle),
            infoItem("mbid", "MBID", detail.releaseGroupID, monospaced: true),
            infoItem("primary-type", "Primary Type", detail.releaseGroupPrimaryType),
            infoItem("secondary-types", "Secondary Types", detail.releaseGroupSecondaryTypes.joined(separator: ", "))
        ].compactMap { $0 }

        if !releaseGroupItems.isEmpty {
            MetadataSectionCard(title: "Release Group", symbolName: "square.stack") {
                MetadataInfoRows(items: releaseGroupItems)
            }
        }

        if !detail.labels.isEmpty {
            MetadataSectionCard(title: "Labels", symbolName: "building.2") {
                ForEach(Array(detail.labels.enumerated()), id: \.element.id) { index, label in
                    MetadataSummaryRow(
                        title: label.labelName.isEmpty ? "Unknown Label" : label.labelName,
                        subtitle: label.catalogNumber.isEmpty ? "" : "Catalog No. \(label.catalogNumber)",
                        trailingText: label.id
                    )

                    if index < detail.labels.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }

        ForEach(detail.media) { medium in
            let mediumItems = [
                infoItem("title", "Title", medium.title),
                infoItem("format", "Format", medium.format),
                infoItem("track-count", "Track Count", medium.trackCount > 0 ? String(medium.trackCount) : "", monospaced: true),
                infoItem("disc-ids", "Disc IDs", medium.discIDs.joined(separator: ", "), monospaced: true)
            ].compactMap { $0 }

            MetadataSectionCard(title: mediumSectionTitle(medium), symbolName: "opticaldiscdrive") {
                if !mediumItems.isEmpty {
                    MetadataInfoRows(items: mediumItems)

                    if !medium.tracks.isEmpty {
                        MetadataCardDivider()
                    }
                }

                if !medium.tracks.isEmpty {
                    ForEach(Array(medium.tracks.enumerated()), id: \.element.id) { index, track in
                        NavigationLink(value: MusicBrainzBrowserDestination.track(track)) {
                            MetadataTrackRow(
                                number: track.number,
                                title: track.title,
                                duration: formattedDuration(track.durationMilliseconds)
                            )
                        }
                        .buttonStyle(.plain)

                        if index < medium.tracks.count - 1 {
                            MetadataCardDivider()
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

    private func infoItem(_ id: String, _ title: String, _ value: String, monospaced: Bool = false) -> MetadataInfoItem? {
        guard !value.isEmpty else { return nil }
        return MetadataInfoItem(id: id, title: title, value: value, monospaced: monospaced)
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
            return "\(base) • \(medium.trackCount) Tracks"
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

    private func prettifiedRelationshipTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                if word == "℗" {
                    return String(word)
                }
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private func comparisonRows(
        for assignment: MusicBrainzReleaseMatchAssignment,
        release: MusicBrainzReleaseDetail
    ) -> [MetadataComparisonRow] {
        [
            comparisonRow("title", "Title", local: assignment.file.title, remote: assignment.track.title),
            comparisonRow(
                "artist",
                "Artist",
                local: assignment.file.artist,
                remote: assignment.track.artistCredit.isEmpty ? release.artistCredit : assignment.track.artistCredit
            ),
            comparisonRow("album-artist", "Album Artist", local: assignment.file.albumArtist, remote: release.artistCredit),
            comparisonRow("album", "Album", local: assignment.file.album, remote: release.title),
            comparisonRow("track-number", "Track Number", local: assignment.file.trackNumber, remote: assignment.track.number, monospaced: true),
            comparisonRow(
                "disc-number",
                "Disc Number",
                local: assignment.file.discNumber,
                remote: assignment.track.mediumPosition > 0 ? String(assignment.track.mediumPosition) : "",
                monospaced: true
            ),
            comparisonRow("release-date", "Release Date", local: assignment.file.releaseDate, remote: release.date),
            comparisonRow(
                "isrc",
                "ISRC",
                local: assignment.file.isrc,
                remote: assignment.track.isrcs.joined(separator: ", "),
                monospaced: true
            ),
            comparisonRow("barcode", "Barcode", local: assignment.file.barcode, remote: release.barcode, monospaced: true)
        ].compactMap { $0 }
    }

    private func comparisonRow(
        _ id: String,
        _ title: String,
        local: String,
        remote: String,
        monospaced: Bool = false
    ) -> MetadataComparisonRow? {
        let localValue = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteValue = remote.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !localValue.isEmpty || !remoteValue.isEmpty else { return nil }

        let status: MetadataComparisonStatus
        if localValue.isEmpty {
            status = .missingLocal
        } else if remoteValue.isEmpty {
            status = .missingRemote
        } else if normalizedComparisonValue(localValue) == normalizedComparisonValue(remoteValue) {
            status = .same
        } else {
            status = .different
        }

        return MetadataComparisonRow(
            id: id,
            title: title,
            localValue: localValue,
            remoteValue: remoteValue,
            status: status,
            monospaced: monospaced
        )
    }

    private func normalizedComparisonValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private extension MusicBrainzMetadataDetailView {
    enum LoadState {
        case loading
        case loaded(MusicBrainzMetadataDetail)
        case failed(String)
    }
}

private struct MetadataInfoItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let monospaced: Bool
}

private struct MetadataComparisonRow: Identifiable {
    let id: String
    let title: String
    let localValue: String
    let remoteValue: String
    let status: MetadataComparisonStatus
    let monospaced: Bool
}

private struct MetadataComparisonGroup: Identifiable {
    let id: String
    let assignment: MusicBrainzReleaseMatchAssignment
    let rows: [MetadataComparisonRow]
}

private enum MetadataComparisonStatus {
    case same
    case different
    case missingLocal
    case missingRemote

    var symbolName: String {
        switch self {
        case .same:
            return "checkmark.circle.fill"
        case .different:
            return "arrow.left.arrow.right.circle.fill"
        case .missingLocal:
            return "square.and.arrow.down.fill"
        case .missingRemote:
            return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .same:
            return .green
        case .different:
            return .orange
        case .missingLocal:
            return .accentColor
        case .missingRemote:
            return .secondary
        }
    }

    var label: String {
        switch self {
        case .same:
            return "Same"
        case .different:
            return "Different"
        case .missingLocal:
            return "Missing Locally"
        case .missingRemote:
            return "Missing on MusicBrainz"
        }
    }
}

private struct MetadataSectionCard<Content: View>: View {
    let title: String
    let symbolName: String?
    @ViewBuilder let content: Content

    init(title: String, symbolName: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbolName = symbolName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 10, weight: .semibold))
                }

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )
        }
    }
}

private struct MetadataInfoRows: View {
    let items: [MetadataInfoItem]

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            MetadataInfoRow(item: item)

            if index < items.count - 1 {
                MetadataCardDivider()
            }
        }
    }
}

private struct MetadataInfoRow: View {
    let item: MetadataInfoItem

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(item.title)
                .font(.system(size: 13))
                .frame(width: 140, alignment: .leading)

            Spacer(minLength: 12)

            Text(item.value)
                .font(item.monospaced ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: 520, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}

private struct MetadataBodyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }
}

private struct MetadataActionRow: View {
    let title: String
    let buttonTitle: String
    let destination: URL

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 140, alignment: .leading)

            Spacer(minLength: 12)

            Link(buttonTitle, destination: destination)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct MetadataSummaryRow: View {
    let title: String
    let subtitle: String
    let trailingText: String
    let buttonTitle: String?
    let destination: URL?

    init(
        title: String,
        subtitle: String = "",
        trailingText: String = "",
        buttonTitle: String? = nil,
        destination: URL? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingText = trailingText
        self.buttonTitle = buttonTitle
        self.destination = destination
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if !trailingText.isEmpty {
                Text(trailingText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .frame(maxWidth: 280, alignment: .trailing)
            }

            if let buttonTitle, let destination {
                Link(buttonTitle, destination: destination)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}

private struct MetadataDetailNavigationRow: View {
    let title: String
    let subtitle: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13))

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct MetadataMatchAssignmentRow: View {
    let assignment: MusicBrainzReleaseMatchAssignment

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.file.preferredDisplayTitle)
                    .font(.system(size: 13))

                let subtitle = fileSubtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(trackTitle)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.trailing)

                Text(assignment.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var fileSubtitle: String {
        [assignment.file.artist, assignment.file.album]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var trackTitle: String {
        let number = assignment.track.number.isEmpty ? "" : "\(assignment.track.number) "
        return number + assignment.track.title
    }
}

private struct MetadataFileSummaryRow: View {
    let file: MusicBrainzFileSearchInput

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.preferredDisplayTitle)
                    .font(.system(size: 13))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var subtitle: String {
        [file.artist, file.album]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct MetadataReleaseTrackSummaryRow: View {
    let track: MusicBrainzReleaseMatchTrack

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trackTitle)
                    .font(.system(size: 13))

                let subtitle = trackSubtitle
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var trackTitle: String {
        let number = track.number.isEmpty ? "" : "\(track.number) "
        return number + track.title
    }

    private var trackSubtitle: String {
        [track.artistCredit, track.mediumFormat.isEmpty ? track.mediumTitle : track.mediumFormat]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct MetadataTrackRow: View {
    let number: String
    let title: String
    let duration: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(number.isEmpty ? "•" : number)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            Text(title)
                .font(.system(size: 13))

            Spacer(minLength: 12)

            if !duration.isEmpty {
                Text(duration)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

private struct MatchedFilesDetailView: View {
    let assignments: [MusicBrainzReleaseMatchAssignment]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                MetadataSectionCard(title: "Matched Files", symbolName: "link") {
                    ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                        MetadataMatchAssignmentRow(assignment: assignment)

                        if index < assignments.count - 1 {
                            MetadataCardDivider()
                        }
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Matched Files")
    }
}

private struct MetadataComparisonDetailView: View {
    let groups: [MetadataComparisonGroup]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                MetadataSectionCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        MetadataComparisonGroupView(
                            assignment: group.assignment,
                            rows: group.rows
                        )

                        if index < groups.count - 1 {
                            MetadataCardDivider()
                        }
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Metadata Comparison")
    }
}

private struct MetadataComparisonGroupView: View {
    let assignment: MusicBrainzReleaseMatchAssignment
    let rows: [MetadataComparisonRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment.file.preferredDisplayTitle)
                        .font(.system(size: 13, weight: .semibold))

                    if !fileSubtitle.isEmpty {
                        Text(fileSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(trackTitle)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.trailing)

                    Text(assignment.reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 260, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if !rows.isEmpty {
                Divider()
                    .padding(.leading, 18)

                MetadataComparisonTableHeader()

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    MetadataComparisonRowView(row: row)

                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }

    private var fileSubtitle: String {
        [assignment.file.artist, assignment.file.album]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var trackTitle: String {
        let number = assignment.track.number.isEmpty ? "" : "\(assignment.track.number) "
        return number + assignment.track.title
    }
}

private struct MetadataComparisonTableHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Field")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("File")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("MusicBrainz")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct MetadataComparisonRowView: View {
    let row: MetadataComparisonRow

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(row.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            comparisonValue(row.localValue)

            Image(systemName: row.status.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(row.status.color)
                .help(row.status.label)
                .frame(width: 18)
                .padding(.top, 1)

            comparisonValue(row.remoteValue)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func comparisonValue(_ value: String) -> some View {
        Text(value.isEmpty ? "—" : value)
            .font(row.monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
            .foregroundStyle(value.isEmpty ? .tertiary : .primary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetadataCardDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 18)
    }
}
