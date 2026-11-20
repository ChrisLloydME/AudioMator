import Foundation

/// Durable rename-journal format constants.
///
/// The journal is recovery evidence only. It deliberately does not persist
/// metadata, drafts, tag values, session file IDs, or security-scope
/// bookmarks. A reader accepts exactly the current version; anything newer is
/// retained untouched for manual inspection.
nonisolated enum RenameJournalFormat {
    static let currentVersion = 1
    static let maximumEntryCount = 4_096
    static let manifestFilePrefix = "operation-"
    static let manifestFileSuffix = ".json"
    static let temporaryFileSuffix = ".tmp"
    static let lockFileName = "rename-journal.lock"

    static func manifestFileName(operationID: UUID) -> String {
        manifestFilePrefix + operationID.uuidString.lowercased() + manifestFileSuffix
    }

    static func temporaryFileName(operationID: UUID) -> String {
        manifestFileName(operationID: operationID) + temporaryFileSuffix
    }

    static func operationID(fromManifestFileName fileName: String) -> UUID? {
        let minimumLength = manifestFilePrefix.count + manifestFileSuffix.count
        guard fileName.count > minimumLength,
              fileName.hasPrefix(manifestFilePrefix),
              fileName.hasSuffix(manifestFileSuffix)
        else { return nil }

        let start = fileName.index(fileName.startIndex, offsetBy: manifestFilePrefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -manifestFileSuffix.count)
        guard start < end else { return nil }
        return UUID(uuidString: String(fileName[start..<end]))
    }
}

nonisolated enum RenameJournalPhase: String, Codable, Hashable, Sendable {
    case prepared
    case committed
}

/// Sanitized diagnostic codes. Unknown codes from a newer writer are ignored by
/// readers; codes never contain paths, file names, or free text.
nonisolated enum RenameJournalDiagnosticCode: String, Codable, Hashable, Sendable, CaseIterable {
    case directoryBarrierUnsupported
    case journalCleanupDeferred
    case commitRecordRewriteFailed
    case rollbackVerificationFailed
    case restoreDirectoryBarrierUnsupported
}

/// Persisted directory-entry identity evidence.
///
/// `Date` values are persisted as their raw `timeIntervalSince1970` `Double`
/// storage so an encode/decode round trip is exact; converting through
/// integer nanoseconds would lose precision. The device/inode pair is required:
/// an operation that cannot record it fails before staging.
nonisolated struct RenameJournalEntryIdentity: Codable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let kind: FileEntryKind
    let size: UInt64
    let modificationTimeIntervalSince1970: Double
    let creationTimeIntervalSince1970: Double?
    let volumeIdentifier: String?

    init(
        device: UInt64,
        inode: UInt64,
        kind: FileEntryKind,
        size: UInt64,
        modificationTimeIntervalSince1970: Double,
        creationTimeIntervalSince1970: Double?,
        volumeIdentifier: String?
    ) {
        self.device = device
        self.inode = inode
        self.kind = kind
        self.size = size
        self.modificationTimeIntervalSince1970 = modificationTimeIntervalSince1970
        self.creationTimeIntervalSince1970 = creationTimeIntervalSince1970
        self.volumeIdentifier = volumeIdentifier
    }

    init(_ identity: RenameEntryIdentity) throws {
        guard let device = identity.device, let inode = identity.inode else {
            throw RenameJournalIdentityError.missingDeviceOrInode
        }
        self.init(
            device: device,
            inode: inode,
            kind: identity.kind,
            size: identity.size,
            modificationTimeIntervalSince1970: identity.modificationDate.timeIntervalSince1970,
            creationTimeIntervalSince1970: identity.creationDate?.timeIntervalSince1970,
            volumeIdentifier: identity.volumeIdentifier
        )
    }

    var renameEntryIdentity: RenameEntryIdentity {
        RenameEntryIdentity(
            device: device,
            inode: inode,
            kind: kind,
            size: size,
            modificationDate: Date(timeIntervalSince1970: modificationTimeIntervalSince1970),
            creationDate: creationTimeIntervalSince1970.map(Date.init(timeIntervalSince1970:)),
            volumeIdentifier: volumeIdentifier,
            linkTarget: nil
        )
    }

    /// Exact evidence comparison. If either side has a volume identity and the
    /// other is missing or different, the match fails so a remounted volume
    /// cannot alias an old device/inode pair. Volumes that do not expose a
    /// stable volume UUID report `nil` on both sides and compare full stat fields.
    func matchesEntryIdentity(_ observed: RenameEntryIdentity) -> Bool {
        guard
            let observedDevice = observed.device,
            let observedInode = observed.inode,
            observedDevice == device,
            observedInode == inode,
            observed.kind == kind,
            observed.size == size,
            observed.modificationDate.timeIntervalSince1970 == modificationTimeIntervalSince1970,
            observed.creationDate?.timeIntervalSince1970 == creationTimeIntervalSince1970
        else { return false }

        switch (volumeIdentifier, observed.volumeIdentifier) {
        case let (expected?, observed?):
            return expected == observed
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

nonisolated enum RenameJournalIdentityError: Error, Equatable, Sendable {
    case missingDeviceOrInode
}

nonisolated struct RenameJournalEntry: Codable, Hashable, Sendable {
    let index: Int
    let originalURL: String
    let temporaryURL: String
    let intendedURL: String
    let sourceIdentity: RenameJournalEntryIdentity
    let linkTarget: String?
}

nonisolated struct RenameJournalManifest: Codable, Hashable, Sendable {
    let formatVersion: Int
    let operationID: UUID
    let phase: RenameJournalPhase
    let createdAt: Double
    let committedAt: Double?
    let diagnostics: [String]
    let entries: [RenameJournalEntry]

    var fileName: String {
        RenameJournalFormat.manifestFileName(operationID: operationID)
    }

    func validate() throws {
        guard formatVersion == RenameJournalFormat.currentVersion else {
            throw RenameJournalValidationError.unsupportedVersion(formatVersion)
        }
        guard !entries.isEmpty else { throw RenameJournalValidationError.emptyBatch }
        guard entries.count <= RenameJournalFormat.maximumEntryCount else {
            throw RenameJournalValidationError.tooManyEntries
        }
        guard entries.map(\.index) == Array(0..<entries.count) else {
            throw RenameJournalValidationError.invalidIndex
        }
        switch phase {
        case .prepared:
            guard committedAt == nil else { throw RenameJournalValidationError.phaseTimestamps }
        case .committed:
            guard committedAt != nil else { throw RenameJournalValidationError.phaseTimestamps }
        }
        for code in diagnostics where !Self.isValidDiagnosticCode(code) {
            throw RenameJournalValidationError.invalidDiagnostic
        }

        var originalKeys: Set<String> = []
        var intendedKeys: Set<String> = []
        var temporaryKeys: Set<String> = []

        for entry in entries {
            guard
                let originalURL = Self.parsedFileURL(entry.originalURL),
                let temporaryURL = Self.parsedFileURL(entry.temporaryURL),
                let intendedURL = Self.parsedFileURL(entry.intendedURL)
            else {
                throw RenameJournalValidationError.invalidURL
            }

            let parent = originalURL.deletingLastPathComponent().absoluteString
            guard
                temporaryURL.deletingLastPathComponent().absoluteString == parent,
                intendedURL.deletingLastPathComponent().absoluteString == parent
            else {
                throw RenameJournalValidationError.mixedParents
            }

            let expectedTemporaryURL = RenameStagingName.url(
                for: originalURL,
                operationID: operationID,
                index: entry.index
            )
            guard expectedTemporaryURL.absoluteString == entry.temporaryURL else {
                throw RenameJournalValidationError.invalidTemporaryName
            }
            guard temporaryURL.absoluteString != originalURL.absoluteString,
                  temporaryURL.absoluteString != intendedURL.absoluteString,
                  originalURL.absoluteString != intendedURL.absoluteString
            else {
                throw RenameJournalValidationError.roleCollision
            }
            guard originalURL.pathExtension == intendedURL.pathExtension else {
                throw RenameJournalValidationError.invalidExtension
            }
            let temporaryKey = FileSystemPathSemantics.directoryEntryKey(for: temporaryURL)
            guard temporaryKeys.insert(temporaryKey).inserted else {
                throw RenameJournalValidationError.duplicateTemporaryName
            }

            let originalKey = FileSystemPathSemantics.directoryEntryKey(for: originalURL)
            guard originalKeys.insert(originalKey).inserted else {
                throw RenameJournalValidationError.duplicateSource
            }
            let intendedKey = FileSystemPathSemantics.directoryEntryKey(for: intendedURL)
            guard intendedKeys.insert(intendedKey).inserted else {
                throw RenameJournalValidationError.duplicateTarget
            }

            guard entry.sourceIdentity.kind != .directory else {
                throw RenameJournalValidationError.unexpectedEntryKind
            }
            if entry.sourceIdentity.kind == .symlink {
                guard entry.linkTarget != nil else {
                    throw RenameJournalValidationError.symlinkEvidenceMissing
                }
            } else {
                guard entry.linkTarget == nil else {
                    throw RenameJournalValidationError.symlinkEvidenceMissing
                }
            }
            guard entry.sourceIdentity.volumeIdentifier?.utf8.count ?? 0 <= 128 else {
                throw RenameJournalValidationError.invalidVolumeIdentity
            }
        }
        guard temporaryKeys.isDisjoint(with: originalKeys),
              temporaryKeys.isDisjoint(with: intendedKeys) else {
            throw RenameJournalValidationError.roleCollision
        }
    }

    private static func parsedFileURL(_ value: String) -> URL? {
        guard
            let url = URL(string: value),
            url.isFileURL,
            url.absoluteString == value,
            url.path.hasPrefix("/"),
            !url.path.isEmpty
        else { return nil }
        return url
    }

    private static func isValidDiagnosticCode(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 64 else { return false }
        guard let first = value.first, first.isLowercase else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

nonisolated enum RenameJournalValidationError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case emptyBatch
    case tooManyEntries
    case invalidIndex
    case phaseTimestamps
    case invalidDiagnostic
    case invalidURL
    case mixedParents
    case invalidTemporaryName
    case invalidExtension
    case roleCollision
    case duplicateTemporaryName
    case duplicateSource
    case duplicateTarget
    case unexpectedEntryKind
    case symlinkEvidenceMissing
    case invalidVolumeIdentity
}

nonisolated enum RenameJournalLoadIssueCategory: String, Equatable, Sendable {
    case unreadable
    case unsupportedVersion
    case invalidManifest
    case incompleteWrite
    case duplicateOperationID
}

/// Sanitized load problem. `manifestFileName` contains only the journal file name
/// (operation UUID); it never contains an audio path.
nonisolated struct RenameJournalLoadIssue: Equatable, Sendable {
    let manifestFileName: String
    let category: RenameJournalLoadIssueCategory
    let detailCode: String?
}

nonisolated struct RenameJournalLoadResult: Sendable {
    let manifests: [RenameJournalManifest]
    let issues: [RenameJournalLoadIssue]
}
