import Foundation
@testable import AudioMator

enum AudioFileTestFactory {
    static func fingerprint(for url: URL, fileSize: UInt64 = 1) -> AudioFileFingerprint {
        AudioFileFingerprint(
            normalizedPath: url.standardizedFileURL.resolvingSymlinksInPath().path,
            fileSize: fileSize,
            contentModificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSystemNumber: 1,
            fileNumber: UInt64(bitPattern: Int64(url.path.hashValue))
        )
    }

    static func make(
        id: UUID = UUID(),
        url: URL = URL(fileURLWithPath: "/tmp/01 - Untitled.mp3"),
        title: String = "",
        artist: String = "",
        album: String = "",
        composer: String = "",
        genre: String = "",
        comment: String = "",
        track: Int = 0,
        trackTotal: Int = 0,
        disc: Int = 0,
        discTotal: Int = 0,
        trackNumberText: String = "",
        discNumberText: String = "",
        year: String = "",
        albumArtist: String = "",
        releaseDate: String = "",
        contentAdvisory: ContentAdvisory? = nil,
        fileFingerprint: AudioFileFingerprint? = nil,
        includeDefaultFileFingerprint: Bool = true
    ) -> AudioFile {
        AudioFile(
            id: id,
            url: url,
            title: title,
            artist: artist,
            album: album,
            composer: composer,
            genre: genre,
            comment: comment,
            track: track,
            trackTotal: trackTotal,
            disc: disc,
            discTotal: discTotal,
            trackNumberText: trackNumberText,
            discNumberText: discNumberText,
            year: year,
            albumArtist: albumArtist,
            releaseDate: releaseDate,
            isrc: "",
            barcode: "",
            itunesAlbumID: "",
            itunesArtistID: "",
            itunesCatalogID: "",
            musicBrainzArtistID: "",
            musicBrainzAlbumID: "",
            musicBrainzTrackID: "",
            musicBrainzReleaseGroupID: "",
            publisher: "",
            copyright: "",
            credits: "",
            lyricist: "",
            remixer: "",
            producer: "",
            engineer: "",
            language: "",
            mediaType: "",
            releaseType: "",
            catalogNumber: "",
            releaseCountry: "",
            contentAdvisory: contentAdvisory,
            duration: 0,
            bitrate: 0,
            sampleRate: 0,
            channels: 0,
            format: "",
            artwork: nil,
            artworkFingerprint: nil,
            fileFingerprint: fileFingerprint ?? (includeDefaultFileFingerprint ? fingerprint(for: url) : nil)
        )
    }
}
