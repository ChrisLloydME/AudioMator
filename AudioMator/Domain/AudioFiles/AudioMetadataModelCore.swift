import Foundation

enum AudioMetadataMergeCore {
    static func mergedValue(_ values: [String], mixedPlaceholder: String = "-") -> String {
        guard let first = values.first else { return mixedPlaceholder }
        return values.allSatisfy { $0 == first } ? first : mixedPlaceholder
    }

    static func duplicateKeys<T>(
        in values: [T],
        key: (T) -> String
    ) -> Set<String> {
        var counts: [String: Int] = [:]
        for value in values {
            let normalized = key(value).trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !normalized.isEmpty else { continue }
            counts[normalized, default: 0] += 1
        }
        return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
    }
}

enum ArtworkReplacementDecision: Equatable {
    case keepExisting
    case replace
    case remove
    case removeNoop
}

enum ArtworkReplacementCore {
    static func decision(hasExistingArtwork: Bool, requestedReplacementDataIsEmpty: Bool, shouldRemove: Bool) -> ArtworkReplacementDecision {
        if shouldRemove {
            return hasExistingArtwork ? .remove : .removeNoop
        }
        return requestedReplacementDataIsEmpty ? .keepExisting : .replace
    }
}
