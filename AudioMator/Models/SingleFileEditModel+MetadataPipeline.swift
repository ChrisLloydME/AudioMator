import Foundation

extension MetadataEditPayload {
    init(_ edit: SingleFileEditModel) {
        self.title = edit.title
        self.artist = edit.artist
        self.album = edit.album
        self.composer = edit.composer
        self.genre = edit.genre
        self.comment = edit.comment
        self.year = edit.year
        self.trackNumberText = edit.trackNumberText
        self.discNumberText = edit.discNumberText
        self.albumArtist = edit.albumArtist
        self.releaseDate = edit.releaseDate
        self.publisher = edit.publisher
        self.isrc = edit.isrc
        self.barcode = edit.barcode
        self.musicBrainzAlbumID = edit.musicBrainzAlbumID
        self.musicBrainzTrackID = edit.musicBrainzTrackID
        self.musicBrainzReleaseGroupID = edit.musicBrainzReleaseGroupID
        self.lyricist = edit.lyricist
        self.remixer = edit.remixer
        self.producer = edit.producer
        self.engineer = edit.engineer
        self.language = edit.language
        self.mediaType = edit.mediaType
        self.releaseType = edit.releaseType
        self.catalogNumber = edit.catalogNumber
        self.releaseCountry = edit.releaseCountry
        self.copyright = edit.copyright
        self.isExplicit = edit.isExplicit

        switch edit.artworkEditAction {
        case .unchanged:
            self.artwork = .unchanged
        case .replace(let pendingArtwork):
            self.artwork = .replace(data: pendingArtwork.data, mimeType: pendingArtwork.mimeType)
        case .remove:
            self.artwork = .remove
        }
    }
}
