import SwiftUI
import WebKit

struct iTunesBrowserView: View {
    @StateObject private var store = iTunesBrowserStore()
    @ObservedObject var viewModel: AudioViewModel
    let onBackToSources: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath: [iTunesBrowserDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                searchHeader
                Divider()
                content
            }
            .audiomatorMacTitlebarScrollEdgeBar()
            .navigationTitle("iTunes")
            .navigationDestination(for: iTunesBrowserDestination.self) { destination in
                switch destination {
                case .track(let track):
                    iTunesTrackDetailView(track: track, store: store, viewModel: viewModel)
                case .album(let album):
                    iTunesAlbumDetailView(album: album, store: store, viewModel: viewModel)
                }
            }
            #if os(macOS)
            .toolbar {
                if navigationPath.isEmpty {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            onBackToSources()
                        } label: {
                            Label("Sources", systemImage: "chevron.left")
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    modePicker
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
                        .disabled(!canClearSearch)
                    }
                }
            }
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if navigationPath.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.search()
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!store.hasSearchText || store.isSearching)
                    }
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
        .onDisappear {
            store.closeWindowSession()
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
            ForEach(iTunesSearchMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var storefrontBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(iTunesStorefront.allCases) { storefront in
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
                Label("Storefront", systemImage: "globe")
            }

            iTunesStorefrontChip(title: "\(store.storefront.emoji) \(store.storefront.displayName)")

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var searchFields: some View {
        switch store.mode {
        case .track:
            HStack(alignment: .top, spacing: 12) {
                iTunesQueryField(title: "Track", symbolName: "music.note", text: $store.titleQuery)
                iTunesQueryField(title: "Artist", symbolName: "person", text: $store.artistQuery)
                iTunesQueryField(title: "Album", symbolName: "opticaldisc", text: $store.albumQuery)
            }
        case .album:
            HStack(alignment: .top, spacing: 12) {
                iTunesQueryField(title: "Album", symbolName: "square.stack", text: $store.albumQuery)
                iTunesQueryField(title: "Album Artist", symbolName: "person.2", text: $store.albumArtistQuery)
            }
        case .file:
            iTunesFileSelectionSummaryView(summary: store.fileSelectionSummary)
        case .link:
            iTunesQueryField(title: "Apple Music or iTunes Album/Track Link", symbolName: "link", text: $store.linkQuery, minimumWidth: 520)
        case .upc:
            iTunesQueryField(title: "UPC/EAN", symbolName: "barcode", text: $store.upcQuery, minimumWidth: 260)
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
                    description: Text(store.lastSubmittedQuery == nil ? "Choose a search mode, then enter what you know." : noResultsDescription)
                )
                .padding(.top, 36)
                Spacer(minLength: 0)
            }
        } else {
            searchResultsList
        }
    }

    private var searchResultsList: some View {
        #if os(iOS)
        List {
            Section {
                searchResultRows
            }
        }
        .iPadRoundedGroupedListStyle()
        #else
            List {
                searchResultRows
            }
            .listStyle(.inset)
            .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        #endif
    }

    @ViewBuilder
    private var searchResultRows: some View {
        switch store.results {
        case .tracks(let tracks):
            ForEach(tracks) { track in
                NavigationLink(value: iTunesBrowserDestination.track(track)) {
                    iTunesTrackRow(track: track)
                        .padding(.vertical, 6)
                }
            }
        case .albums(let albums):
            ForEach(albums) { album in
                NavigationLink(value: iTunesBrowserDestination.album(album)) {
                    iTunesAlbumRow(album: album)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var resultUnitLabel: String {
        switch store.mode {
        case .track:
            return "track"
        case .album, .upc:
            return "album"
        case .file, .link:
            switch store.results {
            case .tracks:
                return "track"
            case .albums:
                return "album"
            }
        }
    }

    private var canClearSearch: Bool {
        !store.titleQuery.isEmpty ||
            !store.artistQuery.isEmpty ||
            !store.albumArtistQuery.isEmpty ||
            !store.albumQuery.isEmpty ||
            !store.upcQuery.isEmpty ||
            !store.linkQuery.isEmpty ||
            !store.results.isEmpty ||
            store.errorMessage != nil
    }

    private var noResultsDescription: String {
        switch store.mode {
        case .track:
            return "No tracks matched this search."
        case .album:
            return "No albums matched this search."
        case .file:
            return store.fileSelectionSummary?.isMultiFile == true
                ? "No strong album matches for the selected files."
                : "No strong track matches for the selected file."
        case .link:
            return "That link didn't resolve to a supported iTunes result."
        case .upc:
            return "No iTunes album matched this UPC/EAN."
        }
    }

    private func seedSelection() {
        store.seed(from: selectedFiles)
        if store.hasSearchText {
            store.search()
        }
    }
}
