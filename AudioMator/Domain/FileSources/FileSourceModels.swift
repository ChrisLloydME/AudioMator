import Foundation
import Combine

enum FileSourceMode {
    case quickImport
    case watchedFolders
}

enum SidebarSelection: Hashable {
    case quickImport
    case watchedLibrary
    case watchedFolder(UUID)

    var sourceMode: FileSourceMode {
        switch self {
        case .quickImport:
            return .quickImport
        case .watchedLibrary, .watchedFolder:
            return .watchedFolders
        }
    }
}

struct WatchedFolderRecord: Codable, Identifiable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data
}

struct WatchedFolder: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let url: URL
    let bookmarkData: Data
}

struct FileAccessGrantRecord: Codable, Identifiable {
    let id: UUID
    let displayName: String
    let bookmarkData: Data
}

struct FileAccessGrant: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let url: URL
    let bookmarkData: Data
}

enum FileAccessAuthorizationOutcome: Equatable {
    case authorized(path: String)
    case cancelled
    case failure(String)
}
