import Foundation

nonisolated enum MusicBrainzProviderLuceneQueryBuilder {
    nonisolated private static let reservedCharacters: Set<Character> = Set(#"+-&|!(){}[]^"~*?:\/"#)
    nonisolated private static let maxPreferredClauseCount = 6
    nonisolated private static let maxPreferredClauseLength = 420
    nonisolated private static let maxCombinedQueryLength = 900

    static func combinedSearchQuery(
        from queries: [String],
        maximumClauseCount: Int
    ) -> String? {
        let normalizedQueries = deduplicatedClauses(queries)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(max(0, maximumClauseCount))

        var acceptedQueries: [String] = []
        for query in normalizedQueries {
            let candidate = acceptedQueries.isEmpty
                ? query
                : anyOf(acceptedQueries + [query])
            guard candidate.count <= maxCombinedQueryLength else { break }
            acceptedQueries.append(query)
        }

        switch acceptedQueries.count {
        case 0:
            return nil
        case 1:
            return acceptedQueries[0]
        default:
            return anyOf(acceptedQueries)
        }
    }

    static func recordingSearchQueries(from query: MusicBrainzProviderSearchQuery) -> [String] {
        finalizedPreferredClauses(
            applyingFilters(to: recordingSearchClauses(from: query), filters: query.releaseFilters)
        )
    }

    static func releaseSearchQueries(from query: MusicBrainzProviderSearchQuery) -> [String] {
        var clauses: [String] = []
        let releaseTitles = releaseTitleVariants(query.album)

        if !releaseTitles.isEmpty, !query.artist.isEmpty {
            for releaseTitle in releaseTitles {
                clauses.append(allOf([
                    fieldClause(name: "release", value: releaseTitle),
                    fieldClause(name: "artist", value: query.artist)
                ]))
            }
        }

        if !releaseTitles.isEmpty {
            clauses.append(contentsOf: releaseTitles.map { fieldClause(name: "release", value: $0) })
            clauses.append(contentsOf: releaseTitles.map(generalClause))
        } else if !query.title.isEmpty {
            clauses.append(fieldClause(name: "release", value: query.title))
            clauses.append(generalClause(query.title))
        }

        if !query.artist.isEmpty {
            clauses.append(fieldClause(name: "artist", value: query.artist))
            clauses.append(generalClause(query.artist))
        }

        return finalizedPreferredClauses(applyingFilters(to: clauses, filters: query.releaseFilters))
    }

    static func fileSearchQueries(from query: MusicBrainzProviderSearchQuery) -> [String] {
        finalizedPreferredClauses(
            applyingFilters(to: recordingSearchClauses(from: query), filters: query.releaseFilters)
        )
    }

    static func fileClusterStrongReleaseSearchQueries(from query: MusicBrainzProviderSearchQuery) -> [String] {
        guard let summary = query.selectionSummary else { return [] }

        var clauses: [String] = []
        let releaseClauses = releaseTitleVariants(summary.albumCandidate)
            .map { fieldClause(name: "release", value: $0) }
        let artistClauses = [summary.albumArtistCandidate, summary.primaryArtistCandidate]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { values, value in
                guard !values.contains(value) else { return }
                values.append(value)
            }
            .map { fieldClause(name: "artist", value: $0) }
        let trackCountClause = summary.trackCountCandidate > 0
            ? numericClause(name: "tracks", value: summary.trackCountCandidate)
            : ""
        let yearClause = summary.releaseYearCandidate.isEmpty
            ? ""
            : fieldClause(name: "date", value: summary.releaseYearCandidate)

        if let releaseIDClause = validMBIDClause(name: "reid", value: summary.providerAlbumIDCandidate) {
            clauses.append(releaseIDClause)
        }

        if !summary.barcodeCandidate.isEmpty {
            clauses.append(fieldClause(name: "barcode", value: summary.barcodeCandidate))
        }

        if !releaseClauses.isEmpty && !artistClauses.isEmpty && !trackCountClause.isEmpty {
            for releaseClause in releaseClauses {
                for artistClause in artistClauses {
                    clauses.append(allOf([releaseClause, artistClause, trackCountClause]))
                }
            }
        }

        if !releaseClauses.isEmpty && !artistClauses.isEmpty {
            for releaseClause in releaseClauses {
                for artistClause in artistClauses {
                    clauses.append(allOf([releaseClause, artistClause]))
                }
            }
        }

        if !releaseClauses.isEmpty && !trackCountClause.isEmpty {
            clauses.append(contentsOf: releaseClauses.map { allOf([$0, trackCountClause]) })
        }

        if !releaseClauses.isEmpty && !yearClause.isEmpty {
            clauses.append(contentsOf: releaseClauses.map { allOf([$0, yearClause]) })
        }

        return finalizedPreferredClauses(applyingFilters(to: clauses, filters: query.releaseFilters))
    }

    static func fileClusterBroadReleaseSearchQueries(from query: MusicBrainzProviderSearchQuery) -> [String] {
        guard let summary = query.selectionSummary else { return [] }

        var clauses: [String] = []

        let releaseTitles = releaseTitleVariants(summary.albumCandidate)
        let artist = summary.albumArtistCandidate.isEmpty
            ? summary.primaryArtistCandidate
            : summary.albumArtistCandidate
        let artistClause = artist.isEmpty ? "" : fieldClause(name: "artist", value: artist)

        if !releaseTitles.isEmpty, !artistClause.isEmpty {
            clauses.append(contentsOf: releaseTitles.map {
                allOf([generalClause($0), artistClause])
            })
        }

        if !releaseTitles.isEmpty {
            clauses.append(contentsOf: releaseTitles.map(generalClause))
            clauses.append(contentsOf: releaseTitles.map { fieldClause(name: "release", value: $0) })
        } else if !artistClause.isEmpty {
            clauses.append(artistClause)
            clauses.append(generalClause(artist))
        }

        if summary.trackCountCandidate > 0 {
            clauses.append(numericClause(name: "tracks", value: summary.trackCountCandidate))
        }

        if !summary.releaseYearCandidate.isEmpty {
            clauses.append(fieldClause(name: "date", value: summary.releaseYearCandidate))
        }

        return finalizedPreferredClauses(applyingFilters(to: clauses, filters: query.releaseFilters))
    }

    static func fileStrongSearchQueries(from query: MusicBrainzProviderSearchQuery) -> [String] {
        var queries: [String] = []
        let titleClause = query.title.isEmpty ? "" : fieldClause(name: "recording", value: query.title)
        let releaseIDClause = validMBIDClause(name: "reid", value: query.albumID)
        let artistClauses = query.artistCandidates.map { fieldClause(name: "artist", value: $0) }
        let trackClauses = trackNumberClauses(query.trackNumber)
        let trackTotalClauses = trackTotalClauses(query.trackTotal)
        let durationClauses = durationClauses(query.quantizedDuration)

        if let trackIDClause = validMBIDClause(name: "tid", value: query.trackID) {
            queries.append(trackIDClause)
        }

        if !query.isrc.isEmpty {
            queries.append(fieldClause(name: "isrc", value: query.isrc))
        }

        if let releaseIDClause {
            var releaseScopedQueries: [String] = []

            if !titleClause.isEmpty && !artistClauses.isEmpty && !trackClauses.isEmpty {
                for artistClause in artistClauses {
                    for trackClause in trackClauses {
                        releaseScopedQueries.append(allOf([releaseIDClause, titleClause, artistClause, trackClause]))
                    }
                }
            }

            for trackClause in trackClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, trackClause]))
            }

            if !titleClause.isEmpty {
                releaseScopedQueries.append(allOf([releaseIDClause, titleClause]))
            }

            for artistClause in artistClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, artistClause]))

                if !titleClause.isEmpty {
                    releaseScopedQueries.append(allOf([releaseIDClause, titleClause, artistClause]))
                }
            }

            for durationClause in durationClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, durationClause]))
            }

            for trackTotalClause in trackTotalClauses {
                releaseScopedQueries.append(allOf([releaseIDClause, trackTotalClause]))
            }

            if releaseScopedQueries.isEmpty {
                releaseScopedQueries.append(releaseIDClause)
            }

            queries.append(contentsOf: releaseScopedQueries)
        }

        return finalizedPreferredClauses(applyingFilters(to: queries, filters: query.releaseFilters))
    }

    nonisolated private static func fieldClause(name: String, value: String) -> String {
        "\(name):\"\(escapeLucene(value))\""
    }

    nonisolated private static func generalClause(_ value: String) -> String {
        let tokens = searchTokens(in: value)
        guard !tokens.isEmpty else { return "" }

        if tokens.count == 1 {
            return escapeLucene(tokens[0])
        }

        return allOf(tokens.map(escapeLucene))
    }

    nonisolated private static func allOf(_ clauses: [String]) -> String {
        "(" + clauses.joined(separator: " AND ") + ")"
    }

    nonisolated private static func anyOf(_ clauses: [String]) -> String {
        "(" + clauses.joined(separator: " OR ") + ")"
    }

    nonisolated private static func numericClause(name: String, value: Int) -> String {
        "\(name):\(value)"
    }

    nonisolated private static func validMBIDClause(name: String, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmed) != nil else { return nil }
        return fieldClause(name: name, value: trimmed)
    }

    nonisolated private static func finalizedPreferredClauses(_ clauses: [String]) -> [String] {
        deduplicatedClauses(clauses)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= maxPreferredClauseLength }
            .prefix(maxPreferredClauseCount)
            .map { $0 }
    }

    nonisolated private static func applyingFilters(
        to clauses: [String],
        filters: MusicBrainzProviderReleaseFilters
    ) -> [String] {
        let filterClauses = releaseFilterClauses(from: filters)
        guard !filterClauses.isEmpty else { return clauses }

        let baseClauses = clauses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !baseClauses.isEmpty else {
            return [allOf(filterClauses)]
        }

        return baseClauses.map { allOf([$0] + filterClauses) }
    }

    nonisolated private static func releaseFilterClauses(from filters: MusicBrainzProviderReleaseFilters) -> [String] {
        var clauses: [String] = []

        if !filters.mediaFormats.isEmpty {
            clauses.append(
                anyOf(
                    filters.mediaFormats
                        .sorted { $0.rawValue < $1.rawValue }
                        .map { fieldClause(name: "format", value: $0.rawValue) }
                )
            )
        }

        let releaseYear = MusicBrainzProviderReleaseFilters.normalizedYear(filters.releaseYear)
        if !releaseYear.isEmpty {
            clauses.append(fieldClause(name: "date", value: releaseYear))
        }

        if !filters.countries.isEmpty {
            clauses.append(
                anyOf(
                    filters.countries
                        .sorted()
                        .map { fieldClause(name: "country", value: $0.lowercased()) }
                )
            )
        }

        if !filters.statuses.isEmpty {
            clauses.append(
                anyOf(
                    filters.statuses
                        .sorted { $0.rawValue < $1.rawValue }
                        .map { fieldClause(name: "status", value: $0.rawValue) }
                )
            )
        }

        return clauses
    }

    nonisolated private static func deduplicatedClauses(_ clauses: [String]) -> [String] {
        (Array(NSOrderedSet(array: clauses.filter { !$0.isEmpty })) as? [String]) ?? []
    }

    nonisolated private static func escapeLucene(_ raw: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(raw.count)

        for character in raw {
            if reservedCharacters.contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        return escaped
    }

    nonisolated private static func searchTokens(in raw: String) -> [String] {
        raw
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    nonisolated static func releaseTitleVariants(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var variants: [String] = []
        let trailingReleaseTypePattern = #"\s*(?:[-–—:]\s*(?:EP|Single|Album)|\((?:EP|Single|Album)\)|\[(?:EP|Single|Album)\])\s*$"#
        if let suffixRange = trimmed.range(
            of: trailingReleaseTypePattern,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let canonicalTitle = trimmed[..<suffixRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !canonicalTitle.isEmpty, canonicalTitle != trimmed {
                variants.append(canonicalTitle)
            }
        }
        variants.append(trimmed)

        return deduplicatedClauses(variants)
    }

    private static func recordingSearchClauses(from query: MusicBrainzProviderSearchQuery) -> [String] {
        let titleClause = query.title.isEmpty ? "" : fieldClause(name: "recording", value: query.title)
        let releaseClause = query.album.isEmpty ? "" : fieldClause(name: "release", value: query.album)
        let artistClauses = query.artistCandidates.map { fieldClause(name: "artist", value: $0) }
        let trackClauses = trackNumberClauses(query.trackNumber)
        let trackTotalClauses = trackTotalClauses(query.trackTotal)
        let durationClauses = durationClauses(query.quantizedDuration)

        var clauses: [String] = []

        if !titleClause.isEmpty && !artistClauses.isEmpty && !releaseClause.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([titleClause, artistClause, releaseClause]))
            }
        }

        if !titleClause.isEmpty && !artistClauses.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([titleClause, artistClause]))
            }
        }

        if !titleClause.isEmpty && !releaseClause.isEmpty {
            clauses.append(allOf([titleClause, releaseClause]))
        }

        if !releaseClause.isEmpty && !artistClauses.isEmpty {
            for artistClause in artistClauses {
                clauses.append(allOf([releaseClause, artistClause]))
            }
        }

        if !titleClause.isEmpty && !trackClauses.isEmpty {
            for trackClause in trackClauses {
                clauses.append(allOf([titleClause, trackClause]))
            }
        }

        if !releaseClause.isEmpty && !trackClauses.isEmpty {
            for trackClause in trackClauses {
                clauses.append(allOf([releaseClause, trackClause]))
            }
        }

        if !titleClause.isEmpty {
            for durationClause in durationClauses {
                clauses.append(allOf([titleClause, durationClause]))
            }
        }

        if !releaseClause.isEmpty {
            for totalTrackClause in trackTotalClauses {
                clauses.append(allOf([releaseClause, totalTrackClause]))
            }
        }

        if !titleClause.isEmpty && !releaseClause.isEmpty {
            for durationClause in durationClauses {
                clauses.append(allOf([titleClause, releaseClause, durationClause]))
            }

            for totalTrackClause in trackTotalClauses {
                clauses.append(allOf([titleClause, releaseClause, totalTrackClause]))
            }
        }

        if !trackClauses.isEmpty {
            for trackClause in trackClauses {
                for durationClause in durationClauses {
                    clauses.append(allOf([trackClause, durationClause]))
                }
            }
        }

        if !titleClause.isEmpty {
            clauses.append(titleClause)
            clauses.append(generalClause(query.title))
        }

        if !releaseClause.isEmpty {
            clauses.append(releaseClause)
            clauses.append(generalClause(query.album))
        }

        clauses.append(contentsOf: artistClauses)
        clauses.append(contentsOf: trackClauses)
        clauses.append(contentsOf: trackTotalClauses)
        clauses.append(contentsOf: durationClauses)

        return clauses
    }

    nonisolated private static func trackNumberClauses(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = trimmed
            .split(separator: "/")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        var clauses: [String] = []

        let numericToken = String(normalized.drop(while: { $0 == "0" }))

        if let numericValue = Int(numericToken), numericValue > 0 {
            clauses.append(numericClause(name: "tnum", value: numericValue))
        } else if let numericValue = Int(normalized), numericValue > 0 {
            clauses.append(numericClause(name: "tnum", value: numericValue))
        }

        if !normalized.isEmpty {
            clauses.append(fieldClause(name: "number", value: normalized))
        }

        return (Array(NSOrderedSet(array: clauses)) as? [String]) ?? clauses
    }

    nonisolated private static func trackTotalClauses(_ trackTotal: Int) -> [String] {
        guard trackTotal > 0 else { return [] }
        return [numericClause(name: "tracks", value: trackTotal)]
    }

    nonisolated private static func durationClauses(_ quantizedDuration: Int?) -> [String] {
        guard let quantizedDuration, quantizedDuration > 0 else { return [] }
        return [numericClause(name: "qdur", value: quantizedDuration)]
    }
}
