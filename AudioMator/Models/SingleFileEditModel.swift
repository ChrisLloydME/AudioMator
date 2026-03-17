import AppKit

struct PendingArtwork {
    var image: NSImage
    var data: Data
    var mimeType: String
}

private func normalizedArtworkComparisonData(for image: NSImage) -> Data? {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:]) ?? tiffData
}

private func artworkImagesMatch(_ lhs: NSImage?, _ rhs: NSImage?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case let (left?, right?):
        guard
            let leftData = normalizedArtworkComparisonData(for: left),
            let rightData = normalizedArtworkComparisonData(for: right)
        else {
            return false
        }

        return leftData == rightData
    default:
        return false
    }
}

enum ArtworkEditAction {
    case unchanged
    case replace(PendingArtwork)
    case remove
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
    var copyright: String
    var isExplicit: Bool
    var artworkEditAction: ArtworkEditAction

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
        copyright: String = "",
        isExplicit: Bool = false,
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
        self.copyright = copyright
        self.isExplicit = isExplicit
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
            trackNumberText: file.track > 0 ? (file.trackTotal > 0 ? "\(file.track)/\(file.trackTotal)" : "\(file.track)") : "",
            discNumberText: file.disc > 0 ? (file.discTotal > 0 ? "\(file.disc)/\(file.discTotal)" : "\(file.disc)") : "",
            albumArtist: file.albumArtist,
            releaseDate: file.releaseDate,
            publisher: file.publisher,
            copyright: file.copyright,
            isExplicit: file.isExplicit
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
            copyright != baseline.copyright ||
            isExplicit != baseline.isExplicit

        switch artworkEditAction {
        case .unchanged:
            return hasMetadataChanges
        case .replace:
            return true
        case .remove:
            return hasMetadataChanges || file.artwork != nil
        }
    }
}

enum MultiFileEditableTextField: CaseIterable, Hashable {
    case title
    case artist
    case album
    case composer
    case genre
    case year
    case trackNumberText
    case discNumberText
    case comment
    case albumArtist
    case releaseDate
    case publisher
    case copyright

    var displayName: String {
        switch self {
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .album:
            return "Album"
        case .composer:
            return "Composer"
        case .genre:
            return "Genre"
        case .year:
            return "Year"
        case .trackNumberText:
            return "Track Number"
        case .discNumberText:
            return "Disc Number"
        case .comment:
            return "Comment"
        case .albumArtist:
            return "Album Artist"
        case .releaseDate:
            return "Release Date"
        case .publisher:
            return "Publisher"
        case .copyright:
            return "Copyright"
        }
    }

    var keyPath: WritableKeyPath<SingleFileEditModel, String> {
        switch self {
        case .title:
            return \.title
        case .artist:
            return \.artist
        case .album:
            return \.album
        case .composer:
            return \.composer
        case .genre:
            return \.genre
        case .year:
            return \.year
        case .trackNumberText:
            return \.trackNumberText
        case .discNumberText:
            return \.discNumberText
        case .comment:
            return \.comment
        case .albumArtist:
            return \.albumArtist
        case .releaseDate:
            return \.releaseDate
        case .publisher:
            return \.publisher
        case .copyright:
            return \.copyright
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
        case .trackNumberText:
            return file.track > 0
                ? (file.trackTotal > 0 ? "\(file.track)/\(file.trackTotal)" : "\(file.track)")
                : ""
        case .discNumberText:
            return file.disc > 0
                ? (file.discTotal > 0 ? "\(file.disc)/\(file.discTotal)" : "\(file.disc)")
                : ""
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
}

enum MultiFileExplicitEditState: String, CaseIterable, Identifiable {
    case keepExisting
    case markExplicit
    case markClean

    var id: String { rawValue }
}

enum MultiFileArtworkState {
    case none
    case shared(NSImage)
    case mixed
}

struct MultiFileEditModel {
    var values: SingleFileEditModel
    private(set) var modifiedTextFields: Set<MultiFileEditableTextField>
    let mixedTextFields: Set<MultiFileEditableTextField>
    let initialExplicitValue: Bool?
    let initialArtworkState: MultiFileArtworkState
    var explicitEditState: MultiFileExplicitEditState
    var artworkEditAction: ArtworkEditAction

    init(files: [AudioFile]) {
        var values = SingleFileEditModel()
        var mixedTextFields = Set<MultiFileEditableTextField>()

        for field in MultiFileEditableTextField.allCases {
            let fieldValues = files.map { field.value(from: $0) }
            let mergedValue: String
            let isMixed: Bool

            if let first = fieldValues.first {
                isMixed = fieldValues.dropFirst().contains { $0 != first }
                mergedValue = isMixed ? "" : first
            } else {
                isMixed = false
                mergedValue = ""
            }

            values[keyPath: field.keyPath] = mergedValue
            if isMixed {
                mixedTextFields.insert(field)
            }
        }

        let explicitValues = files.map(\.isExplicit)
        let initialExplicitValue: Bool?
        if let first = explicitValues.first, explicitValues.dropFirst().allSatisfy({ $0 == first }) {
            initialExplicitValue = first
        } else {
            initialExplicitValue = nil
        }

        let initialArtworkState: MultiFileArtworkState
        if files.allSatisfy({ $0.artwork == nil }) {
            initialArtworkState = .none
        } else if
            let firstArtwork = files.first?.artwork,
            files.dropFirst().allSatisfy({ artworkImagesMatch($0.artwork, firstArtwork) })
        {
            initialArtworkState = .shared(firstArtwork)
        } else {
            initialArtworkState = .mixed
        }

        self.values = values
        self.modifiedTextFields = []
        self.mixedTextFields = mixedTextFields
        self.initialExplicitValue = initialExplicitValue
        self.initialArtworkState = initialArtworkState
        self.explicitEditState = .keepExisting
        self.artworkEditAction = .unchanged
    }

    var hasUnsavedChanges: Bool {
        !modifiedTextFields.isEmpty || explicitEditState != .keepExisting || hasPendingArtworkChange
    }

    func text(for field: MultiFileEditableTextField) -> String {
        values[keyPath: field.keyPath]
    }

    func placeholder(for field: MultiFileEditableTextField) -> String? {
        guard mixedTextFields.contains(field), !modifiedTextFields.contains(field) else { return nil }
        return "Multiple Values"
    }

    var explicitCurrentValueDescription: String {
        switch initialExplicitValue {
        case .some(true):
            return "Current value: Explicit"
        case .some(false):
            return "Current value: Clean"
        case .none:
            return "Current values differ"
        }
    }

    var displayedArtwork: NSImage? {
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
                return "No artwork in the current selection"
            case .shared:
                return "Shared artwork across selected files"
            case .mixed:
                return "Artwork differs across selected files"
            }
        case .replace:
            return "This artwork will be applied to all selected files"
        case .remove:
            return "Artwork will be removed from all selected files"
        }
    }

    var artworkPlaceholderSymbolName: String {
        switch artworkEditAction {
        case .unchanged:
            switch initialArtworkState {
            case .none:
                return "photo.slash"
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
        values[keyPath: field.keyPath] = text
        modifiedTextFields.insert(field)
    }

    mutating func setArtworkEditAction(_ action: ArtworkEditAction) {
        artworkEditAction = action
    }

    func applyingChanges(to file: AudioFile) -> SingleFileEditModel {
        var result = SingleFileEditModel(from: file)

        for field in modifiedTextFields {
            result[keyPath: field.keyPath] = values[keyPath: field.keyPath]
        }

        switch explicitEditState {
        case .keepExisting:
            break
        case .markExplicit:
            result.isExplicit = true
        case .markClean:
            result.isExplicit = false
        }

        result.artworkEditAction = artworkEditAction
        return result
    }
}
