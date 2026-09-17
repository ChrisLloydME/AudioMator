import Foundation

final class FileAccessGrantStore {
    private let userDefaults: UserDefaults
    private let storageKey = "fileAccessGrantRecords"
    private let corruptBackupKey = "fileAccessGrantRecords.corruptBackup"
    private var unresolvedRecords: [FileAccessGrantRecord] = []
    private(set) var loadState: BookmarkCollectionLoadState = .notLoaded

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadGrants() -> [FileAccessGrant] {
        unresolvedRecords = []
        guard let data = userDefaults.data(forKey: storageKey) else {
            loadState = .empty
            return []
        }

        do {
            let records = try JSONDecoder().decode([FileAccessGrantRecord].self, from: data)
            loadState = records.isEmpty ? .empty : .loaded(recordCount: records.count)
            var grants: [FileAccessGrant] = []
            var refreshedRecords: [FileAccessGrantRecord] = []
            var needsSave = false

            for record in records {
                do {
                    var isStale = false
                    let url = try resolveURL(from: record.bookmarkData, isStale: &isStale)
                    let bookmarkData = isStale ? try makeBookmarkData(for: url) : record.bookmarkData
                    let displayName = record.displayName.isEmpty
                        ? FileManager.default.displayName(atPath: url.path)
                        : record.displayName

                    grants.append(
                        FileAccessGrant(
                            id: record.id,
                            displayName: displayName,
                            url: url,
                            bookmarkData: bookmarkData
                        )
                    )
                    refreshedRecords.append(
                        FileAccessGrantRecord(
                            id: record.id,
                            displayName: displayName,
                            bookmarkData: bookmarkData
                        )
                    )

                    if isStale || displayName != record.displayName {
                        needsSave = true
                    }
                } catch {
                    refreshedRecords.append(record)
                    unresolvedRecords.append(record)
                }
            }

            if needsSave {
                saveRecords(refreshedRecords)
            }

            return grants
        } catch {
            loadState = .corrupt
            quarantineCorruptData(data)
            return []
        }
    }

    @discardableResult
    func saveGrants(_ grants: [FileAccessGrant]) -> Bool {
        guard prepareForSave() else { return false }
        let resolvedRecords = grants.map {
            FileAccessGrantRecord(
                id: $0.id,
                displayName: $0.displayName,
                bookmarkData: $0.bookmarkData
            )
        }
        let resolvedIDs = Set(resolvedRecords.map(\.id))
        let records = resolvedRecords + unresolvedRecords.filter { !resolvedIDs.contains($0.id) }
        return saveRecords(records)
    }

    func makeGrant(from url: URL) throws -> FileAccessGrant {
        let normalizedURL = url.standardizedFileURL
        return FileAccessGrant(
            id: UUID(),
            displayName: FileManager.default.displayName(atPath: normalizedURL.path),
            url: normalizedURL,
            bookmarkData: try makeBookmarkData(for: normalizedURL)
        )
    }

    @discardableResult
    private func saveRecords(_ records: [FileAccessGrantRecord]) -> Bool {
        guard loadState != .corrupt else { return false }
        do {
            userDefaults.set(try JSONEncoder().encode(records), forKey: storageKey)
            loadState = records.isEmpty ? .empty : .loaded(recordCount: records.count)
            return true
        } catch {
            return false
        }
    }

    private func prepareForSave() -> Bool {
        guard loadState == .notLoaded else { return loadState != .corrupt }
        guard let data = userDefaults.data(forKey: storageKey) else {
            loadState = .empty
            return true
        }
        do {
            let records = try JSONDecoder().decode([FileAccessGrantRecord].self, from: data)
            loadState = records.isEmpty ? .empty : .loaded(recordCount: records.count)
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

    private func resolveURL(from bookmarkData: Data, isStale: inout Bool) throws -> URL {
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

    private func makeBookmarkData(for url: URL) throws -> Data {
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
