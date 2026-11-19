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
}

private extension Date {
    nonisolated init(timespec: timespec) {
        self.init(
            timeIntervalSince1970: TimeInterval(timespec.tv_sec)
                + TimeInterval(timespec.tv_nsec) / 1_000_000_000
        )
    }
}
