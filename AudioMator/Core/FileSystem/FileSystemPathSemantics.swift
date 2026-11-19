import Foundation

/// Centralized filesystem-aware identity rules for file URLs.
///
/// Existing symlink aliases are resolved before comparison. Case is folded only
/// when the containing volume reports case-insensitive filename semantics, which
/// also makes the rule usable for destinations that do not exist yet.
/// One path resolution that keeps the intermediate evidence so callers can
/// reuse it instead of resolving the same path again.
///
/// `Quick Import` prepares one resolution for a candidate file and one for its
/// parent directory. The comparison key and the canonical path must come from
/// the same volume-semantics query; computing them separately would repeat the
/// filesystem probes that made progressive indexing quadratic.
nonisolated struct FileSystemURLResolution: Hashable, Sendable {
    let canonicalURL: URL
    let canonicalPath: String
    let key: String
    let isCaseSensitive: Bool
}

enum FileSystemPathSemantics {
    nonisolated static func key(for url: URL) -> String {
        identityResolution(for: url).key
    }

    /// Canonical resolution plus comparison key with a single volume-semantics
    /// query. `canonicalPath` is precomposed but not case-folded; `key` applies
    /// the volume's filename rules.
    nonisolated static func identityResolution(for url: URL) -> FileSystemURLResolution {
        let canonicalURL = canonicalURL(for: url)
        let isCaseSensitive = volumeSupportsCaseSensitiveNames(for: canonicalURL) ?? true
        let canonicalPath = canonicalURL.path
        return FileSystemURLResolution(
            canonicalURL: canonicalURL,
            canonicalPath: canonicalPath,
            key: comparisonKey(forCanonicalPath: canonicalPath, isCaseSensitive: isCaseSensitive),
            isCaseSensitive: isCaseSensitive
        )
    }

    /// Reservation identities for one lexical path: the symlink-resolved
    /// comparison identity plus the directory-entry location identity. Writers
    /// reserve both so a symlink object and its target cannot be mutated as if
    /// they were independent entries.
    nonisolated static func reservationKeys(for url: URL) -> Set<String> {
        [key(for: url), directoryEntryKey(for: url)]
    }

    /// Identity of the directory entry formed by resolving only the parent path
    /// and folding the basename using the parent volume's filename semantics.
    nonisolated static func directoryEntryKey(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        let parentURL = standardizedURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let basename = standardizedURL.lastPathComponent.precomposedStringWithCanonicalMapping
        let isCaseSensitive = volumeSupportsCaseSensitiveNames(for: parentURL) ?? true
        let foldedBasename = isCaseSensitive
            ? basename
            : basename.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parentPath = parentURL.path.precomposedStringWithCanonicalMapping
        return "entry:" + parentPath + "/" + foldedBasename
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

    /// Directory-entry location identity computed from evidence that was already
    /// resolved. `quickImport` uses it for rename-journal matching so an accepted
    /// observation does not resolve the same path again.
    nonisolated static func directoryEntryKey(
        canonicalPath: String,
        parentCanonicalPath: String,
        parentIsCaseSensitive: Bool
    ) -> String {
        let basename = URL(fileURLWithPath: canonicalPath).lastPathComponent
            .precomposedStringWithCanonicalMapping
        let foldedBasename = parentIsCaseSensitive
            ? basename
            : basename.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return "entry:" + parentCanonicalPath.precomposedStringWithCanonicalMapping + "/" + foldedBasename
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
