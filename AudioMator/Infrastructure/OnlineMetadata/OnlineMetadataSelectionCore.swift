import Foundation

struct OnlineMetadataFileSelectionSummary: Equatable, Hashable {
    let albumCandidate: String
    let albumArtistCandidate: String
    let primaryArtistCandidate: String
    let totalSelectedFiles: Int
    let trackCountCandidate: Int
    let releaseYearCandidate: String
    let barcodeCandidate: String
    let providerAlbumIDCandidate: String
    let distinctAlbumCount: Int
    let distinctArtistCount: Int

    var isMultiFile: Bool { totalSelectedFiles > 1 }
    var selectionLooksMixed: Bool { distinctAlbumCount > 1 || distinctArtistCount > 1 }
}

enum OnlineMetadataSelectionCore {
    static func normalizedPositiveIndex(_ rawValue: String) -> Int? {
        AudioTagNumberText.positiveIndex(from: rawValue)
    }

    static func normalizedReleaseYear(_ rawValue: String) -> String {
        let digits = rawValue.filter(\.isNumber)
        guard digits.count >= 4 else { return "" }
        return String(digits.prefix(4))
    }

    static func deduplicatedTrimmedValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }

    static func summary(
        albums: [String],
        albumArtists: [String],
        primaryArtists: [String],
        trackTotals: [Int],
        releaseDates: [String],
        barcodes: [String],
        providerAlbumIDs: [String]
    ) -> OnlineMetadataFileSelectionSummary {
        let totalSelectedFiles = max(
            albums.count,
            albumArtists.count,
            primaryArtists.count,
            trackTotals.count,
            releaseDates.count,
            barcodes.count,
            providerAlbumIDs.count
        )

        return OnlineMetadataFileSelectionSummary(
            albumCandidate: majorityValue(albums),
            albumArtistCandidate: majorityValue(albumArtists),
            primaryArtistCandidate: majorityValue(primaryArtists),
            totalSelectedFiles: totalSelectedFiles,
            trackCountCandidate: max(majorityInt(trackTotals.filter { $0 > 0 }) ?? 0, totalSelectedFiles),
            releaseYearCandidate: majorityValue(releaseDates.map(normalizedReleaseYear)),
            barcodeCandidate: majorityValue(barcodes),
            providerAlbumIDCandidate: majorityValue(providerAlbumIDs),
            distinctAlbumCount: distinctValueCount(albums),
            distinctArtistCount: distinctValueCount(albumArtists)
        )
    }

    static func representativeFiles<T>(
        _ files: [T],
        title: (T) -> String,
        discNumber: (T) -> Int?,
        trackNumber: (T) -> Int?,
        limit: Int = 3
    ) -> [T] {
        let ordered = files
            .filter { !title($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                (discNumber($0) ?? 0, trackNumber($0) ?? 0, title($0))
                    < (discNumber($1) ?? 0, trackNumber($1) ?? 0, title($1))
            }

        guard ordered.count > limit, limit == 3 else {
            return Array(ordered.prefix(limit))
        }

        let positions = [0, ordered.count / 2, ordered.count - 1]
        var seen = Set<Int>()
        return positions.compactMap { position in
            guard seen.insert(position).inserted else { return nil }
            return ordered[position]
        }
    }

    private static func majorityValue(_ values: [String]) -> String {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }

        var counts: [String: Int] = [:]
        var best = cleaned[0]
        var bestCount = 0
        for value in cleaned {
            let count = (counts[value] ?? 0) + 1
            counts[value] = count
            if count > bestCount {
                best = value
                bestCount = count
            }
        }
        return best
    }

    private static func majorityInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        var best = values[0]
        var bestCount = 0
        for value in values {
            let count = (counts[value] ?? 0) + 1
            counts[value] = count
            if count > bestCount {
                best = value
                bestCount = count
            }
        }
        return best
    }

    private static func distinctValueCount(_ values: [String]) -> Int {
        Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
    }
}
