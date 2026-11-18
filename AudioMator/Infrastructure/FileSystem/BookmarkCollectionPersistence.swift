import Foundation

/// A persisted bookmark record resolved to a live URL.
///
/// `bookmarkData` is the refreshed bookmark when the stored bookmark reported
/// itself stale, and the stored data otherwise.
struct ResolvedBookmark {
    let id: UUID
    let displayName: String
    let url: URL
    let bookmarkData: Data
}

/// Shared persistence for a collection of security-scoped bookmark records.
///
/// This owns the behavior common to `WatchedFolderStore` and
/// `FileAccessGrantStore`: decoding and encoding the stored record array,
/// scoped-then-unscoped bookmark resolution and creation, stale-bookmark
/// refresh, empty-display-name repair, corrupt-data quarantine with save
/// refusal, and retention of unresolved records across saves.
///
/// Each typed store keeps its own record type, UserDefaults keys and public
/// API. The helper only ever encodes the caller's `Record` type, so the
/// persisted JSON shape remains that record's `Codable` shape.
struct BookmarkCollectionPersistence<Record: Codable & Identifiable> where Record.ID == UUID {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let corruptBackupKey: String
    private let recordDisplayName: (Record) -> String
    private let recordBookmarkData: (Record) -> Data
    private let makeRecord: (UUID, String, Data) -> Record

    private var unresolvedRecords: [Record] = []
    private(set) var loadState: BookmarkCollectionLoadState = .notLoaded

    init(
        userDefaults: UserDefaults,
        storageKey: String,
        corruptBackupKey: String,
        recordDisplayName: @escaping (Record) -> String,
        recordBookmarkData: @escaping (Record) -> Data,
        makeRecord: @escaping (UUID, String, Data) -> Record
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.corruptBackupKey = corruptBackupKey
        self.recordDisplayName = recordDisplayName
        self.recordBookmarkData = recordBookmarkData
        self.makeRecord = makeRecord
    }

    mutating func load() -> [ResolvedBookmark] {
        unresolvedRecords = []
        guard let data = userDefaults.data(forKey: storageKey) else {
            loadState = .empty
            return []
        }

        do {
            let records = try JSONDecoder().decode([Record].self, from: data)
            loadState = records.isEmpty ? .empty : .loaded
            var bookmarks: [ResolvedBookmark] = []
            var refreshedRecords: [Record] = []
            var needsSave = false

            for record in records {
                do {
                    let storedBookmarkData = recordBookmarkData(record)
                    var isStale = false
                    let url = try Self.resolveURL(from: storedBookmarkData, isStale: &isStale)
                    let bookmarkData = isStale
                        ? try Self.createBookmarkData(for: url)
                        : storedBookmarkData
                    let storedDisplayName = recordDisplayName(record)
                    let displayName = storedDisplayName.isEmpty
                        ? FileManager.default.displayName(atPath: url.path)
                        : storedDisplayName

                    bookmarks.append(
                        ResolvedBookmark(
                            id: record.id,
                            displayName: displayName,
                            url: url,
                            bookmarkData: bookmarkData
                        )
                    )
                    refreshedRecords.append(makeRecord(record.id, displayName, bookmarkData))

                    if isStale || displayName != storedDisplayName {
                        needsSave = true
                    }
                } catch {
                    refreshedRecords.append(record)
                    unresolvedRecords.append(record)
                }
            }

            if needsSave {
                _ = saveRecords(refreshedRecords)
            }

            return bookmarks
        } catch {
            loadState = .corrupt
            quarantineCorruptData(data)
            return []
        }
    }

    /// Saves `records`, retaining previously unresolved records unless the
    /// caller supplied a record for the same identifier.
    mutating func save(_ records: [Record]) -> Bool {
        guard prepareForSave() else { return false }
        let resolvedIDs = Set(records.map(\.id))
        let combinedRecords = records + unresolvedRecords.filter { !resolvedIDs.contains($0.id) }
        return saveRecords(combinedRecords)
    }

    func makeBookmarkData(for url: URL) throws -> Data {
        try Self.createBookmarkData(for: url)
    }

    private mutating func saveRecords(_ records: [Record]) -> Bool {
        guard loadState != .corrupt else { return false }
        do {
            userDefaults.set(try JSONEncoder().encode(records), forKey: storageKey)
            loadState = records.isEmpty ? .empty : .loaded
            return true
        } catch {
            return false
        }
    }

    private mutating func prepareForSave() -> Bool {
        guard loadState == .notLoaded else { return loadState != .corrupt }
        guard let data = userDefaults.data(forKey: storageKey) else {
            loadState = .empty
            return true
        }
        do {
            let records = try JSONDecoder().decode([Record].self, from: data)
            loadState = records.isEmpty ? .empty : .loaded
            return true
        } catch {
            loadState = .corrupt
            quarantineCorruptData(data)
            return false
        }
    }

    private func quarantineCorruptData(_ data: Data) {
        if userDefaults.data(forKey: corruptBackupKey) == nil {
            userDefaults.set(data, forKey: corruptBackupKey)
        }
    }

    private static func resolveURL(from bookmarkData: Data, isStale: inout Bool) throws -> URL {
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }

    private static func createBookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }
}
