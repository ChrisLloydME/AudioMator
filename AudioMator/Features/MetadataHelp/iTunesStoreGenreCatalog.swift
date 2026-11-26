import Foundation

nonisolated struct iTunesStoreGenreCatalog: Decodable {
    struct Row: Decodable, Identifiable {
        let id: Int
        let name: String
        let category: String
        let mediaID: Int
    }

    struct MediaCategory: Hashable, Identifiable, Sendable {
        let id: Int
        let name: String
    }

    static let musicID = 34

    let snapshotDate: String
    let rows: [Row]

    var mediaCategories: [Row] {
        rows.filter { $0.id == $0.mediaID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func rowCount(mediaID: Int?) -> Int {
        guard let mediaID else { return rows.count }
        return rows.reduce(into: 0) { count, row in
            if row.mediaID == mediaID { count += 1 }
        }
    }

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "iTunesStoreGenres", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func matching(_ query: String, mediaID: Int?) -> [Row] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericID = Int(value)
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)

        return rows.filter { row in
            guard mediaID == nil || row.mediaID == mediaID else { return false }
            if let numericID { return row.id == numericID }
            return words.allSatisfy { word in
                row.name.localizedStandardContains(word) || row.category.localizedStandardContains(word)
            }
        }
    }
}
