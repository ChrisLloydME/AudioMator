import SwiftUI
import WebKit

struct ITunesTrackDetailView: View {
    let track: ITunesTrackResult
    @ObservedObject var store: ITunesBrowserStore
    @ObservedObject var viewModel: AudioViewModel

    @State private var isPreparingWorkbench = false
    @State private var workbenchStore: ITunesTaggingWorkbenchStore?

    var body: some View {
        detailContent
        .navigationTitle(track.trackName.isEmpty ? "iTunes Track" : track.trackName)
        .sheet(item: $workbenchStore) { store in
            NavigationStack {
                ITunesTaggingWorkbenchView(store: store, viewModel: viewModel)
            }
        }
    }

    private var detailContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if store.seededFileInputs.count == 1 {
                    MetadataSectionCard(title: "Selected File Match", symbolName: "checklist") {
                        ITunesMetadataButtonRow(
                            title: "Review & Apply Tags",
                            subtitle: "Adjust assignments and choose exactly which fields to write",
                            symbolName: "square.and.pencil",
                            isLoading: isPreparingWorkbench
                        ) {
                            prepareWorkbench()
                        }
                        .disabled(isPreparingWorkbench)
                    }
                }

                MetadataSectionCard(title: "Overview", symbolName: "info.circle") {
                    ITunesMetadataInfoRows(items: overviewItems)

                    if let url = track.trackViewURL {
                        MetadataCardDivider()
                        ITunesMetadataLinkRow(title: "Apple Music", destination: url)
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(platformColor: .audiomatorWindowBackground))
    }

    private var overviewItems: [ITunesMetadataInfoItem] {
        [
            infoItem("title", "Title", track.trackName),
            infoItem("artist", "Artist", track.artistName),
            infoItem("album-artist", "Album Artist", track.collectionArtistName),
            infoItem("album", "Album", track.collectionName),
            infoItem("genre", "Genre", track.primaryGenreName),
            infoItem("track", "Track", numberPair(track.trackNumber, track.trackCount), monospaced: true),
            infoItem("disc", "Disc", numberPair(track.discNumber, track.discCount), monospaced: true),
            infoItem("length", "Length", formattedITunesDuration(track.durationMilliseconds), monospaced: true),
            infoItem("release-date", "Release Date", track.releaseDate),
            infoItem("country", "Country", track.country),
            infoItem("explicit", "Explicit", track.contentAdvisory?.displayName ?? L10n.string("Unset")),
            infoItem("advisory", "Advisory", track.contentAdvisoryRating),
            infoItem("kind", "Kind", track.kind),
            infoItem("track-id", "iTunes Track ID", String(track.trackID), monospaced: true),
            infoItem("collection-id", "iTunes Album ID", track.collectionID.map(String.init) ?? "", monospaced: true),
            infoItem("artist-id", "iTunes Artist ID", track.artistID.map(String.init) ?? "", monospaced: true),
            infoItem("collection-artist-id", "iTunes Album Artist ID", track.collectionArtistID.map(String.init) ?? "", monospaced: true),
            infoItem("copyright", "Copyright", track.copyright)
        ].compactMap { $0 }
    }

    private func prepareWorkbench() {
        guard let fileInput = store.seededFileInputs.first else { return }

        Task {
            isPreparingWorkbench = true
            let detail: ITunesAlbumDetail

            if let collectionID = track.collectionID {
                do {
                    detail = try await store.albumDetail(
                        for: ITunesAlbumResult(
                            collectionID: collectionID,
                            artistID: track.artistID,
                            collectionArtistID: track.collectionArtistID,
                            collectionName: track.collectionName,
                            artistName: track.artistName,
                            collectionArtistName: track.collectionArtistName,
                            trackCount: track.trackCount,
                            releaseDate: track.releaseDate,
                            primaryGenreName: track.primaryGenreName,
                            country: track.country,
                            copyright: track.copyright,
                            contentAdvisoryRating: track.contentAdvisoryRating,
                            collectionExplicitness: track.collectionExplicitness,
                            collectionViewURL: track.collectionViewURL,
                            artistViewURL: track.artistViewURL,
                            selectionMatchPreview: nil,
                            selectionMatchScore: nil
                        )
                    )
                } catch {
                    detail = fallbackDetail
                }
            } else {
                detail = fallbackDetail
            }

            let resolvedTrack = detail.tracks.first(where: { $0.trackID == track.trackID }) ?? track
            let preview = ITunesAlbumMatchPreview(
                totalSelectedFiles: 1,
                matchedAssignments: [
                    ITunesAlbumMatchAssignment(
                        id: "\(fileInput.id):\(resolvedTrack.trackID)",
                        file: fileInput,
                        track: resolvedTrack,
                        score: 1,
                        reason: "selected iTunes track"
                    )
                ],
                unmatchedFiles: [],
                unassignedTracks: detail.tracks.filter { $0.trackID != resolvedTrack.trackID },
                overallScore: 1
            )

            workbenchStore = ITunesTaggingWorkbenchStore(
                detail: detail,
                preview: preview,
                loadedFiles: viewModel.files
            )
            isPreparingWorkbench = false
        }
    }

    private func infoItem(_ id: String, _ title: String, _ value: String, monospaced: Bool = false) -> ITunesMetadataInfoItem? {
        guard !value.isEmpty else { return nil }
        return ITunesMetadataInfoItem(id: id, title: title, value: value, monospaced: monospaced)
    }

    private func numberPair(_ number: Int, _ total: Int) -> String {
        guard number > 0 else { return "" }
        return total > 0 ? "\(number)/\(total)" : String(number)
    }

    private var fallbackDetail: ITunesAlbumDetail {
        ITunesAlbumDetail(
            album: ITunesAlbumResult(
                collectionID: track.collectionID ?? track.trackID,
                artistID: track.artistID,
                collectionArtistID: track.collectionArtistID,
                collectionName: track.collectionName,
                artistName: track.artistName,
                collectionArtistName: track.collectionArtistName,
                trackCount: track.trackCount,
                releaseDate: track.releaseDate,
                primaryGenreName: track.primaryGenreName,
                country: track.country,
                copyright: track.copyright,
                contentAdvisoryRating: track.contentAdvisoryRating,
                collectionExplicitness: track.collectionExplicitness,
                collectionViewURL: track.collectionViewURL,
                artistViewURL: track.artistViewURL,
                selectionMatchPreview: nil,
                selectionMatchScore: nil
            ),
            tracks: [track],
            selectionMatchPreview: nil
        )
    }
}

struct ITunesAlbumDetailView: View {
    let album: ITunesAlbumResult
    @ObservedObject var store: ITunesBrowserStore
    @ObservedObject var viewModel: AudioViewModel

    @State private var detailState: DetailState = .loading
    @State private var workbenchStore: ITunesTaggingWorkbenchStore?

    var body: some View {
        Group {
            switch detailState {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading iTunes album...")
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
                albumContent(detail)
            }
        }
        .navigationTitle(album.collectionName.isEmpty ? "iTunes Album" : album.collectionName)
        .task(id: album.collectionID) {
            await loadDetail()
        }
        .sheet(item: $workbenchStore) { store in
            NavigationStack {
                ITunesTaggingWorkbenchView(store: store, viewModel: viewModel)
            }
        }
    }

    private func albumContent(_ detail: ITunesAlbumDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let preview = detail.selectionMatchPreview {
                    matchPreviewSection(preview: preview, detail: detail)
                    unmatchedFilesSection(preview: preview)
                    unassignedTracksSection(preview: preview)
                }

                MetadataSectionCard(title: "Overview", symbolName: "info.circle") {
                    ITunesMetadataInfoRows(items: albumOverviewItems(detail.album))

                    if let url = detail.album.collectionViewURL {
                        MetadataCardDivider()
                        ITunesMetadataLinkRow(title: "Apple Music", destination: url)
                    }
                }

                MetadataSectionCard(title: "Tracks", symbolName: "music.note.list") {
                    ForEach(Array(detail.tracks.enumerated()), id: \.element.id) { index, track in
                        NavigationLink(value: ITunesBrowserDestination.track(track)) {
                            ITunesMetadataTrackRow(
                                number: track.trackNumber > 0 ? String(track.trackNumber) : "",
                                title: track.trackName,
                                subtitle: track.artistName,
                                duration: formattedITunesDuration(track.durationMilliseconds)
                            )
                        }
                        .buttonStyle(.plain)

                        if index < detail.tracks.count - 1 {
                            MetadataCardDivider()
                        }
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(platformColor: .audiomatorWindowBackground))
    }

    private func matchPreviewSection(preview: ITunesAlbumMatchPreview, detail: ITunesAlbumDetail) -> some View {
        let comparisonGroups = ITunesMetadataComparisonBuilder.groups(
            for: preview,
            detail: detail,
            loadedFiles: viewModel.files
        )

        return MetadataSectionCard(title: "Match Preview", symbolName: "checklist") {
            ITunesMetadataInfoRows(items: [
                infoItem("matched", "Matched Files", "\(preview.matchedAssignments.count)/\(preview.totalSelectedFiles)", monospaced: true),
                infoItem("unmatched", "Unmatched Files", preview.unmatchedFiles.isEmpty ? "" : String(preview.unmatchedFiles.count), monospaced: true),
                infoItem("missing", "Unassigned Tracks", preview.unassignedTracks.isEmpty ? "" : String(preview.unassignedTracks.count), monospaced: true),
                infoItem("score", "Average Track Score", String(format: "%.0f%%", preview.overallScore * 100), monospaced: true)
            ].compactMap { $0 })

            if preview.totalSelectedFiles > 0 {
                MetadataCardDivider()

                ITunesMetadataButtonRow(
                    title: "Review & Apply Tags",
                    subtitle: "Adjust assignments and choose exactly which fields to write",
                    symbolName: "square.and.pencil",
                    isDisabled: preview.matchedAssignments.isEmpty
                ) {
                    workbenchStore = ITunesTaggingWorkbenchStore(
                        detail: detail,
                        preview: preview,
                        loadedFiles: viewModel.files
                    )
                }
            }

            if !preview.matchedAssignments.isEmpty {
                MetadataCardDivider()

                NavigationLink {
                    ITunesMatchedFilesDetailView(assignments: preview.matchedAssignments)
                } label: {
                    ITunesMetadataNavigationRow(
                        title: "Matched Files",
                        subtitle: "\(preview.matchedAssignments.count) file-to-track assignment\(preview.matchedAssignments.count == 1 ? "" : "s")",
                        symbolName: "link"
                    )
                }
                .buttonStyle(.plain)

                MetadataCardDivider()

                NavigationLink {
                    ITunesMetadataComparisonDetailView(groups: comparisonGroups)
                } label: {
                    ITunesMetadataNavigationRow(
                        title: "Metadata Comparison",
                        subtitle: "Compare local file tags with iTunes metadata",
                        symbolName: "arrow.left.arrow.right"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func unmatchedFilesSection(preview: ITunesAlbumMatchPreview) -> some View {
        if !preview.unmatchedFiles.isEmpty {
            MetadataSectionCard(title: "Unmatched Files", symbolName: "questionmark.circle") {
                ForEach(Array(preview.unmatchedFiles.enumerated()), id: \.element.id) { index, file in
                    ITunesMetadataFileSummaryRow(file: file)

                    if index < preview.unmatchedFiles.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unassignedTracksSection(preview: ITunesAlbumMatchPreview) -> some View {
        if !preview.unassignedTracks.isEmpty {
            MetadataSectionCard(title: "Unassigned Album Tracks", symbolName: "music.note.list") {
                ForEach(Array(preview.unassignedTracks.enumerated()), id: \.element.id) { index, track in
                    ITunesMetadataReleaseTrackSummaryRow(track: track)

                    if index < preview.unassignedTracks.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    private func albumOverviewItems(_ album: ITunesAlbumResult) -> [ITunesMetadataInfoItem] {
        [
            infoItem("title", "Title", album.collectionName),
            infoItem("artist", "Artist", album.artistName),
            infoItem("album-artist", "Album Artist", album.collectionArtistName),
            infoItem("genre", "Genre", album.primaryGenreName),
            infoItem("release-date", "Release Date", album.releaseDate),
            infoItem("country", "Country", album.country),
            infoItem("track-count", "Track Count", album.trackCount > 0 ? String(album.trackCount) : "", monospaced: true),
            infoItem("explicit", "Explicit", album.contentAdvisory?.displayName ?? L10n.string("Unset")),
            infoItem("advisory", "Advisory", album.contentAdvisoryRating),
            infoItem("collection-id", "iTunes Album ID", String(album.collectionID), monospaced: true),
            infoItem("artist-id", "iTunes Artist ID", album.artistID.map(String.init) ?? "", monospaced: true),
            infoItem("collection-artist-id", "iTunes Album Artist ID", album.collectionArtistID.map(String.init) ?? "", monospaced: true),
            infoItem("copyright", "Copyright", album.copyright)
        ].compactMap { $0 }
    }

    private func infoItem(_ id: String, _ title: String, _ value: String, monospaced: Bool = false) -> ITunesMetadataInfoItem? {
        guard !value.isEmpty else { return nil }
        return ITunesMetadataInfoItem(id: id, title: title, value: value, monospaced: monospaced)
    }

    private func loadDetail() async {
        detailState = .loading
        do {
            detailState = .loaded(try await store.albumDetail(for: album))
        } catch {
            detailState = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private enum DetailState {
        case loading
        case loaded(ITunesAlbumDetail)
        case failed(String)
    }
}

private struct ITunesMetadataInfoItem: Identifiable {
    let id: String
    let title: String
    let value: String
    var monospaced = false
}

private extension ITunesMetadataComparisonStatus {
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
            return L10n.string("Same")
        case .different:
            return L10n.string("Different")
        case .missingLocal:
            return L10n.string("Missing Locally")
        case .missingRemote:
            return L10n.string("Missing on iTunes")
        }
    }
}

private struct ITunesMetadataInfoRows: View {
    let items: [ITunesMetadataInfoItem]

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            ITunesMetadataInfoRow(item: item)

            if index < items.count - 1 {
                MetadataCardDivider()
            }
        }
    }
}

private struct ITunesMetadataInfoRow: View {
    let item: ITunesMetadataInfoItem

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

private struct ITunesMetadataButtonRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: symbolName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
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
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

private struct ITunesMetadataNavigationRow: View {
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

private struct ITunesMetadataLinkRow: View {
    let title: String
    let destination: URL

    var body: some View {
        NavigationLink {
            ITunesEmbeddedWebPageView(
                title: title,
                url: destination
            )
        } label: {
            HStack(alignment: .center, spacing: 18) {
                Text(title)
                    .font(.system(size: 13))
                    .frame(width: 140, alignment: .leading)

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ITunesEmbeddedWebPageView: View {
    let title: String
    let url: URL

    @State private var page = WebPage()

    var body: some View {
        WebView(page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(platformColor: .audiomatorWindowBackground))
            .navigationTitle(title)
            .navigationSubtitle(url.host() ?? "iTunes")
            .task(id: url) {
                page.load(URLRequest(url: url))
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        page.load(URLRequest(url: url))
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Button {
                        PlatformPasteboard.copy(url.absoluteString)
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                }
            }
    }
}

private struct ITunesMetadataTrackRow: View {
    let number: String
    let title: String
    let subtitle: String
    let duration: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(number.isEmpty ? "-" : number)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled Track" : title)
                    .font(.system(size: 13))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

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

private struct ITunesMatchedFilesDetailView: View {
    let assignments: [ITunesAlbumMatchAssignment]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                MetadataSectionCard(title: "Matched Files", symbolName: "link") {
                    ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                        ITunesMetadataMatchAssignmentRow(assignment: assignment)

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
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(platformColor: .audiomatorWindowBackground))
        .navigationTitle("Matched Files")
    }
}

private struct ITunesMetadataMatchAssignmentRow: View {
    let assignment: ITunesAlbumMatchAssignment

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.file.preferredDisplayTitle)
                    .font(.system(size: 13))

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
        let number = assignment.track.trackNumber > 0 ? "\(assignment.track.trackNumber) " : ""
        return number + (assignment.track.trackName.isEmpty ? "Untitled Track" : assignment.track.trackName)
    }
}

private struct ITunesMetadataFileSummaryRow: View {
    let file: ITunesFileSearchInput

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

private struct ITunesMetadataReleaseTrackSummaryRow: View {
    let track: ITunesTrackResult

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trackTitle)
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

    private var trackTitle: String {
        let number = track.trackNumber > 0 ? "\(track.trackNumber) " : ""
        return number + (track.trackName.isEmpty ? "Untitled Track" : track.trackName)
    }

    private var subtitle: String {
        [track.artistName, track.primaryGenreName, track.releaseDate]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct ITunesMetadataComparisonDetailView: View {
    let groups: [ITunesMetadataComparisonGroup]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                MetadataSectionCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        ITunesMetadataComparisonGroupView(
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
        .audiomatorMacTitlebarScrollEdgeBar(subtractsExistingSafeArea: false)
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(platformColor: .audiomatorWindowBackground))
        .navigationTitle("Metadata Comparison")
    }
}

private struct ITunesMetadataComparisonGroupView: View {
    let assignment: ITunesAlbumMatchAssignment
    let rows: [ITunesMetadataComparisonRow]

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

                ITunesMetadataComparisonTableHeader()

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ITunesMetadataComparisonRowView(row: row)

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
        let number = assignment.track.trackNumber > 0 ? "\(assignment.track.trackNumber) " : ""
        return number + (assignment.track.trackName.isEmpty ? "Untitled Track" : assignment.track.trackName)
    }
}

private struct ITunesMetadataComparisonTableHeader: View {
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

            Text("iTunes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct ITunesMetadataComparisonRowView: View {
    let row: ITunesMetadataComparisonRow

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
        Text(value.isEmpty ? "-" : value)
            .font(row.monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
            .foregroundStyle(value.isEmpty ? .tertiary : .primary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
