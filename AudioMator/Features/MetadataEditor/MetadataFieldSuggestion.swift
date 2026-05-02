import Foundation
import TagLibAudioMetadata

struct MetadataFieldSuggestion: Identifiable, Hashable {
    let canonicalKey: String
    let displayName: String
    let category: MetadataFieldCategory
    let aliases: [String]
    let searchKeys: [String]

    nonisolated var id: String { canonicalKey }

    nonisolated var detailText: String {
        "\(canonicalKey) · \(category.displayName)"
    }

    nonisolated static let allSupported: [MetadataFieldSuggestion] = {
        MetadataFieldRegistry.allSchemas
            .filter { !$0.isArtworkField }
            .compactMap(MetadataFieldSuggestion.init(schema:))
            .sorted { lhs, rhs in
                let displayComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if displayComparison != .orderedSame {
                    return displayComparison == .orderedAscending
                }

                return lhs.canonicalKey.localizedCaseInsensitiveCompare(rhs.canonicalKey) == .orderedAscending
            }
    }()

    nonisolated init?(schema: MetadataFieldSchema) {
        guard let preferredKey = schema.propertyMapKeys.first else { return nil }

        let canonicalKey = MetadataFieldRegistry.normalizePropertyMapKey(preferredKey)
        guard !canonicalKey.isEmpty else { return nil }

        let aliases = Self.uniqueNormalizedKeys(schema.propertyMapKeys)
        let searchKeys = Self.uniqueSearchKeys([
            schema.displayName,
            schema.category.displayName,
            canonicalKey
        ] + aliases)

        self.canonicalKey = canonicalKey
        self.displayName = schema.displayName
        self.category = schema.category
        self.aliases = aliases
        self.searchKeys = searchKeys
    }

    nonisolated func matches(query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }

        return searchKeys.contains { searchKey in
            searchKey.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    nonisolated static func resolvedKey(for input: String, suggestions: [MetadataFieldSuggestion] = allSupported) -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return "" }

        let normalizedInput = MetadataFieldRegistry.normalizePropertyMapKey(trimmedInput)
        if let matchingAlias = suggestions.first(where: { $0.aliases.contains(normalizedInput) }) {
            return matchingAlias.canonicalKey
        }

        let displayNameMatches = suggestions.filter {
            $0.displayName.compare(trimmedInput, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if displayNameMatches.count == 1, let match = displayNameMatches.first {
            return match.canonicalKey
        }

        return trimmedInput
    }

    nonisolated private static func uniqueNormalizedKeys(_ keys: [String]) -> [String] {
        var seenKeys = Set<String>()
        var uniqueKeys: [String] = []

        for key in keys {
            let normalizedKey = MetadataFieldRegistry.normalizePropertyMapKey(key)
            guard !normalizedKey.isEmpty, seenKeys.insert(normalizedKey).inserted else { continue }
            uniqueKeys.append(normalizedKey)
        }

        return uniqueKeys
    }

    nonisolated private static func uniqueSearchKeys(_ keys: [String]) -> [String] {
        var seenKeys = Set<String>()
        var uniqueKeys: [String] = []

        for key in keys {
            let searchKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !searchKey.isEmpty else { continue }

            let foldedKey = searchKey.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard seenKeys.insert(foldedKey).inserted else { continue }
            uniqueKeys.append(searchKey)
        }

        return uniqueKeys
    }
}

extension MetadataFieldCategory {
    nonisolated var displayName: String {
        switch self {
        case .basic:
            return "Basic"
        case .numbering:
            return "Numbering"
        case .artwork:
            return "Artwork"
        case .lyricsAndComments:
            return "Lyrics & Comments"
        case .dates:
            return "Dates"
        case .people:
            return "People"
        case .peopleRoles:
            return "People Roles"
        case .sorting:
            return "Sorting"
        case .identifiers:
            return "Identifiers"
        case .release:
            return "Release"
        case .replayGain:
            return "ReplayGain"
        case .itunes:
            return "iTunes"
        case .technical:
            return "Technical"
        case .custom:
            return "Custom"
        }
    }
}
