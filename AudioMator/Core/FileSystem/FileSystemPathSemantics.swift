import Foundation

/// Centralized filesystem-aware identity rules for file URLs.
///
/// Existing symlink aliases are resolved before comparison. Case is folded only
/// when the containing volume reports case-insensitive filename semantics, which
/// also makes the rule usable for destinations that do not exist yet.
enum FileSystemPathSemantics {
    nonisolated static func key(for url: URL) -> String {
        let canonicalURL = canonicalURL(for: url)
        let isCaseSensitive = volumeSupportsCaseSensitiveNames(for: canonicalURL) ?? true
        return comparisonKey(forCanonicalPath: canonicalURL.path, isCaseSensitive: isCaseSensitive)
    }

    nonisolated static func isSameOrDescendant(_ url: URL, of ancestorURL: URL) -> Bool {
        let urlKey = key(for: url)
        let ancestorKey = key(for: ancestorURL)

        if urlKey == ancestorKey {
            return true
        }

        let ancestorPrefix = ancestorKey == "/" ? "/" : ancestorKey + "/"
        return urlKey.hasPrefix(ancestorPrefix)
    }

    nonisolated static func comparisonKey(
        forCanonicalPath path: String,
        isCaseSensitive: Bool
    ) -> String {
        let normalizedPath = path.precomposedStringWithCanonicalMapping
        guard !isCaseSensitive else { return normalizedPath }
        return normalizedPath.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated private static func canonicalURL(for url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    nonisolated private static func volumeSupportsCaseSensitiveNames(for url: URL) -> Bool? {
        var candidateURL = url
        let fileManager = FileManager.default

        while true {
            if fileManager.fileExists(atPath: candidateURL.path),
               let values = try? candidateURL.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
               let isCaseSensitive = values.volumeSupportsCaseSensitiveNames {
                return isCaseSensitive
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL.path != candidateURL.path else { return nil }
            candidateURL = parentURL
        }
    }
}
