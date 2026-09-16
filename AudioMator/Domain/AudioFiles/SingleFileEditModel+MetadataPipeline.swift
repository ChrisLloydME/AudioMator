import Foundation
import TagLibAudioMetadata

extension MetadataEditPayload {
    init(_ edit: SingleFileEditModel) {
        var changedFields = Set(Self.textFieldMappings.map(\.key))
        if edit.year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            changedFields.remove(.date)
        }
        self.init(
            edit,
            changedFields: changedFields,
            contentAdvisoryChanged: true,
            trackNumberTextChanged: true,
            discNumberTextChanged: true
        )
    }

    init(_ edit: SingleFileEditModel, comparedTo file: AudioFile) {
        let baseline = SingleFileEditModel(from: file)
        var changedFields: Set<MetadataFieldKey> = []
        for mapping in Self.textFieldMappings where mapping.value(edit) != mapping.value(baseline) {
            changedFields.insert(mapping.key)
        }

        self.init(
            edit,
            changedFields: changedFields,
            contentAdvisoryChanged: edit.contentAdvisory != baseline.contentAdvisory,
            trackNumberTextChanged: edit.trackNumberText != baseline.trackNumberText ||
                edit.track != baseline.track || edit.trackTotal != baseline.trackTotal,
            discNumberTextChanged: edit.discNumberText != baseline.discNumberText ||
                edit.disc != baseline.disc || edit.discTotal != baseline.discTotal
        )
    }

    private init(
        _ edit: SingleFileEditModel,
        changedFields: Set<MetadataFieldKey>,
        contentAdvisoryChanged: Bool,
        trackNumberTextChanged: Bool,
        discNumberTextChanged: Bool
    ) {
        self.title = edit.title
        self.artist = edit.artist
        self.album = edit.album
        self.composer = edit.composer
        self.genre = edit.genre
        self.comment = edit.comment
        self.year = edit.year
        self.trackNumber = edit.track
        self.trackTotal = edit.trackTotal
        self.discNumber = edit.disc
        self.discTotal = edit.discTotal
        self.trackNumberText = edit.trackNumberText
        self.discNumberText = edit.discNumberText
        self.albumArtist = edit.albumArtist
        self.releaseDate = edit.releaseDate
        self.publisher = edit.publisher
        self.isrc = edit.isrc
        self.barcode = edit.barcode
        self.itunesAlbumID = edit.itunesAlbumID
        self.itunesArtistID = edit.itunesArtistID
        self.itunesCatalogID = edit.itunesCatalogID
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
        self.contentAdvisory = edit.contentAdvisory

        switch edit.artworkEditAction {
        case .unchanged:
            self.artwork = .unchanged
        case .replace(let pendingArtwork):
            self.artwork = .replace(data: pendingArtwork.data, mimeType: pendingArtwork.mimeType)
        case .remove:
            self.artwork = .remove
        }
        self.changedFields = changedFields
        self.contentAdvisoryChanged = contentAdvisoryChanged
        self.trackNumberTextChanged = trackNumberTextChanged
        self.discNumberTextChanged = discNumberTextChanged
    }

    private static let textFieldMappings: [(key: MetadataFieldKey, value: (SingleFileEditModel) -> String)] = [
        (.title, { $0.title }),
        (.artist, { $0.artist }),
        (.album, { $0.album }),
        (.composer, { $0.composer }),
        (.genre, { $0.genre }),
        (.comment, { $0.comment }),
        (.date, { $0.year }),
        (.albumArtist, { $0.albumArtist }),
        (.releaseDate, { $0.releaseDate }),
        (.publisher, { $0.publisher }),
        (.isrc, { $0.isrc }),
        (.barcode, { $0.barcode }),
        (.itunesAlbumID, { $0.itunesAlbumID }),
        (.itunesArtistID, { $0.itunesArtistID }),
        (.itunesCatalogID, { $0.itunesCatalogID }),
        (.musicBrainzAlbumID, { $0.musicBrainzAlbumID }),
        (.musicBrainzTrackID, { $0.musicBrainzTrackID }),
        (.musicBrainzReleaseGroupID, { $0.musicBrainzReleaseGroupID }),
        (.lyricist, { $0.lyricist }),
        (.remixer, { $0.remixer }),
        (.producer, { $0.producer }),
        (.engineer, { $0.engineer }),
        (.language, { $0.language }),
        (.mediaType, { $0.mediaType }),
        (.releaseType, { $0.releaseType }),
        (.catalogNumber, { $0.catalogNumber }),
        (.releaseCountry, { $0.releaseCountry }),
        (.copyright, { $0.copyright }),
    ]
}
