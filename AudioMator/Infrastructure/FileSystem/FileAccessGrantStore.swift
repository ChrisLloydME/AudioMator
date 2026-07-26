import Foundation

final class FileAccessGrantStore {
    private let userDefaults: UserDefaults
    private let storageKey = "fileAccessGrantRecords"
    private var unresolvedRecords: [FileAccessGrantRecord] = []

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadGrants() -> [FileAccessGrant] {
        unresolvedRecords = []
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }

        do {
            let records = try JSONDecoder().decode([FileAccessGrantRecord].self, from: data)
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
            return []
        }
    }

    func saveGrants(_ grants: [FileAccessGrant]) {
        let resolvedRecords = grants.map {
            FileAccessGrantRecord(
                id: $0.id,
                displayName: $0.displayName,
                bookmarkData: $0.bookmarkData
            )
        }
        let resolvedIDs = Set(resolvedRecords.map(\.id))
        let records = resolvedRecords + unresolvedRecords.filter { !resolvedIDs.contains($0.id) }
        saveRecords(records)
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

    private func saveRecords(_ records: [FileAccessGrantRecord]) {
        do {
            userDefaults.set(try JSONEncoder().encode(records), forKey: storageKey)
        } catch {}
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
