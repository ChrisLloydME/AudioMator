import SwiftUI

struct ITunesBrowserView: View {
    @StateObject private var store = ITunesBrowserStore()
    @ObservedObject var viewModel: AudioViewModel
    let onBackToSources: () -> Void

    @State private var navigationPath: [ITunesBrowserDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                searchHeader
                Divider()
                content
            }
            .navigationTitle("iTunes")
            .navigationDestination(for: ITunesBrowserDestination.self) { destination in
                switch destination {
                case .track(let track):
                    ITunesTrackDetailView(track: track, store: store, viewModel: viewModel)
                case .album(let album):
                    ITunesAlbumDetailView(album: album, store: store, viewModel: viewModel)
                }
            }
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        onBackToSources()
                    } label: {
                        Label("Sources", systemImage: "chevron.left")
                    }
                }

                ToolbarItem(placement: .principal) {
                    modePicker
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
                    .disabled(!canClearSearch)
                }
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(platformColor: .audiomatorWindowBackground))
        .onAppear {
            if store.fileSelectionSummary == nil, !selectedFiles.isEmpty {
                seedSelection()
            }
        }
        .onChange(of: store.mode) { oldMode, newMode in
            store.handleModeChange(from: oldMode, to: newMode)
        }
        .onChange(of: store.navigationResetToken) { _, _ in
            navigationPath.removeAll()
        }
        .frame(minWidth: 920, minHeight: 620)
    }

    private var selectedFiles: [AudioFile] {
        viewModel.files.filter { viewModel.selectedAudioIDs.contains($0.id) }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(iOS)
            modePicker
            #endif

            searchFields

            if store.mode != .link {
                storefrontBar
            }

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

    private var modePicker: some View {
        Picker("Search Mode", selection: $store.mode) {
            ForEach(ITunesSearchMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var storefrontBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ITunesStorefront.allCases) { storefront in
                    Button {
                        store.storefront = storefront
                    } label: {
                        if store.storefront == storefront {
                            Label(storefront.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(storefront.menuTitle)
                        }
                    }
                }
            } label: {
                Label(
                    "\(store.storefront.emoji) \(store.storefront.displayName)",
                    systemImage: "globe"
                )
            }

            Text("Storefront")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var searchFields: some View {
        switch store.mode {
        case .track:
            HStack(alignment: .top, spacing: 12) {
                ITunesQueryField(title: "Track", symbolName: "music.note", text: $store.titleQuery)
                ITunesQueryField(title: "Artist", symbolName: "person", text: $store.artistQuery)
                ITunesQueryField(title: "Album", symbolName: "opticaldisc", text: $store.albumQuery)
            }
        case .album:
            HStack(alignment: .top, spacing: 12) {
                ITunesQueryField(title: "Album", symbolName: "square.stack", text: $store.albumQuery)
                ITunesQueryField(title: "Artist", symbolName: "person", text: $store.artistQuery)
            }
        case .file:
            ITunesFileSelectionSummaryView(summary: store.fileSelectionSummary)
        case .link:
            ITunesQueryField(title: "iTunes or Apple Music Link", symbolName: "link", text: $store.linkQuery, minimumWidth: 520)
        case .upc:
            ITunesQueryField(title: "UPC/EAN", symbolName: "barcode", text: $store.upcQuery, minimumWidth: 260)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isSearching && store.results.isEmpty {
            VStack(spacing: 0) {
                ProgressView("Searching iTunes...")
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
        } else if store.results.isEmpty {
            VStack(spacing: 0) {
                ContentUnavailableView(
                    store.lastSubmittedQuery == nil ? "Search iTunes" : "No Results",
                    systemImage: "magnifyingglass",
                    description: Text(store.lastSubmittedQuery == nil ? "Choose a search mode, then enter what you know." : "No iTunes results matched this search.")
                )
                .padding(.top, 36)
                Spacer(minLength: 0)
            }
        } else {
            List {
                searchResultRows
            }
            .listStyle(.inset)
            .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        switch store.results {
        case .tracks(let tracks):
            ForEach(tracks) { track in
                NavigationLink(value: ITunesBrowserDestination.track(track)) {
                    ITunesTrackRow(track: track)
                        .padding(.vertical, 6)
                }
            }
        case .albums(let albums):
            ForEach(albums) { album in
                NavigationLink(value: ITunesBrowserDestination.album(album)) {
                    ITunesAlbumRow(album: album)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var resultUnitLabel: String {
        switch store.results {
        case .tracks: return "track"
        case .albums: return "album"
        }
    }

    private var canClearSearch: Bool {
        !store.titleQuery.isEmpty ||
            !store.artistQuery.isEmpty ||
            !store.albumQuery.isEmpty ||
            !store.upcQuery.isEmpty ||
            !store.linkQuery.isEmpty ||
            !store.results.isEmpty ||
            store.errorMessage != nil
    }

    private func seedSelection() {
        store.seed(from: selectedFiles)
        if store.hasSearchText {
            store.search()
        }
    }
}

private struct ITunesQueryField: View {
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

private struct ITunesFileSelectionSummaryView: View {
    let summary: ITunesFileSelectionSummary?

    var body: some View {
        HStack(spacing: 12) {
            Label(summaryText, systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .medium))

            if let summary {
                summaryChip("Album", summary.albumCandidate)
                summaryChip("Artist", summary.albumArtistCandidate.isEmpty ? summary.primaryArtistCandidate : summary.albumArtistCandidate)
                summaryChip("UPC", summary.barcodeCandidate)
                summaryChip("iTunes ID", summary.itunesAlbumIDCandidate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var summaryText: String {
        guard let summary else { return "No selected files seeded" }
        return summary.files.count == 1 ? "1 selected file" : "\(summary.files.count) selected files"
    }

    @ViewBuilder
    private func summaryChip(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            Text("\(title): \(value)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ITunesTrackRow: View {
    let track: ITunesTrackResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(track.trackName.isEmpty ? "Untitled Track" : track.trackName)
                    .font(.system(size: 13, weight: .semibold))

                if track.isExplicit {
                    Text("Explicit")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var subtitle: String {
        [
            track.artistName,
            track.collectionName,
            track.trackNumber > 0 ? "Track \(track.trackNumber)" : "",
            track.releaseDate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

private struct ITunesAlbumRow: View {
    let album: ITunesAlbumResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(album.collectionName.isEmpty ? "Untitled Album" : album.collectionName)
                    .font(.system(size: 13, weight: .semibold))

                if let score = album.selectionMatchScore {
                    Text("\(Int((score * 100).rounded()))% match")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var subtitle: String {
        [
            album.artistName,
            album.trackCount > 0 ? "\(album.trackCount) tracks" : "",
            album.primaryGenreName,
            album.releaseDate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

private struct ITunesTrackDetailView: View {
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
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(platformColor: .audiomatorWindowBackground))
    }

    private var overviewItems: [ITunesMetadataInfoItem] {
        [
            infoItem("title", "Title", track.trackName),
            infoItem("artist", "Artist", track.artistName),
            infoItem("album", "Album", track.collectionName),
            infoItem("genre", "Genre", track.primaryGenreName),
            infoItem("track", "Track", numberPair(track.trackNumber, track.trackCount), monospaced: true),
            infoItem("disc", "Disc", numberPair(track.discNumber, track.discCount), monospaced: true),
            infoItem("length", "Length", formattedITunesDuration(track.durationMilliseconds), monospaced: true),
            infoItem("release-date", "Release Date", track.releaseDate),
            infoItem("country", "Country", track.country),
            infoItem("explicit", "Explicit", track.isExplicit ? "Yes" : "No"),
            infoItem("track-id", "iTunes Track ID", String(track.trackID), monospaced: true),
            infoItem("collection-id", "iTunes Album ID", track.collectionID.map(String.init) ?? "", monospaced: true),
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
                            collectionName: track.collectionName,
                            artistName: track.artistName,
                            trackCount: track.trackCount,
                            releaseDate: track.releaseDate,
                            primaryGenreName: track.primaryGenreName,
                            country: track.country,
                            copyright: track.copyright,
                            collectionExplicitness: track.collectionExplicitness,
                            collectionViewURL: track.collectionViewURL,
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
                collectionName: track.collectionName,
                artistName: track.artistName,
                trackCount: track.trackCount,
                releaseDate: track.releaseDate,
                primaryGenreName: track.primaryGenreName,
                country: track.country,
                copyright: track.copyright,
                collectionExplicitness: track.collectionExplicitness,
                collectionViewURL: track.collectionViewURL,
                selectionMatchPreview: nil,
                selectionMatchScore: nil
            ),
            tracks: [track],
            selectionMatchPreview: nil
        )
    }
}

private struct ITunesAlbumDetailView: View {
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
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(platformColor: .audiomatorWindowBackground))
    }

    private func matchPreviewSection(preview: ITunesAlbumMatchPreview, detail: ITunesAlbumDetail) -> some View {
        let comparisonGroups = preview.matchedAssignments.map { assignment in
            ITunesMetadataComparisonGroup(
                id: assignment.id,
                assignment: assignment,
                rows: comparisonRows(for: assignment, detail: detail)
            )
        }

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
            infoItem("genre", "Genre", album.primaryGenreName),
            infoItem("release-date", "Release Date", album.releaseDate),
            infoItem("country", "Country", album.country),
            infoItem("track-count", "Track Count", album.trackCount > 0 ? String(album.trackCount) : "", monospaced: true),
            infoItem("explicit", "Explicit", album.isExplicit ? "Yes" : "No"),
            infoItem("collection-id", "iTunes Album ID", String(album.collectionID), monospaced: true),
            infoItem("copyright", "Copyright", album.copyright)
        ].compactMap { $0 }
    }

    private func infoItem(_ id: String, _ title: String, _ value: String, monospaced: Bool = false) -> ITunesMetadataInfoItem? {
        guard !value.isEmpty else { return nil }
        return ITunesMetadataInfoItem(id: id, title: title, value: value, monospaced: monospaced)
    }

    private func comparisonRows(for assignment: ITunesAlbumMatchAssignment, detail: ITunesAlbumDetail) -> [ITunesMetadataComparisonRow] {
        ITunesTagWriteField.allCases.compactMap { field in
            let localValue: String
            if let fileID = UUID(uuidString: assignment.file.id),
               let loadedFile = viewModel.files.first(where: { $0.id == fileID }) {
                localValue = field.localValue(from: loadedFile)
            } else {
                localValue = fallbackLocalValue(for: field, file: assignment.file)
            }

            return comparisonRow(
                id: field.id,
                title: field.displayName,
                local: localValue,
                remote: remoteValue(for: field, assignment: assignment, detail: detail),
                monospaced: field.usesMonospacedComparisonValue
            )
        }
    }

    private func comparisonRow(
        id: String,
        title: String,
        local: String,
        remote: String,
        monospaced: Bool = false
    ) -> ITunesMetadataComparisonRow? {
        let localValue = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteValue = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localValue.isEmpty || !remoteValue.isEmpty else { return nil }

        let status: ITunesMetadataComparisonStatus
        if localValue.isEmpty {
            status = .missingLocal
        } else if remoteValue.isEmpty {
            status = .missingRemote
        } else if normalizedComparisonValue(localValue) == normalizedComparisonValue(remoteValue) {
            status = .same
        } else {
            status = .different
        }

        return ITunesMetadataComparisonRow(
            id: id,
            title: title,
            localValue: localValue,
            remoteValue: remoteValue,
            status: status,
            monospaced: monospaced
        )
    }

    private func fallbackLocalValue(for field: ITunesTagWriteField, file: ITunesFileSearchInput) -> String {
        switch field {
        case .title: return file.title
        case .artist: return file.artist
        case .albumArtist: return file.albumArtist
        case .album: return file.album
        case .trackNumber: return file.trackNumber
        case .trackTotal: return file.trackTotal > 0 ? String(file.trackTotal) : ""
        case .discNumber: return file.discNumber
        case .releaseDate: return file.releaseDate
        case .barcode: return file.barcode
        case .itunesAlbumID: return file.itunesAlbumID
        case .genre, .discTotal, .copyright, .isExplicit: return ""
        }
    }

    private func remoteValue(
        for field: ITunesTagWriteField,
        assignment: ITunesAlbumMatchAssignment,
        detail: ITunesAlbumDetail
    ) -> String {
        let track = assignment.track
        switch field {
        case .title: return track.trackName
        case .artist: return track.artistName
        case .albumArtist: return detail.album.artistName
        case .album: return detail.album.collectionName
        case .genre: return track.primaryGenreName.isEmpty ? detail.album.primaryGenreName : track.primaryGenreName
        case .trackNumber: return track.trackNumber > 0 ? String(track.trackNumber) : ""
        case .trackTotal: return track.trackCount > 0 ? String(track.trackCount) : ""
        case .discNumber: return track.discNumber > 0 ? String(track.discNumber) : ""
        case .discTotal: return track.discCount > 1 ? String(track.discCount) : ""
        case .releaseDate: return track.releaseDate.isEmpty ? detail.album.releaseDate : track.releaseDate
        case .copyright: return track.copyright.isEmpty ? detail.album.copyright : track.copyright
        case .barcode: return assignment.file.barcode
        case .itunesAlbumID: return String(detail.album.collectionID)
        case .isExplicit: return track.isExplicit || detail.album.isExplicit ? "Yes" : "No"
        }
    }

    private func normalizedComparisonValue(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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

private struct ITunesMetadataComparisonRow: Identifiable {
    let id: String
    let title: String
    let localValue: String
    let remoteValue: String
    let status: ITunesMetadataComparisonStatus
    let monospaced: Bool
}

private struct ITunesMetadataComparisonGroup: Identifiable {
    let id: String
    let assignment: ITunesAlbumMatchAssignment
    let rows: [ITunesMetadataComparisonRow]
}

private enum ITunesMetadataComparisonStatus {
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
        Link(destination: destination) {
            HStack(alignment: .center, spacing: 18) {
                Text(title)
                    .font(.system(size: 13))
                    .frame(width: 140, alignment: .leading)

                Spacer(minLength: 12)

                Image(systemName: "arrow.up.forward")
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

private extension ITunesTagWriteField {
    var usesMonospacedComparisonValue: Bool {
        switch self {
        case .trackNumber, .trackTotal, .discNumber, .discTotal, .barcode, .itunesAlbumID:
            return true
        case .title, .artist, .albumArtist, .album, .genre, .releaseDate, .copyright, .isExplicit:
            return false
        }
    }
}

private func formattedITunesDuration(_ milliseconds: Int?) -> String {
    guard let milliseconds, milliseconds > 0 else { return "" }
    let totalSeconds = max(0, milliseconds / 1000)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
