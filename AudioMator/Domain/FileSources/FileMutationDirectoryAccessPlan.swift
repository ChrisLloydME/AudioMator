import Foundation

enum FileMutationDirectoryAccessPlan {
    nonisolated static func missingDirectories(
        for fileURLs: [URL],
        activeDirectoryURLs: [URL]
    ) -> [URL] {
        var directoriesByPath: [String: URL] = [:]

        for fileURL in fileURLs {
            let directoryURL = fileURL.standardizedFileURL.deletingLastPathComponent()
            directoriesByPath[normalizedPath(for: directoryURL)] = directoryURL
        }

        return directoriesByPath.values
            .filter { directoryURL in
                !activeDirectoryURLs.contains { activeDirectoryURL in
                    isSameOrDescendant(directoryURL, of: activeDirectoryURL)
                }
            }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    nonisolated static func isSameOrDescendant(_ url: URL, of ancestorURL: URL) -> Bool {
        let normalizedURL = normalizedPath(for: url)
        let normalizedAncestorURL = normalizedPath(for: ancestorURL)

        if normalizedURL == normalizedAncestorURL {
            return true
        }

        let ancestorPrefix = normalizedAncestorURL == "/" ? "/" : normalizedAncestorURL + "/"
        return normalizedURL.hasPrefix(ancestorPrefix)
    }

    nonisolated private static func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
