//
//  TagLibMetadataExtractor.h
//  AudioMator (Re-write from HiFidelity)
//
//  Objective-C++ wrapper for TagLib metadata extraction
//

#pragma once

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
@property (nonatomic, assign) NSInteger bitrate;     // kbps
@property (nonatomic, assign) NSInteger sampleRate;  // Hz
@property (nonatomic, assign) NSInteger channels;
@property (nonatomic, assign) NSInteger bitDepth;    // bits per sample
@property (nonatomic, copy, nullable) NSString *codec;

// Artwork
@property (nonatomic, strong, nullable) NSData *artworkData;
@property (nonatomic, copy, nullable) NSString *artworkMimeType;

// Additional metadata
@property (nonatomic, assign) NSInteger bpm;
@property (nonatomic, assign) BOOL compilation;
@property (nonatomic, assign) BOOL explicitContent; // YES = explicit, NO = non-explicit/unknown
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

// Release information (professional fields)
@property (nonatomic, copy, nullable) NSString *releaseType;      // Album, EP, Single, etc.
@property (nonatomic, copy, nullable) NSString *catalogNumber;    // Catalog/Matrix number
@property (nonatomic, copy, nullable) NSString *barcode;          // UPC/EAN
@property (nonatomic, copy, nullable) NSString *releaseCountry;   // ISO country code
@property (nonatomic, copy, nullable) NSString *artistType;       // Person, Group, etc.

// Custom/Extended fields
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *customFields;

@end


/// TagLib metadata extractor
@interface TagLibMetadataExtractor : NSObject

/// Extract metadata from an audio file.
///
/// Unsupported or missing tags remain nil/zero on the returned object.
+ (nullable TagLibAudioMetadata *)extractMetadataFromURL:(NSURL *)fileURL
                                                   error:(NSError *_Nullable *_Nullable)error
NS_SWIFT_NAME(extractMetadata(from:));

/// Write metadata back to an audio file.
+ (BOOL)writeMetadata:(TagLibAudioMetadata *)metadata
                toURL:(NSURL *)fileURL
                error:(NSError *_Nullable *_Nullable)error
NS_SWIFT_NAME(writeMetadata(_:to:));

/// Return raw metadata as TagLib sees it for display purposes.
///
/// The returned dictionary typically contains keys such as:
/// - "properties": NSArray<NSDictionary<NSString *, NSString *> *> (TagLib PropertyMap entries)
/// - "id3v2Frames": NSArray<NSDictionary<NSString *, NSString *> *> (ID3v2 frames)
///
/// If extraction fails, this returns nil and sets `error`.
+ (nullable NSDictionary<NSString *, NSObject *> *)rawMetadataForURL:(NSURL *)fileURL
                                                              error:(NSError *_Nullable *_Nullable)error
NS_SWIFT_NAME(rawMetadata(for:));

/// Return a single plain-text dump of metadata as TagLib sees it.
/// Intended for GUI inspection and copy/paste.
+ (nullable NSString *)dumpMetadataTextFromURL:(NSURL *)fileURL
                                        error:(NSError *_Nullable *_Nullable)error
NS_SWIFT_NAME(dumpMetadataText(from:));

/// Check if a file format is supported by TagLib.
+ (BOOL)isSupportedFormat:(NSString *)fileExtension;

/// Get list of all supported file extensions.
+ (NSArray<NSString *> *)supportedExtensions;

@end

NS_ASSUME_NONNULL_END
