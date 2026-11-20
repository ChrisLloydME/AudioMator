import Foundation

enum FileMutationDirectoryAccessPlan {
    nonisolated static func missingDirectories(
        for fileURLs: [URL],
        activeDirectoryURLs: [URL]
    ) -> [URL] {
        directories(for: fileURLs).filter { directory in
            !activeDirectoryURLs.contains { FileSystemPathSemantics.isSameOrDescendant(directory, of: $0) }
        }
    }

    nonisolated static func directories(for fileURLs: [URL]) -> [URL] {
        var directoriesByPath: [String: URL] = [:]

        for fileURL in fileURLs {
            let directoryURL = fileURL.standardizedFileURL.deletingLastPathComponent()
            directoriesByPath[normalizedPath(for: directoryURL)] = directoryURL
        }

        return directoriesByPath.values.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    nonisolated private static func normalizedPath(for url: URL) -> String {
        FileSystemPathSemantics.key(for: url)
    }
}
