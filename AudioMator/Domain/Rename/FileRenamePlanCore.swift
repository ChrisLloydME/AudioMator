import Foundation

enum FileRenameCoreStatus: Equatable {
    case ready
    case unchanged
    case emptyName
    case nameTooLong
    case sourceUnavailable
    case duplicateTarget
    case existingFile

    var isIssue: Bool {
        switch self {
        case .ready, .unchanged:
            return false
        case .emptyName, .nameTooLong, .sourceUnavailable, .duplicateTarget, .existingFile:
            return true
        }
    }
}

struct FileRenameCoreDraft<ID: Hashable>: Equatable {
    let id: ID
    let sourceKey: String?
    let destinationKey: String?
    let destinationExists: Bool
    let initialStatus: FileRenameCoreStatus

    init(
        id: ID,
        sourceKey: String?,
        destinationKey: String?,
        destinationExists: Bool,
        initialStatus: FileRenameCoreStatus
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.destinationKey = destinationKey
        self.destinationExists = destinationExists
        self.initialStatus = initialStatus
    }
}

enum FileRenameCollisionPolicy {
    static func finalizedStatuses<ID: Hashable>(
        for drafts: [FileRenameCoreDraft<ID>]
    ) -> [ID: FileRenameCoreStatus] {
        let duplicateKeySet = duplicateDestinationKeys(in: drafts)
        let activeReadyIDs = resolveReadyIDs(from: drafts, duplicateKeySet: duplicateKeySet)
        var statuses: [ID: FileRenameCoreStatus] = [:]

        for draft in drafts {
            if
                draft.initialStatus == .ready,
                let destinationKey = draft.destinationKey,
                duplicateKeySet.contains(destinationKey)
            {
                statuses[draft.id] = .duplicateTarget
            } else if draft.initialStatus == .ready, !activeReadyIDs.contains(draft.id) {
                statuses[draft.id] = .existingFile
            } else {
                statuses[draft.id] = draft.initialStatus
            }
        }

        return statuses
    }

    private static func duplicateDestinationKeys<ID: Hashable>(
        in drafts: [FileRenameCoreDraft<ID>]
    ) -> Set<String> {
        var destinationCounts: [String: Int] = [:]

        for draft in drafts {
            guard draft.initialStatus == .ready, let destinationKey = draft.destinationKey else { continue }
            destinationCounts[destinationKey, default: 0] += 1
        }

        return Set(destinationCounts.compactMap { $0.value > 1 ? $0.key : nil })
    }

    private static func resolveReadyIDs<ID: Hashable>(
        from drafts: [FileRenameCoreDraft<ID>],
        duplicateKeySet: Set<String>
    ) -> Set<ID> {
        let renamableDrafts = drafts.filter { draft in
            guard draft.initialStatus == .ready, let destinationKey = draft.destinationKey else { return false }
            return !duplicateKeySet.contains(destinationKey)
        }

        var activeReadyIDs = Set(renamableDrafts.map(\.id))
        var didChange = true

        while didChange {
            didChange = false

            let readySourceKeys = Set(
                renamableDrafts.compactMap { draft in
                    activeReadyIDs.contains(draft.id) ? draft.sourceKey : nil
                }
            )

            for draft in renamableDrafts {
                guard activeReadyIDs.contains(draft.id) else { continue }
                guard let sourceKey = draft.sourceKey, let destinationKey = draft.destinationKey else { continue }

                let isBlockedByExistingFile =
                    draft.destinationExists &&
                    destinationKey != sourceKey &&
                    !readySourceKeys.contains(destinationKey)

                if isBlockedByExistingFile {
                    activeReadyIDs.remove(draft.id)
                    didChange = true
                }
            }
        }

        return activeReadyIDs
    }
}
