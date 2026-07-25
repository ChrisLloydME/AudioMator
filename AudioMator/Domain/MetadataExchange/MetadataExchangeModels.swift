import Foundation

enum MetadataConverterMode: String, CaseIterable, Identifiable {
    case metadataToFilename
    case filenameToMetadata
    case metadataToText
    case textToMetadata
    case metadataToCSV
    case csvToMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Metadata to Filename")
        case .filenameToMetadata:
            return L10n.string("Filename to Metadata")
        case .metadataToText:
            return L10n.string("Metadata to Text")
        case .textToMetadata:
            return L10n.string("Text to Metadata")
        case .metadataToCSV:
            return L10n.string("Metadata to CSV")
        case .csvToMetadata:
            return L10n.string("CSV to Metadata")
        }
    }

    var subtitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Build filenames from tags, keeping each file extension.")
        case .filenameToMetadata:
            return L10n.string("Parse the current filename stem into editable tags.")
        case .metadataToText:
            return L10n.string("Render one custom text record per selected file.")
        case .textToMetadata:
            return L10n.string("Parse one text record per line and write matched tag values.")
        case .metadataToCSV:
            return L10n.string("Export selected files as a column-based CSV.")
        case .csvToMetadata:
            return L10n.string("Import CSV columns into selected file metadata.")
        }
    }

    var symbolName: String {
        switch self {
        case .metadataToFilename:
            return "character.cursor.ibeam"
        case .filenameToMetadata:
            return "character.textbox.badge.sparkles"
        case .metadataToText:
            return "text.page"
        case .textToMetadata:
            return "long.text.page.and.pencil"
        case .metadataToCSV:
            return "tablecells"
        case .csvToMetadata:
            return "tablecells.badge.ellipsis"
        }
    }

    var actionTitle: String {
        switch self {
        case .metadataToFilename:
            return L10n.string("Rename")
        case .filenameToMetadata, .textToMetadata, .csvToMetadata:
            return L10n.string("Write Metadata")
        case .metadataToText, .metadataToCSV:
            return L10n.string("Export")
        }
    }
}
enum MetadataExchangeField: CaseIterable, Hashable, Identifiable {
    case fileName
    case baseName
    case path
    case relativePath
    case index
    case title
    case artist
    case album
    case albumArtist
    case composer
    case lyricist
    case producer
    case engineer
    case remixer
    case genre
    case year
    case trackNumber
    case trackTotal
    case discNumber
    case discTotal
    case comment
    case releaseDate
    case publisher
    case copyright
    case isrc
    case barcode
    case language
    case mediaType
    case releaseType
    case catalogNumber
    case releaseCountry
    case itunesAlbumID
    case itunesArtistID
    case itunesCatalogID
    case musicBrainzAlbumID
    case musicBrainzTrackID
    case musicBrainzReleaseGroupID
    case contentAdvisory
    case ignore

    var id: String { placeholderName }

    var displayName: String {
        switch self {
        case .fileName:
            return L10n.string("File Name")
        case .baseName:
            return L10n.string("Base Name")
        case .path:
            return L10n.string("Path")
        case .relativePath:
            return L10n.string("Relative Path")
        case .index:
            return L10n.string("Index")
        case .title:
            return L10n.string("Title")
        case .artist:
            return L10n.string("Artist")
        case .album:
            return L10n.string("Album")
        case .albumArtist:
            return L10n.string("Album Artist")
        case .composer:
            return L10n.string("Composer")
        case .lyricist:
            return L10n.string("Lyricist")
        case .producer:
            return L10n.string("Producer")
        case .engineer:
            return L10n.string("Engineer")
        case .remixer:
            return L10n.string("Remixer")
        case .genre:
            return L10n.string("Genre")
        case .year:
            return L10n.string("Year")
        case .trackNumber:
            return L10n.string("Track Number")
        case .trackTotal:
            return L10n.string("Total Tracks")
        case .discNumber:
            return L10n.string("Disc Number")
        case .discTotal:
            return L10n.string("Total Discs")
        case .comment:
            return L10n.string("Comment")
        case .releaseDate:
            return L10n.string("Release Date")
        case .publisher:
            return L10n.string("Publisher")
        case .copyright:
            return L10n.string("Copyright")
        case .isrc:
            return L10n.string("ISRC")
        case .barcode:
            return L10n.string("Barcode")
        case .language:
            return L10n.string("Language")
        case .mediaType:
            return L10n.string("Media Type")
        case .releaseType:
            return L10n.string("Release Type")
        case .catalogNumber:
            return L10n.string("Catalog Number")
        case .releaseCountry:
            return L10n.string("Release Country")
        case .itunesAlbumID:
            return L10n.string("iTunes Album ID")
        case .itunesArtistID:
            return L10n.string("iTunes Artist ID")
        case .itunesCatalogID:
            return L10n.string("iTunes Catalog ID")
        case .musicBrainzAlbumID:
            return L10n.string("MusicBrainz Release ID")
        case .musicBrainzTrackID:
            return L10n.string("MusicBrainz Track ID")
        case .musicBrainzReleaseGroupID:
            return L10n.string("MusicBrainz Release Group ID")
        case .contentAdvisory:
            return L10n.string("Content Advisory")
        case .ignore:
            return L10n.string("Ignore")
        }
    }

    var placeholderName: String {
        switch self {
        case .fileName:
            return "fileName"
        case .baseName:
            return "baseName"
        case .path:
            return "path"
        case .relativePath:
            return "relativePath"
        case .index:
            return "index"
        case .title:
            return "title"
        case .artist:
            return "artist"
        case .album:
            return "album"
        case .albumArtist:
            return "albumArtist"
        case .composer:
            return "composer"
        case .lyricist:
            return "lyricist"
        case .producer:
            return "producer"
        case .engineer:
            return "engineer"
        case .remixer:
            return "remixer"
        case .genre:
            return "genre"
        case .year:
            return "year"
        case .trackNumber:
            return "trackNumber"
        case .trackTotal:
            return "trackTotal"
        case .discNumber:
            return "discNumber"
        case .discTotal:
            return "discTotal"
        case .comment:
            return "comment"
        case .releaseDate:
            return "releaseDate"
        case .publisher:
            return "publisher"
        case .copyright:
            return "copyright"
        case .isrc:
            return "isrc"
        case .barcode:
            return "barcode"
        case .language:
            return "language"
        case .mediaType:
            return "mediaType"
        case .releaseType:
            return "releaseType"
        case .catalogNumber:
            return "catalogNumber"
        case .releaseCountry:
            return "releaseCountry"
        case .itunesAlbumID:
            return "itunesAlbumID"
        case .itunesArtistID:
            return "itunesArtistID"
        case .itunesCatalogID:
            return "itunesCatalogID"
        case .musicBrainzAlbumID:
            return "musicBrainzAlbumID"
        case .musicBrainzTrackID:
            return "musicBrainzTrackID"
        case .musicBrainzReleaseGroupID:
            return "musicBrainzReleaseGroupID"
        case .contentAdvisory:
            return "contentAdvisory"
        case .ignore:
            return "_ignore"
        }
    }

    var token: String {
        "{{\(placeholderName)}}"
    }

    var isWritableMetadataField: Bool {
        switch self {
        case .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
                .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal,
                .discNumber, .discTotal, .comment, .releaseDate, .publisher, .copyright,
                .isrc, .barcode, .language, .mediaType, .releaseType, .catalogNumber,
                .releaseCountry, .itunesAlbumID, .itunesArtistID, .itunesCatalogID,
                .musicBrainzAlbumID, .musicBrainzTrackID, .musicBrainzReleaseGroupID,
                .contentAdvisory:
            return true
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            return false
        }
    }

    var isLocatorField: Bool {
        switch self {
        case .fileName, .baseName, .path, .relativePath, .index:
            return true
        case .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
                .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal,
                .discNumber, .discTotal, .comment, .releaseDate, .publisher, .copyright,
                .isrc, .barcode, .language, .mediaType, .releaseType, .catalogNumber,
                .releaseCountry, .itunesAlbumID, .itunesArtistID, .itunesCatalogID,
                .musicBrainzAlbumID, .musicBrainzTrackID, .musicBrainzReleaseGroupID,
                .contentAdvisory, .ignore:
            return false
        }
    }

    var writeOrderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Int.max
    }

    var propertyMapKey: String? {
        switch self {
        case .title:
            return "TITLE"
        case .artist:
            return "ARTIST"
        case .album:
            return "ALBUM"
        case .albumArtist:
            return "ALBUMARTIST"
        case .composer:
            return "COMPOSER"
        case .lyricist:
            return "LYRICIST"
        case .producer:
            return "PRODUCER"
        case .engineer:
            return "ENGINEER"
        case .remixer:
            return "REMIXER"
        case .genre:
            return "GENRE"
        case .year:
            return "DATE"
        case .trackNumber:
            return "TRACKNUMBER"
        case .trackTotal:
            return "TRACKTOTAL"
        case .discNumber:
            return "DISCNUMBER"
        case .discTotal:
            return "DISCTOTAL"
        case .comment:
            return "COMMENT"
        case .releaseDate:
            return "RELEASEDATE"
        case .publisher:
            return "PUBLISHER"
        case .copyright:
            return "COPYRIGHT"
        case .isrc:
            return "ISRC"
        case .barcode:
            return "BARCODE"
        case .language:
            return "LANGUAGE"
        case .mediaType:
            return "MEDIA"
        case .releaseType:
            return "RELEASETYPE"
        case .catalogNumber:
            return "CATALOGNUMBER"
        case .releaseCountry:
            return "RELEASECOUNTRY"
        case .itunesAlbumID:
            return "ITUNESALBUMID"
        case .itunesArtistID:
            return "ITUNESARTISTID"
        case .itunesCatalogID:
            return "ITUNESCATALOGID"
        case .musicBrainzAlbumID:
            return "MUSICBRAINZ_ALBUMID"
        case .musicBrainzTrackID:
            return "MUSICBRAINZ_TRACKID"
        case .musicBrainzReleaseGroupID:
            return "MUSICBRAINZ_RELEASEGROUPID"
        case .contentAdvisory:
            return "ITUNESADVISORY"
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            return nil
        }
    }

    static let exportPalette: [Self] = [
        .fileName, .baseName, .path, .relativePath, .index,
        .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
        .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal, .discNumber,
        .discTotal, .comment, .releaseDate, .publisher, .copyright, .isrc, .barcode,
        .language, .mediaType, .releaseType, .catalogNumber, .releaseCountry,
        .itunesAlbumID, .itunesArtistID, .itunesCatalogID, .musicBrainzAlbumID,
        .musicBrainzTrackID, .musicBrainzReleaseGroupID, .contentAdvisory
    ]

    static let importPalette: [Self] = [
        .fileName, .baseName, .path, .relativePath, .index,
        .title, .artist, .album, .albumArtist, .composer, .lyricist, .producer,
        .engineer, .remixer, .genre, .year, .trackNumber, .trackTotal, .discNumber,
        .discTotal, .comment, .releaseDate, .publisher, .copyright, .isrc, .barcode,
        .language, .mediaType, .releaseType, .catalogNumber, .releaseCountry,
        .itunesAlbumID, .itunesArtistID, .itunesCatalogID, .musicBrainzAlbumID,
        .musicBrainzTrackID, .musicBrainzReleaseGroupID, .contentAdvisory, .ignore
    ]

    static func field(forPlaceholderName placeholderName: String) -> Self? {
        switch placeholderName {
        case "totalTracks", "trackCount":
            return .trackTotal
        case "totalDiscs", "discCount":
            return .discTotal
        default:
            return allCases.first { $0.placeholderName == placeholderName }
        }
    }

    static func field(forExactToken token: String) -> Self? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}"), trimmed.count >= 4 else { return nil }
        return field(forPlaceholderName: String(trimmed.dropFirst(2).dropLast(2)))
    }

    func value(from file: AudioFile, index: Int, relativeBasePath: String?) -> String {
        switch self {
        case .fileName:
            return file.url.lastPathComponent
        case .baseName:
            return file.url.deletingPathExtension().lastPathComponent
        case .path:
            return file.url.path
        case .relativePath:
            guard
                let relativeBasePath,
                let relativePath = makeRelativePath(for: file.url, basePath: relativeBasePath)
            else {
                return file.url.lastPathComponent
            }
            return relativePath
        case .index:
            return "\(index + 1)"
        case .title:
            return file.title
        case .artist:
            return file.artist
        case .album:
            return file.album
        case .albumArtist:
            return file.albumArtist
        case .composer:
            return file.composer
        case .lyricist:
            return file.lyricist
        case .producer:
            return file.producer
        case .engineer:
            return file.engineer
        case .remixer:
            return file.remixer
        case .genre:
            return file.genre
        case .year:
            return file.year
        case .trackNumber:
            return AudioTagNumberPair(
                rawText: file.trackNumberText,
                number: file.track,
                total: file.trackTotal
            ).displayedNumberText
        case .trackTotal:
            return AudioTagNumberPair(
                rawText: file.trackNumberText,
                number: file.track,
                total: file.trackTotal
            ).displayedTotalText
        case .discNumber:
            return AudioTagNumberPair(
                rawText: file.discNumberText,
                number: file.disc,
                total: file.discTotal
            ).displayedNumberText
        case .discTotal:
            return AudioTagNumberPair(
                rawText: file.discNumberText,
                number: file.disc,
                total: file.discTotal
            ).displayedTotalText
        case .comment:
            return file.comment
        case .releaseDate:
            return file.releaseDate
        case .publisher:
            return file.publisher
        case .copyright:
            return file.copyright
        case .isrc:
            return file.isrc
        case .barcode:
            return file.barcode
        case .language:
            return file.language
        case .mediaType:
            return file.mediaType
        case .releaseType:
            return file.releaseType
        case .catalogNumber:
            return file.catalogNumber
        case .releaseCountry:
            return file.releaseCountry
        case .itunesAlbumID:
            return file.itunesAlbumID
        case .itunesArtistID:
            return file.itunesArtistID
        case .itunesCatalogID:
            return file.itunesCatalogID
        case .musicBrainzAlbumID:
            return file.musicBrainzAlbumID
        case .musicBrainzTrackID:
            return file.musicBrainzTrackID
        case .musicBrainzReleaseGroupID:
            return file.musicBrainzReleaseGroupID
        case .contentAdvisory:
            return file.contentAdvisory.map { String($0.rawValue) } ?? ""
        case .ignore:
            return ""
        }
    }

    func applyImportedValue(_ value: String, to edit: inout SingleFileEditModel) {
        switch self {
        case .title:
            edit.title = value
        case .artist:
            edit.artist = value
        case .album:
            edit.album = value
        case .albumArtist:
            edit.albumArtist = value
        case .composer:
            edit.composer = value
        case .lyricist:
            edit.lyricist = value
        case .producer:
            edit.producer = value
        case .engineer:
            edit.engineer = value
        case .remixer:
            edit.remixer = value
        case .genre:
            edit.genre = value
        case .year:
            edit.year = value
        case .trackNumber:
            edit.setTrackNumberText(value)
        case .trackTotal:
            edit.setTrackTotalFieldText(value)
        case .discNumber:
            edit.setDiscNumberText(value)
        case .discTotal:
            edit.setDiscTotalFieldText(value)
        case .comment:
            edit.comment = value
        case .releaseDate:
            edit.releaseDate = value
        case .publisher:
            edit.publisher = value
        case .copyright:
            edit.copyright = value
        case .isrc:
            edit.isrc = value
        case .barcode:
            edit.barcode = value
        case .language:
            edit.language = value
        case .mediaType:
            edit.mediaType = value
        case .releaseType:
            edit.releaseType = value
        case .catalogNumber:
            edit.catalogNumber = value
        case .releaseCountry:
            edit.releaseCountry = value
        case .itunesAlbumID:
            edit.itunesAlbumID = value
        case .itunesArtistID:
            edit.itunesArtistID = value
        case .itunesCatalogID:
            edit.itunesCatalogID = value
        case .musicBrainzAlbumID:
            edit.musicBrainzAlbumID = value
        case .musicBrainzTrackID:
            edit.musicBrainzTrackID = value
        case .musicBrainzReleaseGroupID:
            edit.musicBrainzReleaseGroupID = value
        case .contentAdvisory:
            edit.contentAdvisory = ContentAdvisory.fromDisplayName(value)
        case .fileName, .baseName, .path, .relativePath, .index, .ignore:
            break
        }
    }

    func canonicalImportedValue(_ value: String) -> String {
        guard self == .contentAdvisory, !value.isEmpty else { return value }
        return ContentAdvisory.fromDisplayName(value).map { String($0.rawValue) } ?? value
    }

    func importedValueValidationMessage(_ value: String) -> String? {
        if value.unicodeScalars.contains(where: { $0.value == 0 }) {
            return "\(displayName) contains a null character, which cannot be written safely."
        }

        guard !value.isEmpty else { return nil }

        switch self {
        case .trackNumber, .discNumber:
            let components = value.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count <= 2,
                  components.allSatisfy({ component in
                      let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                      return !trimmed.isEmpty && Int(trimmed).map { $0 >= 0 } == true
                  })
            else {
                return "\(displayName) must be a non-negative integer, optionally followed by / and a total."
            }
        case .trackTotal, .discTotal:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Int(trimmed).map({ $0 >= 0 }) == true else {
                return "\(displayName) must be a non-negative integer."
            }
        case .contentAdvisory:
            guard ContentAdvisory.fromDisplayName(value) != nil else {
                return "Content Advisory must be Explicit, Clean, Not Explicit, Yes, No, True, False, 1, 2, or 0."
            }
        case .fileName, .baseName, .path, .relativePath, .index, .title, .artist,
                .album, .albumArtist, .composer, .lyricist, .producer, .engineer,
                .remixer, .genre, .year, .comment, .releaseDate, .publisher,
                .copyright, .isrc, .barcode, .language, .mediaType, .releaseType,
                .catalogNumber, .releaseCountry, .itunesAlbumID, .itunesArtistID,
                .itunesCatalogID, .musicBrainzAlbumID, .musicBrainzTrackID,
                .musicBrainzReleaseGroupID, .ignore:
            break
        }

        return nil
    }

    fileprivate func makeRelativePath(for url: URL, basePath: String) -> String? {
        let filePath = url.standardizedFileURL.path
        let normalizedBasePath = URL(fileURLWithPath: basePath).standardizedFileURL.path

        if filePath == normalizedBasePath {
            return url.lastPathComponent
        }

        let basePrefix = normalizedBasePath.hasSuffix("/") ? normalizedBasePath : normalizedBasePath + "/"
        guard filePath.hasPrefix(basePrefix) else { return nil }
        return String(filePath.dropFirst(basePrefix.count))
    }
}
