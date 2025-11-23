
#import <swift/bridging>
#import <CoreFoundation/CoreFoundation.h>
#import <tuple>
#import <string>
#import <optional>
#import <taglib/tag.h>
#import <taglib/id3v1tag.h>
#import <taglib/id3v2tag.h>
#import <taglib/xiphcomment.h>
#import <taglib/apetag.h>
#import <taglib/mp4tag.h>
#import <taglib/attachedpictureframe.h>
#import "InterfaceEnums.hpp"

/// Attempts to combine different [Tags](https://taglib.org/api/classTagLib_1_1Tag.html) into single interface.
struct AudioMetadata final {
    /// Macro to escape writing boilerplate for `setter` for `Swift` & `C++` **Interoperability**.
    /// Quircks:
    ///     - `setter` accepts `T` instead of `std::optional<T>` from `Swift`.
    /// Which means you read `optional` value, but if you wan't to nil it from swift, you just don't set it.
    /// The reason for this is `Swift` `C++` interop inability to construct `std.optional` although it's easy to do opposite.
    #define OPTIONAL_PROPERTY(_type, _accessor, _property) \
        std::optional<_type> _accessor; \
        void set##_property(const _type newValue) SWIFT_COMPUTED_PROPERTY { _accessor = newValue; }
protected:
    enum TagSource: uint8_t {
        Abstract = 1 << 0,
        ID3v1 = 1 << 1,
        ID3v2 = 1 << 2,
        MP4 = 1 << 3,
        APE = 1 << 4,
        Xiph = 1 << 5
    };
public:
    // MARK: - Tag Source option set
    uint8_t tagSource;
    // MARK: - Basic Properties shared across ID3v1, ID3v2 and some other Tags
    OPTIONAL_PROPERTY(std::string, title, Title);
    OPTIONAL_PROPERTY(std::string, albumTitle, AlbumTitle);
    OPTIONAL_PROPERTY(std::string, artist, Artist);
    OPTIONAL_PROPERTY(std::string, genre, Genre);
    OPTIONAL_PROPERTY(std::string, releaseDate, ReleaseDate);
    OPTIONAL_PROPERTY(std::string, comment, Comment);
    OPTIONAL_PROPERTY(int, trackNumber, TrackNumber);
    OPTIONAL_PROPERTY(int, discNumber, DiscNumber);
    OPTIONAL_PROPERTY(int, discTotal, DiscTotal);
    // MARK: - ID3v2 Properties
    OPTIONAL_PROPERTY(int, trackTotal, TrackTotal);
    OPTIONAL_PROPERTY(std::string, composer, Composer);
    OPTIONAL_PROPERTY(std::string, albumArtist, AlbumArtist);
    OPTIONAL_PROPERTY(int, beatPerMinute, BeatPerMinute);
    OPTIONAL_PROPERTY(int, rating, Rating);
    OPTIONAL_PROPERTY(std::string, lyrics, Lyrics);
    OPTIONAL_PROPERTY(bool, compilation, Compilation);
    OPTIONAL_PROPERTY(std::string, internationalStandardRecordingCode, InternationalStandardRecordingCode);
    OPTIONAL_PROPERTY(std::string, mediaCatalogNumber, MediaCatalogNumber);
    OPTIONAL_PROPERTY(std::string, musicBrainzReleaseID, MusicBrainzReleaseID);
    OPTIONAL_PROPERTY(std::string, musicBrainzRecordingID, MusicBrainzRecordingID);

    // MARK: - Attached Pictures
    /// `Picture`: raw `bytes`, `size`, `kind`, `description` and `type`.
    struct Picture final {
    public:
        using Bytes = std::vector<char>;
        Bytes bytes;
        unsigned int size;
        std::string description;
        enum class Kind: unsigned int {
            /// A type not otherwise enumerated
            other = 0x00,
            /// 32x32 PNG image that should be used as the file icon
            fileIcon = 0x01,
            /// File icon of a different size or format
            otherFileIcon = 0x02,
            /// Front cover image of the album
            frontCover = 0x03,
            /// Back cover image of the album
            backCover = 0x04,
            /// Inside leaflet page of the album
            leafletPage = 0x05,
            /// Image from the album itself
            media = 0x06,
            /// Picture of the lead artist or soloist
            leadArtist = 0x07,
            /// Picture of the artist or performer
            artist = 0x08,
            /// Picture of the conductor
            conductor = 0x09,
            /// Picture of the band or orchestra
            band = 0x0A,
            /// Picture of the composer
            composer = 0x0B,
            /// Picture of the lyricist or text writer
            lyricist = 0x0C,
            /// Picture of the recording location or studio
            recordingLocation = 0x0D,
            /// Picture of the artists during recording
            duringRecording = 0x0E,
            /// Picture of the artists during performance
            duringPerformance = 0x0F,
            /// Picture from a movie or video related to the track
            movieScreenCapture = 0x10,
            /// Picture of a large, coloured fish
            colouredFish = 0x11,
            /// Illustration related to the track
            illustration = 0x12,
            /// Logo of the band or performer
            bandLogo = 0x13,
            /// Logo of the publisher (record company)
            publisherLogo = 0x14,
        };
        Kind kind;
    protected:
        // MARK: - ImageIO computed properties
        using MIMEType = std::string;
        MIMEType mime_type();
        /// `(MIME type, pixel width, pixel height, color depth)`.
        using Properties = std::tuple<std::string, int, int, int>;
        Properties properties();
    public:
        // MARK: - Convenience Constructor for Swift
        static Picture create_from_CFData(CFDataRef data, std::string description, Kind kind);
        
        // MARK: - Attached Picture: Format specific builders
        using FLACPicture = TagLib::FLAC::Picture *;
        FLACPicture convert_to_FLACPicture();
        using MP4Picture = TagLib::MP4::CoverArt;
        MP4Picture convert_to_MP4Picture();
        using ID3v2Picture = TagLib::ID3v2::AttachedPictureFrame *;
        ID3v2Picture convert_to_ID3v2Picture();
        using APEPicture = std::optional<std::tuple<std::string, TagLib::ByteVector>>;
        APEPicture convert_to_APEPicture();

        // MARK: - AttachedPicture: builders from specific format
        static std::optional<Picture> create_from_byte_vector(const TagLib::ByteVector *bytes);
        static std::optional<Picture> create_from_FLACPicture(const TagLib::FLAC::Picture *flacPicture);
        static std::optional<Picture> create_from_MP4Picture(const TagLib::MP4::CoverArt *coverArt);
        static std::optional<Picture> create_from_ID3v2Picture(const TagLib::ID3v2::AttachedPictureFrame *frame);
        static std::optional<Picture> create_from_APEPicture(const TagLib::APE::Item *item, const char* key);
    };
    using AttachedPictures = std::vector<Picture>;
    AttachedPictures attachedPictures;
    int attachedPicturesCount = 0;

    // MARK: - Additional Metadata
    using AdditionalMetadataPair = std::pair<std::string, std::string>;
    using AdditionalMetadata = std::vector<AdditionalMetadataPair>;
    AdditionalMetadata additional;

    // MARK: - Abstract Tag
    static AudioMetadata read_from_tag(const TagLib::Tag *tag, const MetadataReadingOptions options);
    void write_to_tag(TagLib::Tag *tag) const;

    // MARK: - ID3v1 Tag
    static AudioMetadata read_from_ID3v1_tag(const TagLib::ID3v1::Tag *tag, const MetadataReadingOptions options);
    void write_to_ID3v1_tag(TagLib::ID3v1::Tag *tag) const;

    // MARK: - ID3v2 Tag
    static AudioMetadata read_from_ID3v2_tag(const TagLib::ID3v2::Tag *tag, const MetadataReadingOptions options);
    void write_to_ID3v2_tag(TagLib::ID3v2::Tag *tag, bool shouldWritePictures = true) const;

    // MARK: - Xiph Comment
    static AudioMetadata read_from_XiphComment(const TagLib::Ogg::XiphComment *tag, const MetadataReadingOptions options);
    void write_to_XiphComment(TagLib::Ogg::XiphComment *tag, bool shouldWritePictures = true) const;

    // MARK: - APE Tag
    static AudioMetadata read_from_APE_tag(const TagLib::APE::Tag *tag, const MetadataReadingOptions options);
    void write_to_APE_tag(TagLib::APE::Tag *tag, bool shouldWritePictures = true) const;

    // MARK: - MP4 Tag
    static AudioMetadata read_from_MP4_tag(const TagLib::MP4::Tag *tag, const MetadataReadingOptions options);
    void write_to_MP4_tag(TagLib::MP4::Tag *tag, bool shouldWritePictures = true) const;

    // MARK: - Utility
    void overlay(const AudioMetadata layer, const MetadataOverlayStrategy strategy);
};
