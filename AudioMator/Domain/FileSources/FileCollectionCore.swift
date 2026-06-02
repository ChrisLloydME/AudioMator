import Foundation

struct CoreAudioFileReference: Equatable, Hashable {
    let id: String
    let path: String
    let displayName: String
}

enum FileCollectionCore {
    static func sortedImportURLs(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func mergePreservingExistingOrder(
        existing: [CoreAudioFileReference],
        incoming: [CoreAudioFileReference]
    ) -> [CoreAudioFileReference] {
        var seenPaths = Set(existing.map(normalizedPath))
        var result = existing

        for file in incoming where seenPaths.insert(normalizedPath(file)).inserted {
            result.append(file)
        }

        return result
    }

    static func groupedByAlbum(
        files: [CoreAudioFileReference],
        album: (CoreAudioFileReference) -> String,
        albumArtist: (CoreAudioFileReference) -> String,
        compilationKey: (CoreAudioFileReference) -> String
    ) -> [String: [CoreAudioFileReference]] {
        Dictionary(grouping: files) { file in
            let albumValue = album(file).trimmingCharacters(in: .whitespacesAndNewlines)
            let artistValue = albumArtist(file).trimmingCharacters(in: .whitespacesAndNewlines)
            let compilationValue = compilationKey(file).trimmingCharacters(in: .whitespacesAndNewlines)
            return [albumValue, artistValue.isEmpty ? compilationValue : artistValue]
                .filter { !$0.isEmpty }
                .joined(separator: "|")
        }
    }

    nonisolated private static func normalizedPath(_ file: CoreAudioFileReference) -> String {
        URL(fileURLWithPath: file.path).standardizedFileURL.path.lowercased()
    }
}
