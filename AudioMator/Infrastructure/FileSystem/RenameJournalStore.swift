import Darwin
import Foundation

nonisolated enum RenameDirectoryBarrierSupport: Sendable {
    case supported
    case unsupported
}

nonisolated enum RenameJournalStoreError: Error, Equatable, Sendable {
    case directoryUnavailable(code: Int32)
    case encodeFailed
    case writeFailed(code: Int32)
    case syncFailed(code: Int32)
    case duplicateOperation(operationID: UUID)
    case manifestMissing(operationID: UUID)
    case lockUnavailable(code: Int32)
    case removalFailed(code: Int32)
}

/// Held cross-process journal lock. The lock is released when the token is
/// deallocated (or explicitly released); the lock file itself is never moved or
/// removed.
nonisolated final class RenameJournalLock: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func release() {
        lock.lock()
        let descriptor = self.descriptor
        self.descriptor = -1
        lock.unlock()
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    deinit {
        release()
    }
}

/// Injected durable-journal seam. The implementation owns manifest I/O and the
/// stable lock file; the transaction service owns ordering and recovery policy.
nonisolated protocol RenameJournalStoring: Sendable {
    var directoryURL: URL { get }
    func ensureDirectory() throws
    func loadManifests() -> RenameJournalLoadResult
    func tryAcquireLock() throws -> RenameJournalLock?
    func directoryBarrierSupport() -> RenameDirectoryBarrierSupport
    func writePrepared(_ manifest: RenameJournalManifest) throws
    func markCommitted(_ manifest: RenameJournalManifest) throws
    func removeManifest(operationID: UUID) throws
}

/// Application Support journal store.
///
/// One versioned manifest file per operation UUID plus a stable, never-renamed
/// lock file in the same directory. Manifest writes are atomic (temporary file,
/// file flush, atomic install, directory flush). Malformed or unsupported files
/// are retained byte-for-byte and reported as sanitized issues.
nonisolated final class LocalRenameJournalStore: RenameJournalStoring {
    let directoryURL: URL

    nonisolated init(directoryURL: URL = LocalRenameJournalStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("AudioMator", isDirectory: true)
            .appendingPathComponent("RenameJournal", isDirectory: true)
    }

    func ensureDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw RenameJournalStoreError.directoryUnavailable(
                code: Int32((error as NSError).code)
            )
        }
    }

    func loadManifests() -> RenameJournalLoadResult {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return RenameJournalLoadResult(manifests: [], issues: [])
        }

        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).sorted()
        } catch {
            return RenameJournalLoadResult(
                manifests: [],
                issues: [RenameJournalLoadIssue(
                    manifestFileName: "RenameJournal",
                    category: .unreadable,
                    detailCode: "directory"
                )]
            )
        }

        var manifests: [RenameJournalManifest] = []
        var issues: [RenameJournalLoadIssue] = []
        var seenOperationIDs: Set<UUID> = []

        for name in names {
            if name == RenameJournalFormat.lockFileName { continue }

            if name.hasPrefix(RenameJournalFormat.manifestFilePrefix),
               name.hasSuffix(RenameJournalFormat.temporaryFileSuffix) {
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: .incompleteWrite,
                    detailCode: "temporary"
                ))
                continue
            }

            guard
                name.hasPrefix(RenameJournalFormat.manifestFilePrefix),
                name.hasSuffix(RenameJournalFormat.manifestFileSuffix)
            else { continue }

            let fileURL = directoryURL.appendingPathComponent(name, isDirectory: false)
            guard let data = try? Data(contentsOf: fileURL) else {
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: .unreadable,
                    detailCode: "read"
                ))
                continue
            }

            let manifest: RenameJournalManifest
            do {
                manifest = try JSONDecoder().decode(RenameJournalManifest.self, from: data)
            } catch {
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: .unreadable,
                    detailCode: "decode"
                ))
                continue
            }

            guard manifest.formatVersion == RenameJournalFormat.currentVersion else {
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: .unsupportedVersion,
                    detailCode: "version"
                ))
                continue
            }

            do {
                try manifest.validate()
            } catch let error as RenameJournalValidationError {
                let category: RenameJournalLoadIssueCategory
                switch error {
                case .unsupportedVersion:
                    category = .unsupportedVersion
                default:
                    category = .invalidManifest
                }
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: category,
                    detailCode: "validation"
                ))
                continue
            } catch {
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: .invalidManifest,
                    detailCode: "validation"
                ))
                continue
            }

            guard seenOperationIDs.insert(manifest.operationID).inserted else {
                issues.append(RenameJournalLoadIssue(
                    manifestFileName: name,
                    category: .duplicateOperationID,
                    detailCode: "duplicate"
                ))
                continue
            }

            manifests.append(manifest)
        }

        return RenameJournalLoadResult(manifests: manifests, issues: issues)
    }

    func tryAcquireLock() throws -> RenameJournalLock? {
        try ensureDirectory()

        let lockFileURL = directoryURL.appendingPathComponent(
            RenameJournalFormat.lockFileName,
            isDirectory: false
        )
        let descriptor = lockFileURL.path.withCString {
            open($0, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else {
            throw RenameJournalStoreError.lockUnavailable(code: errno)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw RenameJournalStoreError.lockUnavailable(code: code)
        }

        return RenameJournalLock(descriptor: descriptor)
    }

    func directoryBarrierSupport() -> RenameDirectoryBarrierSupport {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return .unsupported
        }
        let descriptor = directoryURL.path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return .unsupported }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            let code = errno
            return (code == EINVAL || code == ENOTSUP) ? .unsupported : .supported
        }
        return .supported
    }

    func writePrepared(_ manifest: RenameJournalManifest) throws {
        guard manifest.phase == .prepared else {
            throw RenameJournalStoreError.writeFailed(code: EINVAL)
        }
        try ensureDirectory()
        let data = try encode(manifest)
        try writeAtomically(data, manifest: manifest, replacingExistingManifest: false)
    }

    func markCommitted(_ manifest: RenameJournalManifest) throws {
        guard manifest.phase == .committed else {
            throw RenameJournalStoreError.writeFailed(code: EINVAL)
        }
        let finalURL = directoryURL.appendingPathComponent(manifest.fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: finalURL.path) else {
            throw RenameJournalStoreError.manifestMissing(operationID: manifest.operationID)
        }
        let data = try encode(manifest)
        try writeAtomically(data, manifest: manifest, replacingExistingManifest: true)
    }

    func removeManifest(operationID: UUID) throws {
        let finalURL = directoryURL.appendingPathComponent(
            RenameJournalFormat.manifestFileName(operationID: operationID),
            isDirectory: false
        )
        let result = finalURL.path.withCString { unlink($0) }
        guard result == 0 else {
            throw RenameJournalStoreError.removalFailed(code: errno)
        }
        try? flushDirectory()
    }

    private func encode(_ manifest: RenameJournalManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(manifest)
        } catch {
            throw RenameJournalStoreError.encodeFailed
        }
    }

    private func writeAtomically(
        _ data: Data,
        manifest: RenameJournalManifest,
        replacingExistingManifest: Bool
    ) throws {
        let temporaryURL = directoryURL.appendingPathComponent(
            RenameJournalFormat.temporaryFileName(operationID: manifest.operationID),
            isDirectory: false
        )
        let finalURL = directoryURL.appendingPathComponent(manifest.fileName, isDirectory: false)

        let descriptor = temporaryURL.path.withCString {
            open($0, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else {
            throw RenameJournalStoreError.writeFailed(code: errno)
        }

        do {
            try writeAll(data, to: descriptor)
            try flushFile(descriptor)
        } catch {
            close(descriptor)
            _ = temporaryURL.path.withCString { unlink($0) }
            throw error
        }
        close(descriptor)

        let installResult: Int32
        if replacingExistingManifest {
            installResult = temporaryURL.path.withCString { temporaryPath in
                finalURL.path.withCString { finalPath in
                    rename(temporaryPath, finalPath)
                }
            }
        } else {
            installResult = temporaryURL.path.withCString { temporaryPath in
                finalURL.path.withCString { finalPath in
                    renameatx_np(AT_FDCWD, temporaryPath, AT_FDCWD, finalPath, UInt32(RENAME_EXCL))
                }
            }
        }

        guard installResult == 0 else {
            let code = errno
            _ = temporaryURL.path.withCString { unlink($0) }
            if code == EEXIST {
                throw RenameJournalStoreError.duplicateOperation(operationID: manifest.operationID)
            }
            throw RenameJournalStoreError.writeFailed(code: code)
        }

        do {
            try flushDirectory()
        } catch {
            // The manifest is installed but its directory barrier was not proven.
            // Callers record an honest durability diagnostic; the record remains
            // usable for process-termination recovery.
            throw error
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw RenameJournalStoreError.writeFailed(code: errno)
                }
                offset += written
            }
        }
    }

    private func flushFile(_ descriptor: Int32) throws {
        // Prefer the strongest supported on-disk barrier; fall back to fsync when
        // the filesystem rejects F_FULLFSYNC.
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        if fsync(descriptor) == 0 { return }
        throw RenameJournalStoreError.syncFailed(code: errno)
    }

    private func flushDirectory() throws {
        let descriptor = directoryURL.path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw RenameJournalStoreError.syncFailed(code: errno)
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            let code = errno
            if code == EINVAL || code == ENOTSUP {
                // Reported through directoryBarrierSupport/diagnostics; not a
                // process-termination recovery failure.
                return
            }
            throw RenameJournalStoreError.syncFailed(code: code)
        }
    }
}
