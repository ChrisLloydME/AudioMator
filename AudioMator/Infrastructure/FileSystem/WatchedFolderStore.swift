import Foundation

/// Persistent security-scoped bookmarks for the user's watched folders.
/// Storage, bookmark refresh and corrupt-collection handling are shared with
/// `FileAccessGrantStore` through `BookmarkCollectionPersistence`.
final class WatchedFolderStore {
    private var persistence: BookmarkCollectionPersistence<WatchedFolderRecord>

    var loadState: BookmarkCollectionLoadState { persistence.loadState }

    init(userDefaults: UserDefaults = .standard) {
        persistence = BookmarkCollectionPersistence(
            userDefaults: userDefaults,
            storageKey: "watchedFolderRecords",
            corruptBackupKey: "watchedFolderRecords.corruptBackup",
            recordDisplayName: { $0.displayName },
            recordBookmarkData: { $0.bookmarkData },
            makeRecord: { WatchedFolderRecord(id: $0, displayName: $1, bookmarkData: $2) }
        )
    }

    func loadFolders() -> [WatchedFolder] {
        persistence.load().map {
            WatchedFolder(
                id: $0.id,
                displayName: $0.displayName,
                url: $0.url,
                bookmarkData: $0.bookmarkData
            )
        }
    }

    @discardableResult
    func saveFolders(_ folders: [WatchedFolder]) -> Bool {
        persistence.save(
            folders.map {
                WatchedFolderRecord(
                    id: $0.id,
                    displayName: $0.displayName,
                    bookmarkData: $0.bookmarkData
                )
            }
        )
    }

    func makeFolder(from url: URL) throws -> WatchedFolder {
        let normalizedURL = url.standardizedFileURL
        return WatchedFolder(
            id: UUID(),
            displayName: FileManager.default.displayName(atPath: normalizedURL.path),
            url: normalizedURL,
            bookmarkData: try persistence.makeBookmarkData(for: normalizedURL)
        )
    }
}
