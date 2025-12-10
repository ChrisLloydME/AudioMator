//
//  TagLibMetadataExtractor.h
//  HiFidelity
//
//  Objective-C++ wrapper for TagLib metadata extraction
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Comprehensive metadata container for audio tracks
@interface TagLibAudioMetadata : NSObject

// Core metadata
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSString *album;
@property (nonatomic, copy, nullable) NSString *albumArtist;
@property (nonatomic, copy, nullable) NSString *composer;
@property (nonatomic, copy, nullable) NSString *genre;
@property (nonatomic, copy, nullable) NSString *year;
@property (nonatomic, copy, nullable) NSString *comment;

// Track/Disc information
@property (nonatomic, assign) NSInteger trackNumber;
@property (nonatomic, assign) NSInteger totalTracks;
@property (nonatomic, assign) NSInteger discNumber;
@property (nonatomic, assign) NSInteger totalDiscs;

// Audio properties
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSInteger bitrate; // in kbps
@property (nonatomic, assign) NSInteger sampleRate; // in Hz
@property (nonatomic, assign) NSInteger channels;
@property (nonatomic, assign) NSInteger bitDepth; // bits per sample
@property (nonatomic, copy, nullable) NSString *codec;

// Artwork
@property (nonatomic, strong, nullable) NSData *artworkData;
@property (nonatomic, copy, nullable) NSString *artworkMimeType;

// Additional metadata
@property (nonatomic, assign) NSInteger bpm;
@property (nonatomic, assign) BOOL compilation;
@property (nonatomic, copy, nullable) NSString *copyright;
@property (nonatomic, copy, nullable) NSString *lyrics;
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, copy, nullable) NSString *isrc;
@property (nonatomic, copy, nullable) NSString *encodedBy;
@property (nonatomic, copy, nullable) NSString *encoderSettings;

// Sort fields
@property (nonatomic, copy, nullable) NSString *sortTitle;
@property (nonatomic, copy, nullable) NSString *sortArtist;
@property (nonatomic, copy, nullable) NSString *sortAlbum;
@property (nonatomic, copy, nullable) NSString *sortAlbumArtist;
@property (nonatomic, copy, nullable) NSString *sortComposer;

// Date fields
@property (nonatomic, copy, nullable) NSString *releaseDate;
@property (nonatomic, copy, nullable) NSString *originalReleaseDate;

// Personnel
@property (nonatomic, copy, nullable) NSString *conductor;
@property (nonatomic, copy, nullable) NSString *remixer;
@property (nonatomic, copy, nullable) NSString *producer;
@property (nonatomic, copy, nullable) NSString *engineer;
@property (nonatomic, copy, nullable) NSString *lyricist;

// Descriptive
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *grouping;
@property (nonatomic, copy, nullable) NSString *movement;
@property (nonatomic, copy, nullable) NSString *mood;
@property (nonatomic, copy, nullable) NSString *language;
@property (nonatomic, copy, nullable) NSString *musicalKey;

// MusicBrainz IDs
@property (nonatomic, copy, nullable) NSString *musicBrainzArtistId;
@property (nonatomic, copy, nullable) NSString *musicBrainzAlbumId;
@property (nonatomic, copy, nullable) NSString *musicBrainzTrackId;
@property (nonatomic, copy, nullable) NSString *musicBrainzReleaseGroupId;

// ReplayGain
@property (nonatomic, copy, nullable) NSString *replayGainTrack;
@property (nonatomic, copy, nullable) NSString *replayGainAlbum;

// Media type
@property (nonatomic, copy, nullable) NSString *mediaType;

// Release information (Professional music player fields)
@property (nonatomic, copy, nullable) NSString *releaseType;      // Album, EP, Single, Compilation, Live, etc.
@property (nonatomic, copy, nullable) NSString *catalogNumber;    // Catalog/Matrix number
@property (nonatomic, copy, nullable) NSString *barcode;          // UPC/EAN barcode
@property (nonatomic, copy, nullable) NSString *releaseCountry;   // ISO country code
@property (nonatomic, copy, nullable) NSString *artistType;       // Person, Group, Orchestra, etc.

// Custom/Extended fields dictionary
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *customFields;

@end


/// TagLib metadata extractor
@interface TagLibMetadataExtractor : NSObject

/// Extract metadata from an audio file.
///
/// This method uses TagLib to read a wide range of tags, including:
/// - Core tags: title, artist, album, albumArtist, composer, genre, year, comment
/// - Track/disc info: trackNumber, totalTracks, discNumber, totalDiscs
/// - Audio properties: duration, bitrate, sampleRate, channels, bitDepth, codec
/// - Artwork: embedded cover image (artworkData + artworkMimeType)
/// - Extended fields: bpm, compilation, copyright, lyrics, label, isrc,
///   encoder / encoderSettings, sort fields, grouping, mood, etc.
/// - Date fields: `releaseDate` and `originalReleaseDate` when available
///   (for example ID3 TDRC/TDOR in MP3, or ©day / ORIGINAL YEAR atoms in MP4/M4A).
/// - Professional music player fields (releaseType, catalogNumber, barcode,
///   releaseCountry, artistType) and any custom freeform fields.
///
/// Unsupported or missing tags will simply remain nil or zero on the returned
/// TagLibAudioMetadata instance.
///
/// @param fileURL URL to the audio file
/// @param error Error pointer for error handling
/// @return Metadata object or nil if extraction fails
+ (nullable TagLibAudioMetadata *)extractMetadataFromURL:(NSURL *)fileURL
                                                   error:(NSError *_Nullable *_Nullable)error;

/// Write metadata back to an audio file
/// @param metadata Metadata object to write
/// @param fileURL URL to the audio file
/// @param error Error pointer for error handling
/// @return YES if write succeeds, NO otherwise
+ (BOOL)writeMetadata:(TagLibAudioMetadata *)metadata
                toURL:(NSURL *)fileURL
                error:(NSError *_Nullable *_Nullable)error
NS_SWIFT_NAME(writeMetadata(_:to:));

/// Check if a file format is supported by TagLib
/// @param fileExtension File extension (without dot)
/// @return YES if supported, NO otherwise
+ (BOOL)isSupportedFormat:(NSString *)fileExtension;

/// Get list of all supported file extensions
/// @return Array of supported extensions
+ (NSArray<NSString *> *)supportedExtensions;

@end

NS_ASSUME_NONNULL_END
