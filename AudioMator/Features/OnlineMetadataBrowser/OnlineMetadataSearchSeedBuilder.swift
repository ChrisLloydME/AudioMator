import Foundation

/// Builds the MusicBrainz search seed from the current selection without contacting a
/// provider. Shared by the main-window routing controller and the window session's
/// local-seed fallback so both derive identical query fields.
enum OnlineMetadataSearchSeedBuilder {
    static func musicBrainzSeed(from files: [AudioFile]) -> MusicBrainzSearchSeed? {
        let fileInputs = files.map { MusicBrainzFilenameFallbackResolver.makeSearchInput(for: $0) }
        guard let selectedFile = files.first, let selectedInput = fileInputs.first else { return nil }

        return MusicBrainzSearchSeed(
            mode: .file,
            title: selectedInput.title,
            artist: selectedInput.artist,
            albumArtist: selectedInput.albumArtist,
            album: selectedInput.album,
            trackNumber: selectedInput.trackNumber,
            trackTotal: selectedFile.trackTotal,
            durationMilliseconds: AudioNumericConversion.positiveDurationMilliseconds(selectedFile.duration),
            releaseDate: selectedInput.releaseDate,
            isrc: selectedFile.isrc,
            barcode: selectedFile.barcode,
            musicBrainzAlbumID: selectedFile.musicBrainzAlbumID,
            musicBrainzTrackID: selectedFile.musicBrainzTrackID,
            fileInputs: fileInputs,
            link: "",
            sourceDescription: files.count == 1
                ? "From the selected file metadata, filename, and path."
                : "From \(files.count) selected files, with filename and path fallback."
        )
    }
}
