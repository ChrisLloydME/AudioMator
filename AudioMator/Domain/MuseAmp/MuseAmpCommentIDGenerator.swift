import Foundation

let museAmpSupportEnabledDefaultsKey = "museAmpSupportEnabled"

struct MuseAmpTrackIdentity: Hashable {
    var album: String
    var albumArtist: String
    var trackKey: String

    init(album: String, albumArtist: String, trackKey: String) {
        self.album = album
        self.albumArtist = albumArtist
        self.trackKey = trackKey
    }
}

struct MuseAmpCommentID: Equatable {
    var albumID: String
    var trackID: String
    var version: Int

    var commentText: String {
        MuseAmpCommentIDGenerator.commentText(albumID: albumID, trackID: trackID, version: version)
    }
}

enum MuseAmpCommentIDGenerator {
    static let currentVersion = 1

    static func commentText(albumID: String, trackID: String, version: Int = currentVersion) -> String {
        "{\"albumID\":\"\(albumID)\",\"trackID\":\"\(trackID)\",\"v\":\(version)}"
    }

    static func assignments(for tracks: [MuseAmpTrackIdentity]) -> [MuseAmpCommentID] {
        var albumIDsByKey: [AlbumKey: String] = [:]
        var usedIDs = Set<String>()

        return tracks.map { track in
            let albumKey = AlbumKey(album: track.album, albumArtist: track.albumArtist)
            let albumID = albumIDsByKey[albumKey] ?? {
                let id = uniqueNumericID(for: "album", key: albumKey.stableKey, usedIDs: &usedIDs)
                albumIDsByKey[albumKey] = id
                return id
            }()

            let trackID = uniqueNumericID(
                for: "track",
                key: track.stableTrackKey(albumKey: albumKey),
                usedIDs: &usedIDs
            )

            return MuseAmpCommentID(albumID: albumID, trackID: trackID, version: currentVersion)
        }
    }

    static func numericID(for namespace: String, key: String, salt: UInt64 = 0) -> String {
        var hasher = FNV1a64()
        hasher.append(namespace)
        hasher.append("\u{1F}")
        hasher.append(key)
        hasher.append("\u{1F}")
        hasher.append(String(salt))
        return String(hasher.finalize())
    }

    private static func uniqueNumericID(for namespace: String, key: String, usedIDs: inout Set<String>) -> String {
        var salt: UInt64 = 0

        while true {
            let id = numericID(for: namespace, key: key, salt: salt)
            if usedIDs.insert(id).inserted {
                return id
            }
            salt += 1
        }
    }
}

private struct AlbumKey: Hashable {
    var album: String
    var albumArtist: String

    var stableKey: String {
        "\(album)\u{1F}\(albumArtist)"
    }
}

private extension MuseAmpTrackIdentity {
    func stableTrackKey(albumKey: AlbumKey) -> String {
        "\(albumKey.stableKey)\u{1F}\(trackKey)"
    }
}

private struct FNV1a64 {
    private var hash: UInt64 = 14_695_981_039_346_656_037

    mutating func append(_ string: String) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
    }

    func finalize() -> UInt64 {
        hash == 0 ? 1 : hash
    }
}
