import Foundation

struct PendingArtwork {
    var image: PlatformImage
    var data: Data
    var mimeType: String
}

enum ArtworkEditAction {
    case unchanged
    case replace(PendingArtwork)
    case remove
}

enum ContentAdvisory: Int, CaseIterable, Identifiable, Sendable {
    case notExplicit = 0
    case explicit = 1
    case clean = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .notExplicit:
            return L10n.string("Not Explicit")
        case .explicit:
            return L10n.string("Explicit")
        case .clean:
            return L10n.string("Clean")
        }
    }

    var currentValueDescription: String {
        switch self {
        case .notExplicit:
            return L10n.string("Current value: Not Explicit")
        case .explicit:
            return L10n.string("Current value: Explicit")
        case .clean:
            return L10n.string("Current value: Clean")
        }
    }

    nonisolated var isExplicit: Bool { self == .explicit }

    static var inspectorSelectionOrder: [ContentAdvisory] { [.explicit, .clean, .notExplicit] }

    static func fromDisplayName(_ value: String) -> ContentAdvisory? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "explicit", "yes", "true", "1":
            return .explicit
        case "clean", "cleaned", "2":
            return .clean
        case "not explicit", "notexplicit", "no", "false", "0":
            return .notExplicit
        default:
            return nil
        }
    }

    static func fromITunesExplicitness(_ explicitness: String) -> ContentAdvisory? {
        let normalized = explicitness.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "explicit":
            return .explicit
        case "clean", "cleaned":
            return .clean
        case "notexplicit", "not explicit":
            return .notExplicit
        default:
            return nil
        }
    }
}

enum ExplicitInspectorSelection: Hashable, Identifiable {
    case unset
    case advisory(ContentAdvisory)

    init(contentAdvisory: ContentAdvisory?) {
        if let contentAdvisory {
            self = .advisory(contentAdvisory)
        } else {
            self = .unset
        }
    }

    var id: String {
        switch self {
        case .unset:
            return "unset"
        case .advisory(let advisory):
            return "advisory-\(advisory.rawValue)"
        }
    }

    var contentAdvisory: ContentAdvisory? {
        switch self {
        case .unset:
            return nil
        case .advisory(let advisory):
            return advisory
        }
    }

    var displayName: String {
        switch self {
        case .unset:
            return L10n.string("Unset")
        case .advisory(let advisory):
            return advisory.displayName
        }
    }

    static var inspectorSelectionOrder: [ExplicitInspectorSelection] {
        [.unset] + ContentAdvisory.inspectorSelectionOrder.map(ExplicitInspectorSelection.advisory)
    }
}

struct SingleFileEditModel {
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var comment: String
    var track: Int
    var trackTotal: Int
    var disc: Int
    var discTotal: Int
    var year: String
    var trackNumberText: String   // e.g. "1" / "01" / "01/10" (TRCK)
    var discNumberText: String    // e.g. "1" / "1/2" (TPOS)
    var albumArtist: String
    var releaseDate: String
    var publisher: String
    var isrc: String
    var barcode: String
    var itunesAlbumID: String
    var itunesArtistID: String
    var itunesCatalogID: String
    var musicBrainzAlbumID: String
    var musicBrainzTrackID: String
    var musicBrainzReleaseGroupID: String
    var lyricist: String
    var remixer: String
    var producer: String
    var engineer: String
    var language: String
    var mediaType: String
    var releaseType: String
    var catalogNumber: String
    var releaseCountry: String
    var copyright: String
    var contentAdvisory: ContentAdvisory?
    var artworkEditAction: ArtworkEditAction

    var isExplicit: Bool { contentAdvisory?.isExplicit ?? false }

    init(
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
        year: String = "",
        trackNumberText: String = "",
        discNumberText: String = "",
        albumArtist: String = "",
        releaseDate: String = "",
        publisher: String = "",
        isrc: String = "",
        barcode: String = "",
        itunesAlbumID: String = "",
        itunesArtistID: String = "",
        itunesCatalogID: String = "",
        musicBrainzAlbumID: String = "",
        musicBrainzTrackID: String = "",
        musicBrainzReleaseGroupID: String = "",
        lyricist: String = "",
        remixer: String = "",
        producer: String = "",
        engineer: String = "",
        language: String = "",
        mediaType: String = "",
        releaseType: String = "",
        catalogNumber: String = "",
        releaseCountry: String = "",
        copyright: String = "",
        contentAdvisory: ContentAdvisory? = nil,
        artworkEditAction: ArtworkEditAction = .unchanged
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.composer = composer
        self.genre = genre
        self.comment = comment
        self.track = track
        self.trackTotal = trackTotal
        self.disc = disc
        self.discTotal = discTotal
        self.year = year
        self.trackNumberText = trackNumberText
        self.discNumberText = discNumberText
        self.albumArtist = albumArtist
        self.releaseDate = releaseDate
        self.publisher = publisher
        self.isrc = isrc
        self.barcode = barcode
        self.itunesAlbumID = itunesAlbumID
        self.itunesArtistID = itunesArtistID
        self.itunesCatalogID = itunesCatalogID
        self.musicBrainzAlbumID = musicBrainzAlbumID
        self.musicBrainzTrackID = musicBrainzTrackID
        self.musicBrainzReleaseGroupID = musicBrainzReleaseGroupID
        self.lyricist = lyricist
        self.remixer = remixer
        self.producer = producer
        self.engineer = engineer
        self.language = language
        self.mediaType = mediaType
        self.releaseType = releaseType
        self.catalogNumber = catalogNumber
        self.releaseCountry = releaseCountry
        self.copyright = copyright
        self.contentAdvisory = contentAdvisory
        self.artworkEditAction = artworkEditAction
    }

    init(from file: AudioFile) {
        self.init(
            title: file.title,
            artist: file.artist,
            album: file.album,
            composer: file.composer,
            genre: file.genre,
            comment: file.comment,
            track: file.track,
            trackTotal: file.trackTotal,
            disc: file.disc,
            discTotal: file.discTotal,
            year: file.year,
            trackNumberText: file.trackNumberText,
            discNumberText: file.discNumberText,
            albumArtist: file.albumArtist,
            releaseDate: file.releaseDate,
            publisher: file.publisher,
            isrc: file.isrc,
            barcode: file.barcode,
            itunesAlbumID: file.itunesAlbumID,
            itunesArtistID: file.itunesArtistID,
            itunesCatalogID: file.itunesCatalogID,
            musicBrainzAlbumID: file.musicBrainzAlbumID,
            musicBrainzTrackID: file.musicBrainzTrackID,
            musicBrainzReleaseGroupID: file.musicBrainzReleaseGroupID,
            lyricist: file.lyricist,
            remixer: file.remixer,
            producer: file.producer,
            engineer: file.engineer,
            language: file.language,
            mediaType: file.mediaType,
            releaseType: file.releaseType,
            catalogNumber: file.catalogNumber,
            releaseCountry: file.releaseCountry,
            copyright: file.copyright,
            contentAdvisory: file.contentAdvisory
        )
    }

    func hasUnsavedChanges(comparedTo file: AudioFile) -> Bool {
        let baseline = SingleFileEditModel(from: file)

        let hasMetadataChanges =
            title != baseline.title ||
            artist != baseline.artist ||
            album != baseline.album ||
            composer != baseline.composer ||
            genre != baseline.genre ||
            comment != baseline.comment ||
            track != baseline.track ||
            trackTotal != baseline.trackTotal ||
            disc != baseline.disc ||
            discTotal != baseline.discTotal ||
            year != baseline.year ||
            trackNumberText != baseline.trackNumberText ||
            discNumberText != baseline.discNumberText ||
            albumArtist != baseline.albumArtist ||
            releaseDate != baseline.releaseDate ||
            publisher != baseline.publisher ||
            isrc != baseline.isrc ||
            barcode != baseline.barcode ||
            itunesAlbumID != baseline.itunesAlbumID ||
            itunesArtistID != baseline.itunesArtistID ||
            itunesCatalogID != baseline.itunesCatalogID ||
            musicBrainzAlbumID != baseline.musicBrainzAlbumID ||
            musicBrainzTrackID != baseline.musicBrainzTrackID ||
            musicBrainzReleaseGroupID != baseline.musicBrainzReleaseGroupID ||
            lyricist != baseline.lyricist ||
            remixer != baseline.remixer ||
            producer != baseline.producer ||
            engineer != baseline.engineer ||
            language != baseline.language ||
            mediaType != baseline.mediaType ||
            releaseType != baseline.releaseType ||
            catalogNumber != baseline.catalogNumber ||
            releaseCountry != baseline.releaseCountry ||
            copyright != baseline.copyright ||
            contentAdvisory != baseline.contentAdvisory

        switch artworkEditAction {
        case .unchanged:
            return hasMetadataChanges
        case .replace:
            return true
        case .remove:
            return hasMetadataChanges || file.artwork != nil
        }
    }

    var trackNumberFieldText: String {
        AudioTagNumberPair(rawText: trackNumberText, number: track, total: trackTotal).displayedNumberText
    }

    var trackTotalFieldText: String {
        AudioTagNumberPair(rawText: trackNumberText, number: track, total: trackTotal).displayedTotalText
    }

    var discNumberFieldText: String {
        AudioTagNumberPair(rawText: discNumberText, number: disc, total: discTotal).displayedNumberText
    }

    var discTotalFieldText: String {
        AudioTagNumberPair(rawText: discNumberText, number: disc, total: discTotal).displayedTotalText
    }

    mutating func setTrackNumberFieldText(_ text: String) {
        let pair = AudioTagNumberPair(rawText: trackNumberText, number: track, total: trackTotal)
            .replacingNumberText(text)
        applyTrackPair(pair)
    }

    mutating func setTrackTotalFieldText(_ text: String) {
        let pair = AudioTagNumberPair(rawText: trackNumberText, number: track, total: trackTotal)
            .replacingTotalText(text)
        applyTrackPair(pair)
    }

    mutating func setDiscNumberFieldText(_ text: String) {
        let pair = AudioTagNumberPair(rawText: discNumberText, number: disc, total: discTotal)
            .replacingNumberText(text)
        applyDiscPair(pair)
    }

    mutating func setDiscTotalFieldText(_ text: String) {
        let pair = AudioTagNumberPair(rawText: discNumberText, number: disc, total: discTotal)
            .replacingTotalText(text)
        applyDiscPair(pair)
    }

    mutating func setTrackNumberText(_ text: String) {
        applyTrackPair(AudioTagNumberPair(rawText: text, number: track, total: trackTotal))
    }

    mutating func setDiscNumberText(_ text: String) {
        applyDiscPair(AudioTagNumberPair(rawText: text, number: disc, total: discTotal))
    }

    private mutating func applyTrackPair(_ pair: AudioTagNumberPair) {
        track = pair.number
        trackTotal = pair.total
        trackNumberText = pair.canonicalRawText
    }

    private mutating func applyDiscPair(_ pair: AudioTagNumberPair) {
        disc = pair.number
        discTotal = pair.total
        discNumberText = pair.canonicalRawText
    }
}

enum MultiFileEditableTextField: CaseIterable, Hashable {
    case title
    case artist
    case album
    case composer
    case genre
    case year
    case trackNumber
    case trackTotal
    case discNumber
    case discTotal
    case comment
    case albumArtist
    case releaseDate
    case publisher
    case copyright

    var displayName: String {
        switch self {
        case .title:
            return L10n.string("Title")
        case .artist:
            return L10n.string("Artist")
        case .album:
            return L10n.string("Album")
        case .composer:
            return L10n.string("Composer")
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
        case .albumArtist:
            return L10n.string("Album Artist")
        case .releaseDate:
            return L10n.string("Release Date")
        case .publisher:
            return L10n.string("Publisher")
        case .copyright:
            return L10n.string("Copyright")
        }
    }

    func value(from edit: SingleFileEditModel) -> String {
        switch self {
        case .title:
            return edit.title
        case .artist:
            return edit.artist
        case .album:
            return edit.album
        case .composer:
            return edit.composer
        case .genre:
            return edit.genre
        case .year:
            return edit.year
        case .trackNumber:
            return edit.trackNumberFieldText
        case .trackTotal:
            return edit.trackTotalFieldText
        case .discNumber:
            return edit.discNumberFieldText
        case .discTotal:
            return edit.discTotalFieldText
        case .comment:
            return edit.comment
        case .albumArtist:
            return edit.albumArtist
        case .releaseDate:
            return edit.releaseDate
        case .publisher:
            return edit.publisher
        case .copyright:
            return edit.copyright
        }
    }

    func value(from file: AudioFile) -> String {
        switch self {
        case .title:
            return file.title
        case .artist:
            return file.artist
        case .album:
            return file.album
        case .composer:
            return file.composer
        case .genre:
            return file.genre
        case .year:
            return file.year
        case .trackNumber:
            return AudioTagNumberPair(rawText: file.trackNumberText, number: file.track, total: file.trackTotal).displayedNumberText
        case .trackTotal:
            return AudioTagNumberPair(rawText: file.trackNumberText, number: file.track, total: file.trackTotal).displayedTotalText
        case .discNumber:
            return AudioTagNumberPair(rawText: file.discNumberText, number: file.disc, total: file.discTotal).displayedNumberText
        case .discTotal:
            return AudioTagNumberPair(rawText: file.discNumberText, number: file.disc, total: file.discTotal).displayedTotalText
        case .comment:
            return file.comment
        case .albumArtist:
            return file.albumArtist
        case .releaseDate:
            return file.releaseDate
        case .publisher:
            return file.publisher
        case .copyright:
            return file.copyright
        }
    }

    func apply(_ text: String, to edit: inout SingleFileEditModel) {
        switch self {
        case .title:
            edit.title = text
        case .artist:
            edit.artist = text
        case .album:
            edit.album = text
        case .composer:
            edit.composer = text
        case .genre:
            edit.genre = text
        case .year:
            edit.year = text
        case .trackNumber:
            edit.setTrackNumberFieldText(text)
        case .trackTotal:
            edit.setTrackTotalFieldText(text)
        case .discNumber:
            edit.setDiscNumberFieldText(text)
        case .discTotal:
            edit.setDiscTotalFieldText(text)
        case .comment:
            edit.comment = text
        case .albumArtist:
            edit.albumArtist = text
        case .releaseDate:
            edit.releaseDate = text
        case .publisher:
            edit.publisher = text
        case .copyright:
            edit.copyright = text
        }
    }
}

enum MultiFileExplicitEditState: Hashable, Identifiable {
    case keepExisting
    case set(ContentAdvisory?)

    var id: String {
        switch self {
        case .keepExisting:
            return "keepExisting"
        case .set(.none):
            return "unset"
        case .set(.some(let advisory)):
            return "set-\(advisory.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .keepExisting:
            return L10n.string("Keep Existing")
        case .set(.none):
            return L10n.string("Unset")
        case .set(.some(let advisory)):
            return advisory.displayName
        }
    }
}

enum MultiFileArtworkState {
    case none
    case shared(PlatformImage)
    case mixed
}

struct MultiFileEditModel {
    var values: SingleFileEditModel
    private(set) var modifiedTextFields: Set<MultiFileEditableTextField>
    let mixedTextFields: Set<MultiFileEditableTextField>
    let initialContentAdvisory: ContentAdvisory??
    let initialArtworkState: MultiFileArtworkState
    var explicitEditState: MultiFileExplicitEditState
    var artworkEditAction: ArtworkEditAction

    init(files: [AudioFile]) {
        var values = SingleFileEditModel()
        var mixedTextFields = Set<MultiFileEditableTextField>()

        for field in MultiFileEditableTextField.allCases {
            guard let firstFile = files.first else {
                field.apply("", to: &values)
                continue
            }

            let firstValue = field.value(from: firstFile)
            let isMixed = files.dropFirst().contains { field.value(from: $0) != firstValue }
            let mergedValue = isMixed ? "" : firstValue

            field.apply(mergedValue, to: &values)
            if isMixed {
                mixedTextFields.insert(field)
            }
        }

        let initialContentAdvisory: ContentAdvisory??
        if let first = files.first?.contentAdvisory, files.dropFirst().allSatisfy({ $0.contentAdvisory == first }) {
            initialContentAdvisory = .some(first)
        } else if files.allSatisfy({ $0.contentAdvisory == nil }) {
            initialContentAdvisory = .some(nil)
        } else {
            initialContentAdvisory = nil
        }

        self.values = values
        self.modifiedTextFields = []
        self.mixedTextFields = mixedTextFields
        self.initialContentAdvisory = initialContentAdvisory
        self.initialArtworkState = MultiFileEditModel.resolveArtworkState(for: files)
        self.explicitEditState = .keepExisting
        self.artworkEditAction = .unchanged
    }

    var hasUnsavedChanges: Bool {
        !modifiedTextFields.isEmpty || explicitEditState != .keepExisting || hasPendingArtworkChange
    }

    func text(for field: MultiFileEditableTextField) -> String {
        field.value(from: values)
    }

    func placeholder(for field: MultiFileEditableTextField) -> String? {
        guard mixedTextFields.contains(field), !modifiedTextFields.contains(field) else { return nil }
        return L10n.string("Multiple Values")
    }

    var explicitCurrentValueDescription: String {
        switch initialContentAdvisory {
        case .some(.some(let advisory)):
            return advisory.currentValueDescription
        case .some(.none):
            return L10n.string("Current value: Unset")
        case .none:
            return L10n.string("Current values differ")
        }
    }

    var displayedArtwork: PlatformImage? {
        switch artworkEditAction {
        case .unchanged:
            switch initialArtworkState {
            case .none, .mixed:
                return nil
            case .shared(let image):
                return image
            }
        case .replace(let artwork):
            return artwork.image
        case .remove:
            return nil
        }
    }

    var artworkSummary: String {
        switch artworkEditAction {
        case .unchanged:
            switch initialArtworkState {
            case .none:
                return L10n.string("No artwork in the current selection")
            case .shared:
                return L10n.string("Shared artwork across selected files")
            case .mixed:
                return L10n.string("Artwork differs across selected files")
            }
        case .replace:
            return L10n.string("This artwork will be applied to all selected files")
        case .remove:
            return L10n.string("Artwork will be removed from all selected files")
        }
    }

    var artworkPlaceholderSymbolName: String {
        switch artworkEditAction {
        case .unchanged:
            switch initialArtworkState {
            case .none:
                return "photo.badge.exclamationmark"
            case .shared:
                return "photo"
            case .mixed:
                return "photo.on.rectangle.angled"
            }
        case .replace:
            return "photo"
        case .remove:
            return "trash"
        }
    }

    var hasPendingArtworkChange: Bool {
        switch artworkEditAction {
        case .unchanged:
            return false
        case .replace, .remove:
            return true
        }
    }

    var canClearArtwork: Bool {
        switch artworkEditAction {
        case .remove:
            return false
        case .replace:
            return true
        case .unchanged:
            switch initialArtworkState {
            case .none:
                return false
            case .shared, .mixed:
                return true
            }
        }
    }

    mutating func setText(_ text: String, for field: MultiFileEditableTextField) {
        field.apply(text, to: &values)
        modifiedTextFields.insert(field)
    }

    mutating func setArtworkEditAction(_ action: ArtworkEditAction) {
        artworkEditAction = action
    }

    func applyingChanges(to file: AudioFile) -> SingleFileEditModel {
        var result = SingleFileEditModel(from: file)

        for field in modifiedTextFields {
            field.apply(field.value(from: values), to: &result)
        }

        switch explicitEditState {
        case .keepExisting:
            break
        case .set(let advisory):
            result.contentAdvisory = advisory
        }

        result.artworkEditAction = artworkEditAction
        return result
    }

    private static func resolveArtworkState(for files: [AudioFile]) -> MultiFileArtworkState {
        guard let firstFile = files.first else { return .none }
        guard let firstFingerprint = firstFile.artworkFingerprint else {
            return files.allSatisfy({ $0.artworkFingerprint == nil }) ? .none : .mixed
        }

        guard let firstArtwork = firstFile.artwork else {
            return .mixed
        }

        return files.dropFirst().allSatisfy({ $0.artworkFingerprint == firstFingerprint })
            ? .shared(firstArtwork)
            : .mixed
    }
}
