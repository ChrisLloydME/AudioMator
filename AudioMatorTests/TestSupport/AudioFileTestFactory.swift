import Foundation
import TagLibAudioMetadata
@testable import AudioMator

private final class AudioFileTestFactoryBundleAnchor {}

enum AudioFileTestFactory {
    /// A real fixture snapshot supplies a genuine opaque `MetadataFileVersion`
    /// and conflict baseline for deliberately manufactured test observations.
    /// Production code never reads a version from metadata; tests that need a
    /// versioned target must use a real token.
    private static let fixtureSnapshot: MetadataSnapshot? = {
        let bundle = Bundle(for: AudioFileTestFactoryBundleAnchor.self)
        let url = bundle.url(forResource: "testAudioFile.flac", withExtension: nil,
                             subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil)
        guard let url else { return nil }
        return try? TagLibMetadataManager.readSnapshot(from: url, includingAudioContent: true)
    }()

    static var fixtureFileVersion: MetadataFileVersion? {
        fixtureSnapshot?.fileVersion
    }

    static var fixtureConflictBaseline: MetadataConflictBaseline? {
        fixtureSnapshot.map(MetadataConflictBaseline.init)
    }

    static func fingerprint(for url: URL, fileSize: UInt64 = 1) -> AudioFileFingerprint {
        AudioFileFingerprint(
            normalizedPath: url.standardizedFileURL.resolvingSymlinksInPath().path,
            fileSize: fileSize,
            contentModificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSystemNumber: 1,
            fileNumber: UInt64(bitPattern: Int64(url.path.hashValue))
        )
    }

    /// A display-only model: no write authority.
    static func makeDisplayOnly(
        id: UUID = UUID(),
        url: URL = URL(fileURLWithPath: "/tmp/01 - Untitled.mp3"),
        title: String = "",
        fileFingerprint: AudioFileFingerprint? = nil
    ) -> AudioFile {
        make(id: id, url: url, title: title, fileFingerprint: fileFingerprint,
             includeDefaultFileFingerprint: false)
    }

    /// A deliberately manufactured coherent observation. Only for tests; the
    /// version must come from a real fixture or real file because the package
    /// token is opaque.
    static func makeObserved(
        id: UUID = UUID(),
        url: URL,
        title: String = "",
        artist: String = "",
        album: String = "",
        fileFingerprint: AudioFileFingerprint,
        metadataFileVersion: MetadataFileVersion,
        metadataConflictBaseline: MetadataConflictBaseline? = nil
    ) -> AudioFile {
        let baseline = metadataConflictBaseline ?? fixtureConflictBaseline
        let observation: AudioFile.Observation? = baseline.map {
            AudioFile.Observation(
                fileID: id,
                url: url,
                fingerprint: fileFingerprint,
                version: metadataFileVersion,
                conflictBaseline: $0
            )
        }
        return makeWithObservation(
            id: id, url: url, title: title, artist: artist, album: album,
            observation: observation
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
        date: String = "",
        albumArtist: String = "",
        releaseDate: String = "",
        originalReleaseDate: String = "",
        contentAdvisory: ContentAdvisory? = nil,
        duration: Double = 0,
        artworkData: Data? = nil,
        fileFingerprint: AudioFileFingerprint? = nil,
        metadataFileVersion: MetadataFileVersion? = nil,
        includeDefaultFileFingerprint: Bool = true
    ) -> AudioFile {
        let resolvedFingerprint = fileFingerprint
            ?? (includeDefaultFileFingerprint ? fingerprint(for: url) : nil)
        let observation: AudioFile.Observation?
        if includeDefaultFileFingerprint,
           let resolvedFingerprint,
           let snapshot = fixtureSnapshot,
           let version = metadataFileVersion ?? snapshot.fileVersion {
            observation = AudioFile.Observation(
                fileID: id,
                url: url,
                fingerprint: resolvedFingerprint,
                version: version,
                conflictBaseline: MetadataConflictBaseline(snapshot)
            )
        } else {
            observation = nil
        }
        return makeWithObservation(
            id: id, url: url, title: title, artist: artist, album: album,
            composer: composer, genre: genre, comment: comment, track: track,
            trackTotal: trackTotal, disc: disc, discTotal: discTotal,
            trackNumberText: trackNumberText, discNumberText: discNumberText,
            year: year, date: date, albumArtist: albumArtist,
            releaseDate: releaseDate, originalReleaseDate: originalReleaseDate,
            contentAdvisory: contentAdvisory, duration: duration,
            artworkData: artworkData, observation: observation
        )
    }

    private static func makeWithObservation(
        id: UUID,
        url: URL,
        title: String,
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
        date: String = "",
        albumArtist: String = "",
        releaseDate: String = "",
        originalReleaseDate: String = "",
        contentAdvisory: ContentAdvisory? = nil,
        duration: Double = 0,
        artworkData: Data? = nil,
        observation: AudioFile.Observation?
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
            duration: duration,
            bitrate: 0,
            sampleRate: 0,
            channels: 0,
            format: "",
            artworkData: artworkData,
            date: date,
            originalReleaseDate: originalReleaseDate,
            observation: observation
        )
    }
}
