import SwiftUI

struct ITunesQueryField: View {
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

struct ITunesFileSelectionSummaryView: View {
    let summary: ITunesFileSelectionSummary?

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
                ITunesFileSelectionSummaryList(rows: summaryRows(for: summary))

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
            return "Select files in AudioMator, then choose Find in iTunes."
        }

        if summary.isMultiFile {
            return "Find matching albums, then map the selected files to iTunes tracks."
        }

        return "Find the best iTunes track match from the selected file's metadata."
    }

    private func summaryRows(for summary: ITunesFileSelectionSummary) -> [ITunesSelectionSummaryRow] {
        var rows: [ITunesSelectionSummaryRow] = [
            ITunesSelectionSummaryRow(id: "files", title: "Files", value: "\(summary.totalSelectedFiles)", symbolName: "music.note.list")
        ]

        if !summary.albumCandidate.isEmpty {
            rows.append(ITunesSelectionSummaryRow(id: "album", title: "Album", value: summary.albumCandidate, symbolName: "opticaldisc"))
        }

        if !summary.albumArtistCandidate.isEmpty {
            rows.append(
                ITunesSelectionSummaryRow(
                    id: "album-artist",
                    title: "Album Artist",
                    value: summary.albumArtistCandidate,
                    symbolName: "person.2"
                )
            )
        } else if !summary.primaryArtistCandidate.isEmpty {
            rows.append(
                ITunesSelectionSummaryRow(
                    id: "artist",
                    title: "Artist",
                    value: summary.primaryArtistCandidate,
                    symbolName: "person"
                )
            )
        }

        if summary.trackCountCandidate > 0 {
            rows.append(
                ITunesSelectionSummaryRow(
                    id: "track-count",
                    title: "Track Count",
                    value: "\(summary.trackCountCandidate)",
                    symbolName: "number"
                )
            )
        }

        if !summary.releaseYearCandidate.isEmpty {
            rows.append(
                ITunesSelectionSummaryRow(
                    id: "year",
                    title: "Year",
                    value: summary.releaseYearCandidate,
                    symbolName: "calendar"
                )
            )
        }

        if !summary.barcodeCandidate.isEmpty {
            rows.append(
                ITunesSelectionSummaryRow(
                    id: "barcode",
                    title: "UPC/EAN",
                    value: summary.barcodeCandidate,
                    symbolName: "barcode"
                )
            )
        }

        if !summary.itunesAlbumIDCandidate.isEmpty {
            rows.append(
                ITunesSelectionSummaryRow(
                    id: "itunes-id",
                    title: "iTunes Album ID",
                    value: summary.itunesAlbumIDCandidate,
                    symbolName: "number.square"
                )
            )
        }

        return rows
    }
}

private struct ITunesSelectionSummaryRow: Identifiable {
    let id: String
    let title: String
    let value: String
    let symbolName: String
}

private struct ITunesFileSelectionSummaryList: View {
    let rows: [ITunesSelectionSummaryRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ITunesFileSelectionRow(row: row)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(platformColor: .audiomatorControlBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(platformColor: .audiomatorSeparator).opacity(0.3), lineWidth: 1)
        )
    }
}

private struct ITunesFileSelectionRow: View {
    let row: ITunesSelectionSummaryRow

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

struct ITunesTrackRow: View {
    let track: ITunesTrackResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(track.trackName.isEmpty ? "Untitled Track" : track.trackName)
                    .font(.system(size: 15, weight: .semibold))

                if track.isExplicit {
                    Text("Explicit")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                        .foregroundStyle(Color.orange)
                }

                Spacer()
            }

            if !track.artistName.isEmpty {
                Label(track.artistName, systemImage: "person.2")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if !track.collectionName.isEmpty {
                    ITunesMetaPill(title: "Album", value: track.collectionName)
                }

                if track.trackNumber > 0 {
                    ITunesMetaPill(title: "Track", value: track.trackCount > 0 ? "\(track.trackNumber)/\(track.trackCount)" : "\(track.trackNumber)")
                }

                let durationText = formattedITunesDuration(track.durationMilliseconds)
                if !durationText.isEmpty {
                    ITunesMetaPill(title: "Length", value: durationText)
                }

                if !track.releaseDate.isEmpty {
                    ITunesMetaPill(title: "Release Date", value: track.releaseDate)
                }

                if !track.country.isEmpty {
                    ITunesMetaPill(title: "Country", value: track.country)
                }
            }

            if !track.primaryGenreName.isEmpty {
                Text(track.primaryGenreName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ITunesAlbumRow: View {
    let album: ITunesAlbumResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(album.collectionName.isEmpty ? "Untitled Album" : album.collectionName)
                    .font(.system(size: 15, weight: .semibold))

                if let preview = album.selectionMatchPreview {
                    Text("Matched \(preview.matchedAssignments.count)/\(preview.totalSelectedFiles)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                        .foregroundStyle(Color.green)

                    Text("\(Int((preview.overallScore * 100).rounded()))%")
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

            if !album.artistName.isEmpty {
                Label(album.artistName, systemImage: "person.2")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let preview = album.selectionMatchPreview {
                    if !preview.unmatchedFiles.isEmpty {
                        ITunesMetaPill(title: "Unmatched", value: "\(preview.unmatchedFiles.count)")
                    }

                    if !preview.unassignedTracks.isEmpty {
                        ITunesMetaPill(title: "Missing Tracks", value: "\(preview.unassignedTracks.count)")
                    }
                }

                if album.trackCount > 0 {
                    ITunesMetaPill(title: "Tracks", value: "\(album.trackCount)")
                }

                if !album.primaryGenreName.isEmpty {
                    ITunesMetaPill(title: "Genre", value: album.primaryGenreName)
                }

                if !album.releaseDate.isEmpty {
                    ITunesMetaPill(title: "Release Date", value: album.releaseDate)
                }

                if !album.country.isEmpty {
                    ITunesMetaPill(title: "Country", value: album.country)
                }
            }

            if album.selectionMatchPreview != nil,
               album.selectionMatchScore ?? 0 < 0.55 {
                Text("Low confidence match. Check the file-to-track matches in the detail view.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ITunesStorefrontChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(Color.accentColor)
    }
}

private struct ITunesMetaPill: View {
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

func formattedITunesDuration(_ milliseconds: Int?) -> String {
    guard let milliseconds, milliseconds > 0 else { return "" }
    let totalSeconds = max(0, milliseconds / 1000)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
