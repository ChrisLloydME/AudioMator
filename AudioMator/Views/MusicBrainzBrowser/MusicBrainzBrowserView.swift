import SwiftUI

struct MusicBrainzBrowserView: View {
    static let windowID = "musicbrainz-browser"

    @ObservedObject var store: MusicBrainzBrowserStore
    @State private var navigationPath: [MusicBrainzBrowserDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                searchHeader

                Divider()

                content
            }
            .navigationDestination(for: MusicBrainzBrowserDestination.self) { destination in
                MusicBrainzMetadataDetailView(store: store, destination: destination)
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
                    store.lastSubmittedQuery == nil ? "No Search Yet" : "No Results",
                    systemImage: "magnifyingglass",
                    description: Text(
                            store.lastSubmittedQuery == nil
                                ? "Choose Track, Album, File, or MusicBrainz Link search, then fill in the fields above."
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
            VStack(alignment: .leading, spacing: 12) {
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
                        title: "Album Artist",
                        symbolName: "person.2",
                        text: $store.albumArtistQuery
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    MusicBrainzQueryField(
                        title: "Album",
                        symbolName: "opticaldisc",
                        text: $store.albumQuery
                    )

                    MusicBrainzQueryField(
                        title: "Track No.",
                        symbolName: "number",
                        text: $store.trackNumberQuery,
                        minimumWidth: 140
                    )
                }
            }
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
            return "track"
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
            return "MusicBrainz did not return any tracks for the current query."
        case .album:
            return "MusicBrainz did not return any albums for the current query."
        case .file:
            return "MusicBrainz did not return any good track matches for the current file metadata."
        case .link:
            return "MusicBrainz did not resolve the supplied link to a supported result."
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

            HStack(spacing: 12) {
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
