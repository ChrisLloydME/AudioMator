import Darwin
import Foundation

/// Identity of one open directory used for exclusive same-directory renames.
nonisolated struct RenameDirectoryIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let volumeIdentifier: String?
}

nonisolated enum RenameFileSystemError: Error, Equatable, Sendable {
    case sourceMissing
    case destinationOccupied
    case exclusiveRenameUnsupported
    case directorySyncUnsupported
    case entryIdentityUnavailable
    case io(code: Int32)
}

/// A held directory descriptor.
///
/// The descriptor is opened once, verified against the authorized lexical
/// directory path, and used for every name operation of one service call. It is
/// released when the handle is deallocated at the end of that call.
nonisolated final class RenameDirectoryHandle: Sendable {
    let url: URL
    let identity: RenameDirectoryIdentity
    let descriptor: Int32

    init(url: URL, identity: RenameDirectoryIdentity, descriptor: Int32) {
        self.url = url
        self.identity = identity
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}

/// Exclusive same-directory filesystem seam for the rename transaction service.
///
/// Platform calls (`renameatx_np`, `fstatat`, `readlink`, `fsync`) stay in the
/// local implementation so tests can inject faults and unsupported-volume
/// behaviour.
nonisolated protocol RenameFileSystem: Sendable {
    nonisolated func fileExists(at url: URL) -> Bool
    nonisolated func fingerprint(at url: URL) throws -> AudioFileFingerprint
    nonisolated func entryIdentity(at url: URL) throws -> RenameEntryIdentity
    nonisolated func entryIdentityIfPresent(at url: URL) throws -> RenameEntryIdentity?
    nonisolated func linkTarget(at url: URL) -> String?
    nonisolated func volumeIdentifier(forDirectoryAt url: URL) -> String?
    nonisolated func volumeSupportsExclusiveRename(forDirectoryAt url: URL) throws -> Bool
    nonisolated func openDirectory(at url: URL) throws -> RenameDirectoryHandle
    nonisolated func directoryIdentity(_ handle: RenameDirectoryHandle) throws -> RenameDirectoryIdentity
    nonisolated func authorizedPathStillIdentifiesDirectory(_ handle: RenameDirectoryHandle) -> Bool
    nonisolated func entryIdentity(named name: String, in handle: RenameDirectoryHandle) throws -> RenameEntryIdentity?
    nonisolated func actualEntryName(inDirectoryAt url: URL, matching name: String) throws -> String?
    nonisolated func exclusiveMove(named sourceName: String, to destinationName: String, in handle: RenameDirectoryHandle) throws
    nonisolated func syncDirectory(_ handle: RenameDirectoryHandle) throws
}

nonisolated struct LocalRenameFileSystem: RenameFileSystem {
    nonisolated init() {}

    nonisolated func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated func fingerprint(at url: URL) throws -> AudioFileFingerprint {
        try AudioFileFingerprint.capture(at: url)
    }

    nonisolated func entryIdentity(at url: URL) throws -> RenameEntryIdentity {
        try FileEntryIdentityCapture.capture(at: url)
    }

    nonisolated func entryIdentityIfPresent(at url: URL) throws -> RenameEntryIdentity? {
        try FileEntryIdentityCapture.captureIfPresent(at: url)
    }

    nonisolated func linkTarget(at url: URL) -> String? {
        FileEntryIdentityCapture.linkTarget(at: url)
    }

    nonisolated func volumeIdentifier(forDirectoryAt url: URL) -> String? {
        FileEntryIdentityCapture.volumeIdentifier(at: url)
    }

    nonisolated func volumeSupportsExclusiveRename(forDirectoryAt url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.volumeSupportsExclusiveRenamingKey])
        return values.volumeSupportsExclusiveRenaming == true
    }

    nonisolated func openDirectory(at url: URL) throws -> RenameDirectoryHandle {
        let descriptor = url.path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw RenameFileSystemError.io(code: errno)
        }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let code = errno
            close(descriptor)
            throw RenameFileSystemError.io(code: code)
        }
        let identity = RenameDirectoryIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            volumeIdentifier: FileEntryIdentityCapture.volumeIdentifier(at: url)
        )
        return RenameDirectoryHandle(url: url, identity: identity, descriptor: descriptor)
    }

    nonisolated func directoryIdentity(_ handle: RenameDirectoryHandle) throws -> RenameDirectoryIdentity {
        var info = stat()
        guard fstat(handle.descriptor, &info) == 0 else {
            throw RenameFileSystemError.io(code: errno)
        }
        return RenameDirectoryIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            volumeIdentifier: handle.identity.volumeIdentifier
        )
    }

    nonisolated func authorizedPathStillIdentifiesDirectory(_ handle: RenameDirectoryHandle) -> Bool {
        var info = stat()
        let result = handle.url.path.withCString { stat($0, &info) }
        guard result == 0 else { return false }
        return UInt64(info.st_dev) == handle.identity.device
            && UInt64(info.st_ino) == handle.identity.inode
    }

    nonisolated func entryIdentity(named name: String, in handle: RenameDirectoryHandle) throws -> RenameEntryIdentity? {
        var info = stat()
        let result = name.withCString {
            fstatat(handle.descriptor, $0, &info, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return FileEntryIdentityCapture.identity(from: info) }
        if errno == ENOENT || errno == ENOTDIR { return nil }
        throw RenameFileSystemError.io(code: errno)
    }

    nonisolated func actualEntryName(inDirectoryAt url: URL, matching name: String) throws -> String? {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        } catch {
            throw RenameFileSystemError.io(code: (error as NSError).code == NSFileReadNoSuchFileError ? ENOENT : EIO)
        }
        if names.contains(name) { return name }
        for candidate in names where candidate.compare(name, options: .caseInsensitive) == .orderedSame {
            return candidate
        }
        return nil
    }

    nonisolated func exclusiveMove(
        named sourceName: String,
        to destinationName: String,
        in handle: RenameDirectoryHandle
    ) throws {
        let result = sourceName.withCString { source in
            destinationName.withCString { destination in
                renameatx_np(handle.descriptor, source, handle.descriptor, destination, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            switch errno {
            case EEXIST:
                throw RenameFileSystemError.destinationOccupied
            case ENOENT:
                throw RenameFileSystemError.sourceMissing
            case EINVAL, ENOTSUP:
                throw RenameFileSystemError.exclusiveRenameUnsupported
            default:
                throw RenameFileSystemError.io(code: errno)
            }
        }
    }

    nonisolated func syncDirectory(_ handle: RenameDirectoryHandle) throws {
        guard fsync(handle.descriptor) == 0 else {
            let code = errno
            if code == EINVAL || code == ENOTSUP {
                throw RenameFileSystemError.directorySyncUnsupported
            }
            throw RenameFileSystemError.io(code: code)
        }
    }
}
