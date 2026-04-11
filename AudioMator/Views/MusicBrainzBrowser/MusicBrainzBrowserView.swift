#if os(macOS)
import SwiftUI

struct MusicBrainzBrowserView: View {
    static let windowID = "musicbrainz-browser"

    @ObservedObject var store: MusicBrainzBrowserStore
    @ObservedObject var viewModel: AudioViewModel
    @State private var navigationPath: [MusicBrainzBrowserDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                searchHeader

                Divider()

                content
            }
            .navigationDestination(for: MusicBrainzBrowserDestination.self) { destination in
                MusicBrainzMetadataDetailView(
                    store: store,
                    viewModel: viewModel,
                    destination: destination
                )
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.mode) { oldMode, newMode in
            store.handleModeChange(from: oldMode, to: newMode)
        }
        .onChange(of: store.navigationResetToken) { _, _ in
            navigationPath.removeAll()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Search Mode", selection: $store.mode) {
                    ForEach(MusicBrainzSearchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if navigationPath.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Search") {
                        store.search()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.hasSearchText || store.isSearching)

                    Button("Clear") {
                        store.clearSearch()
                    }
                    .disabled(
                        store.titleQuery.isEmpty &&
                        store.artistQuery.isEmpty &&
                        store.albumArtistQuery.isEmpty &&
                        store.albumQuery.isEmpty &&
                        store.trackNumberQuery.isEmpty &&
                        store.linkQuery.isEmpty &&
                        store.results.isEmpty &&
                        store.errorMessage == nil
                    )
                }
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchFields

            HStack(spacing: 8) {
                Spacer()

                if store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if store.lastSubmittedQuery != nil {
                    Text("\(store.results.count) \(resultUnitLabel) result\(store.results.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .onSubmit {
            store.search()
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isSearching && store.results.isEmpty {
            VStack(spacing: 0) {
                ProgressView("Searching MusicBrainz…")
                    .padding(.top, 56)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let errorMessage = store.errorMessage {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "Search Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .padding(.top, 36)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if store.results.isEmpty {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    store.lastSubmittedQuery == nil ? "Search MusicBrainz" : "No Results",
                    systemImage: "magnifyingglass",
                    description: Text(
                            store.lastSubmittedQuery == nil
                                ? "Choose a search mode, then enter what you know."
                                : noResultsDescription
                    )
                )
                .padding(.top, 36)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            List {
                switch store.results {
                case .recordings(let results):
                    ForEach(results) { result in
                        NavigationLink(value: MusicBrainzBrowserDestination.recording(result)) {
                            MusicBrainzRecordingRow(result: result)
                                .padding(.vertical, 6)
                        }
                    }
                case .releases(let results):
                    ForEach(results) { result in
                        NavigationLink(value: MusicBrainzBrowserDestination.release(result)) {
                            MusicBrainzReleaseRow(result: result)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var searchFields: some View {
        switch store.mode {
        case .track:
            HStack(alignment: .top, spacing: 12) {
                MusicBrainzQueryField(
                    title: "Track",
                    symbolName: "music.note",
                    text: $store.titleQuery
                )

                MusicBrainzQueryField(
                    title: "Artist",
                    symbolName: "person",
                    text: $store.artistQuery
                )

                MusicBrainzQueryField(
                    title: "Album",
                    symbolName: "opticaldisc",
                    text: $store.albumQuery
                )
            }
        case .album:
            HStack(alignment: .top, spacing: 12) {
                MusicBrainzQueryField(
                    title: "Release",
                    symbolName: "square.stack",
                    text: $store.albumQuery
                )

                MusicBrainzQueryField(
                    title: "Artist",
                    symbolName: "person",
                    text: $store.artistQuery
                )
            }
        case .file:
            MusicBrainzFileSelectionSummaryView(summary: store.fileSelectionSummary)
        case .link:
            MusicBrainzQueryField(
                title: "MusicBrainz Link",
                symbolName: "network",
                text: $store.linkQuery
            )
        }
    }

    private var resultUnitLabel: String {
        switch store.mode {
        case .track:
            return "track"
        case .album:
            return "album"
        case .file:
            switch store.results {
            case .recordings:
                return "track"
            case .releases:
                return "album"
            }
        case .link:
            switch store.results {
            case .recordings:
                return "track"
            case .releases:
                return "album"
            }
        }
    }

    private var noResultsDescription: String {
        switch store.mode {
        case .track:
            return "No tracks matched this search."
        case .album:
            return "No albums matched this search."
        case .file:
            return store.isMultiFileSelection
                ? "No strong album matches for the selected files."
                : "No strong track matches for the selected file."
        case .link:
            return "That link didn't resolve to a supported MusicBrainz result."
        }
    }
}

private struct MusicBrainzQueryField: View {
    let title: String
    let symbolName: String
    @Binding var text: String
    var minimumWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.leading, 2)

            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: minimumWidth)
        }
    }
}

private struct MusicBrainzFileSelectionSummaryView: View {
    let summary: MusicBrainzFileSelectionSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: summary?.isMultiFile == true ? "square.stack.3d.up" : "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(selectionTitle)
                    .font(.system(size: 13, weight: .semibold))
            }

            Text(selectionDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let summary {
                MusicBrainzFileSelectionSummaryList(rows: summaryRows(for: summary))

                if summary.selectionLooksMixed {
                    Label("Selection looks mixed. Album matches may be less accurate.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var selectionTitle: String {
        guard let summary else { return "No Files Selected" }
        return summary.isMultiFile ? "Selected Files" : "Selected File"
    }

    private var selectionDescription: String {
        guard let summary else {
            return "Select files in AudioMator, then choose Find in MusicBrainz."
        }

        if summary.isMultiFile {
            return "Find matching releases, then map the selected files to album tracks."
        }

        return "Find the best recording match from the selected file's metadata."
    }

    private func summaryRows(for summary: MusicBrainzFileSelectionSummary) -> [SelectionSummaryRow] {
        var rows: [SelectionSummaryRow] = [
            SelectionSummaryRow(id: "files", title: "Files", value: "\(summary.totalSelectedFiles)", symbolName: "music.note.list")
        ]

        if !summary.albumCandidate.isEmpty {
            rows.append(SelectionSummaryRow(id: "album", title: "Album", value: summary.albumCandidate, symbolName: "opticaldisc"))
        }

        if !summary.albumArtistCandidate.isEmpty {
            rows.append(
                SelectionSummaryRow(
                    id: "album-artist",
                    title: "Album Artist",
                    value: summary.albumArtistCandidate,
                    symbolName: "person.2"
                )
            )
        } else if !summary.primaryArtistCandidate.isEmpty {
            rows.append(
                SelectionSummaryRow(
                    id: "artist",
                    title: "Artist",
                    value: summary.primaryArtistCandidate,
                    symbolName: "person"
                )
            )
        }

        if summary.releaseTrackCountCandidate > 0 {
            rows.append(
                SelectionSummaryRow(
                    id: "track-count",
                    title: "Track Count",
                    value: "\(summary.releaseTrackCountCandidate)",
                    symbolName: "number"
                )
            )
        }

        if !summary.releaseYearCandidate.isEmpty {
            rows.append(
                SelectionSummaryRow(
                    id: "year",
                    title: "Year",
                    value: summary.releaseYearCandidate,
                    symbolName: "calendar"
                )
            )
        }

        return rows
    }
}

private struct SelectionSummaryRow: Identifiable {
    let id: String
    let title: String
    let value: String
    let symbolName: String
}

private struct MusicBrainzFileSelectionSummaryList: View {
    let rows: [SelectionSummaryRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                MusicBrainzFileSelectionRow(row: row)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

private struct MusicBrainzFileSelectionRow: View {
    let row: SelectionSummaryRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Label {
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: row.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .frame(width: 132, alignment: .leading)

            Spacer(minLength: 0)

            Text(row.value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct MusicBrainzRecordingRow: View {
    let result: MusicBrainzRecordingResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(result.title)
                    .font(.system(size: 15, weight: .semibold))

                Text("Score \(result.score)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)

                Spacer()
            }

            if !result.artistCredit.isEmpty {
                Label(result.artistCredit, systemImage: "person.2")
                    .foregroundStyle(.secondary)
            }

            if !result.disambiguation.isEmpty {
                Text(result.disambiguation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !result.firstReleaseDate.isEmpty {
                    MusicBrainzMetaPill(
                        title: "First Release",
                        value: result.firstReleaseDate
                    )
                }

                if let durationText = formattedDuration(result.durationMilliseconds) {
                    MusicBrainzMetaPill(
                        title: "Length",
                        value: durationText
                    )
                }

                if let release = result.primaryRelease {
                    if !release.country.isEmpty {
                        MusicBrainzMetaPill(
                            title: "Country",
                            value: release.country
                        )
                    }

                    if !release.status.isEmpty {
                        MusicBrainzMetaPill(
                            title: "Status",
                            value: release.status
                        )
                    }
                }
            }

            if let release = result.primaryRelease {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Primary release")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(release.title)
                        .font(.system(size: 13))

                    if !release.date.isEmpty {
                        Text(release.date)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func formattedDuration(_ milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }

        let totalSeconds = milliseconds / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}

private struct MusicBrainzReleaseRow: View {
    let result: MusicBrainzReleaseSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(result.title)
                    .font(.system(size: 15, weight: .semibold))

                if let preview = result.selectionMatchPreview {
                    Text("Matched \(preview.matchedFileCount)/\(preview.totalSelectedFiles)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                        .foregroundStyle(Color.green)

                    Text("MB \(result.score)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Score \(result.score)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()
            }

            if !result.artistCredit.isEmpty {
                Label(result.artistCredit, systemImage: "person.2")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let preview = result.selectionMatchPreview {
                    if !preview.unmatchedFiles.isEmpty {
                        MusicBrainzMetaPill(title: "Unmatched", value: "\(preview.unmatchedFiles.count)")
                    }

                    if !preview.unassignedTracks.isEmpty {
                        MusicBrainzMetaPill(title: "Missing Tracks", value: "\(preview.unassignedTracks.count)")
                    }
                }

                if !result.mediaFormatSummary.isEmpty {
                    MusicBrainzMetaPill(title: "Medium", value: result.mediaFormatSummary)
                }

                if !result.date.isEmpty {
                    MusicBrainzMetaPill(title: "Release Date", value: result.date)
                }

                if !result.country.isEmpty {
                    MusicBrainzMetaPill(title: "Country", value: result.country)
                }

                if !result.status.isEmpty {
                    MusicBrainzMetaPill(title: "Status", value: result.status)
                }
            }

            if let releaseGroup = result.releaseGroup,
               !releaseGroup.primaryType.isEmpty || !releaseGroup.secondaryTypes.isEmpty {
                let detail = ([releaseGroup.primaryType] + releaseGroup.secondaryTypes)
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let preview = result.selectionMatchPreview, preview.selectionLooksMixed {
                Text("Selection looks mixed. Check the file-to-track matches in the detail view.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MusicBrainzMetaPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
#endif
