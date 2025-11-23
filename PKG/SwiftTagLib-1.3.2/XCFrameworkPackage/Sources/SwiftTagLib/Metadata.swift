
@_implementationOnly import CxxTagLibBridge
private import CxxStdlib

public extension AudioFile {
    /// Aggregate metadata container built from `AuidoFile.Formt` specific combination of the following: `TagLib::Tag`, `TagLib:ID3v1::Tag`, `TagLib::ID3v2::Tag`, `TagLib::Ogg::XiphComment`, `TagLib::APE::Tag`, `TagLib::MP4::Tag`.
    struct Metadata: CxxRepresentable, Hashable {
        // MARK: - Basic Properties shared across ID3v1, ID3v2 and some other Tags
        /// Might be limited to `28 ... 30` characters if the file has `ID3v1` in `tagSource`.
        public var title: String?
        /// Might be limited to `28 ... 30` characters if the file has `ID3v1` in `tagSource`.
        public var albumTitle: String?
        /// Might be limited to `28 ... 30` characters if the file has `ID3v1` in `tagSource`.
        public var artist: String?
        public var genre: String?
        public var releaseDate: String?
        /// Might be limited to `28 ... 30` characters if the file has `ID3v1` in `tagSource`.
        public var comment: String?
        // MARK: - ID3v2 Properties
        public var composer: String?
        public var albumArtist: String?
        /// Appropriate values are within `1 ... 300`.
        public var beatPerMinute: Int32?
        /// Appropriate values are within `1 ... 100`.
        public var rating: Int32?
        /// Appropriate values are within `1 ... trackTotal`.
        public var trackNumber: Int32?
        /// Appropriate values are within `1 ... 255`.
        public var trackTotal: Int32?
        /// Appropriate values are within `1 ... discTotal`.
        public var discNumber: Int32?
        /// Appropriate values are within `1 ... 99`.
        public var discTotal: Int32?
        public var lyrics: String?
        public var compilation: Bool?
        public var internationalStandardRecordingCode: String?
        public var mediaCatalogNumber: String?
        public var musicBrainzReleaseID: String?
        public var musicBrainzRecordingID: String?
        // MARK: - Attached Pictures
        public var attachedPictures: [AttachedPicture] = []
        internal private(set) var attachedPicturesCount: Int32 = 0
        /// might give false positives when skipping pictures(images may carry no data, but unless read the count is based on metadata frames)
        public var hasAttachedPictures: Bool {
            attachedPicturesCount > 0 || attachedPictures.count > 0
        }
        // MARK: - Additional Metadata
        public var additional: [AdditionalMetadataPair] = []
        // MARK: - Tag Source
        public private(set) var tagSource: TagSource = .undefined
        // MARK: - init
        public init() {}

        /// unfortunately `TagSource` might change after `write` so we need to exclude it from being hashed.
        public func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(albumTitle)
            hasher.combine(artist)
            hasher.combine(genre)
            hasher.combine(releaseDate)
            hasher.combine(comment)
            hasher.combine(composer)
            hasher.combine(albumArtist)
            hasher.combine(beatPerMinute)
            hasher.combine(rating)
            hasher.combine(trackNumber)
            hasher.combine(trackTotal)
            hasher.combine(discNumber)
            hasher.combine(discTotal)
            hasher.combine(lyrics)
            hasher.combine(compilation)
            hasher.combine(internationalStandardRecordingCode)
            hasher.combine(mediaCatalogNumber)
            hasher.combine(musicBrainzReleaseID)
            hasher.combine(musicBrainzRecordingID)
            hasher.combine(attachedPictures)
            hasher.combine(additional)
        }

        init(cxxRepresentation metadata: AudioMetadata) {
            self.tagSource = TagSource(rawValue: metadata.tagSource)
            if let title = Optional(fromCxx: metadata.title) {
                self.title = String(title)
            }
            if let albumTitle = Optional(fromCxx: metadata.albumTitle) {
                self.albumTitle = String(albumTitle)
            }
            if let artist = Optional(fromCxx: metadata.artist) {
                self.artist = String(artist)
            }
            if let genre = Optional(fromCxx: metadata.genre) {
                self.genre = String(genre)
            }
            if let releaseDate = Optional(fromCxx: metadata.releaseDate) {
                self.releaseDate = String(releaseDate)
            }
            if let comment = Optional(fromCxx: metadata.comment) {
                self.comment = String(comment)
            }
            if let composer = Optional(fromCxx: metadata.composer) {
                self.composer = String(composer)
            }
            if let albumArtist = Optional(fromCxx: metadata.albumArtist) {
                self.albumArtist = String(albumArtist)
            }
            if let beatPerMinute = Optional(fromCxx: metadata.beatPerMinute) {
                self.beatPerMinute = beatPerMinute
            }
            if let rating = Optional(fromCxx: metadata.rating) {
                self.rating = rating
            }
            if let trackNumber = Optional(fromCxx: metadata.trackNumber) {
                self.trackNumber = trackNumber
            }
            if let trackTotal = Optional(fromCxx: metadata.trackTotal) {
                self.trackTotal = trackTotal
            }
            if let discNumber = Optional(fromCxx: metadata.discNumber) {
                self.discNumber = discNumber
            }
            if let discTotal = Optional(fromCxx: metadata.discTotal) {
                self.discTotal = discTotal
            }
            if let lyrics = Optional(fromCxx: metadata.lyrics) {
                self.lyrics = String(lyrics)
            }
            if let compilation = Optional(fromCxx: metadata.compilation) {
                self.compilation = compilation
            }
            if let internationalStandardRecordingCode = Optional(fromCxx: metadata.internationalStandardRecordingCode) {
                self.internationalStandardRecordingCode = String(internationalStandardRecordingCode)
            }
            if let mediaCatalogNumber = Optional(fromCxx: metadata.mediaCatalogNumber) {
                self.mediaCatalogNumber = String(mediaCatalogNumber)
            }
            if let musicBrainzReleaseID = Optional(fromCxx: metadata.musicBrainzReleaseID) {
                self.musicBrainzReleaseID = String(musicBrainzReleaseID)
            }
            if let musicBrainzRecordingID = Optional(fromCxx: metadata.musicBrainzRecordingID) {
                self.musicBrainzRecordingID = String(musicBrainzRecordingID)
            }
            attachedPictures = metadata.attachedPictures.map(AttachedPicture.init)
            attachedPicturesCount = metadata.attachedPicturesCount
            additional = metadata.additional.map(AdditionalMetadataPair.init)
        }

        var cxxRepresentation: AudioMetadata {
            var metadata = AudioMetadata()
            if let title {
                metadata.setTitle(std.string(title))
            }
            if let albumTitle {
                metadata.setAlbumTitle(std.string(albumTitle))
            }
            if let artist {
                metadata.setArtist(std.string(artist))
            }
            if let genre {
                metadata.setGenre(std.string(genre))
            }
            if let releaseDate {
                metadata.setReleaseDate(std.string(releaseDate));
            }
            if let comment {
                metadata.setComment(std.string(comment))
            }
            if let composer {
                metadata.setComposer(std.string(composer))
            }
            if let albumArtist {
                metadata.setAlbumArtist(std.string(albumArtist))
            }
            if let beatPerMinute {
                metadata.setBeatPerMinute(beatPerMinute)
            }
            if let rating {
                metadata.setRating(rating)
            }
            if let trackNumber {
                metadata.setTrackNumber(trackNumber)
            }
            if let trackTotal {
                metadata.setTrackTotal(trackTotal)
            }
            if let discNumber {
                metadata.setDiscNumber(discNumber)
            }
            if let discTotal {
                metadata.setDiscTotal(discTotal)
            }
            if let lyrics {
                metadata.setLyrics(std.string(lyrics))
            }
            if let compilation {
                metadata.setCompilation(compilation)
            }
            if let internationalStandardRecordingCode {
                metadata.setInternationalStandardRecordingCode(std.string(internationalStandardRecordingCode))
            }
            if let mediaCatalogNumber {
                metadata.setMediaCatalogNumber(std.string(mediaCatalogNumber))
            }
            if let musicBrainzReleaseID {
                metadata.setMusicBrainzReleaseID(std.string(musicBrainzReleaseID))
            }
            if let musicBrainzRecordingID {
                metadata.setMusicBrainzRecordingID(std.string(musicBrainzRecordingID))
            }
            /// unfortunately this is the only way of converting Array of more complex types than int/bool/string
            /// to std::vector, generalization isn't possible yet. 22.11.2024
            var attachedPictures = AudioMetadata.AttachedPictures()
            self.attachedPictures.forEach { attachedPictures.push_back($0.cxxRepresentation) }
            metadata.attachedPictures = attachedPictures
            var additional = AudioMetadata.AdditionalMetadata()
            self.additional.forEach { additional.push_back($0.cxxRepresentation) }
            metadata.additional = additional
            return metadata
        }
    }
}

// MARK: - read
import struct Foundation.URL

extension AudioFile.Metadata {
    static func readMetadataAndProperties(
        from url: URL,
        format: AudioFile.Format,
        options: ReadingOptions,
        overlayStrategy: OverlayStrategy,
    ) throws(AudioFile.InitializationError) -> (metadata: Self, properties: AudioFile.Properties) {
        var metadata = AudioMetadata()
        var properties = AudioProperties()
        let implementation = format.implementationMetatype.init(std.string(url.path))
        var errorDescription = std.string()
        let outcome = implementation.readMetadata(
            &metadata,
            &properties,
            options.cxxRepresentation,
            overlayStrategy.cxxRepresentation,
            &errorDescription
        )
        try AudioFile.InitializationError.throwIfNeeded(outcome, String(errorDescription))
        return (.init(cxxRepresentation: metadata), .init(cxxRepresentation: properties))
    }
}

// MARK: - write
extension AudioFile.Metadata {
    func write(
        to url: URL,
        format: AudioFile.Format
    ) throws(AudioFile.MetadataWritingError) {
        let implementation = format.implementationMetatype.init(std.string(url.path))
        var metadata = cxxRepresentation
        var errorDescription = std.string()
        let outcome = implementation.writeMetadata(&metadata, &errorDescription)
        try AudioFile.MetadataWritingError.throwIfNeeded(outcome, String(errorDescription))
    }
}
