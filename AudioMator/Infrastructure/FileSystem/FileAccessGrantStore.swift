import Foundation

/// Persistent security-scoped bookmarks for folders the user permitted for
/// file access. Storage, bookmark refresh and corrupt-collection handling are
/// shared with `WatchedFolderStore` through `BookmarkCollectionPersistence`.
final class FileAccessGrantStore {
    private var persistence: BookmarkCollectionPersistence<FileAccessGrantRecord>

    var loadState: BookmarkCollectionLoadState { persistence.loadState }

    init(userDefaults: UserDefaults = .standard) {
        persistence = BookmarkCollectionPersistence(
            userDefaults: userDefaults,
            storageKey: "fileAccessGrantRecords",
            corruptBackupKey: "fileAccessGrantRecords.corruptBackup",
            recordDisplayName: { $0.displayName },
            recordBookmarkData: { $0.bookmarkData },
            makeRecord: { FileAccessGrantRecord(id: $0, displayName: $1, bookmarkData: $2) }
        )
    }

    func loadGrants() -> [FileAccessGrant] {
        persistence.load().map {
            FileAccessGrant(
                id: $0.id,
                displayName: $0.displayName,
                url: $0.url,
                bookmarkData: $0.bookmarkData
            )
        }
    }

    @discardableResult
    func saveGrants(_ grants: [FileAccessGrant]) -> Bool {
        persistence.save(
            grants.map {
                FileAccessGrantRecord(
                    id: $0.id,
                    displayName: $0.displayName,
                    bookmarkData: $0.bookmarkData
                )
            }
        )
    }

    func makeGrant(from url: URL) throws -> FileAccessGrant {
        let normalizedURL = url.standardizedFileURL
        return FileAccessGrant(
            id: UUID(),
            displayName: FileManager.default.displayName(atPath: normalizedURL.path),
            url: normalizedURL,
            bookmarkData: try persistence.makeBookmarkData(for: normalizedURL)
        )
    }
}
