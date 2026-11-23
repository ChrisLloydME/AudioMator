import Foundation

nonisolated enum FileSourceMode: Hashable, Sendable {
    case quickImport
    case watchedFolders
}

nonisolated enum SidebarSelection: Hashable, Sendable {
    case quickImport
    case watchedLibrary
    case watchedFolder(UUID)
    case watchedSubfolder(rootFolderID: UUID, relativePathKey: String)

    var sourceMode: FileSourceMode {
        switch self {
        case .quickImport:
            return .quickImport
        case .watchedLibrary, .watchedFolder, .watchedSubfolder:
            return .watchedFolders
        }
    }

    var watchedRootFolderID: UUID? {
        switch self {
        case .quickImport, .watchedLibrary:
            return nil
        case .watchedFolder(let id), .watchedSubfolder(let id, _):
            return id
        }
    }
}

nonisolated struct WatchedFolderRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data
}

nonisolated struct WatchedFolder: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let url: URL
    let bookmarkData: Data
}

nonisolated struct FileAccessGrantRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data
}

nonisolated struct FileAccessGrant: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let url: URL
    let bookmarkData: Data
}

nonisolated enum FileAccessAuthorizationOutcome: Equatable, Sendable {
    case authorized(path: String)
    case cancelled
    case failure(String)
}
