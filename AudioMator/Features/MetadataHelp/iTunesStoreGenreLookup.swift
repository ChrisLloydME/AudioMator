import SwiftUI

struct iTunesStoreGenreSection: View {
    let catalog: iTunesStoreGenreCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iTunes Store Genre IDs")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("Apple’s iTunes Store assigns a numeric identifier to each genre within a media type—for example, 21 for Rock under Music. This numeric ID is stored separately from the text Genre field.")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text("Select a media type below to browse and search its genre IDs offline, then enter the numeric ID in Metadata Editor.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let catalog {
                mediaTypesList(in: catalog)
            } else {
                GroupBox {
                    ContentUnavailableView(
                        "Genre Catalog Unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
        }
    }

    private func mediaTypesList(in catalog: iTunesStoreGenreCatalog) -> some View {
        let categories = catalog.mediaCategories

        return GroupBox {
            VStack(spacing: 0) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, 6)
                    }

                    iTunesStoreGenreMediaNavigationRow(
                        category: iTunesStoreGenreCatalog.MediaCategory(
                            id: category.id,
                            name: category.name
                        ),
                        count: catalog.rowCount(mediaID: category.id)
                    )
                }
            }
        }
        .textSelection(.disabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("iTunes Store Media Types")
    }
}

private struct iTunesStoreGenreMediaNavigationRow: View {
    let category: iTunesStoreGenreCatalog.MediaCategory
    let count: Int

    var body: some View {
        NavigationLink(value: category) {
            HStack(alignment: .center, spacing: 12) {
                mediaBadge
                    .accessibilityHidden(true)

                Text(verbatim: category.name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                genreCountText
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var mediaBadge: some View {
        let appearance = badgeAppearance
        return Image(systemName: appearance.symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(appearance.color.gradient)
            )
    }

    private var badgeAppearance: (symbolName: String, color: Color) {
        switch category.id {
        case 26: ("mic.fill", .purple)                  // Podcasts
        case 31: ("play.rectangle.fill", .pink)         // Music Videos
        case 32: ("tv.fill", .indigo)                   // TV Shows
        case 33: ("film.fill", .red)                    // Movies
        case 34: ("music.note", .pink)                  // Music
        case 35: ("gamecontroller.fill", .gray)         // iPod Games
        case 36: ("bag.fill", .blue)                    // App Store
        case 37: ("bell.fill", .red)                    // Tones
        case 38: ("book.fill", .orange)                 // Books
        case 39: ("laptopcomputer", .blue)              // Mac App Store
        case 40: ("text.book.closed.fill", .teal)       // Textbooks
        case 500: ("figure.run", .green)                // Fitness Music
        case 40_000_000: ("graduationcap.fill", .indigo) // iTunes U
        case 50_000_024: ("headphones", .orange)        // Audiobooks
        default: ("tag.fill", .gray)
        }
    }

    private var genreCountText: Text {
        if count == 1 {
            Text("1 Genre")
        } else {
            Text("\(count) Genres")
        }
    }
}

struct iTunesStoreGenreMediaDetailView: View {
    let catalog: iTunesStoreGenreCatalog
    let category: iTunesStoreGenreCatalog.MediaCategory

    @State private var query = ""

    var body: some View {
        let rows = catalog.matching(query, mediaID: category.id)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        Group {
            if rows.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    GroupBox {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 24) {
                                Text("Genre")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Genre ID")
                                    .font(.headline)
                                    .frame(width: 110, alignment: .trailing)
                            }

                            Divider()

                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Divider()
                                }

                                HStack(alignment: .top, spacing: 24) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: row.name)
                                            .fontWeight(.medium)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if row.category != row.name {
                                            Text(verbatim: row.category)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(verbatim: String(row.id))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 110, alignment: .trailing)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .audiomatorScrollEdgeEffect(.soft, for: .vertical)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(category.name)
        .searchable(
            text: $query,
            placement: .toolbar,
            prompt: Text("Search by genre or ID")
        )
    }
}
