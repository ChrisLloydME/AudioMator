import SwiftUI

struct MusicBrainzBrowserView: View {
    static let windowID = "musicbrainz-browser"

    @ObservedObject var store: MusicBrainzBrowserStore

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()

            content
        }
        .frame(minWidth: 920, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.mode) { oldMode, newMode in
            store.handleModeChange(from: oldMode, to: newMode)
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
                    store.albumQuery.isEmpty &&
                    store.results.isEmpty &&
                    store.errorMessage == nil
                )
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                MusicBrainzQueryField(
                    title: store.mode == .track ? "Track" : "Release",
                    symbolName: store.mode == .track ? "music.note" : "square.stack",
                    text: primaryQueryBinding
                )

                MusicBrainzQueryField(
                    title: "Artist",
                    symbolName: "person",
                    text: $store.artistQuery
                )

                if store.mode == .track {
                    MusicBrainzQueryField(
                        title: "Album",
                        symbolName: "opticaldisc",
                        text: $store.albumQuery
                    )
                }
            }

            HStack(spacing: 8) {
                Spacer()

                if store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if store.lastSubmittedQuery != nil {
                    Text("\(store.results.count) \(store.visibleResultMode == .track ? "track" : "album") result\(store.results.count == 1 ? "" : "s")")
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
                                ? "Choose Track or Album search, then fill in the fields above."
                            : "MusicBrainz did not return any \(store.visibleResultMode == .track ? "tracks" : "albums") for the current query."
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
                        MusicBrainzRecordingRow(result: result)
                            .padding(.vertical, 6)
                    }
                case .releases(let results):
                    ForEach(results) { result in
                        MusicBrainzReleaseRow(result: result)
                            .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var primaryQueryBinding: Binding<String> {
        switch store.mode {
        case .track:
            return $store.titleQuery
        case .album:
            return $store.albumQuery
        }
    }
}

private struct MusicBrainzQueryField: View {
    let title: String
    let symbolName: String
    @Binding var text: String

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
                .frame(minWidth: 220)
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

                if let url = result.musicBrainzURL {
                    Link(destination: url) {
                        Label("Recording", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.link)
                }

                if let releaseURL = result.primaryRelease?.musicBrainzURL {
                    Link(destination: releaseURL) {
                        Label("Release", systemImage: "music.note.list")
                    }
                    .buttonStyle(.link)
                }
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

                if let url = result.musicBrainzURL {
                    Link(destination: url) {
                        Label("Release", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.link)
                }
            }

            if !result.artistCredit.isEmpty {
                Label(result.artistCredit, systemImage: "person.2")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
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
