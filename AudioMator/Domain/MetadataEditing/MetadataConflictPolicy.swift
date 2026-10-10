import Foundation

// Explicit priorities apply only to edited fields that also changed on disk.
enum MetadataConflictPolicy: String, CaseIterable, Sendable {
    case mergeNonConflicting
    case preferUserChanges
    case preferDiskChanges
    case requireReload

    nonisolated static let defaultsKey = "metadata.conflictPolicy"

    nonisolated static func load(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .mergeNonConflicting
    }
}
