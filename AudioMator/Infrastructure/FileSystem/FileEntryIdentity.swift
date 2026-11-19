import Darwin
import Foundation

/// Captures directory-entry identity without following a final symlink.
///
/// The filesystem platform calls stay in Infrastructure; Domain consumes the value
/// through `RenameEntryIdentity`.
nonisolated enum FileEntryIdentityCapture {
    nonisolated static func capture(at url: URL) throws -> RenameEntryIdentity {
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        guard result == 0 else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return identity(from: info)
    }

    /// Returns `nil` only when the entry does not exist. Other failures propagate
    /// so classification can distinguish "missing" from "directory unavailable".
    nonisolated static func captureIfPresent(at url: URL) throws -> RenameEntryIdentity? {
        var info = stat()
        let result = url.path.withCString { lstat($0, &info) }
        if result == 0 { return identity(from: info) }
        if errno == ENOENT || errno == ENOTDIR { return nil }
        throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }

    nonisolated static func identity(from info: stat) -> RenameEntryIdentity {
        let kind: FileEntryKind
        switch info.st_mode & S_IFMT {
        case S_IFREG: kind = .regular
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symlink
        default: kind = .other
        }

        return RenameEntryIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            kind: kind,
            size: UInt64(max(info.st_size, 0)),
            modificationDate: Date(timespec: info.st_mtimespec),
            creationDate: Date(timespec: info.st_birthtimespec)
        )
    }

    /// Exact `readlink` target for a symlink entry. Evidence only; callers never
    /// resolve it to choose a scope or a path.
    nonisolated static func linkTarget(at url: URL) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = url.path.withCString { readlink($0, &buffer, buffer.count - 1) }
        guard count > 0 else { return nil }
        buffer[Int(count)] = 0
        return String(cString: buffer)
    }

    /// Stable volume identity when the volume reports one. `nil` means the
    /// evidence cannot distinguish an entry after a remount.
    nonisolated static func volumeIdentifier(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]) else {
            return nil
        }
        return values.volumeUUIDString
    }
}

private extension Date {
    nonisolated init(timespec: timespec) {
        self.init(
            timeIntervalSince1970: TimeInterval(timespec.tv_sec)
                + TimeInterval(timespec.tv_nsec) / 1_000_000_000
        )
    }
}
