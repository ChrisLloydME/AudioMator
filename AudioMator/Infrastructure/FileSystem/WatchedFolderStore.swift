import Foundation

final class WatchedFolderStore {
    private let userDefaults: UserDefaults
    private let storageKey = "watchedFolderRecords"
    private var unresolvedRecords: [WatchedFolderRecord] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadFolders() -> [WatchedFolder] {
        unresolvedRecords = []
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }

        do {
            let records = try JSONDecoder().decode([WatchedFolderRecord].self, from: data)
            var folders: [WatchedFolder] = []
            var refreshedRecords: [WatchedFolderRecord] = []
            var needsSave = false

            for record in records {
                do {
                    var isStale = false
                    let url = try resolveURL(from: record.bookmarkData, isStale: &isStale)
                    let bookmarkData = isStale ? try makeBookmarkData(for: url) : record.bookmarkData
                    let displayName = record.displayName.isEmpty
                        ? FileManager.default.displayName(atPath: url.path)
                        : record.displayName

                    folders.append(
                        WatchedFolder(
                            id: record.id,
                            displayName: displayName,
                            url: url,
                            bookmarkData: bookmarkData
                        )
                    )
                    refreshedRecords.append(
                        WatchedFolderRecord(
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

            return folders
        } catch {
            return []
        }
    }

    func saveFolders(_ folders: [WatchedFolder]) {
        let resolvedRecords = folders.map {
            WatchedFolderRecord(
                id: $0.id,
                displayName: $0.displayName,
                bookmarkData: $0.bookmarkData
            )
        }
        let resolvedIDs = Set(resolvedRecords.map(\.id))
        let records = resolvedRecords + unresolvedRecords.filter { !resolvedIDs.contains($0.id) }

        saveRecords(records)
    }

    private func saveRecords(_ records: [WatchedFolderRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            userDefaults.set(data, forKey: storageKey)
        } catch {}
    }

    func makeFolder(from url: URL) throws -> WatchedFolder {
        let normalizedURL = url.standardizedFileURL
        let displayName = FileManager.default.displayName(atPath: normalizedURL.path)

        return WatchedFolder(
            id: UUID(),
            displayName: displayName,
            url: normalizedURL,
            bookmarkData: try makeBookmarkData(for: normalizedURL)
        )
    }

    private func resolveURL(from bookmarkData: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
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
        #else
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif
    }

    private func makeBookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
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
        #else
        return try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }
}
