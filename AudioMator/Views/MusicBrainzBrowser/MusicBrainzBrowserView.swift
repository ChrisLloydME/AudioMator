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
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MusicBrainz Browser")
                    .font(.system(size: 24, weight: .semibold))

                Text(store.sourceDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 12) {
                MusicBrainzQueryField(
                    title: "Title",
                    text: $store.titleQuery,
                    prompt: "Track title"
                )

                MusicBrainzQueryField(
                    title: "Artist",
                    text: $store.artistQuery,
                    prompt: "Artist credit"
                )

                MusicBrainzQueryField(
                    title: "Album",
                    text: $store.albumQuery,
                    prompt: "Release title"
                )

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

            if let lastSubmittedQuery = store.lastSubmittedQuery, !lastSubmittedQuery.isEmpty {
                HStack(spacing: 8) {
                    Text("Current search")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(lastSubmittedQuery.summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Spacer()

                    if store.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("\(store.results.count) result\(store.results.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .onSubmit {
            store.search()
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isSearching && store.results.isEmpty {
            VStack {
                Spacer()
                ProgressView("Searching MusicBrainz…")
                Spacer()
            }
        } else if let errorMessage = store.errorMessage {
            ContentUnavailableView(
                "Search Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if store.results.isEmpty {
            ContentUnavailableView(
                store.lastSubmittedQuery == nil ? "No Search Yet" : "No Results",
                systemImage: "magnifyingglass",
                description: Text(
                    store.lastSubmittedQuery == nil
                        ? "Open this window from the toolbar to seed the query from the current track, or type your own fields above."
                        : "MusicBrainz did not return any recordings for the current query."
                )
            )
        } else {
            List(store.results) { result in
                MusicBrainzRecordingRow(result: result)
                    .padding(.vertical, 6)
            }
            .listStyle(.inset)
        }
    }
}

private struct MusicBrainzQueryField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
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
