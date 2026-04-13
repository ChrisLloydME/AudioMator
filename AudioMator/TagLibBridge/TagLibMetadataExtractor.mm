//
//  TagLibMetadataExtractor.mm
//  AudioMator
//
//  Objective-C++ implementation using TagLib
//

#import "TagLibMetadataExtractor.h"
#include <stdarg.h>

// TagLib C++ headers
#include "taglib/taglib/fileref.h"
#include "taglib/taglib/tag.h"
#include "taglib/taglib/audioproperties.h"
#include "taglib/taglib/toolkit/tpropertymap.h"

// Format-specific headers
#include "taglib/taglib/mpeg/mpegfile.h"
#include "taglib/taglib/mpeg/id3v1/id3v1tag.h"
#include "taglib/taglib/mpeg/id3v2/id3v2tag.h"
#include "taglib/taglib/mpeg/id3v2/id3v2frame.h"
#include "taglib/taglib/mpeg/id3v2/frames/attachedpictureframe.h"
#include "taglib/taglib/mpeg/id3v2/frames/textidentificationframe.h"
#include "taglib/taglib/mpeg/id3v2/frames/commentsframe.h"
#include "taglib/taglib/mpeg/id3v2/frames/unsynchronizedlyricsframe.h"
#include "taglib/taglib/mpeg/id3v2/frames/popularimeterframe.h"

#include "taglib/taglib/mp4/mp4file.h"
#include "taglib/taglib/mp4/mp4tag.h"
#include "taglib/taglib/mp4/mp4item.h"
#include "taglib/taglib/mp4/mp4coverart.h"

#include "taglib/taglib/flac/flacfile.h"
#include "taglib/taglib/flac/flacpicture.h"
#include "taglib/taglib/ogg/xiphcomment.h"

#include "taglib/taglib/ogg/vorbis/vorbisfile.h"
#include "taglib/taglib/ogg/opus/opusfile.h"
#include "taglib/taglib/ogg/flac/oggflacfile.h"

#include "taglib/taglib/ape/apefile.h"
#include "taglib/taglib/ape/apetag.h"

#include "taglib/taglib/riff/wav/wavfile.h"
#include "taglib/taglib/riff/aiff/aifffile.h"
#include "taglib/taglib/wavpack/wavpackfile.h"
#include "taglib/taglib/trueaudio/trueaudiofile.h"

#include "taglib/taglib/mpc/mpcfile.h"
#include "taglib/taglib/ogg/speex/speexfile.h"
#include "taglib/taglib/asf/asffile.h"

#include "taglib/taglib/dsf/dsffile.h"
#include "taglib/taglib/dsdiff/dsdifffile.h"

#include "taglib/taglib/toolkit/tstring.h"
#include "taglib/taglib/toolkit/tstringlist.h"

@implementation TagLibAudioMetadata

- (instancetype)init {
    if (self = [super init]) {
        _trackNumber = 0;
        _totalTracks = 0;
        _discNumber = 0;
        _totalDiscs = 0;
        _duration = 0.0;
        _bitrate = 0;
        _sampleRate = 0;
        _channels = 0;
        _bitDepth = 0;
        _bpm = 0;
        _compilation = NO;
        _explicitContent = NO;
        _removeArtwork = NO;
    }
    return self;
}

@end

// Simple logging helper for TagLib debugging
static bool TagLibDebugLoggingEnabled() {
    static bool enabled = [] {
        NSString *value = [NSProcessInfo processInfo].environment[@"AUDIOMATOR_TAGLIB_DEBUG"] ?: @"";
        NSString *normalized = value.lowercaseString;
        return [normalized isEqualToString:@"1"] ||
               [normalized isEqualToString:@"true"] ||
               [normalized isEqualToString:@"yes"] ||
               [normalized isEqualToString:@"on"];
    }();
    return enabled;
}

static inline void TLog(NSString *format, ...) {
    if (!TagLibDebugLoggingEnabled()) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[TagLib] %@", message);
}

@implementation TagLibMetadataExtractor

#pragma mark - Helper Functions


// Convert TagLib::String to NSString
static NSString* _Nullable TagStringToNSString(const TagLib::String& str) {
    if (str.isEmpty()) {
        return nil;
    }
    std::string utf8 = str.to8Bit(true);
    return [NSString stringWithUTF8String:utf8.c_str()];
}

// Extract number from string (e.g., "3/12" -> 3)
static NSInteger ExtractNumber(const TagLib::String& str) {
    if (str.isEmpty()) {
        return 0;
    }
    return str.toInt();
}

// Parse track/disc number string (e.g., "3/12" -> (3, 12))
static void ParseNumberPair(const TagLib::String& str, NSInteger& number, NSInteger& total) {
    if (str.isEmpty()) {
        return;
    }
    
    std::string s = str.to8Bit(true);
    size_t slashPos = s.find('/');
    
    if (slashPos != std::string::npos) {
        number = atoi(s.substr(0, slashPos).c_str());
        total = atoi(s.substr(slashPos + 1).c_str());
    } else {
        number = str.toInt();
    }
}

// Convert NSString to TagLib::String (UTF-8)
static TagLib::String NSStringToTagString(NSString * _Nullable string) {
    if (!string || string.length == 0) {
        return TagLib::String();
    }
    return TagLib::String(string.UTF8String, TagLib::String::UTF8);
}

static void ApplyBasicTagMetadata(TagLib::Tag * _Nullable tag,
                                  TagLibAudioMetadata *metadata)
{
    if (!tag || !metadata) {
        return;
    }

    if (!metadata.title) {
        metadata.title = TagStringToNSString(tag->title());
    }
    if (!metadata.artist) {
        metadata.artist = TagStringToNSString(tag->artist());
    }
    if (!metadata.album) {
        metadata.album = TagStringToNSString(tag->album());
    }
    if (!metadata.genre) {
        metadata.genre = TagStringToNSString(tag->genre());
    }
    if (!metadata.comment) {
        metadata.comment = TagStringToNSString(tag->comment());
    }

    if (metadata.year.length == 0 && tag->year() > 0) {
        metadata.year = [NSString stringWithFormat:@"%u", tag->year()];
    }

    if (metadata.trackNumber <= 0 && tag->track() > 0) {
        metadata.trackNumber = tag->track();
    }

    if (metadata.trackNumberText.length == 0 && tag->track() > 0) {
        metadata.trackNumberText = PreferredNumberText(
            metadata.trackNumberText,
            [NSString stringWithFormat:@"%u", tag->track()]
        );
    }
}

static void ApplyPreferredBasicTagMetadata(TagLib::Tag * _Nullable tag,
                                           TagLibAudioMetadata *metadata)
{
    if (!tag || !metadata) {
        return;
    }

    NSString *title = TagStringToNSString(tag->title());
    if (title.length > 0) {
        metadata.title = title;
    }

    NSString *artist = TagStringToNSString(tag->artist());
    if (artist.length > 0) {
        metadata.artist = artist;
    }

    NSString *album = TagStringToNSString(tag->album());
    if (album.length > 0) {
        metadata.album = album;
    }

    NSString *genre = TagStringToNSString(tag->genre());
    if (genre.length > 0) {
        metadata.genre = genre;
    }

    NSString *comment = TagStringToNSString(tag->comment());
    if (comment.length > 0) {
        metadata.comment = comment;
    }

    if (tag->year() > 0) {
        metadata.year = [NSString stringWithFormat:@"%u", tag->year()];
    }

    if (tag->track() > 0) {
        metadata.trackNumber = tag->track();
        metadata.trackNumberText = PreferredNumberText(
            metadata.trackNumberText,
            [NSString stringWithFormat:@"%u", tag->track()]
        );
    }
}

static void ApplyAudioPropertiesMetadata(TagLib::AudioProperties * _Nullable properties,
                                         TagLibAudioMetadata *metadata)
{
    if (!properties || !metadata) {
        return;
    }

    if (metadata.duration <= 0.0) {
        metadata.duration = properties->lengthInSeconds();
    }
    if (metadata.bitrate <= 0) {
        metadata.bitrate = properties->bitrate();
    }
    if (metadata.sampleRate <= 0) {
        metadata.sampleRate = properties->sampleRate();
    }
    if (metadata.channels <= 0) {
        metadata.channels = properties->channels();
    }
}

static NSString * _Nullable TrimmedStringOrNil(NSString * _Nullable value) {
    if (!value) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

static NSString * _Nullable UppercaseTrimmedString(NSString * _Nullable value) {
    NSString *trimmed = TrimmedStringOrNil(value);
    return trimmed ? trimmed.uppercaseString : nil;
}

static NSSet<NSString *> *KnownMetadataFieldKeys()
{
    static NSSet<NSString *> *keys = [NSSet setWithArray:@[
        @"TITLE", @"ARTIST", @"ARTISTS", @"ALBUM", @"COMMENT", @"GENRE", @"COMPOSER", @"ALBUMARTIST",
        @"DATE", @"YEAR", @"RELEASEDATE", @"ORIGINALDATE", @"ORIGINAL YEAR",
        @"TRACKNUMBER", @"TRACK", @"TRACKTOTAL", @"TOTALTRACKS", @"DISCNUMBER", @"DISC", @"DISCTOTAL", @"TOTALDISCS",
        @"AUDIOMATOR_TRACKNUMBER_TEXT", @"AUDIOMATOR_DISCNUMBER_TEXT",
        @"COPYRIGHT", @"LYRICS", @"LABEL", @"ISRC", @"ENCODEDBY", @"ENCODING", @"ENCODERSETTINGS",
        @"TITLESORT", @"ARTISTSORT", @"ALBUMSORT", @"ALBUMARTISTSORT", @"COMPOSERSORT",
        @"GROUPING", @"SUBTITLE", @"LYRICIST", @"CONDUCTOR", @"REMIXER", @"PRODUCER", @"ENGINEER",
        @"MOVEMENT", @"MOOD", @"LANGUAGE", @"INITIALKEY", @"KEY", @"MEDIATYPE", @"MEDIA", @"MEDIA TYPE",
        @"ITUNESALBUMID", @"ITUNESARTISTID", @"ITUNESCATALOGID", @"ITUNESGENREID",
        @"ITUNESMEDIATYPE", @"ITUNESPURCHASEDATE", @"ITUNNORM", @"ITUNSMPB",
        @"RELEASETYPE", @"BARCODE", @"UPC", @"EAN", @"CATALOGNUMBER", @"CATALOG", @"RELEASECOUNTRY",
        @"ARTISTTYPE", @"MUSICBRAINZ ARTIST TYPE", @"MUSICBRAINZ_ARTISTTYPE",
        @"BPM", @"COMPILATION", @"ITUNESADVISORY", @"ADVISORY", @"EXPLICITCONTENT", @"EXPLICIT",
        @"MUSICBRAINZ_ARTISTID", @"MUSICBRAINZ ARTISTID", @"MUSICBRAINZ ARTIST ID",
        @"MUSICBRAINZ_ALBUMID", @"MUSICBRAINZ ALBUMID", @"MUSICBRAINZ ALBUM ID",
        @"MUSICBRAINZ_TRACKID", @"MUSICBRAINZ TRACKID", @"MUSICBRAINZ TRACK ID",
        @"MUSICBRAINZ_RELEASEGROUPID", @"MUSICBRAINZ RELEASEGROUPID", @"MUSICBRAINZ RELEASE GROUP ID",
        @"MUSICBRAINZ_ALBUMTYPE", @"MUSICBRAINZ ALBUM TYPE",
        @"MUSICBRAINZ_ALBUMRELEASECOUNTRY", @"MUSICBRAINZ ALBUM RELEASE COUNTRY",
        @"REPLAYGAIN_TRACK_GAIN", @"REPLAYGAIN_ALBUM_GAIN"
    ]];
    return keys;
}

static bool IsKnownMetadataFieldKey(NSString * _Nullable key)
{
    NSString *normalizedKey = UppercaseTrimmedString(key);
    return normalizedKey && [KnownMetadataFieldKeys() containsObject:normalizedKey];
}

static NSInteger NumberTextPreferenceScore(NSString * _Nullable value) {
    NSString *trimmed = TrimmedStringOrNil(value);
    if (!trimmed) {
        return NSIntegerMin;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"/"];
    NSString *leftPart = parts.count > 0 ? parts[0] : trimmed;
    NSString *leftTrimmed = [leftPart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    BOOL hasLeadingZeros = leftTrimmed.length > 1 && [leftTrimmed hasPrefix:@"0"];
    BOOL hasExplicitTotal = [trimmed containsString:@"/"];

    return (hasLeadingZeros ? 1000 : 0)
        + (hasExplicitTotal ? 100 : 0)
        + (NSInteger)trimmed.length;
}

static NSString * _Nullable PreferredNumberText(NSString * _Nullable currentValue,
                                                NSString * _Nullable candidateValue) {
    NSString *trimmedCurrent = TrimmedStringOrNil(currentValue);
    NSString *trimmedCandidate = TrimmedStringOrNil(candidateValue);

    if (!trimmedCandidate) {
        return trimmedCurrent;
    }

    if (!trimmedCurrent) {
        return trimmedCandidate;
    }

    return NumberTextPreferenceScore(trimmedCandidate) > NumberTextPreferenceScore(trimmedCurrent)
        ? trimmedCandidate
        : trimmedCurrent;
}

// Internal-only MP4 freeform atoms used to preserve the user's exact track/disc text
// (for example "01/10") across formats that otherwise normalize numeric pairs.
static constexpr const char *kAudioMatorMP4TrackNumberTextKey = "----:com.apple.iTunes:AUDIOMATOR_TRACKNUMBER_TEXT";
static constexpr const char *kAudioMatorMP4DiscNumberTextKey = "----:com.apple.iTunes:AUDIOMATOR_DISCNUMBER_TEXT";

static bool IsMP4LikeExtension(NSString * _Nullable ext);

typedef NS_ENUM(NSInteger, AudioMatorTagFileFormat) {
    AudioMatorTagFileFormatUnknown = 0,
    AudioMatorTagFileFormatMPEGID3,
    AudioMatorTagFileFormatMPEGAAC,
    AudioMatorTagFileFormatMP4,
    AudioMatorTagFileFormatFLAC,
    AudioMatorTagFileFormatOggVorbis,
    AudioMatorTagFileFormatOggOpus,
    AudioMatorTagFileFormatOggFlac,
    AudioMatorTagFileFormatOggSpeex,
    AudioMatorTagFileFormatAPE,
    AudioMatorTagFileFormatWavPack,
    AudioMatorTagFileFormatMPC,
    AudioMatorTagFileFormatWAV,
    AudioMatorTagFileFormatAIFF,
    AudioMatorTagFileFormatTTA,
    AudioMatorTagFileFormatASF,
    AudioMatorTagFileFormatDSF,
    AudioMatorTagFileFormatDSDIFF,
};

typedef NS_OPTIONS(NSUInteger, AudioMatorMetadataContainerMask) {
    AudioMatorMetadataContainerNone = 0,
    AudioMatorMetadataContainerTag = 1 << 0,
    AudioMatorMetadataContainerPropertyMap = 1 << 1,
    AudioMatorMetadataContainerID3v1 = 1 << 2,
    AudioMatorMetadataContainerID3v2 = 1 << 3,
    AudioMatorMetadataContainerAPE = 1 << 4,
    AudioMatorMetadataContainerMP4ItemMap = 1 << 5,
    AudioMatorMetadataContainerXiph = 1 << 6,
    AudioMatorMetadataContainerASF = 1 << 7,
    AudioMatorMetadataContainerRIFFInfo = 1 << 8,
};

static AudioMatorTagFileFormat DetectTagFileFormat(NSString * _Nullable ext)
{
    if (!ext) return AudioMatorTagFileFormatUnknown;
    NSString *lower = ext.lowercaseString;

    if ([lower isEqualToString:@"mp3"] || [lower isEqualToString:@"mp2"]) {
        return AudioMatorTagFileFormatMPEGID3;
    }
    if ([lower isEqualToString:@"aac"]) {
        return AudioMatorTagFileFormatMPEGAAC;
    }
    if ([lower isEqualToString:@"m4a"] || [lower isEqualToString:@"m4b"] || [lower isEqualToString:@"m4p"] || [lower isEqualToString:@"mp4"]) {
        return AudioMatorTagFileFormatMP4;
    }
    if ([lower isEqualToString:@"flac"]) {
        return AudioMatorTagFileFormatFLAC;
    }
    if ([lower isEqualToString:@"ogg"]) {
        return AudioMatorTagFileFormatOggVorbis;
    }
    if ([lower isEqualToString:@"opus"]) {
        return AudioMatorTagFileFormatOggOpus;
    }
    if ([lower isEqualToString:@"oga"]) {
        return AudioMatorTagFileFormatOggFlac;
    }
    if ([lower isEqualToString:@"spx"]) {
        return AudioMatorTagFileFormatOggSpeex;
    }
    if ([lower isEqualToString:@"ape"]) {
        return AudioMatorTagFileFormatAPE;
    }
    if ([lower isEqualToString:@"wv"]) {
        return AudioMatorTagFileFormatWavPack;
    }
    if ([lower isEqualToString:@"mpc"]) {
        return AudioMatorTagFileFormatMPC;
    }
    if ([lower isEqualToString:@"wav"]) {
        return AudioMatorTagFileFormatWAV;
    }
    if ([lower isEqualToString:@"aiff"] || [lower isEqualToString:@"aif"]) {
        return AudioMatorTagFileFormatAIFF;
    }
    if ([lower isEqualToString:@"tta"]) {
        return AudioMatorTagFileFormatTTA;
    }
    if ([lower isEqualToString:@"wma"] || [lower isEqualToString:@"asf"]) {
        return AudioMatorTagFileFormatASF;
    }
    if ([lower isEqualToString:@"dsf"]) {
        return AudioMatorTagFileFormatDSF;
    }
    if ([lower isEqualToString:@"dff"]) {
        return AudioMatorTagFileFormatDSDIFF;
    }

    return AudioMatorTagFileFormatUnknown;
}

static AudioMatorMetadataContainerMask ContainerMaskForFormat(AudioMatorTagFileFormat format)
{
    switch (format) {
        case AudioMatorTagFileFormatMPEGID3:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerID3v1
                 | AudioMatorMetadataContainerID3v2
                 | AudioMatorMetadataContainerAPE;
        case AudioMatorTagFileFormatMPEGAAC:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap;
        case AudioMatorTagFileFormatMP4:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerMP4ItemMap;
        case AudioMatorTagFileFormatFLAC:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerXiph
                 | AudioMatorMetadataContainerID3v1
                 | AudioMatorMetadataContainerID3v2;
        case AudioMatorTagFileFormatOggVorbis:
        case AudioMatorTagFileFormatOggOpus:
        case AudioMatorTagFileFormatOggFlac:
        case AudioMatorTagFileFormatOggSpeex:
            return AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerXiph;
        case AudioMatorTagFileFormatAPE:
        case AudioMatorTagFileFormatWavPack:
        case AudioMatorTagFileFormatMPC:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerAPE;
        case AudioMatorTagFileFormatWAV:
        case AudioMatorTagFileFormatAIFF:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerID3v2
                 | AudioMatorMetadataContainerRIFFInfo;
        case AudioMatorTagFileFormatTTA:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerID3v1
                 | AudioMatorMetadataContainerID3v2;
        case AudioMatorTagFileFormatASF:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerASF;
        case AudioMatorTagFileFormatDSF:
        case AudioMatorTagFileFormatDSDIFF:
            return AudioMatorMetadataContainerTag
                 | AudioMatorMetadataContainerPropertyMap
                 | AudioMatorMetadataContainerID3v2;
        case AudioMatorTagFileFormatUnknown:
            return AudioMatorMetadataContainerNone;
    }
}

static NSSet<NSString *> *HiddenInternalMetadataFieldKeys()
{
    static NSSet<NSString *> *keys = [NSSet setWithArray:@[
        @"AUDIOMATOR_TRACKNUMBER_TEXT",
        @"AUDIOMATOR_DISCNUMBER_TEXT",
        @"----:COM.APPLE.ITUNES:AUDIOMATOR_TRACKNUMBER_TEXT",
        @"----:COM.APPLE.ITUNES:AUDIOMATOR_DISCNUMBER_TEXT",
    ]];
    return keys;
}

static bool IsHiddenInternalMetadataFieldKey(NSString * _Nullable key)
{
    NSString *normalizedKey = UppercaseTrimmedString(key);
    return normalizedKey && [HiddenInternalMetadataFieldKeys() containsObject:normalizedKey];
}

static NSString * _Nullable RawPropertyValueForCandidateKeys(NSDictionary<NSString *, NSString *> *properties,
                                                             NSArray<NSString *> *candidateKeys)
{
    if (!properties || properties.count == 0 || candidateKeys.count == 0) {
        return nil;
    }

    NSSet<NSString *> *normalizedCandidates = [NSSet setWithArray:candidateKeys];
    for (NSString *rawKey in properties) {
        NSString *normalizedKey = UppercaseTrimmedString(rawKey);
        if (!normalizedKey || ![normalizedCandidates containsObject:normalizedKey]) {
            continue;
        }

        NSString *value = TrimmedStringOrNil(properties[rawKey]);
        if (value) {
            return value;
        }
    }

    return nil;
}

static NSDictionary<NSString *, NSString *> *NormalizedRawPropertiesForWrite(NSDictionary<NSString *, NSString *> *properties,
                                                                             NSString *ext)
{
    NSMutableDictionary<NSString *, NSString *> *normalizedProperties = [NSMutableDictionary dictionary];

    for (NSString *rawKey in properties ?: @{}) {
        NSString *trimmedKey = TrimmedStringOrNil(rawKey);
        NSString *trimmedValue = TrimmedStringOrNil(properties[rawKey]);
        if (!trimmedKey || !trimmedValue) {
            continue;
        }

        if (IsHiddenInternalMetadataFieldKey(trimmedKey)) {
            continue;
        }

        normalizedProperties[trimmedKey] = trimmedValue;
    }

    if (IsMP4LikeExtension(ext)) {
        NSString *trackText = RawPropertyValueForCandidateKeys(normalizedProperties, @[ @"TRACKNUMBER", @"TRACK" ]);
        NSString *discText = RawPropertyValueForCandidateKeys(normalizedProperties, @[ @"DISCNUMBER", @"DISC" ]);

        if (trackText) {
            normalizedProperties[@"AUDIOMATOR_TRACKNUMBER_TEXT"] = trackText;
        }

        if (discText) {
            normalizedProperties[@"AUDIOMATOR_DISCNUMBER_TEXT"] = discText;
        }
    }

    return [normalizedProperties copy];
}

static bool IsMP4LikeExtension(NSString * _Nullable ext) {
    return DetectTagFileFormat(ext) == AudioMatorTagFileFormatMP4;
}

static void SetMP4TextItem(TagLib::MP4::Tag *tag,
                           const char *key,
                           NSString * _Nullable value)
{
    if (!tag || !key) return;

    NSString *trimmed = TrimmedStringOrNil(value);
    if (!trimmed) {
        tag->removeItem(key);
        return;
    }

    TagLib::StringList list;
    list.append(NSStringToTagString(trimmed));
    tag->setItem(key, TagLib::MP4::Item(list));
}

static NSString * _Nullable MP4TextItemValue(const TagLib::MP4::ItemMap &items,
                                             const char *key)
{
    if (!key || !items.contains(key)) {
        return nil;
    }

    return TrimmedStringOrNil(TagStringToNSString(items[key].toStringList().toString(", ")));
}

static void SetMP4IntPairItem(TagLib::MP4::Tag *tag,
                              const char *key,
                              NSInteger number,
                              NSInteger total)
{
    if (!tag || !key) return;

    int first = (number > 0) ? (int)number : 0;
    int second = (total > 0) ? (int)total : 0;

    if (first <= 0 && second <= 0) {
        tag->removeItem(key);
        return;
    }

    tag->setItem(key, TagLib::MP4::Item(first, second));
}

static NSString * _Nullable MP4FreeformDescriptionForItemKey(const TagLib::String &itemKey)
{
    static const std::string prefix = "----:com.apple.iTunes:";
    std::string rawKey = itemKey.to8Bit(true);
    if (rawKey.rfind(prefix, 0) != 0) {
        return nil;
    }

    return TrimmedStringOrNil([NSString stringWithUTF8String:rawKey.substr(prefix.size()).c_str()]);
}

static void SetMP4FreeformTextItem(TagLib::MP4::Tag *tag,
                                   NSString * _Nullable description,
                                   NSString * _Nullable value)
{
    NSString *trimmedDescription = TrimmedStringOrNil(description);
    if (!trimmedDescription) {
        return;
    }

    NSString *fullKey = [@"----:com.apple.iTunes:" stringByAppendingString:trimmedDescription];
    std::string key = fullKey.UTF8String ? fullKey.UTF8String : "";
    if (key.empty()) {
        return;
    }

    SetMP4TextItem(tag, key.c_str(), value);
}

static void SetPropertyMapString(TagLib::PropertyMap &properties,
                                 const char *key,
                                 NSString * _Nullable value)
{
    if (!key) return;

    NSString *trimmed = TrimmedStringOrNil(value);
    if (!trimmed) {
        properties.erase(key);
        return;
    }

    TagLib::StringList values;
    values.append(NSStringToTagString(trimmed));
    properties.replace(key, values);
}

static void SetPropertyMapNumberText(TagLib::PropertyMap &properties,
                                     const char *key,
                                     NSString * _Nullable value)
{
    SetPropertyMapString(properties, key, value);
}

static void SetPropertyMapDynamicString(TagLib::PropertyMap &properties,
                                        NSString * _Nullable key,
                                        NSString * _Nullable value)
{
    NSString *trimmedKey = TrimmedStringOrNil(key);
    if (!trimmedKey) {
        return;
    }

    TagLib::String dynamicKey(trimmedKey.UTF8String, TagLib::String::UTF8);
    NSString *trimmedValue = TrimmedStringOrNil(value);
    if (!trimmedValue) {
        properties.erase(dynamicKey);
        return;
    }

    TagLib::StringList values;
    values.append(NSStringToTagString(trimmedValue));
    properties.replace(dynamicKey, values);
}

static void SetCustomMetadataField(TagLibAudioMetadata *metadata,
                                   NSString * _Nullable key,
                                   NSString * _Nullable value)
{
    if (!metadata) {
        return;
    }

    NSString *trimmedKey = TrimmedStringOrNil(key);
    NSString *trimmedValue = TrimmedStringOrNil(value);
    if (!trimmedKey || !trimmedValue || IsKnownMetadataFieldKey(trimmedKey)) {
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *customFields =
        metadata.customFields ? [metadata.customFields mutableCopy] : [NSMutableDictionary dictionary];
    customFields[trimmedKey] = trimmedValue;
    metadata.customFields = customFields.count > 0 ? [customFields copy] : nil;
}

static void MergeCustomPropertyMapFields(const TagLib::PropertyMap &properties,
                                         TagLibAudioMetadata *metadata)
{
    if (!metadata || properties.isEmpty()) {
        return;
    }

    for (const auto &[key, values] : properties) {
        if (values.isEmpty()) {
            continue;
        }

        NSString *fieldKey = TrimmedStringOrNil(TagStringToNSString(key));
        if (!fieldKey || IsKnownMetadataFieldKey(fieldKey)) {
            continue;
        }

        NSString *fieldValue = TrimmedStringOrNil(TagStringToNSString(values.toString("; ")));
        SetCustomMetadataField(metadata, fieldKey, fieldValue);
    }
}

static void ApplyCustomFieldsToPropertyMap(TagLib::PropertyMap &properties,
                                           NSDictionary<NSString *, NSString *> * _Nullable customFields)
{
    if (!customFields || customFields.count == 0) {
        return;
    }

    for (NSString *key in customFields) {
        if (IsKnownMetadataFieldKey(key)) {
            continue;
        }

        SetPropertyMapDynamicString(properties, key, customFields[key]);
    }
}

static bool ParseExplicitTagValue(const TagLib::String &value, BOOL &explicitContent)
{
    if (value.isEmpty()) {
        return false;
    }

    TagLib::String upper = value.upper();
    std::string raw = upper.to8Bit(true);

    if (upper == "EXPLICIT" || upper == "TRUE" || upper == "YES") {
        explicitContent = YES;
        return true;
    }

    if (upper == "CLEAN" || upper == "FALSE" || upper == "NO" || upper == "NONE") {
        explicitContent = NO;
        return true;
    }

    if (raw == "4" || raw == "1") {
        explicitContent = YES;
        return true;
    }

    if (raw == "2" || raw == "0" || raw == "-1") {
        explicitContent = NO;
        return true;
    }

    return false;
}

static void ApplyExplicitPropertyKeys(const TagLib::PropertyMap &properties,
                                      TagLibAudioMetadata *metadata)
{
    if (!metadata || properties.isEmpty()) return;

    static const char *kExplicitKeys[] = {
        "ITUNESADVISORY",
        "ADVISORY",
        "EXPLICITCONTENT",
        "EXPLICIT"
    };

    for (const char *key : kExplicitKeys) {
        if (!properties.contains(key) || properties[key].isEmpty()) {
            continue;
        }

        for (const auto &explicitCandidate : properties[key]) {
            BOOL explicitValue = metadata.explicitContent;
            if (ParseExplicitTagValue(explicitCandidate, explicitValue)) {
                metadata.explicitContent = explicitValue;
                return;
            }
        }
    }
}

static bool ApplyKnownCustomMetadataField(NSString * _Nullable key,
                                          NSString * _Nullable value,
                                          TagLibAudioMetadata *metadata)
{
    if (!metadata) {
        return false;
    }

    NSString *normalizedKey = UppercaseTrimmedString(key);
    NSString *trimmedValue = TrimmedStringOrNil(value);
    if (!normalizedKey) {
        return false;
    }

    if ([normalizedKey isEqualToString:@"RELEASETYPE"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ ALBUM TYPE"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_ALBUMTYPE"]) {
        metadata.releaseType = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"BARCODE"] ||
        [normalizedKey isEqualToString:@"UPC"] ||
        [normalizedKey isEqualToString:@"EAN"]) {
        metadata.barcode = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"CATALOGNUMBER"] ||
        [normalizedKey isEqualToString:@"CATALOG NUMBER"] ||
        [normalizedKey isEqualToString:@"CATALOG"]) {
        metadata.catalogNumber = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"RELEASECOUNTRY"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ ALBUM RELEASE COUNTRY"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_ALBUMRELEASECOUNTRY"]) {
        metadata.releaseCountry = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ARTISTTYPE"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ ARTIST TYPE"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_ARTISTTYPE"]) {
        metadata.artistType = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MUSICBRAINZ ARTIST ID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ ARTISTID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_ARTISTID"]) {
        metadata.musicBrainzArtistId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MUSICBRAINZ ALBUM ID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ ALBUMID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_ALBUMID"]) {
        metadata.musicBrainzAlbumId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MUSICBRAINZ TRACK ID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ TRACKID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_TRACKID"]) {
        metadata.musicBrainzTrackId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MUSICBRAINZ RELEASE GROUP ID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ RELEASEGROUPID"] ||
        [normalizedKey isEqualToString:@"MUSICBRAINZ_RELEASEGROUPID"]) {
        metadata.musicBrainzReleaseGroupId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"LABEL"]) {
        metadata.label = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"YEAR"]) {
        metadata.year = trimmedValue;
        if (metadata.releaseDate.length == 0 && trimmedValue.length > 0) {
            metadata.releaseDate = trimmedValue;
        }
        return true;
    }

    if ([normalizedKey isEqualToString:@"TRACKNUMBER"] ||
        [normalizedKey isEqualToString:@"TRACK"]) {
        metadata.trackNumberText = PreferredNumberText(metadata.trackNumberText, trimmedValue);
        if (trimmedValue.length > 0) {
            NSInteger trackNum = 0, trackTotal = 0;
            ParseNumberPair(NSStringToTagString(trimmedValue), trackNum, trackTotal);
            if (trackNum > 0) metadata.trackNumber = trackNum;
            if (trackTotal > 0) metadata.totalTracks = trackTotal;
        }
        return true;
    }

    if ([normalizedKey isEqualToString:@"TRACKTOTAL"] ||
        [normalizedKey isEqualToString:@"TOTALTRACKS"]) {
        metadata.totalTracks = trimmedValue.length > 0 ? trimmedValue.integerValue : 0;
        return true;
    }

    if ([normalizedKey isEqualToString:@"DISCNUMBER"] ||
        [normalizedKey isEqualToString:@"DISC"]) {
        metadata.discNumberText = PreferredNumberText(metadata.discNumberText, trimmedValue);
        if (trimmedValue.length > 0) {
            NSInteger discNum = 0, discTotal = 0;
            ParseNumberPair(NSStringToTagString(trimmedValue), discNum, discTotal);
            if (discNum > 0) metadata.discNumber = discNum;
            if (discTotal > 0) metadata.totalDiscs = discTotal;
        }
        return true;
    }

    if ([normalizedKey isEqualToString:@"DISCTOTAL"] ||
        [normalizedKey isEqualToString:@"TOTALDISCS"]) {
        metadata.totalDiscs = trimmedValue.length > 0 ? trimmedValue.integerValue : 0;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ISRC"]) {
        metadata.isrc = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ENCODEDBY"] ||
        [normalizedKey isEqualToString:@"ENCODING"]) {
        metadata.encodedBy = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ENCODERSETTINGS"]) {
        metadata.encoderSettings = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"SUBTITLE"]) {
        metadata.subtitle = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"GROUPING"]) {
        metadata.grouping = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"LYRICIST"]) {
        metadata.lyricist = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"CONDUCTOR"]) {
        metadata.conductor = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"REMIXER"]) {
        metadata.remixer = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"PRODUCER"]) {
        metadata.producer = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ENGINEER"]) {
        metadata.engineer = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MOVEMENT"]) {
        metadata.movement = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MOOD"]) {
        metadata.mood = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"LANGUAGE"]) {
        metadata.language = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"INITIALKEY"] ||
        [normalizedKey isEqualToString:@"KEY"]) {
        metadata.musicalKey = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ORIGINAL YEAR"]) {
        metadata.originalReleaseDate = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"MEDIATYPE"] ||
        [normalizedKey isEqualToString:@"MEDIA TYPE"] ||
        [normalizedKey isEqualToString:@"MEDIA"]) {
        metadata.mediaType = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESALBUMID"]) {
        metadata.itunesAlbumId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESARTISTID"]) {
        metadata.itunesArtistId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESCATALOGID"]) {
        metadata.itunesCatalogId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESGENREID"]) {
        metadata.itunesGenreId = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESMEDIATYPE"]) {
        metadata.itunesMediaType = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESPURCHASEDATE"]) {
        metadata.itunesPurchaseDate = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNNORM"]) {
        metadata.itunesNorm = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNSMPB"]) {
        metadata.itunesSmpb = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"REPLAYGAIN_TRACK_GAIN"]) {
        metadata.replayGainTrack = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"REPLAYGAIN_ALBUM_GAIN"]) {
        metadata.replayGainAlbum = trimmedValue;
        return true;
    }

    if ([normalizedKey isEqualToString:@"ITUNESADVISORY"] ||
        [normalizedKey isEqualToString:@"ADVISORY"] ||
        [normalizedKey isEqualToString:@"EXPLICITCONTENT"] ||
        [normalizedKey isEqualToString:@"EXPLICIT"]) {
        BOOL explicitValue = metadata.explicitContent;
        TagLib::String explicitString(trimmedValue.UTF8String, TagLib::String::UTF8);
        if (ParseExplicitTagValue(explicitString, explicitValue)) {
            metadata.explicitContent = explicitValue;
        }
        return true;
    }

    return false;
}

static TagLib::PropertyMap PreservedUnknownPropertyMapEntries(const TagLib::PropertyMap &existingProperties)
{
    TagLib::PropertyMap properties;
    if (existingProperties.isEmpty()) {
        return properties;
    }

    for (const auto &[key, values] : existingProperties) {
        if (values.isEmpty()) {
            continue;
        }

        NSString *fieldKey = TrimmedStringOrNil(TagStringToNSString(key));
        if (!fieldKey) {
            continue;
        }

        if (IsHiddenInternalMetadataFieldKey(fieldKey) || IsKnownMetadataFieldKey(fieldKey)) {
            continue;
        }

        properties.replace(key, values);
    }

    return properties;
}

static TagLib::PropertyMap BuildGenericPropertyMap(
    TagLibAudioMetadata *metadata,
    const TagLib::PropertyMap * _Nullable existingProperties = nullptr
)
{
    TagLib::PropertyMap properties;
    if (existingProperties) {
        properties = PreservedUnknownPropertyMapEntries(*existingProperties);
    }
    if (!metadata) return properties;

    NSString *yearValue = TrimmedStringOrNil(metadata.year);
    if (!yearValue && metadata.releaseDate.length >= 4) {
        yearValue = [metadata.releaseDate substringToIndex:4];
    }

    SetPropertyMapString(properties, "TITLE", metadata.title);
    SetPropertyMapString(properties, "ARTIST", metadata.artist);
    SetPropertyMapString(properties, "ALBUM", metadata.album);
    SetPropertyMapString(properties, "COMPOSER", metadata.composer);
    SetPropertyMapString(properties, "GENRE", metadata.genre);
    SetPropertyMapString(properties, "COMMENT", metadata.comment);
    SetPropertyMapString(properties, "ALBUMARTIST", metadata.albumArtist);
    SetPropertyMapString(properties, "DATE", metadata.releaseDate.length > 0 ? metadata.releaseDate : metadata.year);
    SetPropertyMapString(properties, "YEAR", yearValue);
    SetPropertyMapString(properties, "ORIGINALDATE", metadata.originalReleaseDate);
    SetPropertyMapString(properties, "COPYRIGHT", metadata.copyright);
    SetPropertyMapString(properties, "LABEL", metadata.label);
    SetPropertyMapString(properties, "LYRICS", metadata.lyrics);
    SetPropertyMapString(properties, "ISRC", metadata.isrc);
    SetPropertyMapString(properties, "ENCODEDBY", metadata.encodedBy);
    SetPropertyMapString(properties, "ENCODERSETTINGS", metadata.encoderSettings);
    SetPropertyMapString(properties, "TITLESORT", metadata.sortTitle);
    SetPropertyMapString(properties, "ARTISTSORT", metadata.sortArtist);
    SetPropertyMapString(properties, "ALBUMSORT", metadata.sortAlbum);
    SetPropertyMapString(properties, "ALBUMARTISTSORT", metadata.sortAlbumArtist);
    SetPropertyMapString(properties, "COMPOSERSORT", metadata.sortComposer);
    SetPropertyMapString(properties, "CONDUCTOR", metadata.conductor);
    SetPropertyMapString(properties, "REMIXER", metadata.remixer);
    SetPropertyMapString(properties, "PRODUCER", metadata.producer);
    SetPropertyMapString(properties, "ENGINEER", metadata.engineer);
    SetPropertyMapString(properties, "LYRICIST", metadata.lyricist);
    SetPropertyMapString(properties, "SUBTITLE", metadata.subtitle);
    SetPropertyMapString(properties, "GROUPING", metadata.grouping);
    SetPropertyMapString(properties, "MOVEMENT", metadata.movement);
    SetPropertyMapString(properties, "MOOD", metadata.mood);
    SetPropertyMapString(properties, "LANGUAGE", metadata.language);
    SetPropertyMapString(properties, "INITIALKEY", metadata.musicalKey);
    SetPropertyMapString(properties, "RELEASETYPE", metadata.releaseType);
    SetPropertyMapString(properties, "BARCODE", metadata.barcode);
    SetPropertyMapString(properties, "CATALOGNUMBER", metadata.catalogNumber);
    SetPropertyMapString(properties, "RELEASECOUNTRY", metadata.releaseCountry);
    SetPropertyMapString(properties, "MUSICBRAINZ_ARTISTTYPE", metadata.artistType);
    SetPropertyMapString(properties, "MUSICBRAINZ_ARTISTID", metadata.musicBrainzArtistId);
    SetPropertyMapString(properties, "MUSICBRAINZ_ALBUMID", metadata.musicBrainzAlbumId);
    SetPropertyMapString(properties, "MUSICBRAINZ_TRACKID", metadata.musicBrainzTrackId);
    SetPropertyMapString(properties, "MUSICBRAINZ_RELEASEGROUPID", metadata.musicBrainzReleaseGroupId);
    SetPropertyMapString(properties, "REPLAYGAIN_TRACK_GAIN", metadata.replayGainTrack);
    SetPropertyMapString(properties, "REPLAYGAIN_ALBUM_GAIN", metadata.replayGainAlbum);
    SetPropertyMapString(properties, "MEDIATYPE", metadata.mediaType);
    SetPropertyMapString(properties, "ITUNESALBUMID", metadata.itunesAlbumId);
    SetPropertyMapString(properties, "ITUNESARTISTID", metadata.itunesArtistId);
    SetPropertyMapString(properties, "ITUNESCATALOGID", metadata.itunesCatalogId);
    SetPropertyMapString(properties, "ITUNESGENREID", metadata.itunesGenreId);
    SetPropertyMapString(properties, "ITUNESMEDIATYPE", metadata.itunesMediaType);
    SetPropertyMapString(properties, "ITUNESPURCHASEDATE", metadata.itunesPurchaseDate);
    SetPropertyMapString(properties, "ITUNNORM", metadata.itunesNorm);
    SetPropertyMapString(properties, "ITUNSMPB", metadata.itunesSmpb);
    SetPropertyMapString(
        properties,
        "BPM",
        metadata.bpm > 0 ? [NSString stringWithFormat:@"%ld", (long)metadata.bpm] : nil
    );
    SetPropertyMapString(properties, "COMPILATION", metadata.compilation ? @"1" : nil);
    SetPropertyMapString(properties, "ITUNESADVISORY", metadata.explicitContent ? @"1" : nil);

    NSString *trackText = TrimmedStringOrNil(metadata.trackNumberText);
    if (!trackText && (metadata.trackNumber > 0 || metadata.totalTracks > 0)) {
        if (metadata.trackNumber > 0 && metadata.totalTracks > 0) {
            trackText = [NSString stringWithFormat:@"%ld/%ld",
                         (long)metadata.trackNumber,
                         (long)metadata.totalTracks];
        } else if (metadata.trackNumber > 0) {
            trackText = [NSString stringWithFormat:@"%ld", (long)metadata.trackNumber];
        }
    }
    SetPropertyMapNumberText(properties, "TRACKNUMBER", trackText);
    SetPropertyMapString(
        properties,
        "TRACKTOTAL",
        metadata.totalTracks > 0 ? [NSString stringWithFormat:@"%ld", (long)metadata.totalTracks] : nil
    );

    NSString *discText = TrimmedStringOrNil(metadata.discNumberText);
    if (!discText && (metadata.discNumber > 0 || metadata.totalDiscs > 0)) {
        if (metadata.discNumber > 0 && metadata.totalDiscs > 0) {
            discText = [NSString stringWithFormat:@"%ld/%ld",
                        (long)metadata.discNumber,
                        (long)metadata.totalDiscs];
        } else if (metadata.discNumber > 0) {
            discText = [NSString stringWithFormat:@"%ld", (long)metadata.discNumber];
        }
    }
    SetPropertyMapNumberText(properties, "DISCNUMBER", discText);
    SetPropertyMapString(
        properties,
        "DISCTOTAL",
        metadata.totalDiscs > 0 ? [NSString stringWithFormat:@"%ld", (long)metadata.totalDiscs] : nil
    );
    ApplyCustomFieldsToPropertyMap(properties, metadata.customFields);

    return properties;
}

static NSString *NormalizedArtworkMimeType(NSString * _Nullable mimeType)
{
    NSString *trimmed = TrimmedStringOrNil(mimeType);
    if (!trimmed) {
        return @"image/png";
    }

    NSString *lower = trimmed.lowercaseString;
    if ([lower isEqualToString:@"image/jpg"]) {
        return @"image/jpeg";
    }

    return lower;
}

static TagLib::List<TagLib::VariantMap> BuildPictureComplexProperties(TagLibAudioMetadata *metadata)
{
    TagLib::List<TagLib::VariantMap> pictures;
    if (!metadata || metadata.artworkData.length == 0) {
        return pictures;
    }

    TagLib::VariantMap picture;
    picture.insert("data", TagLib::ByteVector((const char *)metadata.artworkData.bytes,
                                               (unsigned int)metadata.artworkData.length));
    picture.insert("mimeType", NSStringToTagString(NormalizedArtworkMimeType(metadata.artworkMimeType)));
    picture.insert("pictureType", NSStringToTagString(@"Front Cover"));
    pictures.append(picture);

    return pictures;
}

template <typename ComplexPropertyTarget>
static bool ApplyPictureComplexProperties(ComplexPropertyTarget *target,
                                          TagLibAudioMetadata *metadata,
                                          NSError **error,
                                          NSInteger clearErrorCode,
                                          NSString *clearErrorMessage,
                                          NSInteger writeErrorCode,
                                          NSString *writeErrorMessage,
                                          NSString *logContext)
{
    if (!target || !metadata) {
        return true;
    }

    if (metadata.removeArtwork) {
        if (!target->setComplexProperties("PICTURE", TagLib::List<TagLib::VariantMap>())) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:clearErrorCode
                                         userInfo:@{ NSLocalizedDescriptionKey : clearErrorMessage }];
            }
            TLog(@"Failed to clear artwork for %@ via complex properties", logContext);
            return false;
        }
    } else if (metadata.artworkData.length > 0) {
        if (!target->setComplexProperties("PICTURE", BuildPictureComplexProperties(metadata))) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:writeErrorCode
                                         userInfo:@{ NSLocalizedDescriptionKey : writeErrorMessage }];
            }
            TLog(@"Failed to write artwork for %@ via complex properties", logContext);
            return false;
        }
    }

    return true;
}

template <typename ComplexPropertyTarget>
static void ExtractArtworkFromComplexProperties(ComplexPropertyTarget *target,
                                                TagLibAudioMetadata *metadata)
{
    if (!target || !metadata || metadata.artworkData.length > 0) {
        return;
    }

    TagLib::List<TagLib::VariantMap> pictures = target->complexProperties("PICTURE");
    if (pictures.isEmpty()) {
        return;
    }

    TagLib::ByteVector fallbackData;
    NSString *fallbackMimeType = nil;

    for (const auto &picture : pictures) {
        TagLib::ByteVector imageData = picture.value("data").value<TagLib::ByteVector>();
        if (imageData.isEmpty()) {
            continue;
        }

        NSString *mimeType = TagStringToNSString(picture.value("mimeType").value<TagLib::String>());
        TagLib::String pictureType = picture.value("pictureType").value<TagLib::String>();

        if (fallbackData.isEmpty()) {
            fallbackData = imageData;
            fallbackMimeType = mimeType;
        }

        if (pictureType.isEmpty() || pictureType.upper() == "FRONT COVER") {
            metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
            metadata.artworkMimeType = mimeType;
            return;
        }
    }

    if (!fallbackData.isEmpty()) {
        metadata.artworkData = [NSData dataWithBytes:fallbackData.data() length:fallbackData.size()];
        metadata.artworkMimeType = fallbackMimeType;
    }
}

template <typename FileType>
static void ApplyGenericPropertyMapToFile(FileType &file, TagLibAudioMetadata *metadata)
{
    TagLib::PropertyMap existingProperties = file.properties();
    TagLib::PropertyMap properties = BuildGenericPropertyMap(metadata, &existingProperties);
    file.setProperties(properties);
}

static TagLib::PropertyMap BuildRawPropertyMap(NSDictionary<NSString *, NSString *> *properties)
{
    TagLib::PropertyMap propertyMap;

    if (!properties || properties.count == 0) {
        return propertyMap;
    }

    for (NSString *key in properties) {
        NSString *trimmedKey = TrimmedStringOrNil(key);
        NSString *trimmedValue = TrimmedStringOrNil(properties[key]);
        if (!trimmedKey || !trimmedValue) {
            continue;
        }

        SetPropertyMapDynamicString(propertyMap, trimmedKey, trimmedValue);
    }

    return propertyMap;
}

static void AppendRawPropertyEntries(NSMutableArray<NSDictionary<NSString *, NSObject *> *> *propertiesOut,
                                     const TagLib::PropertyMap &propertyMap)
{
    if (!propertiesOut) {
        return;
    }

    for (auto pit = propertyMap.begin(); pit != propertyMap.end(); ++pit) {
        NSString *nsKey = TagStringToNSString(pit->first) ?: @"";
        if (IsHiddenInternalMetadataFieldKey(nsKey)) {
            continue;
        }

        NSMutableArray<NSString *> *values = [NSMutableArray array];
        for (auto vit = pit->second.begin(); vit != pit->second.end(); ++vit) {
            [values addObject:(TagStringToNSString(*vit) ?: @"")];
        }
        NSString *joined = values.count ? [values componentsJoinedByString:@"; "] : @"";
        [propertiesOut addObject:@{ @"key": nsKey, @"value": joined, @"values": values, @"count": @(values.count) }];
    }
}

template <typename FileType>
static BOOL WriteRawPropertyMapToFile(FileType &file,
                                      NSDictionary<NSString *, NSString *> *properties,
                                      NSError **error,
                                      NSInteger openErrorCode,
                                      NSString *openErrorMessage,
                                      NSInteger saveErrorCode,
                                      NSString *saveErrorMessage,
                                      NSString *logContext)
{
    if (!file.isValid()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:openErrorCode
                                     userInfo:@{ NSLocalizedDescriptionKey : openErrorMessage }];
        }
        TLog(@"Failed to open %@ for raw property-map writing", logContext);
        return NO;
    }

    file.setProperties(BuildRawPropertyMap(properties));

    if (!file.save()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:saveErrorCode
                                     userInfo:@{ NSLocalizedDescriptionKey : saveErrorMessage }];
        }
        TLog(@"TagLib save() failed after raw property-map write for %@", logContext);
        return NO;
    }

    return YES;
}

template <typename FileType>
static bool WritePropertyMapNumberTextToFile(FileType &file,
                                             NSString * _Nullable trackNumberText,
                                             NSString * _Nullable discNumberText,
                                             NSError **error,
                                             NSInteger openErrorCode,
                                             NSString *openErrorMessage,
                                             NSInteger saveErrorCode,
                                             NSString *saveErrorMessage,
                                             NSString *logContext)
{
    if (!file.isValid()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:openErrorCode
                                     userInfo:@{ NSLocalizedDescriptionKey : openErrorMessage }];
        }
        TLog(@"Failed to open %@ for track/disc write", logContext);
        return false;
    }

    TagLib::PropertyMap properties = file.properties();
    SetPropertyMapNumberText(properties, "TRACKNUMBER", trackNumberText);
    if (discNumberText != nil) {
        SetPropertyMapNumberText(properties, "DISCNUMBER", discNumberText);
    }
    file.setProperties(properties);

    if (!file.save()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:saveErrorCode
                                     userInfo:@{ NSLocalizedDescriptionKey : saveErrorMessage }];
        }
        TLog(@"TagLib save() failed after track/disc write for %@", logContext);
        return false;
    }

    return true;
}

// Ensure an ID3v2 text frame exists and set its text
static void SetID3v2TextFrame(TagLib::ID3v2::Tag *tag,
                              const char *frameID,
                              NSString * _Nullable value) {
    if (!tag || !frameID) {
        return;
    }
    NSString *trimmed = TrimmedStringOrNil(value);
    TagLib::ID3v2::FrameList frames = tag->frameList(frameID);

    if (!trimmed) {
        for (auto it = frames.begin(); it != frames.end(); ++it) {
            tag->removeFrame(*it);
        }
        return;
    }

    TagLib::ID3v2::TextIdentificationFrame *textFrame = nullptr;
    
    if (!frames.isEmpty()) {
        textFrame = dynamic_cast<TagLib::ID3v2::TextIdentificationFrame *>(frames.front());
    }
    
    TagLib::String tValue(trimmed.UTF8String, TagLib::String::UTF8);
    
    if (!textFrame) {
        TagLib::ByteVector id(frameID, 4);
        textFrame = new TagLib::ID3v2::TextIdentificationFrame(id, TagLib::String::UTF8);
        tag->addFrame(textFrame);
    }
    
    textFrame->setText(tValue);
}

// Ensure an ID3v2 user text frame (TXXX) with given description exists and set its text
static void SetID3v2UserTextFrame(TagLib::ID3v2::Tag *tag,
                                  const char *description,
                                  NSString * _Nullable value)
{
    if (!tag || !description) {
        return;
    }

    TagLib::String descStr(description, TagLib::String::UTF8);

    // Find existing TXXX frame with matching description
    TagLib::ID3v2::FrameList frames = tag->frameList("TXXX");
    TagLib::ID3v2::UserTextIdentificationFrame *userFrame = nullptr;

    for (auto it = frames.begin(); it != frames.end(); ++it) {
        auto *f = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(*it);
        if (!f) continue;
        if (f->description().upper() == descStr.upper()) {
            userFrame = f;
            break;
        }
    }

    // If the value is empty or nil, remove the frame (clear the field)
    if (!value || value.length == 0) {
        if (userFrame) {
            tag->removeFrame(userFrame);
        }
        return;
    }

    TagLib::String tValue(value.UTF8String, TagLib::String::UTF8);
    TagLib::StringList textList;
    textList.append(tValue);

    if (!userFrame) {
        // Create a new TXXX frame with the given description
        userFrame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::UTF8);
        userFrame->setDescription(descStr);
        tag->addFrame(userFrame);
    }

    userFrame->setText(textList);
}

static void SetID3v2LyricsFrame(TagLib::ID3v2::Tag *tag,
                                NSString * _Nullable value)
{
    if (!tag) {
        return;
    }

    NSString *trimmed = TrimmedStringOrNil(value);
    TagLib::ID3v2::FrameList frames = tag->frameList("USLT");
    for (auto it = frames.begin(); it != frames.end(); ++it) {
        tag->removeFrame(*it);
    }

    if (!trimmed) {
        return;
    }

    auto *lyricsFrame = new TagLib::ID3v2::UnsynchronizedLyricsFrame(TagLib::String::UTF8);
    lyricsFrame->setDescription(TagLib::String());
    lyricsFrame->setLanguage(TagLib::ByteVector("eng", 3));
    lyricsFrame->setText(NSStringToTagString(trimmed));
    tag->addFrame(lyricsFrame);
}

static void ApplyCustomFieldsToID3v2Tag(TagLib::ID3v2::Tag *tag,
                                        NSDictionary<NSString *, NSString *> * _Nullable customFields)
{
    if (!tag) {
        return;
    }

    if (!customFields || customFields.count == 0) {
        return;
    }

    // Preserve unknown TXXX frames by default; only upsert keys explicitly
    // provided by the current edit payload.
    for (NSString *key in customFields) {
        if (IsKnownMetadataFieldKey(key)) {
            continue;
        }

        SetID3v2UserTextFrame(tag, key.UTF8String, customFields[key]);
    }
}

static void ApplyCustomFieldsToMP4Tag(TagLib::MP4::Tag *tag,
                                      NSDictionary<NSString *, NSString *> * _Nullable customFields)
{
    if (!tag) {
        return;
    }

    if (!customFields || customFields.count == 0) {
        return;
    }

    // Preserve unknown freeform atoms by default; only upsert keys explicitly
    // provided by the current edit payload.
    for (NSString *key in customFields) {
        if (IsKnownMetadataFieldKey(key)) {
            continue;
        }

        SetMP4FreeformTextItem(tag, key, customFields[key]);
    }
}

static NSString * _Nullable FirstStringFromProperty(const TagLib::PropertyMap &properties,
                                                    std::initializer_list<const char *> keys,
                                                    bool joinMultipleValues = false)
{
    for (const char *key : keys) {
        if (!key) continue;
        if (properties.contains(key) && !properties[key].isEmpty()) {
            NSMutableArray<NSString *> *trimmedValues = [NSMutableArray array];
            for (const auto &value : properties[key]) {
                NSString *trimmed = TrimmedStringOrNil(TagStringToNSString(value));
                if (trimmed) {
                    [trimmedValues addObject:trimmed];
                }
            }

            if (trimmedValues.count == 0) {
                continue;
            }

            if (joinMultipleValues && trimmedValues.count > 1) {
                return [trimmedValues componentsJoinedByString:@"; "];
            }

            return trimmedValues.firstObject;
        }
    }
    return nil;
}

static void ApplyGenericPropertyMapMetadata(const TagLib::PropertyMap &properties,
                                            TagLibAudioMetadata *metadata)
{
    if (!metadata || properties.isEmpty()) return;

    metadata.title = FirstStringFromProperty(properties, {"TITLE"}) ?: metadata.title;
    metadata.artist = FirstStringFromProperty(properties, {"ARTIST", "ARTISTS"}, true) ?: metadata.artist;
    metadata.album = FirstStringFromProperty(properties, {"ALBUM"}) ?: metadata.album;
    metadata.comment = FirstStringFromProperty(properties, {"COMMENT"}) ?: metadata.comment;
    metadata.genre = FirstStringFromProperty(properties, {"GENRE"}, true) ?: metadata.genre;
    metadata.composer = FirstStringFromProperty(properties, {"COMPOSER"}, true) ?: metadata.composer;
    metadata.albumArtist = FirstStringFromProperty(properties, {"ALBUMARTIST"}, true) ?: metadata.albumArtist;

    NSString *dateValue = FirstStringFromProperty(properties, {"RELEASEDATE", "DATE", "YEAR"});
    if (dateValue.length > 0) {
        metadata.releaseDate = dateValue;
        if (metadata.year.length == 0 && dateValue.length >= 4) {
            metadata.year = [dateValue substringToIndex:4];
        }
    }

    NSString *originalDate = FirstStringFromProperty(properties, {"ORIGINALDATE"});
    if (originalDate.length > 0) {
        metadata.originalReleaseDate = originalDate;
    }

    const char *trackKey = nullptr;
    if (properties.contains("TRACKNUMBER") && !properties["TRACKNUMBER"].isEmpty()) {
        trackKey = "TRACKNUMBER";
    } else if (properties.contains("TRACK") && !properties["TRACK"].isEmpty()) {
        trackKey = "TRACK";
    }
    if (trackKey) {
        for (const auto &trackValue : properties[trackKey]) {
            NSString *trackText = TrimmedStringOrNil(TagStringToNSString(trackValue));
            NSInteger trackNum = 0, trackTotal = 0;
            ParseNumberPair(trackValue, trackNum, trackTotal);
            metadata.trackNumberText = PreferredNumberText(metadata.trackNumberText, trackText);
            if (trackNum > 0) metadata.trackNumber = trackNum;
            if (trackTotal > 0) metadata.totalTracks = trackTotal;
        }
    }
    NSString *trackTotalValue = FirstStringFromProperty(properties, {"TRACKTOTAL", "TOTALTRACKS"});
    if (trackTotalValue.length > 0) metadata.totalTracks = trackTotalValue.integerValue;

    const char *discKey = nullptr;
    if (properties.contains("DISCNUMBER") && !properties["DISCNUMBER"].isEmpty()) {
        discKey = "DISCNUMBER";
    } else if (properties.contains("DISC") && !properties["DISC"].isEmpty()) {
        discKey = "DISC";
    }
    if (discKey) {
        for (const auto &discValue : properties[discKey]) {
            NSString *discText = TrimmedStringOrNil(TagStringToNSString(discValue));
            NSInteger discNum = 0, discTotal = 0;
            ParseNumberPair(discValue, discNum, discTotal);
            metadata.discNumberText = PreferredNumberText(metadata.discNumberText, discText);
            if (discNum > 0) metadata.discNumber = discNum;
            if (discTotal > 0) metadata.totalDiscs = discTotal;
        }
    }
    NSString *discTotalValue = FirstStringFromProperty(properties, {"DISCTOTAL", "TOTALDISCS"});
    if (discTotalValue.length > 0) metadata.totalDiscs = discTotalValue.integerValue;

    NSString *copyrightValue = FirstStringFromProperty(properties, {"COPYRIGHT"});
    if (copyrightValue.length > 0) metadata.copyright = copyrightValue;

    NSString *lyricsValue = FirstStringFromProperty(properties, {"LYRICS"}, true);
    if (lyricsValue.length > 0) metadata.lyrics = lyricsValue;

    NSString *labelValue = FirstStringFromProperty(properties, {"LABEL"});
    if (labelValue.length > 0) metadata.label = labelValue;

    NSString *isrcValue = FirstStringFromProperty(properties, {"ISRC"});
    if (isrcValue.length > 0) metadata.isrc = isrcValue;

    NSString *encodedByValue = FirstStringFromProperty(properties, {"ENCODEDBY", "ENCODING"});
    if (encodedByValue.length > 0) metadata.encodedBy = encodedByValue;
    NSString *encoderSettingsValue = FirstStringFromProperty(properties, {"ENCODERSETTINGS"});
    if (encoderSettingsValue.length > 0) metadata.encoderSettings = encoderSettingsValue;

    NSString *sortTitle = FirstStringFromProperty(properties, {"TITLESORT"});
    if (sortTitle.length > 0) metadata.sortTitle = sortTitle;
    NSString *sortArtist = FirstStringFromProperty(properties, {"ARTISTSORT"});
    if (sortArtist.length > 0) metadata.sortArtist = sortArtist;
    NSString *sortAlbum = FirstStringFromProperty(properties, {"ALBUMSORT"});
    if (sortAlbum.length > 0) metadata.sortAlbum = sortAlbum;
    NSString *sortAlbumArtist = FirstStringFromProperty(properties, {"ALBUMARTISTSORT"});
    if (sortAlbumArtist.length > 0) metadata.sortAlbumArtist = sortAlbumArtist;
    NSString *sortComposer = FirstStringFromProperty(properties, {"COMPOSERSORT"});
    if (sortComposer.length > 0) metadata.sortComposer = sortComposer;

    NSString *groupingValue = FirstStringFromProperty(properties, {"GROUPING"}, true);
    if (groupingValue.length > 0) metadata.grouping = groupingValue;

    NSString *subtitleValue = FirstStringFromProperty(properties, {"SUBTITLE"});
    if (subtitleValue.length > 0) metadata.subtitle = subtitleValue;

    NSString *lyricistValue = FirstStringFromProperty(properties, {"LYRICIST"}, true);
    if (lyricistValue.length > 0) metadata.lyricist = lyricistValue;

    NSString *conductorValue = FirstStringFromProperty(properties, {"CONDUCTOR"}, true);
    if (conductorValue.length > 0) metadata.conductor = conductorValue;

    NSString *remixerValue = FirstStringFromProperty(properties, {"REMIXER"}, true);
    if (remixerValue.length > 0) metadata.remixer = remixerValue;

    NSString *producerValue = FirstStringFromProperty(properties, {"PRODUCER"}, true);
    if (producerValue.length > 0) metadata.producer = producerValue;

    NSString *engineerValue = FirstStringFromProperty(properties, {"ENGINEER"}, true);
    if (engineerValue.length > 0) metadata.engineer = engineerValue;
    NSString *movementValue = FirstStringFromProperty(properties, {"MOVEMENT"});
    if (movementValue.length > 0) metadata.movement = movementValue;

    NSString *moodValue = FirstStringFromProperty(properties, {"MOOD"}, true);
    if (moodValue.length > 0) metadata.mood = moodValue;

    NSString *languageValue = FirstStringFromProperty(properties, {"LANGUAGE"}, true);
    if (languageValue.length > 0) metadata.language = languageValue;
    NSString *musicalKeyValue = FirstStringFromProperty(properties, {"INITIALKEY", "KEY"});
    if (musicalKeyValue.length > 0) metadata.musicalKey = musicalKeyValue;

    NSString *releaseTypeValue = FirstStringFromProperty(properties, {"RELEASETYPE"});
    if (releaseTypeValue.length > 0) metadata.releaseType = releaseTypeValue;

    NSString *barcodeValue = FirstStringFromProperty(properties, {"BARCODE", "UPC", "EAN"});
    if (barcodeValue.length > 0) metadata.barcode = barcodeValue;

    NSString *catalogValue = FirstStringFromProperty(properties, {"CATALOGNUMBER"});
    if (catalogValue.length > 0) metadata.catalogNumber = catalogValue;

    NSString *releaseCountryValue = FirstStringFromProperty(properties, {"RELEASECOUNTRY"});
    if (releaseCountryValue.length > 0) metadata.releaseCountry = releaseCountryValue;
    NSString *artistTypeValue = FirstStringFromProperty(properties, {"MUSICBRAINZ_ARTISTTYPE", "ARTISTTYPE"});
    if (artistTypeValue.length > 0) metadata.artistType = artistTypeValue;

    NSString *mbArtistValue = FirstStringFromProperty(properties, {"MUSICBRAINZ_ARTISTID"});
    if (mbArtistValue.length > 0) metadata.musicBrainzArtistId = mbArtistValue;
    NSString *mbAlbumValue = FirstStringFromProperty(properties, {"MUSICBRAINZ_ALBUMID"});
    if (mbAlbumValue.length > 0) metadata.musicBrainzAlbumId = mbAlbumValue;
    NSString *mbTrackValue = FirstStringFromProperty(properties, {"MUSICBRAINZ_TRACKID"});
    if (mbTrackValue.length > 0) metadata.musicBrainzTrackId = mbTrackValue;
    NSString *mbReleaseGroupValue = FirstStringFromProperty(properties, {"MUSICBRAINZ_RELEASEGROUPID"});
    if (mbReleaseGroupValue.length > 0) metadata.musicBrainzReleaseGroupId = mbReleaseGroupValue;

    NSString *replayGainTrackValue = FirstStringFromProperty(properties, {"REPLAYGAIN_TRACK_GAIN"});
    if (replayGainTrackValue.length > 0) metadata.replayGainTrack = replayGainTrackValue;
    NSString *replayGainAlbumValue = FirstStringFromProperty(properties, {"REPLAYGAIN_ALBUM_GAIN"});
    if (replayGainAlbumValue.length > 0) metadata.replayGainAlbum = replayGainAlbumValue;

    NSString *mediaTypeValue = FirstStringFromProperty(properties, {"MEDIATYPE", "MEDIA", "MEDIA TYPE"});
    if (mediaTypeValue.length > 0) metadata.mediaType = mediaTypeValue;

    NSString *itunesAlbumIdValue = FirstStringFromProperty(properties, {"ITUNESALBUMID"});
    if (itunesAlbumIdValue.length > 0) metadata.itunesAlbumId = itunesAlbumIdValue;
    NSString *itunesArtistIdValue = FirstStringFromProperty(properties, {"ITUNESARTISTID"});
    if (itunesArtistIdValue.length > 0) metadata.itunesArtistId = itunesArtistIdValue;
    NSString *itunesCatalogIdValue = FirstStringFromProperty(properties, {"ITUNESCATALOGID"});
    if (itunesCatalogIdValue.length > 0) metadata.itunesCatalogId = itunesCatalogIdValue;
    NSString *itunesGenreIdValue = FirstStringFromProperty(properties, {"ITUNESGENREID"});
    if (itunesGenreIdValue.length > 0) metadata.itunesGenreId = itunesGenreIdValue;
    NSString *itunesMediaTypeValue = FirstStringFromProperty(properties, {"ITUNESMEDIATYPE"});
    if (itunesMediaTypeValue.length > 0) metadata.itunesMediaType = itunesMediaTypeValue;
    NSString *itunesPurchaseDateValue = FirstStringFromProperty(properties, {"ITUNESPURCHASEDATE"});
    if (itunesPurchaseDateValue.length > 0) metadata.itunesPurchaseDate = itunesPurchaseDateValue;
    NSString *itunesNormValue = FirstStringFromProperty(properties, {"ITUNNORM"});
    if (itunesNormValue.length > 0) metadata.itunesNorm = itunesNormValue;
    NSString *itunesSmpbValue = FirstStringFromProperty(properties, {"ITUNSMPB"});
    if (itunesSmpbValue.length > 0) metadata.itunesSmpb = itunesSmpbValue;

    if (properties.contains("BPM") && !properties["BPM"].isEmpty()) {
        metadata.bpm = ExtractNumber(properties["BPM"].front());
    }

    if (properties.contains("COMPILATION") && !properties["COMPILATION"].isEmpty()) {
        TagLib::String comp = properties["COMPILATION"].front();
        metadata.compilation = (comp == "1" || comp.upper() == "TRUE");
    }

    ApplyExplicitPropertyKeys(properties, metadata);
    MergeCustomPropertyMapFields(properties, metadata);
}

#pragma mark - Format-Specific Extraction

// Extract ID3v2 metadata (MP3)
static void ExtractID3v2Metadata(TagLib::ID3v2::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;

    // Prefer ID3v2's basic fields over any generic/ID3v1 fallback values that may
    // have been populated earlier through FileRef.tag() or the file property map.
    ApplyPreferredBasicTagMetadata(tag, metadata);
    
    const TagLib::ID3v2::FrameList& frames = tag->frameList();
    
    for (auto it = frames.begin(); it != frames.end(); ++it) {
        TagLib::ID3v2::Frame* frame = *it;
        TagLib::ByteVector frameID = frame->frameID();
        std::string frameIDStr(frameID.data(), frameID.size());
        
        // User-defined text frames (TXXX) - handle these before generic text frames
        // because UserTextIdentificationFrame is also a TextIdentificationFrame.
        if (auto userFrame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame*>(frame)) {
            TagLib::String description = userFrame->description();
            TagLib::StringList userFields = userFrame->fieldList();
            if (userFields.isEmpty()) {
                continue;
            }
            TagLib::String userValue = userFields.back();
            NSString *descriptionString = TagStringToNSString(description);
            NSString *userValueString = TagStringToNSString(userValue);

            if (!ApplyKnownCustomMetadataField(descriptionString, userValueString, metadata)) {
                SetCustomMetadataField(metadata, descriptionString, userValueString);
            }
        }
        // Text identification frames
        else if (auto textFrame = dynamic_cast<TagLib::ID3v2::TextIdentificationFrame*>(frame)) {
            TagLib::StringList fieldList = textFrame->fieldList();
            if (fieldList.isEmpty()) continue;
            
            TagLib::String value = fieldList.toString(", ");

            if (frameIDStr == "TIT2") {
                metadata.title = TagStringToNSString(value);
            }
            else if (frameIDStr == "TPE1") {
                metadata.artist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TALB") {
                metadata.album = TagStringToNSString(value);
            }
            else if (frameIDStr == "TCOM") {
                metadata.composer = TagStringToNSString(value);
            }
            else if (frameIDStr == "TCON") {
                metadata.genre = TagStringToNSString(value);
            }
            // Track number
            else if (frameIDStr == "TRCK") {
                NSInteger trackNum = 0, trackTotal = 0;
                ParseNumberPair(value, trackNum, trackTotal);
                metadata.trackNumberText = PreferredNumberText(
                    metadata.trackNumberText,
                    TagStringToNSString(value)
                );
                metadata.trackNumber = trackNum;
                metadata.totalTracks = trackTotal;
            }
            // Disc number
            else if (frameIDStr == "TPOS") {
                NSInteger discNum = 0, discTotal = 0;
                ParseNumberPair(value, discNum, discTotal);
                metadata.discNumberText = PreferredNumberText(
                    metadata.discNumberText,
                    TagStringToNSString(value)
                );
                metadata.discNumber = discNum;
                metadata.totalDiscs = discTotal;
            }
            // BPM
            else if (frameIDStr == "TBPM") {
                metadata.bpm = value.toInt();
            }
            // Album Artist
            else if (frameIDStr == "TPE2") {
                metadata.albumArtist = TagStringToNSString(value);
            }
            // Sort fields
            else if (frameIDStr == "TSOT") {
                metadata.sortTitle = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSOP") {
                metadata.sortArtist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSOA") {
                metadata.sortAlbum = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSO2") {
                metadata.sortAlbumArtist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSOC") {
                metadata.sortComposer = TagStringToNSString(value);
            }
            // Date fields
            else if (frameIDStr == "TDRL") {
                metadata.releaseDate = TagStringToNSString(value);
            }
            else if (frameIDStr == "TDRC") {
                NSString *dateValue = TagStringToNSString(value);
                if (dateValue.length > 0) {
                    if (metadata.year.length == 0 && dateValue.length >= 4) {
                        metadata.year = [dateValue substringToIndex:4];
                    }
                    if (metadata.releaseDate.length == 0) {
                        metadata.releaseDate = dateValue;
                    }
                }
            }
            else if (frameIDStr == "TYER") {
                NSString *yearValue = TagStringToNSString(value);
                if (yearValue.length > 0) {
                    metadata.year = yearValue;
                    if (metadata.releaseDate.length == 0) {
                        metadata.releaseDate = yearValue;
                    }
                }
            }
            else if (frameIDStr == "TDOR") {
                metadata.originalReleaseDate = TagStringToNSString(value);
            }
            // Personnel
            else if (frameIDStr == "TPE3") {
                metadata.conductor = TagStringToNSString(value);
            }
            else if (frameIDStr == "TPE4") {
                metadata.remixer = TagStringToNSString(value);
            }
            else if (frameIDStr == "TEXT") {
                metadata.lyricist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TPUB") {
                metadata.label = TagStringToNSString(value);
            }
            else if (frameIDStr == "TENC") {
                metadata.encodedBy = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSSE") {
                metadata.encoderSettings = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSRC") {
                metadata.isrc = TagStringToNSString(value);
            }
            else if (frameIDStr == "TCOP") {
                metadata.copyright = TagStringToNSString(value);
            }
            else if (frameIDStr == "TIT3") {
                metadata.subtitle = TagStringToNSString(value);
            }
            else if (frameIDStr == "TIT1") {
                metadata.grouping = TagStringToNSString(value);
            }
            else if (frameIDStr == "TLAN") {
                metadata.language = TagStringToNSString(value);
            }
            else if (frameIDStr == "TKEY") {
                metadata.musicalKey = TagStringToNSString(value);
            }
            else if (frameIDStr == "TMOO") {
                metadata.mood = TagStringToNSString(value);
            }
            else if (frameIDStr == "TMED") {
                metadata.mediaType = TagStringToNSString(value);
            }
            else if (frameIDStr == "MVNM") {
                metadata.movement = TagStringToNSString(value);
            }
            // Compilation flag
            else if (frameIDStr == "TCMP") {
                metadata.compilation = (value == "1");
            }
        }
        // Comments
        else if (auto commFrame = dynamic_cast<TagLib::ID3v2::CommentsFrame*>(frame)) {
            if (metadata.comment == nil) {
                metadata.comment = TagStringToNSString(commFrame->text());
            }
        }
        // Lyrics
        else if (auto lyricsFrame = dynamic_cast<TagLib::ID3v2::UnsynchronizedLyricsFrame*>(frame)) {
            if (metadata.lyrics == nil) {
                metadata.lyrics = TagStringToNSString(lyricsFrame->text());
            }
        }
        // Attached picture (album art)
        else if (auto picFrame = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(frame)) {
            if (metadata.artworkData == nil &&
                picFrame->type() == TagLib::ID3v2::AttachedPictureFrame::FrontCover) {
                TagLib::ByteVector picData = picFrame->picture();
                metadata.artworkData = [NSData dataWithBytes:picData.data() length:picData.size()];
                metadata.artworkMimeType = TagStringToNSString(picFrame->mimeType());
            }
        }
    }
}

// Extract MP4 metadata
static void ExtractMP4Metadata(TagLib::MP4::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    ApplyGenericPropertyMapMetadata(tag->properties(), metadata);

    const TagLib::MP4::ItemMap& items = tag->itemMap();
    metadata.trackNumberText = PreferredNumberText(
        metadata.trackNumberText,
        MP4TextItemValue(items, kAudioMatorMP4TrackNumberTextKey)
    );
    metadata.discNumberText = PreferredNumberText(
        metadata.discNumberText,
        MP4TextItemValue(items, kAudioMatorMP4DiscNumberTextKey)
    );
    
    // Track number
    if (items.contains("trkn")) {
        TagLib::MP4::Item::IntPair trackPair = items["trkn"].toIntPair();
        metadata.trackNumber = trackPair.first;
        metadata.totalTracks = trackPair.second;
        if (metadata.trackNumberText.length == 0 && trackPair.first > 0) {
            metadata.trackNumberText = trackPair.second > 0
                ? [NSString stringWithFormat:@"%d/%d", trackPair.first, trackPair.second]
                : [NSString stringWithFormat:@"%d", trackPair.first];
        }
    }
    
    // Disc number
    if (items.contains("disk")) {
        TagLib::MP4::Item::IntPair discPair = items["disk"].toIntPair();
        metadata.discNumber = discPair.first;
        metadata.totalDiscs = discPair.second;
        if (metadata.discNumberText.length == 0 && discPair.first > 0) {
            metadata.discNumberText = discPair.second > 0
                ? [NSString stringWithFormat:@"%d/%d", discPair.first, discPair.second]
                : [NSString stringWithFormat:@"%d", discPair.first];
        }
    }
    
    // BPM
    if (items.contains("tmpo")) {
        metadata.bpm = items["tmpo"].toInt();
    }
    
    // Album Artist
    if (items.contains("aART")) {
        metadata.albumArtist = TagStringToNSString(items["aART"].toStringList().toString(", "));
    }

    // Composer
    if (items.contains("\xA9" "wrt")) {
        metadata.composer = TagStringToNSString(items["\xA9" "wrt"].toStringList().toString(", "));
    }
    
    // Compilation
    if (items.contains("cpil")) {
        metadata.compilation = items["cpil"].toBool();
    }

    // Explicit rating (rtng atom: 0 = none, 2 = clean, 4 = explicit)
    if (items.contains("rtng")) {
        const TagLib::MP4::Item &ratingItem = items["rtng"];
        BOOL explicitValue = metadata.explicitContent;
        std::string ratingRaw = std::to_string(ratingItem.toInt());
        TagLib::String ratingString(ratingRaw.c_str(), TagLib::String::UTF8);
        if (ParseExplicitTagValue(ratingString, explicitValue)) {
            metadata.explicitContent = explicitValue;
        }
    }

    if (items.contains("----:com.apple.iTunes:ITUNESADVISORY")) {
        TagLib::String advisoryValue =
            items["----:com.apple.iTunes:ITUNESADVISORY"].toStringList().toString();
        BOOL explicitValue = metadata.explicitContent;
        if (ParseExplicitTagValue(advisoryValue, explicitValue)) {
            metadata.explicitContent = explicitValue;
        }
    }
    
    // Sort fields
    if (items.contains("sonm")) {
        metadata.sortTitle = TagStringToNSString(items["sonm"].toStringList().toString());
    }
    if (items.contains("soar")) {
        metadata.sortArtist = TagStringToNSString(items["soar"].toStringList().toString());
    }
    if (items.contains("soal")) {
        metadata.sortAlbum = TagStringToNSString(items["soal"].toStringList().toString());
    }
    if (items.contains("soaa")) {
        metadata.sortAlbumArtist = TagStringToNSString(items["soaa"].toStringList().toString());
    }
    if (items.contains("soco")) {
        metadata.sortComposer = TagStringToNSString(items["soco"].toStringList().toString());
    }
    
    // Grouping
    if (items.contains("©grp")) {
        metadata.grouping = TagStringToNSString(items["©grp"].toStringList().toString());
    }
    
    // Copyright
    if (items.contains("cprt")) {
        metadata.copyright = TagStringToNSString(items["cprt"].toStringList().toString());
    }
    
    // Lyrics
    if (items.contains("©lyr")) {
        metadata.lyrics = TagStringToNSString(items["©lyr"].toStringList().toString());
    }
    
    // Encoded by
    if (items.contains("©too")) {
        metadata.encodedBy = TagStringToNSString(items["©too"].toStringList().toString());
    }
    
    // Cover art
    if (items.contains("covr")) {
        TagLib::MP4::CoverArtList coverArtList = items["covr"].toCoverArtList();
        if (!coverArtList.isEmpty()) {
            TagLib::MP4::CoverArt coverArt = coverArtList.front();
            TagLib::ByteVector imageData = coverArt.data();
            metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
            
            // Determine MIME type
            switch (coverArt.format()) {
                case TagLib::MP4::CoverArt::JPEG:
                    metadata.artworkMimeType = @"image/jpeg";
                    break;
                case TagLib::MP4::CoverArt::PNG:
                    metadata.artworkMimeType = @"image/png";
                    break;
                case TagLib::MP4::CoverArt::BMP:
                    metadata.artworkMimeType = @"image/bmp";
                    break;
                case TagLib::MP4::CoverArt::GIF:
                    metadata.artworkMimeType = @"image/gif";
                    break;
                default:
                    metadata.artworkMimeType = @"image/jpeg";
                    break;
            }
        }
    }

    // Date fields
    // Standard iTunes/MP4 release date atom (©day, e.g. "2024-11-12")
    // NOTE: We split the string literal so that the \xA9 escape stops before 'd',
    //       avoiding an out-of-range hex escape like "\xA9d".
    if (items.contains("\xA9" "day")) {
        metadata.releaseDate = TagStringToNSString(items["\xA9" "day"].toStringList().toString());
        if (metadata.year.length == 0 && metadata.releaseDate.length >= 4) {
            metadata.year = [metadata.releaseDate substringToIndex:4];
        }
    }
    
    // Some tools store original year as a freeform atom
    if (items.contains("----:com.apple.iTunes:ORIGINAL YEAR")) {
        metadata.originalReleaseDate = TagStringToNSString(items["----:com.apple.iTunes:ORIGINAL YEAR"].toStringList().toString());
    }
    
    // Professional music player fields - freeform atoms
    // MP4 uses freeform identifiers like ----:com.apple.iTunes:FIELDNAME
    if (items.contains("----:com.apple.iTunes:RELEASETYPE")) {
        metadata.releaseType = TagStringToNSString(items["----:com.apple.iTunes:RELEASETYPE"].toStringList().toString());
    } else if (items.contains("----:com.apple.iTunes:MusicBrainz Album Type")) {
        metadata.releaseType = TagStringToNSString(items["----:com.apple.iTunes:MusicBrainz Album Type"].toStringList().toString());
    }
    
    if (items.contains("----:com.apple.iTunes:BARCODE")) {
        metadata.barcode = TagStringToNSString(items["----:com.apple.iTunes:BARCODE"].toStringList().toString());
    }

    if (items.contains("----:com.apple.iTunes:LABEL")) {
        metadata.label = TagStringToNSString(items["----:com.apple.iTunes:LABEL"].toStringList().toString());
    }
    
    if (items.contains("----:com.apple.iTunes:CATALOGNUMBER")) {
        metadata.catalogNumber = TagStringToNSString(items["----:com.apple.iTunes:CATALOGNUMBER"].toStringList().toString());
    }
    
    if (items.contains("----:com.apple.iTunes:MusicBrainz Album Release Country")) {
        metadata.releaseCountry = TagStringToNSString(items["----:com.apple.iTunes:MusicBrainz Album Release Country"].toStringList().toString());
    }

    for (const auto &[itemKey, itemValue] : items) {
        NSString *description = MP4FreeformDescriptionForItemKey(itemKey);
        if (!description) {
            continue;
        }

        NSString *itemValueString = TrimmedStringOrNil(
            TagStringToNSString(itemValue.toStringList().toString(", "))
        );
        if (!itemValueString) {
            continue;
        }

        if (!ApplyKnownCustomMetadataField(description, itemValueString, metadata)) {
            SetCustomMetadataField(metadata, description, itemValueString);
        }
    }
}

// Extract Xiph Comment metadata (FLAC, OGG Vorbis, Opus, etc.)
static void ExtractXiphCommentMetadata(TagLib::Ogg::XiphComment* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;

    ApplyBasicTagMetadata(tag, metadata);

    const TagLib::PropertyMap& properties = tag->properties();
    ApplyGenericPropertyMapMetadata(properties, metadata);
    
    // Track/Disc numbers
    if (properties.contains("TRACKNUMBER")) {
        TagLib::String trackStr = properties["TRACKNUMBER"].front();
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(trackStr, trackNum, trackTotal);
        metadata.trackNumberText = PreferredNumberText(
            metadata.trackNumberText,
            TagStringToNSString(trackStr)
        );
        metadata.trackNumber = trackNum;
        if (trackTotal > 0) metadata.totalTracks = trackTotal;
    }
    if (properties.contains("TRACKTOTAL") || properties.contains("TOTALTRACKS")) {
        TagLib::String key = properties.contains("TRACKTOTAL") ? "TRACKTOTAL" : "TOTALTRACKS";
        metadata.totalTracks = ExtractNumber(properties[key].front());
    }
    if (properties.contains("DISCNUMBER")) {
        TagLib::String discStr = properties["DISCNUMBER"].front();
        NSInteger discNum = 0, discTotal = 0;
        ParseNumberPair(discStr, discNum, discTotal);
        metadata.discNumberText = PreferredNumberText(
            metadata.discNumberText,
            TagStringToNSString(discStr)
        );
        metadata.discNumber = discNum;
        if (discTotal > 0) metadata.totalDiscs = discTotal;
    }
    if (properties.contains("DISCTOTAL") || properties.contains("TOTALDISCS")) {
        TagLib::String key = properties.contains("DISCTOTAL") ? "DISCTOTAL" : "TOTALDISCS";
        metadata.totalDiscs = ExtractNumber(properties[key].front());
    }
    
    // Album Artist
    if (properties.contains("ALBUMARTIST")) {
        metadata.albumArtist = TagStringToNSString(properties["ALBUMARTIST"].front());
    }
    
    // BPM
    if (properties.contains("BPM")) {
        metadata.bpm = ExtractNumber(properties["BPM"].front());
    }
    
    // Sort fields
    if (properties.contains("TITLESORT")) {
        metadata.sortTitle = TagStringToNSString(properties["TITLESORT"].front());
    }
    if (properties.contains("ARTISTSORT")) {
        metadata.sortArtist = TagStringToNSString(properties["ARTISTSORT"].front());
    }
    if (properties.contains("ALBUMSORT")) {
        metadata.sortAlbum = TagStringToNSString(properties["ALBUMSORT"].front());
    }
    if (properties.contains("ALBUMARTISTSORT")) {
        metadata.sortAlbumArtist = TagStringToNSString(properties["ALBUMARTISTSORT"].front());
    }
    if (properties.contains("COMPOSERSORT")) {
        metadata.sortComposer = TagStringToNSString(properties["COMPOSERSORT"].front());
    }
    
    // Personnel
    if (properties.contains("CONDUCTOR")) {
        metadata.conductor = TagStringToNSString(properties["CONDUCTOR"].front());
    }
    if (properties.contains("REMIXER")) {
        metadata.remixer = TagStringToNSString(properties["REMIXER"].front());
    }
    if (properties.contains("PRODUCER")) {
        metadata.producer = TagStringToNSString(properties["PRODUCER"].front());
    }
    if (properties.contains("ENGINEER")) {
        metadata.engineer = TagStringToNSString(properties["ENGINEER"].front());
    }
    if (properties.contains("LYRICIST")) {
        metadata.lyricist = TagStringToNSString(properties["LYRICIST"].front());
    }
    
    // Descriptive
    if (properties.contains("SUBTITLE")) {
        metadata.subtitle = TagStringToNSString(properties["SUBTITLE"].front());
    }
    if (properties.contains("GROUPING")) {
        metadata.grouping = TagStringToNSString(properties["GROUPING"].front());
    }
    if (properties.contains("MOVEMENT")) {
        metadata.movement = TagStringToNSString(properties["MOVEMENT"].front());
    }
    if (properties.contains("MOOD")) {
        metadata.mood = TagStringToNSString(properties["MOOD"].front());
    }
    if (properties.contains("LANGUAGE")) {
        metadata.language = TagStringToNSString(properties["LANGUAGE"].front());
    }
    if (properties.contains("INITIALKEY") || properties.contains("KEY")) {
        TagLib::String key = properties.contains("INITIALKEY") ? "INITIALKEY" : "KEY";
        metadata.musicalKey = TagStringToNSString(properties[key].front());
    }
    
    // Other metadata
    if (properties.contains("COPYRIGHT")) {
        metadata.copyright = TagStringToNSString(properties["COPYRIGHT"].front());
    }
    if (properties.contains("LYRICS")) {
        metadata.lyrics = TagStringToNSString(properties["LYRICS"].front());
    }
    if (properties.contains("LABEL")) {
        metadata.label = TagStringToNSString(properties["LABEL"].front());
    }
    if (properties.contains("ISRC")) {
        metadata.isrc = TagStringToNSString(properties["ISRC"].front());
    }
    if (properties.contains("ENCODEDBY")) {
        metadata.encodedBy = TagStringToNSString(properties["ENCODEDBY"].front());
    }
    if (properties.contains("ENCODERSETTINGS")) {
        metadata.encoderSettings = TagStringToNSString(properties["ENCODERSETTINGS"].front());
    }
    
    // Date fields
    if (properties.contains("RELEASEDATE")) {
        metadata.releaseDate = TagStringToNSString(properties["RELEASEDATE"].front());
    } else if (properties.contains("DATE")) {
        metadata.releaseDate = TagStringToNSString(properties["DATE"].front());
    }
    if (properties.contains("ORIGINALDATE")) {
        metadata.originalReleaseDate = TagStringToNSString(properties["ORIGINALDATE"].front());
    }
    
    // MusicBrainz IDs
    if (properties.contains("MUSICBRAINZ_ARTISTID")) {
        metadata.musicBrainzArtistId = TagStringToNSString(properties["MUSICBRAINZ_ARTISTID"].front());
    }
    if (properties.contains("MUSICBRAINZ_ALBUMID")) {
        metadata.musicBrainzAlbumId = TagStringToNSString(properties["MUSICBRAINZ_ALBUMID"].front());
    }
    if (properties.contains("MUSICBRAINZ_TRACKID")) {
        metadata.musicBrainzTrackId = TagStringToNSString(properties["MUSICBRAINZ_TRACKID"].front());
    }
    if (properties.contains("MUSICBRAINZ_RELEASEGROUPID")) {
        metadata.musicBrainzReleaseGroupId = TagStringToNSString(properties["MUSICBRAINZ_RELEASEGROUPID"].front());
    }
    
    // Professional music player fields
    if (properties.contains("RELEASETYPE")) {
        metadata.releaseType = TagStringToNSString(properties["RELEASETYPE"].front());
    } else if (properties.contains("MUSICBRAINZ_ALBUMTYPE")) {
        metadata.releaseType = TagStringToNSString(properties["MUSICBRAINZ_ALBUMTYPE"].front());
    }
    
    if (properties.contains("BARCODE")) {
        metadata.barcode = TagStringToNSString(properties["BARCODE"].front());
    } else if (properties.contains("UPC")) {
        metadata.barcode = TagStringToNSString(properties["UPC"].front());
    } else if (properties.contains("EAN")) {
        metadata.barcode = TagStringToNSString(properties["EAN"].front());
    }
    
    if (properties.contains("CATALOGNUMBER")) {
        metadata.catalogNumber = TagStringToNSString(properties["CATALOGNUMBER"].front());
    } else if (properties.contains("CATALOG")) {
        metadata.catalogNumber = TagStringToNSString(properties["CATALOG"].front());
    }
    
    if (properties.contains("RELEASECOUNTRY")) {
        metadata.releaseCountry = TagStringToNSString(properties["RELEASECOUNTRY"].front());
    } else if (properties.contains("MUSICBRAINZ_ALBUMRELEASECOUNTRY")) {
        metadata.releaseCountry = TagStringToNSString(properties["MUSICBRAINZ_ALBUMRELEASECOUNTRY"].front());
    }
    
    if (properties.contains("MUSICBRAINZ_ARTISTTYPE")) {
        metadata.artistType = TagStringToNSString(properties["MUSICBRAINZ_ARTISTTYPE"].front());
    }
    
    // ReplayGain
    if (properties.contains("REPLAYGAIN_TRACK_GAIN")) {
        metadata.replayGainTrack = TagStringToNSString(properties["REPLAYGAIN_TRACK_GAIN"].front());
    }
    if (properties.contains("REPLAYGAIN_ALBUM_GAIN")) {
        metadata.replayGainAlbum = TagStringToNSString(properties["REPLAYGAIN_ALBUM_GAIN"].front());
    }
    
    // Compilation
    if (properties.contains("COMPILATION")) {
        TagLib::String compStr = properties["COMPILATION"].front();
        metadata.compilation = (compStr == "1" || compStr.upper() == "TRUE");
    }

    ApplyExplicitPropertyKeys(properties, metadata);
}

// Extract FLAC picture
static void ExtractFLACPicture(TagLib::FLAC::File* file, TagLibAudioMetadata* metadata) {
    if (!file) return;
    
    const TagLib::List<TagLib::FLAC::Picture*>& pictures = file->pictureList();
    for (auto pic : pictures) {
        if (pic->type() == TagLib::FLAC::Picture::FrontCover) {
            TagLib::ByteVector imageData = pic->data();
            metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
            metadata.artworkMimeType = TagStringToNSString(pic->mimeType());
            break;
        }
    }
}

// Extract APE metadata
static void ExtractAPEMetadata(TagLib::APE::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;

    ApplyBasicTagMetadata(tag, metadata);

    const TagLib::APE::ItemListMap& items = tag->itemListMap();
    
    // Track/Disc numbers
    if (items.contains("TRACK")) {
        TagLib::String trackStr = items["TRACK"].values().front();
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(trackStr, trackNum, trackTotal);
        metadata.trackNumberText = PreferredNumberText(
            metadata.trackNumberText,
            TagStringToNSString(trackStr)
        );
        metadata.trackNumber = trackNum;
        if (trackTotal > 0) metadata.totalTracks = trackTotal;
    }
    if (items.contains("DISC")) {
        TagLib::String discStr = items["DISC"].values().front();
        NSInteger discNum = 0, discTotal = 0;
        ParseNumberPair(discStr, discNum, discTotal);
        metadata.discNumberText = PreferredNumberText(
            metadata.discNumberText,
            TagStringToNSString(discStr)
        );
        metadata.discNumber = discNum;
        if (discTotal > 0) metadata.totalDiscs = discTotal;
    }
    
    // Album Artist
    if (items.contains("ALBUM ARTIST") || items.contains("ALBUMARTIST")) {
        TagLib::String key = items.contains("ALBUM ARTIST") ? "ALBUM ARTIST" : "ALBUMARTIST";
        metadata.albumArtist = TagStringToNSString(items[key].values().front());
    }
    
    // BPM
    if (items.contains("BPM")) {
        metadata.bpm = items["BPM"].values().front().toInt();
    }
    
    // Other metadata
    if (items.contains("COPYRIGHT")) {
        metadata.copyright = TagStringToNSString(items["COPYRIGHT"].values().front());
    }
    if (items.contains("LYRICS")) {
        metadata.lyrics = TagStringToNSString(items["LYRICS"].values().front());
    }
    if (items.contains("ISRC")) {
        metadata.isrc = TagStringToNSString(items["ISRC"].values().front());
    }
    if (items.contains("LABEL")) {
        metadata.label = TagStringToNSString(items["LABEL"].values().front());
    }
    
    // Professional music player fields
    if (items.contains("RELEASETYPE")) {
        metadata.releaseType = TagStringToNSString(items["RELEASETYPE"].values().front());
    }
    if (items.contains("BARCODE")) {
        metadata.barcode = TagStringToNSString(items["BARCODE"].values().front());
    } else if (items.contains("UPC")) {
        metadata.barcode = TagStringToNSString(items["UPC"].values().front());
    }
    if (items.contains("CATALOGNUMBER")) {
        metadata.catalogNumber = TagStringToNSString(items["CATALOGNUMBER"].values().front());
    }
    if (items.contains("RELEASECOUNTRY")) {
        metadata.releaseCountry = TagStringToNSString(items["RELEASECOUNTRY"].values().front());
    }
    
    // Cover art
    if (items.contains("COVER ART (FRONT)")) {
        TagLib::ByteVector coverData = items["COVER ART (FRONT)"].binaryData();
        // APE cover art typically has description followed by null byte, then image data
        if (coverData.size() > 0) {
            // Find first null byte to skip description
            unsigned int startPos = 0;
            for (unsigned int i = 0; i < coverData.size(); ++i) {
                if (coverData[i] == 0) {
                    startPos = i + 1;
                    break;
                }
            }
            if (startPos < coverData.size()) {
                metadata.artworkData = [NSData dataWithBytes:coverData.data() + startPos
                                                      length:coverData.size() - startPos];
            }
        }
    }
}

#pragma mark - Main Extraction Method

+ (nullable TagLibAudioMetadata *)extractMetadataFromURL:(NSURL *)fileURL
                                                   error:(NSError **)error {
    if (!fileURL || ![fileURL isFileURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid file URL"}];
        }
        return nil;
    }
    
    const char* filePath = [fileURL.path UTF8String];
    NSString *extension = fileURL.pathExtension.lowercaseString;
    std::string ext = [extension UTF8String];
    AudioMatorTagFileFormat format = DetectTagFileFormat(extension);

    TagLibAudioMetadata* metadata = [[TagLibAudioMetadata alloc] init];
    TLog(@"Created TagLibAudioMetadata object for '%@'", fileURL.lastPathComponent);
    bool openedSpecificFile = false;
    
    // Extract format-specific metadata
    // MP3
    if (format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC) {
        TagLib::MPEG::File mpegFile(filePath);
        if (mpegFile.isValid()) {
            bool isAAC = (format == AudioMatorTagFileFormatMPEGAAC);
            openedSpecificFile = true;

            ApplyBasicTagMetadata(mpegFile.tag(), metadata);
            ApplyGenericPropertyMapMetadata(mpegFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(mpegFile.audioProperties(), metadata);

            if (format == AudioMatorTagFileFormatMPEGAAC) {
                metadata.codec = @"AAC";
            } else if (ext == "mp2") {
                metadata.codec = @"MP2";
            } else {
                metadata.codec = @"MP3";
            }

            if (!isAAC) {
                if (mpegFile.ID3v2Tag()) {
                    ExtractID3v2Metadata(mpegFile.ID3v2Tag(), metadata);
                }

                if (mpegFile.APETag()) {
                    ExtractAPEMetadata(mpegFile.APETag(), metadata);
                }

                if (mpegFile.ID3v1Tag()) {
                    // ID3v1 is a low-fidelity fallback. It must not overwrite richer
                    // values already gathered from PropertyMap / ID3v2.
                    ApplyBasicTagMetadata(mpegFile.ID3v1Tag(), metadata);
                }
            }
        }
    }
    // MP4/M4A
    else if (format == AudioMatorTagFileFormatMP4) {
        TagLib::MP4::File mp4File(filePath);
        if (mp4File.isValid()) {
            openedSpecificFile = true;
            metadata.codec = ext == "mp4" ? @"MP4" : @"AAC";

            ApplyGenericPropertyMapMetadata(mp4File.properties(), metadata);
            ApplyAudioPropertiesMetadata(mp4File.audioProperties(), metadata);

            if (mp4File.tag()) {
                ApplyBasicTagMetadata(mp4File.tag(), metadata);
                ExtractMP4Metadata(mp4File.tag(), metadata);
            }
        }
    }
    // FLAC
    else if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File flacFile(filePath);
        if (flacFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"FLAC";

            ApplyGenericPropertyMapMetadata(flacFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(flacFile.audioProperties(), metadata);

            if (flacFile.xiphComment()) {
                ExtractXiphCommentMetadata(flacFile.xiphComment(), metadata);
            }

            // Extract bit depth
            if (flacFile.audioProperties()) {
                metadata.bitDepth = flacFile.audioProperties()->bitsPerSample();
            }
            
            // Extract cover art
            ExtractFLACPicture(&flacFile, metadata);
        }
    }
    // OGG Vorbis
    else if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);
        if (vorbisFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"Vorbis";

            ApplyGenericPropertyMapMetadata(vorbisFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(vorbisFile.audioProperties(), metadata);

            if (vorbisFile.tag()) {
                ExtractXiphCommentMetadata(vorbisFile.tag(), metadata);
                ExtractArtworkFromComplexProperties(vorbisFile.tag(), metadata);
            }
        }
    }
    // Opus
    else if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File opusFile(filePath);
        if (opusFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"Opus";

            ApplyGenericPropertyMapMetadata(opusFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(opusFile.audioProperties(), metadata);

            if (opusFile.tag()) {
                ExtractXiphCommentMetadata(opusFile.tag(), metadata);
                ExtractArtworkFromComplexProperties(opusFile.tag(), metadata);
            }
        }
    }
    // OGG FLAC
    else if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File oggFlacFile(filePath);
        if (oggFlacFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"OGG FLAC";

            ApplyGenericPropertyMapMetadata(oggFlacFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(oggFlacFile.audioProperties(), metadata);

            if (oggFlacFile.tag()) {
                ExtractXiphCommentMetadata(oggFlacFile.tag(), metadata);
                ExtractArtworkFromComplexProperties(oggFlacFile.tag(), metadata);
            }
        }
    }
    // APE (Monkey's Audio)
    else if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File apeFile(filePath);
        if (apeFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"APE";

            ApplyGenericPropertyMapMetadata(apeFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(apeFile.audioProperties(), metadata);

            if (apeFile.APETag()) {
                ExtractAPEMetadata(apeFile.APETag(), metadata);
            }
        }
    }
    // WavPack
    else if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File wvFile(filePath);
        if (wvFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"WavPack";

            ApplyGenericPropertyMapMetadata(wvFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(wvFile.audioProperties(), metadata);

            if (wvFile.APETag()) {
                ExtractAPEMetadata(wvFile.APETag(), metadata);
            }
        }
    }
    // WAV
    else if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File wavFile(filePath);
        if (wavFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"WAV";

            ApplyGenericPropertyMapMetadata(wavFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(wavFile.audioProperties(), metadata);

            if (wavFile.ID3v2Tag()) {
                ExtractID3v2Metadata(wavFile.ID3v2Tag(), metadata);
            }
            
            // Extract bit depth
            if (wavFile.audioProperties()) {
                metadata.bitDepth = wavFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // AIFF
    else if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File aiffFile(filePath);
        if (aiffFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"AIFF";

            ApplyGenericPropertyMapMetadata(aiffFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(aiffFile.audioProperties(), metadata);

            if (aiffFile.tag()) {
                ExtractID3v2Metadata(aiffFile.tag(), metadata);
            }
            
            // Extract bit depth
            if (aiffFile.audioProperties()) {
                metadata.bitDepth = aiffFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // TrueAudio
    else if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File ttaFile(filePath);
        if (ttaFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"TrueAudio";

            ApplyGenericPropertyMapMetadata(ttaFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(ttaFile.audioProperties(), metadata);

            if (ttaFile.ID3v2Tag()) {
                ExtractID3v2Metadata(ttaFile.ID3v2Tag(), metadata);
            }

            if (ttaFile.ID3v1Tag()) {
                // ID3v1 is only used to fill gaps for legacy files.
                ApplyBasicTagMetadata(ttaFile.ID3v1Tag(), metadata);
            }
            // Extract bit depth
            if (ttaFile.audioProperties()) {
                metadata.bitDepth = ttaFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // Musepack
    else if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File mpcFile(filePath);
        if (mpcFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"Musepack";

            ApplyGenericPropertyMapMetadata(mpcFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(mpcFile.audioProperties(), metadata);

            if (mpcFile.APETag()) {
                ExtractAPEMetadata(mpcFile.APETag(), metadata);
            }
        }
    }
    // Speex
    else if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File speexFile(filePath);
        if (speexFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"Speex";

            ApplyGenericPropertyMapMetadata(speexFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(speexFile.audioProperties(), metadata);

            if (speexFile.tag()) {
                ExtractXiphCommentMetadata(speexFile.tag(), metadata);
                ExtractArtworkFromComplexProperties(speexFile.tag(), metadata);
            }
        }
    }
    // ASF/WMA
    else if (format == AudioMatorTagFileFormatASF) {
        TagLib::ASF::File asfFile(filePath);
        if (asfFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"WMA";
            ApplyBasicTagMetadata(asfFile.tag(), metadata);
            ApplyGenericPropertyMapMetadata(asfFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(asfFile.audioProperties(), metadata);
            if (asfFile.tag()) {
                ExtractArtworkFromComplexProperties(asfFile.tag(), metadata);
            }
        }
    }
    // DSF
    else if (format == AudioMatorTagFileFormatDSF) {
        TagLib::DSF::File dsfFile(filePath);
        if (dsfFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"DSF";

            ApplyGenericPropertyMapMetadata(dsfFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(dsfFile.audioProperties(), metadata);

            // DSF files use ID3v2 tags, but accessed via tag() method
            if (dsfFile.tag()) {
                // The tag() method returns an ID3v2::Tag*
                if (auto id3tag = dynamic_cast<TagLib::ID3v2::Tag*>(dsfFile.tag())) {
                    ExtractID3v2Metadata(id3tag, metadata);
                }
            }
        }
    }
    // DSDIFF
    else if (format == AudioMatorTagFileFormatDSDIFF) {
        TagLib::DSDIFF::File dsdiffFile(filePath);
        if (dsdiffFile.isValid()) {
            openedSpecificFile = true;
            metadata.codec = @"DSDIFF";

            ApplyGenericPropertyMapMetadata(dsdiffFile.properties(), metadata);
            ApplyAudioPropertiesMetadata(dsdiffFile.audioProperties(), metadata);

            if (dsdiffFile.hasID3v2Tag()) {
                ExtractID3v2Metadata(dsdiffFile.ID3v2Tag(), metadata);
            }
        }
    }

    // Fallback path: only pay the generic FileRef cost if the format-specific
    // opener could not read the file at all.
    if (!openedSpecificFile) {
        TagLib::FileRef fileRef(filePath);
        if (!fileRef.isNull()) {
            ApplyBasicTagMetadata(fileRef.tag(), metadata);
            if (fileRef.file()) {
                ApplyGenericPropertyMapMetadata(fileRef.file()->properties(), metadata);
            }
            ApplyAudioPropertiesMetadata(fileRef.audioProperties(), metadata);
        }
    }
    
    TLog(@"Basic tag for '%@': title=%@ artist=%@ album=%@ genre=%@ comment=%@ year=%@ track=%ld",
         fileURL.lastPathComponent,
         metadata.title ?: @"<nil>",
         metadata.artist ?: @"<nil>",
         metadata.album ?: @"<nil>",
         metadata.genre ?: @"<nil>",
         metadata.comment ?: @"<nil>",
         metadata.year ?: @"<nil>",
         (long)metadata.trackNumber);

    TLog(@"Audio props for '%@': duration=%.1f s, bitrate=%ld kbps, sampleRate=%ld Hz, channels=%ld",
         fileURL.lastPathComponent,
         metadata.duration,
         (long)metadata.bitrate,
         (long)metadata.sampleRate,
         (long)metadata.channels);

    TLog(@"[READ-OUT] '%@' explicitContent=%@",
         fileURL.lastPathComponent,
         metadata.explicitContent ? @"YES" : @"NO");

    bool hasReadableMetadata =
        metadata.title.length > 0 ||
        metadata.artist.length > 0 ||
        metadata.album.length > 0 ||
        metadata.genre.length > 0 ||
        metadata.comment.length > 0 ||
        metadata.composer.length > 0 ||
        metadata.albumArtist.length > 0 ||
        metadata.releaseDate.length > 0 ||
        metadata.year.length > 0 ||
        metadata.trackNumber > 0 ||
        metadata.discNumber > 0 ||
        metadata.artworkData.length > 0;

    if (!openedSpecificFile && !hasReadableMetadata && metadata.duration <= 0.0 && metadata.bitrate <= 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read file or no metadata found"}];
        }
        return nil;
    }

    return metadata;
}



// Build an ID3v2 TRCK text string.
// - If padWidth > 0, the track number is left-padded with zeros to that width (e.g. 1 -> "01").
// - The total track count is written as-is (no padding).
static NSString * _Nullable BuildTRCKString(NSInteger trackNumber, NSInteger totalTracks, NSInteger padWidth) {
    if (trackNumber <= 0 && totalTracks <= 0) {
        return nil;
    }

    NSString *trackPart = nil;
    if (trackNumber > 0) {
        if (padWidth > 0) {
            trackPart = [NSString stringWithFormat:@"%0*ld", (int)padWidth, (long)trackNumber];
        } else {
            trackPart = [NSString stringWithFormat:@"%ld", (long)trackNumber];
        }
    } else {
        trackPart = @"0";
    }

    if (totalTracks > 0) {
        return [NSString stringWithFormat:@"%@/%ld", trackPart, (long)totalTracks];
    }

    return trackPart;
}

// Write only track numbering (TRCK + TagLib::Tag::setTrack) to a file.
+ (BOOL)writeTrackNumber:(NSInteger)trackNumber
             totalTracks:(NSInteger)totalTracks
                padWidth:(NSInteger)padWidth
                   toURL:(NSURL *)fileURL
                   error:(NSError **)error
{
    if (!fileURL || ![fileURL isFileURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:40
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file URL" }];
        }
        return NO;
    }

    NSString *ext = fileURL.pathExtension.lowercaseString;
    AudioMatorTagFileFormat format = DetectTagFileFormat(ext);
    if (format == AudioMatorTagFileFormatUnknown) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:41
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing track numbers is currently supported for every format that AudioMator can edit metadata for" }];
        }
        TLog(@"Track renumber skipped for '%@' (extension '%@' not supported)", fileURL.lastPathComponent, ext);
        return NO;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC) {
        TagLib::MPEG::File mpegFile(filePath);

        if (format == AudioMatorTagFileFormatMPEGAAC) {
            if (!WritePropertyMapNumberTextToFile(mpegFile,
                                                  BuildTRCKString(trackNumber, totalTracks, padWidth),
                                                  nil,
                                                  error,
                                                  42,
                                                  @"Unable to open AAC file for writing track numbers",
                                                  44,
                                                  @"TagLib failed to save AAC track numbers",
                                                  [NSString stringWithFormat:@"AAC '%@'", fileURL.lastPathComponent])) {
                return NO;
            }
        } else {
            if (!mpegFile.isValid()) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:42
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open file for writing track numbers" }];
                }
                TLog(@"Failed to open '%@' for track renumbering", fileURL.lastPathComponent);
                return NO;
            }

            TagLib::Tag *tag = mpegFile.tag();
            if (!tag) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:43
                                             userInfo:@{ NSLocalizedDescriptionKey : @"No tag found to write track numbers into" }];
                }
                TLog(@"No tag object available for '%@' (track renumbering)", fileURL.lastPathComponent);
                return NO;
            }

            if (trackNumber > 0) {
                tag->setTrack((unsigned int)trackNumber);
            }

            TagLib::ID3v2::Tag *id3v2Tag = mpegFile.ID3v2Tag(true);
            SetID3v2TextFrame(id3v2Tag, "TRCK", BuildTRCKString(trackNumber, totalTracks, padWidth));

            if (!mpegFile.save()) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:44
                                             userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save after writing track numbers" }];
                }
                TLog(@"TagLib save() failed after track renumbering for '%@'", fileURL.lastPathComponent);
                return NO;
            }
        }
    } else if (format == AudioMatorTagFileFormatMP4) {
        TagLib::MP4::File mp4File(filePath);

        if (!mp4File.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:45
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open MP4/M4A file for writing track numbers" }];
            }
            TLog(@"Failed to open MP4 '%@' for track renumbering", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::MP4::Tag *mp4Tag = mp4File.tag();
        if (!mp4Tag) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:46
                                         userInfo:@{ NSLocalizedDescriptionKey : @"No MP4 tag found to write track numbers into" }];
            }
            TLog(@"No MP4 tag object available for '%@' (track renumbering)", fileURL.lastPathComponent);
            return NO;
        }

        if (trackNumber > 0) {
            mp4Tag->setTrack((unsigned int)trackNumber);
        } else {
            mp4Tag->setTrack(0);
        }

        SetMP4IntPairItem(mp4Tag, "trkn", trackNumber, totalTracks);

        if (!mp4File.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:47
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save MP4/M4A track numbers" }];
            }
            TLog(@"TagLib save() failed after MP4 track renumbering for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File flacFile(filePath);
        if (!WritePropertyMapNumberTextToFile(flacFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              48,
                                              @"Unable to open FLAC file for writing track numbers",
                                              49,
                                              @"TagLib failed to save FLAC track numbers",
                                              [NSString stringWithFormat:@"FLAC '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);
        if (!WritePropertyMapNumberTextToFile(vorbisFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              74,
                                              @"Unable to open Ogg Vorbis file for writing track numbers",
                                              75,
                                              @"TagLib failed to save Ogg Vorbis track numbers",
                                              [NSString stringWithFormat:@"Ogg Vorbis '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File opusFile(filePath);
        if (!WritePropertyMapNumberTextToFile(opusFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              76,
                                              @"Unable to open Opus file for writing track numbers",
                                              77,
                                              @"TagLib failed to save Opus track numbers",
                                              [NSString stringWithFormat:@"Opus '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File oggFlacFile(filePath);
        if (!WritePropertyMapNumberTextToFile(oggFlacFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              78,
                                              @"Unable to open Ogg FLAC file for writing track numbers",
                                              79,
                                              @"TagLib failed to save Ogg FLAC track numbers",
                                              [NSString stringWithFormat:@"Ogg FLAC '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File speexFile(filePath);
        if (!WritePropertyMapNumberTextToFile(speexFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              80,
                                              @"Unable to open Speex file for writing track numbers",
                                              81,
                                              @"TagLib failed to save Speex track numbers",
                                              [NSString stringWithFormat:@"Speex '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File apeFile(filePath);
        if (!WritePropertyMapNumberTextToFile(apeFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              82,
                                              @"Unable to open APE file for writing track numbers",
                                              83,
                                              @"TagLib failed to save APE track numbers",
                                              [NSString stringWithFormat:@"APE '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File wavPackFile(filePath);
        if (!WritePropertyMapNumberTextToFile(wavPackFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              84,
                                              @"Unable to open WavPack file for writing track numbers",
                                              85,
                                              @"TagLib failed to save WavPack track numbers",
                                              [NSString stringWithFormat:@"WavPack '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File mpcFile(filePath);
        if (!WritePropertyMapNumberTextToFile(mpcFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              86,
                                              @"Unable to open Musepack file for writing track numbers",
                                              87,
                                              @"TagLib failed to save Musepack track numbers",
                                              [NSString stringWithFormat:@"Musepack '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File wavFile(filePath);
        if (!WritePropertyMapNumberTextToFile(wavFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              60,
                                              @"Unable to open WAV file for writing track numbers",
                                              61,
                                              @"TagLib failed to save WAV track numbers",
                                              [NSString stringWithFormat:@"WAV '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File aiffFile(filePath);
        if (!WritePropertyMapNumberTextToFile(aiffFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              62,
                                              @"Unable to open AIFF file for writing track numbers",
                                              63,
                                              @"TagLib failed to save AIFF track numbers",
                                              [NSString stringWithFormat:@"AIFF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File ttaFile(filePath);
        if (!WritePropertyMapNumberTextToFile(ttaFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              88,
                                              @"Unable to open TrueAudio file for writing track numbers",
                                              89,
                                              @"TagLib failed to save TrueAudio track numbers",
                                              [NSString stringWithFormat:@"TrueAudio '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatASF) {
        TagLib::ASF::File asfFile(filePath);
        if (!WritePropertyMapNumberTextToFile(asfFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              90,
                                              @"Unable to open ASF/WMA file for writing track numbers",
                                              91,
                                              @"TagLib failed to save ASF/WMA track numbers",
                                              [NSString stringWithFormat:@"ASF/WMA '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatDSF) {
        TagLib::DSF::File dsfFile(filePath);
        if (!WritePropertyMapNumberTextToFile(dsfFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              92,
                                              @"Unable to open DSF file for writing track numbers",
                                              93,
                                              @"TagLib failed to save DSF track numbers",
                                              [NSString stringWithFormat:@"DSF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatDSDIFF) {
        TagLib::DSDIFF::File dsdiffFile(filePath);
        if (!WritePropertyMapNumberTextToFile(dsdiffFile,
                                              BuildTRCKString(trackNumber, totalTracks, padWidth),
                                              nil,
                                              error,
                                              94,
                                              @"Unable to open DSDIFF file for writing track numbers",
                                              95,
                                              @"TagLib failed to save DSDIFF track numbers",
                                              [NSString stringWithFormat:@"DSDIFF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:41
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing track numbers is currently supported for every format that AudioMator can edit metadata for" }];
        }
        return NO;
    }

    TLog(@"Successfully wrote track numbers to '%@' (track=%ld, total=%ld, padWidth=%ld)",
         fileURL.lastPathComponent,
         (long)trackNumber,
         (long)totalTracks,
         (long)padWidth);

    return YES;
}

+ (BOOL)writeRawPropertyMap:(NSDictionary<NSString *, NSString *> *)properties
                     toURL:(NSURL *)fileURL
                     error:(NSError **)error
{
    if (!fileURL || !fileURL.isFileURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:100
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file URL" }];
        }
        return NO;
    }

    NSString *ext = fileURL.pathExtension.lowercaseString;
    AudioMatorTagFileFormat format = DetectTagFileFormat(ext);
    if (format == AudioMatorTagFileFormatUnknown) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:101
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Unsupported audio format" }];
        }
        return NO;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (!filePath) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:102
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file path" }];
        }
        return NO;
    }

    NSDictionary<NSString *, NSString *> *normalizedProperties = NormalizedRawPropertiesForWrite(properties ?: @{}, ext);

    if (format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC) {
        TagLib::MPEG::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         166,
                                         @"Unable to open MPEG audio file for metadata editing",
                                         167,
                                         @"TagLib failed to save MPEG metadata property changes",
                                         [NSString stringWithFormat:@"MPEG '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatMP4) {
        TagLib::MP4::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         168,
                                         @"Unable to open MP4/M4A file for metadata editing",
                                         169,
                                         @"TagLib failed to save MP4/M4A metadata property changes",
                                         [NSString stringWithFormat:@"MP4 '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         170,
                                         @"Unable to open FLAC file for metadata editing",
                                         171,
                                         @"TagLib failed to save FLAC metadata property changes",
                                         [NSString stringWithFormat:@"FLAC '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         172,
                                         @"Unable to open Ogg Vorbis file for metadata editing",
                                         173,
                                         @"TagLib failed to save Ogg Vorbis metadata property changes",
                                         [NSString stringWithFormat:@"Ogg Vorbis '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         174,
                                         @"Unable to open Opus file for metadata editing",
                                         175,
                                         @"TagLib failed to save Opus metadata property changes",
                                         [NSString stringWithFormat:@"Opus '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         176,
                                         @"Unable to open Ogg FLAC file for metadata editing",
                                         177,
                                         @"TagLib failed to save Ogg FLAC metadata property changes",
                                         [NSString stringWithFormat:@"Ogg FLAC '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         178,
                                         @"Unable to open Speex file for metadata editing",
                                         179,
                                         @"TagLib failed to save Speex metadata property changes",
                                         [NSString stringWithFormat:@"Speex '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         180,
                                         @"Unable to open APE file for metadata editing",
                                         181,
                                         @"TagLib failed to save APE metadata property changes",
                                         [NSString stringWithFormat:@"APE '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         182,
                                         @"Unable to open WavPack file for metadata editing",
                                         183,
                                         @"TagLib failed to save WavPack metadata property changes",
                                         [NSString stringWithFormat:@"WavPack '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         184,
                                         @"Unable to open Musepack file for metadata editing",
                                         185,
                                         @"TagLib failed to save Musepack metadata property changes",
                                         [NSString stringWithFormat:@"Musepack '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         186,
                                         @"Unable to open WAV file for metadata editing",
                                         187,
                                         @"TagLib failed to save WAV metadata property changes",
                                         [NSString stringWithFormat:@"WAV '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         188,
                                         @"Unable to open AIFF file for metadata editing",
                                         189,
                                         @"TagLib failed to save AIFF metadata property changes",
                                         [NSString stringWithFormat:@"AIFF '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         190,
                                         @"Unable to open TrueAudio file for metadata editing",
                                         191,
                                         @"TagLib failed to save TrueAudio metadata property changes",
                                         [NSString stringWithFormat:@"TrueAudio '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatASF) {
        TagLib::ASF::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         192,
                                         @"Unable to open ASF/WMA file for metadata editing",
                                         193,
                                         @"TagLib failed to save ASF/WMA metadata property changes",
                                         [NSString stringWithFormat:@"ASF/WMA '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatDSF) {
        TagLib::DSF::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         194,
                                         @"Unable to open DSF file for metadata editing",
                                         195,
                                         @"TagLib failed to save DSF metadata property changes",
                                         [NSString stringWithFormat:@"DSF '%@'", fileURL.lastPathComponent]);
    }

    if (format == AudioMatorTagFileFormatDSDIFF) {
        TagLib::DSDIFF::File file(filePath);
        return WriteRawPropertyMapToFile(file,
                                         normalizedProperties,
                                         error,
                                         196,
                                         @"Unable to open DSDIFF file for metadata editing",
                                         197,
                                         @"TagLib failed to save DSDIFF metadata property changes",
                                         [NSString stringWithFormat:@"DSDIFF '%@'", fileURL.lastPathComponent]);
    }

    if (error) {
        *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                     code:101
                                 userInfo:@{ NSLocalizedDescriptionKey : @"Unsupported audio format" }];
    }
    return NO;
}

// Parse an NSString like "03/12" or "03" into numeric components and an inferred pad width.
// padWidth is inferred only from the *track/disc part* (before '/'): if it contains leading zeros,
// we treat its string length as the desired pad width.
static void ParseNumberPairFromNSString(NSString *text,
                                       NSInteger &number,
                                       NSInteger &total,
                                       NSInteger &padWidth)
{
    number = 0;
    total = 0;
    padWidth = 0;

    if (!text || text.length == 0) {
        return;
    }

    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"/"];
    NSString *left = parts.count > 0 ? parts[0] : trimmed;

    // Infer padding width from leading zeros in the left part.
    // Example: "01" -> padWidth=2, "1" -> padWidth=0.
    NSString *leftTrim = [left stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (leftTrim.length > 1 && [leftTrim hasPrefix:@"0"]) {
        padWidth = (NSInteger)leftTrim.length;
    }

    // Parse numbers.
    number = leftTrim.integerValue;
    if (parts.count >= 2) {
        NSString *right = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        total = right.integerValue;
    }
}

// Write only track/disc number text. This is useful for auto-renumbering where the UI
// may already have produced a padded representation like "01/10".
+ (BOOL)writeTrackNumberText:(NSString *)trackNumberText
              discNumberText:(NSString *)discNumberText
                       toURL:(NSURL *)fileURL
                       error:(NSError **)error
{
    if (!fileURL || ![fileURL isFileURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:50
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file URL" }];
        }
        return NO;
    }

    NSString *ext = fileURL.pathExtension.lowercaseString;
    AudioMatorTagFileFormat format = DetectTagFileFormat(ext);
    if (format == AudioMatorTagFileFormatUnknown) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:51
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing track/disc numbers is currently supported for every format that AudioMator can edit metadata for" }];
        }
        TLog(@"Track/disc write skipped for '%@' (extension '%@' not supported)", fileURL.lastPathComponent, ext);
        return NO;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC) {
        TagLib::MPEG::File mpegFile(filePath);

        if (format == AudioMatorTagFileFormatMPEGAAC) {
            if (!WritePropertyMapNumberTextToFile(mpegFile,
                                                  TrimmedStringOrNil(trackNumberText),
                                                  discNumberText,
                                                  error,
                                                  52,
                                                  @"Unable to open AAC file for writing track/disc numbers",
                                                  54,
                                                  @"TagLib failed to save AAC track/disc numbers",
                                                  [NSString stringWithFormat:@"AAC '%@'", fileURL.lastPathComponent])) {
                return NO;
            }
        } else {
            if (!mpegFile.isValid()) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:52
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open file for writing track/disc numbers" }];
                }
                TLog(@"Failed to open '%@' for track/disc write", fileURL.lastPathComponent);
                return NO;
            }

            TagLib::Tag *tag = mpegFile.tag();
            if (!tag) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:53
                                             userInfo:@{ NSLocalizedDescriptionKey : @"No tag found to write track/disc numbers into" }];
                }
                TLog(@"No tag object available for '%@' (track/disc write)", fileURL.lastPathComponent);
                return NO;
            }

            TagLib::ID3v2::Tag *id3v2Tag = mpegFile.ID3v2Tag(true);

            NSString *trimmedTrackText = TrimmedStringOrNil(trackNumberText);
            if (trimmedTrackText) {
                NSInteger trackNumber = 0;
                NSInteger totalTracks = 0;
                NSInteger padWidth = 0;
                ParseNumberPairFromNSString(trimmedTrackText, trackNumber, totalTracks, padWidth);
                tag->setTrack(trackNumber > 0 ? (unsigned int)trackNumber : 0);

                if (id3v2Tag) {
                    NSString *trckToWrite = BuildTRCKString(trackNumber, totalTracks, padWidth) ?: trimmedTrackText;
                    SetID3v2TextFrame(id3v2Tag, "TRCK", trckToWrite);
                }
            } else {
                tag->setTrack(0);
                SetID3v2TextFrame(id3v2Tag, "TRCK", nil);
            }

            if (discNumberText != nil && id3v2Tag) {
                SetID3v2TextFrame(id3v2Tag, "TPOS", TrimmedStringOrNil(discNumberText));
            }

            if (!mpegFile.save()) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:54
                                             userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save after writing track/disc numbers" }];
                }
                TLog(@"TagLib save() failed after track/disc write for '%@'", fileURL.lastPathComponent);
                return NO;
            }
        }
    } else if (format == AudioMatorTagFileFormatMP4) {
        TagLib::MP4::File mp4File(filePath);

        if (!mp4File.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:55
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open MP4/M4A file for writing track/disc numbers" }];
            }
            TLog(@"Failed to open MP4 '%@' for track/disc write", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::MP4::Tag *mp4Tag = mp4File.tag();
        if (!mp4Tag) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:56
                                         userInfo:@{ NSLocalizedDescriptionKey : @"No MP4 tag found to write track/disc numbers into" }];
            }
            TLog(@"No MP4 tag object available for '%@' (track/disc write)", fileURL.lastPathComponent);
            return NO;
        }

        NSString *trimmedTrackText = TrimmedStringOrNil(trackNumberText);
        if (trimmedTrackText) {
            NSInteger trackNumber = 0;
            NSInteger totalTracks = 0;
            NSInteger padWidth = 0;
            ParseNumberPairFromNSString(trimmedTrackText, trackNumber, totalTracks, padWidth);
            (void)padWidth;
            SetMP4IntPairItem(mp4Tag, "trkn", trackNumber, totalTracks);
            mp4Tag->setTrack(trackNumber > 0 ? (unsigned int)trackNumber : 0);
            SetMP4TextItem(mp4Tag, kAudioMatorMP4TrackNumberTextKey, trimmedTrackText);
        } else {
            mp4Tag->removeItem("trkn");
            mp4Tag->setTrack(0);
            SetMP4TextItem(mp4Tag, kAudioMatorMP4TrackNumberTextKey, nil);
        }

        if (discNumberText) {
            NSString *trimmedDiscText = TrimmedStringOrNil(discNumberText);
            if (trimmedDiscText) {
                NSInteger discNumber = 0;
                NSInteger totalDiscs = 0;
                NSInteger padWidth = 0;
                ParseNumberPairFromNSString(trimmedDiscText, discNumber, totalDiscs, padWidth);
                (void)padWidth;
                SetMP4IntPairItem(mp4Tag, "disk", discNumber, totalDiscs);
                SetMP4TextItem(mp4Tag, kAudioMatorMP4DiscNumberTextKey, trimmedDiscText);
            } else {
                mp4Tag->removeItem("disk");
                SetMP4TextItem(mp4Tag, kAudioMatorMP4DiscNumberTextKey, nil);
            }
        }

        if (!mp4File.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:57
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save MP4/M4A track/disc numbers" }];
            }
            TLog(@"TagLib save() failed after MP4 track/disc write for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File flacFile(filePath);
        if (!WritePropertyMapNumberTextToFile(flacFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              58,
                                              @"Unable to open FLAC file for writing track/disc numbers",
                                              59,
                                              @"TagLib failed to save FLAC track/disc numbers",
                                              [NSString stringWithFormat:@"FLAC '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);
        if (!WritePropertyMapNumberTextToFile(vorbisFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              96,
                                              @"Unable to open Ogg Vorbis file for writing track/disc numbers",
                                              97,
                                              @"TagLib failed to save Ogg Vorbis track/disc numbers",
                                              [NSString stringWithFormat:@"Ogg Vorbis '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File opusFile(filePath);
        if (!WritePropertyMapNumberTextToFile(opusFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              98,
                                              @"Unable to open Opus file for writing track/disc numbers",
                                              99,
                                              @"TagLib failed to save Opus track/disc numbers",
                                              [NSString stringWithFormat:@"Opus '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File oggFlacFile(filePath);
        if (!WritePropertyMapNumberTextToFile(oggFlacFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              100,
                                              @"Unable to open Ogg FLAC file for writing track/disc numbers",
                                              101,
                                              @"TagLib failed to save Ogg FLAC track/disc numbers",
                                              [NSString stringWithFormat:@"Ogg FLAC '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File speexFile(filePath);
        if (!WritePropertyMapNumberTextToFile(speexFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              102,
                                              @"Unable to open Speex file for writing track/disc numbers",
                                              103,
                                              @"TagLib failed to save Speex track/disc numbers",
                                              [NSString stringWithFormat:@"Speex '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File apeFile(filePath);
        if (!WritePropertyMapNumberTextToFile(apeFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              104,
                                              @"Unable to open APE file for writing track/disc numbers",
                                              105,
                                              @"TagLib failed to save APE track/disc numbers",
                                              [NSString stringWithFormat:@"APE '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File wavPackFile(filePath);
        if (!WritePropertyMapNumberTextToFile(wavPackFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              106,
                                              @"Unable to open WavPack file for writing track/disc numbers",
                                              107,
                                              @"TagLib failed to save WavPack track/disc numbers",
                                              [NSString stringWithFormat:@"WavPack '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File mpcFile(filePath);
        if (!WritePropertyMapNumberTextToFile(mpcFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              108,
                                              @"Unable to open Musepack file for writing track/disc numbers",
                                              109,
                                              @"TagLib failed to save Musepack track/disc numbers",
                                              [NSString stringWithFormat:@"Musepack '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File wavFile(filePath);
        if (!WritePropertyMapNumberTextToFile(wavFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              64,
                                              @"Unable to open WAV file for writing track/disc numbers",
                                              65,
                                              @"TagLib failed to save WAV track/disc numbers",
                                              [NSString stringWithFormat:@"WAV '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File aiffFile(filePath);
        if (!WritePropertyMapNumberTextToFile(aiffFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              66,
                                              @"Unable to open AIFF file for writing track/disc numbers",
                                              67,
                                              @"TagLib failed to save AIFF track/disc numbers",
                                              [NSString stringWithFormat:@"AIFF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File ttaFile(filePath);
        if (!WritePropertyMapNumberTextToFile(ttaFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              110,
                                              @"Unable to open TrueAudio file for writing track/disc numbers",
                                              111,
                                              @"TagLib failed to save TrueAudio track/disc numbers",
                                              [NSString stringWithFormat:@"TrueAudio '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatASF) {
        TagLib::ASF::File asfFile(filePath);
        if (!WritePropertyMapNumberTextToFile(asfFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              112,
                                              @"Unable to open ASF/WMA file for writing track/disc numbers",
                                              113,
                                              @"TagLib failed to save ASF/WMA track/disc numbers",
                                              [NSString stringWithFormat:@"ASF/WMA '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatDSF) {
        TagLib::DSF::File dsfFile(filePath);
        if (!WritePropertyMapNumberTextToFile(dsfFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              114,
                                              @"Unable to open DSF file for writing track/disc numbers",
                                              115,
                                              @"TagLib failed to save DSF track/disc numbers",
                                              [NSString stringWithFormat:@"DSF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatDSDIFF) {
        TagLib::DSDIFF::File dsdiffFile(filePath);
        if (!WritePropertyMapNumberTextToFile(dsdiffFile,
                                              TrimmedStringOrNil(trackNumberText),
                                              discNumberText,
                                              error,
                                              116,
                                              @"Unable to open DSDIFF file for writing track/disc numbers",
                                              117,
                                              @"TagLib failed to save DSDIFF track/disc numbers",
                                              [NSString stringWithFormat:@"DSDIFF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:51
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing track/disc numbers is currently supported for every format that AudioMator can edit metadata for" }];
        }
        return NO;
    }

    TLog(@"Successfully wrote track/disc text to '%@' (TRCK=%@, TPOS=%@)",
         fileURL.lastPathComponent,
         trackNumberText ?: @"<nil>",
         discNumberText ?: @"<nil>");

    return YES;
}
// Write metadata to file (MPEG, MP4/M4A, FLAC, WAV, AIFF supported)
+ (BOOL)writeMetadata:(TagLibAudioMetadata *)metadata
                toURL:(NSURL *)fileURL
                error:(NSError **)error
{
    if (!fileURL || ![fileURL isFileURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:10
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file URL" }];
        }
        return NO;
    }
    
    NSString *ext = fileURL.pathExtension.lowercaseString;
    AudioMatorTagFileFormat format = DetectTagFileFormat(ext);
    AudioMatorMetadataContainerMask containers = ContainerMaskForFormat(format);
    bool isMPEG = format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC;
    bool isAAC = format == AudioMatorTagFileFormatMPEGAAC;
    bool isMP4Like = format == AudioMatorTagFileFormatMP4;

    if (format == AudioMatorTagFileFormatUnknown || containers == AudioMatorMetadataContainerNone) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:11
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing metadata is currently supported for every format that AudioMator can edit metadata for" }];
        }
        TLog(@"Write skipped for '%@' (extension '%@' not supported for writing)", fileURL.lastPathComponent, ext);
        return NO;
    }
    
    // Log the incoming values so we can verify the bridge from Swift is correct
    TLog(@"[WRITE-IN] '%@' title=%@ artist=%@ album=%@ composer=%@ genre=%@ comment=%@ albumArtist=%@ year=%@ track=%ld/%ld disc=%ld/%ld",
         fileURL.lastPathComponent,
         metadata.title ?: @"<nil>",
         metadata.artist ?: @"<nil>",
         metadata.album ?: @"<nil>",
         metadata.composer ?: @"<nil>",
         metadata.genre ?: @"<nil>",
         metadata.comment ?: @"<nil>",
         metadata.albumArtist ?: @"<nil>",
         metadata.year ?: @"<nil>",
         (long)metadata.trackNumber,
         (long)metadata.totalTracks,
         (long)metadata.discNumber,
         (long)metadata.totalDiscs);
    
    const char *filePath = fileURL.path.UTF8String;
    if (isMPEG) {
        TagLib::MPEG::File mpegFile(filePath);

        if (!mpegFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:12
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open file for writing metadata" }];
            }
            TLog(@"Failed to open '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        if (isAAC) {
            ApplyGenericPropertyMapToFile(mpegFile, metadata);
            if (!ApplyPictureComplexProperties(&mpegFile,
                                               metadata,
                                               error,
                                               68,
                                               @"Unable to clear artwork from AAC metadata",
                                               69,
                                               @"Unable to write artwork into AAC metadata",
                                               [NSString stringWithFormat:@"AAC '%@'", fileURL.lastPathComponent])) {
                return NO;
            }

            if (!mpegFile.save()) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:14
                                             userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to AAC file" }];
                }
                TLog(@"TagLib save() failed for AAC '%@'", fileURL.lastPathComponent);
                return NO;
            }
        } else {
            TagLib::Tag *tag = mpegFile.tag();
            if (!tag) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:13
                                             userInfo:@{ NSLocalizedDescriptionKey : @"No tag found to write metadata into" }];
                }
                TLog(@"No tag object available for '%@'", fileURL.lastPathComponent);
                return NO;
            }

            // --- Basic fields via TagLib::Tag ---
            // Only overwrite fields when we have a non-nil NSString from Swift.
            if (metadata.title) {
                tag->setTitle(NSStringToTagString(metadata.title));
            }
            if (metadata.artist) {
                tag->setArtist(NSStringToTagString(metadata.artist));
            }
            if (metadata.album) {
                tag->setAlbum(NSStringToTagString(metadata.album));
            }
            if (metadata.genre) {
                tag->setGenre(NSStringToTagString(metadata.genre));
            }
            if (metadata.comment) {
                tag->setComment(NSStringToTagString(metadata.comment));
            }

            if (metadata.year.length > 0) {
                tag->setYear((unsigned int)metadata.year.integerValue);
            } else {
                tag->setYear(0);
            }

            if (metadata.trackNumber > 0) {
                tag->setTrack((unsigned int)metadata.trackNumber);
            } else {
                tag->setTrack(0);
            }

            // --- ID3v2-specific extended fields ---
            TagLib::ID3v2::Tag *id3v2Tag = mpegFile.ID3v2Tag(true); // create if missing
            if (id3v2Tag) {
                SetID3v2TextFrame(id3v2Tag, "TPE2", metadata.albumArtist);
                SetID3v2TextFrame(id3v2Tag, "TCOM", metadata.composer);
                SetID3v2TextFrame(
                    id3v2Tag,
                    "TBPM",
                    metadata.bpm > 0 ? [NSString stringWithFormat:@"%ld", (long)metadata.bpm] : nil
                );
                SetID3v2TextFrame(id3v2Tag, "TSOT", metadata.sortTitle);
                SetID3v2TextFrame(id3v2Tag, "TSOP", metadata.sortArtist);
                SetID3v2TextFrame(id3v2Tag, "TSOA", metadata.sortAlbum);
                SetID3v2TextFrame(id3v2Tag, "TSO2", metadata.sortAlbumArtist);
                SetID3v2TextFrame(id3v2Tag, "TSOC", metadata.sortComposer);
                SetID3v2TextFrame(id3v2Tag, "TPE3", metadata.conductor);
                SetID3v2TextFrame(id3v2Tag, "TPE4", metadata.remixer);
                SetID3v2TextFrame(id3v2Tag, "TEXT", metadata.lyricist);
                SetID3v2TextFrame(id3v2Tag, "TENC", metadata.encodedBy);
                SetID3v2TextFrame(id3v2Tag, "TSSE", metadata.encoderSettings);
                SetID3v2TextFrame(id3v2Tag, "TSRC", metadata.isrc);
                SetID3v2TextFrame(id3v2Tag, "TCOP", metadata.copyright);
                SetID3v2TextFrame(id3v2Tag, "TIT3", metadata.subtitle);
                SetID3v2TextFrame(id3v2Tag, "TIT1", metadata.grouping);
                SetID3v2TextFrame(id3v2Tag, "TLAN", metadata.language);
                SetID3v2TextFrame(id3v2Tag, "TKEY", metadata.musicalKey);
                SetID3v2TextFrame(id3v2Tag, "TMOO", metadata.mood);
                SetID3v2TextFrame(id3v2Tag, "TMED", metadata.mediaType);
                SetID3v2TextFrame(id3v2Tag, "MVNM", metadata.movement);
                SetID3v2TextFrame(id3v2Tag, "TCMP", metadata.compilation ? @"1" : nil);
                SetID3v2LyricsFrame(id3v2Tag, metadata.lyrics);

                NSString *trackString = TrimmedStringOrNil(metadata.trackNumberText);
                if (!trackString && metadata.trackNumber > 0 && metadata.totalTracks > 0) {
                    trackString = [NSString stringWithFormat:@"%ld/%ld",
                                   (long)metadata.trackNumber,
                                   (long)metadata.totalTracks];
                } else if (!trackString && metadata.trackNumber > 0) {
                    trackString = [NSString stringWithFormat:@"%ld", (long)metadata.trackNumber];
                }
                SetID3v2TextFrame(id3v2Tag, "TRCK", trackString);

                NSString *discString = TrimmedStringOrNil(metadata.discNumberText);
                if (!discString && metadata.discNumber > 0 && metadata.totalDiscs > 0) {
                    discString = [NSString stringWithFormat:@"%ld/%ld",
                                  (long)metadata.discNumber,
                                  (long)metadata.totalDiscs];
                } else if (!discString && metadata.discNumber > 0) {
                    discString = [NSString stringWithFormat:@"%ld", (long)metadata.discNumber];
                }
                SetID3v2TextFrame(id3v2Tag, "TPOS", discString);

                NSString *releaseDate = metadata.releaseDate.length > 0 ? metadata.releaseDate : metadata.year;
                NSString *id3v2Year = metadata.year.length > 0
                    ? metadata.year
                    : (releaseDate.length >= 4 ? [releaseDate substringToIndex:4] : nil);
                SetID3v2TextFrame(
                    id3v2Tag,
                    "TDRL",
                    releaseDate
                );
                SetID3v2TextFrame(id3v2Tag, "TDRC", releaseDate);
                SetID3v2TextFrame(id3v2Tag, "TYER", id3v2Year);
                SetID3v2TextFrame(id3v2Tag, "TDOR", metadata.originalReleaseDate);
                SetID3v2TextFrame(id3v2Tag, "TPUB", metadata.label);
                SetID3v2UserTextFrame(id3v2Tag, "RELEASETYPE", metadata.releaseType);
                SetID3v2UserTextFrame(id3v2Tag, "BARCODE", metadata.barcode);
                SetID3v2UserTextFrame(id3v2Tag, "CATALOGNUMBER", metadata.catalogNumber);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESALBUMID", metadata.itunesAlbumId);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESARTISTID", metadata.itunesArtistId);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESCATALOGID", metadata.itunesCatalogId);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESGENREID", metadata.itunesGenreId);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESMEDIATYPE", metadata.itunesMediaType);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESPURCHASEDATE", metadata.itunesPurchaseDate);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNNORM", metadata.itunesNorm);
                SetID3v2UserTextFrame(id3v2Tag, "ITUNSMPB", metadata.itunesSmpb);
                SetID3v2UserTextFrame(id3v2Tag, "RELEASECOUNTRY", metadata.releaseCountry);
                SetID3v2UserTextFrame(id3v2Tag, "ARTISTTYPE", metadata.artistType);
                SetID3v2UserTextFrame(id3v2Tag, "MusicBrainz Artist Id", metadata.musicBrainzArtistId);
                SetID3v2UserTextFrame(id3v2Tag, "MusicBrainz Album Id", metadata.musicBrainzAlbumId);
                SetID3v2UserTextFrame(id3v2Tag, "MusicBrainz Track Id", metadata.musicBrainzTrackId);
                SetID3v2UserTextFrame(id3v2Tag, "MusicBrainz Release Group Id", metadata.musicBrainzReleaseGroupId);
                SetID3v2UserTextFrame(id3v2Tag, "PRODUCER", metadata.producer);
                SetID3v2UserTextFrame(id3v2Tag, "ENGINEER", metadata.engineer);
                SetID3v2UserTextFrame(id3v2Tag, "REPLAYGAIN_TRACK_GAIN", metadata.replayGainTrack);
                SetID3v2UserTextFrame(id3v2Tag, "REPLAYGAIN_ALBUM_GAIN", metadata.replayGainAlbum);

                // Explicit advisory (TXXX:ITUNESADVISORY, 0 = none, 1 = explicit, 2 = clean)
                // Here we treat `explicitContent == YES` as advisory = 1, otherwise 0.
                if (metadata.explicitContent) {
                    SetID3v2UserTextFrame(id3v2Tag, "ITUNESADVISORY", @"1");
                } else {
                    // If you prefer to completely remove the advisory when non-explicit,
                    // you can change @"0" to nil.
                    SetID3v2UserTextFrame(id3v2Tag, "ITUNESADVISORY", @"0");
                }
                ApplyCustomFieldsToID3v2Tag(id3v2Tag, metadata.customFields);

                if (!ApplyPictureComplexProperties(id3v2Tag,
                                                   metadata,
                                                   error,
                                                   68,
                                                   @"Unable to clear artwork from the ID3v2 tag",
                                                   69,
                                                   @"Unable to write artwork into the ID3v2 tag",
                                                   [NSString stringWithFormat:@"MPEG '%@'", fileURL.lastPathComponent])) {
                    return NO;
                }
            }

            // --- Save ---
            if (!mpegFile.save()) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:14
                                             userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to file" }];
                }
                TLog(@"TagLib save() failed for '%@'", fileURL.lastPathComponent);
                return NO;
            }
        }
    } else if (isMP4Like) {
        TagLib::MP4::File mp4File(filePath);

        if (!mp4File.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:15
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open MP4/M4A file for writing metadata" }];
            }
            TLog(@"Failed to open MP4 '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::MP4::Tag *tag = mp4File.tag();
        if (!tag) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:16
                                         userInfo:@{ NSLocalizedDescriptionKey : @"No MP4 tag found to write metadata into" }];
            }
            TLog(@"No MP4 tag object available for '%@'", fileURL.lastPathComponent);
            return NO;
        }

        // Basic fields
        if (metadata.title)   tag->setTitle(NSStringToTagString(metadata.title));
        if (metadata.artist)  tag->setArtist(NSStringToTagString(metadata.artist));
        if (metadata.album)   tag->setAlbum(NSStringToTagString(metadata.album));
        if (metadata.genre)   tag->setGenre(NSStringToTagString(metadata.genre));
        if (metadata.comment) tag->setComment(NSStringToTagString(metadata.comment));

        if (metadata.year.length > 0) {
            tag->setYear((unsigned int)metadata.year.integerValue);
        } else {
            tag->setYear(0);
        }

        if (metadata.trackNumber > 0) {
            tag->setTrack((unsigned int)metadata.trackNumber);
        } else {
            tag->setTrack(0);
        }

        // Extended MP4 items
        SetMP4TextItem(tag, "aART", metadata.albumArtist);   // Album Artist
        SetMP4TextItem(tag, "\xA9" "wrt", metadata.composer); // Composer
        SetMP4TextItem(tag, "\xA9" "day", metadata.releaseDate.length > 0 ? metadata.releaseDate : metadata.year);
        SetMP4TextItem(tag, "cprt", metadata.copyright);     // Copyright
        SetMP4TextItem(tag, "sonm", metadata.sortTitle);
        SetMP4TextItem(tag, "soar", metadata.sortArtist);
        SetMP4TextItem(tag, "soal", metadata.sortAlbum);
        SetMP4TextItem(tag, "soaa", metadata.sortAlbumArtist);
        SetMP4TextItem(tag, "soco", metadata.sortComposer);
        SetMP4TextItem(tag, "\xA9" "grp", metadata.grouping);
        SetMP4TextItem(tag, "\xA9" "lyr", metadata.lyrics);
        SetMP4TextItem(tag, "\xA9" "too", metadata.encodedBy);

        // Publisher/label convention for MP4 freeform atoms.
        SetMP4TextItem(tag, "----:com.apple.iTunes:LABEL", metadata.label);
        SetMP4TextItem(tag, "----:com.apple.iTunes:ITUNESADVISORY", metadata.explicitContent ? @"1" : @"0");
        SetMP4TextItem(tag, kAudioMatorMP4TrackNumberTextKey, metadata.trackNumberText);
        SetMP4TextItem(tag, kAudioMatorMP4DiscNumberTextKey, metadata.discNumberText);
        SetMP4FreeformTextItem(tag, @"ENCODERSETTINGS", metadata.encoderSettings);
        SetMP4FreeformTextItem(tag, @"SUBTITLE", metadata.subtitle);
        SetMP4FreeformTextItem(tag, @"MOVEMENT", metadata.movement);
        SetMP4FreeformTextItem(tag, @"MOOD", metadata.mood);
        SetMP4FreeformTextItem(tag, @"LANGUAGE", metadata.language);
        SetMP4FreeformTextItem(tag, @"INITIALKEY", metadata.musicalKey);
        SetMP4FreeformTextItem(tag, @"CONDUCTOR", metadata.conductor);
        SetMP4FreeformTextItem(tag, @"REMIXER", metadata.remixer);
        SetMP4FreeformTextItem(tag, @"PRODUCER", metadata.producer);
        SetMP4FreeformTextItem(tag, @"ENGINEER", metadata.engineer);
        SetMP4FreeformTextItem(tag, @"LYRICIST", metadata.lyricist);
        SetMP4FreeformTextItem(tag, @"ISRC", metadata.isrc);
        SetMP4FreeformTextItem(tag, @"ORIGINAL YEAR", metadata.originalReleaseDate);
        SetMP4FreeformTextItem(tag, @"RELEASETYPE", metadata.releaseType);
        SetMP4FreeformTextItem(tag, @"BARCODE", metadata.barcode);
        SetMP4FreeformTextItem(tag, @"CATALOGNUMBER", metadata.catalogNumber);
        SetMP4FreeformTextItem(tag, @"MusicBrainz Album Release Country", metadata.releaseCountry);
        SetMP4FreeformTextItem(tag, @"ARTISTTYPE", metadata.artistType);
        SetMP4FreeformTextItem(tag, @"MusicBrainz Artist Id", metadata.musicBrainzArtistId);
        SetMP4FreeformTextItem(tag, @"MusicBrainz Album Id", metadata.musicBrainzAlbumId);
        SetMP4FreeformTextItem(tag, @"MusicBrainz Track Id", metadata.musicBrainzTrackId);
        SetMP4FreeformTextItem(tag, @"MusicBrainz Release Group Id", metadata.musicBrainzReleaseGroupId);
        SetMP4FreeformTextItem(tag, @"REPLAYGAIN_TRACK_GAIN", metadata.replayGainTrack);
        SetMP4FreeformTextItem(tag, @"REPLAYGAIN_ALBUM_GAIN", metadata.replayGainAlbum);
        SetMP4FreeformTextItem(tag, @"MEDIATYPE", metadata.mediaType);
        SetMP4FreeformTextItem(tag, @"ITUNESALBUMID", metadata.itunesAlbumId);
        SetMP4FreeformTextItem(tag, @"ITUNESARTISTID", metadata.itunesArtistId);
        SetMP4FreeformTextItem(tag, @"ITUNESCATALOGID", metadata.itunesCatalogId);
        SetMP4FreeformTextItem(tag, @"ITUNESGENREID", metadata.itunesGenreId);
        SetMP4FreeformTextItem(tag, @"ITUNESMEDIATYPE", metadata.itunesMediaType);
        SetMP4FreeformTextItem(tag, @"ITUNESPURCHASEDATE", metadata.itunesPurchaseDate);
        SetMP4FreeformTextItem(tag, @"ITUNNORM", metadata.itunesNorm);
        SetMP4FreeformTextItem(tag, @"ITUNSMPB", metadata.itunesSmpb);

        SetMP4IntPairItem(tag, "trkn", metadata.trackNumber, metadata.totalTracks);
        SetMP4IntPairItem(tag, "disk", metadata.discNumber, metadata.totalDiscs);
        if (metadata.bpm > 0) {
            tag->setItem("tmpo", TagLib::MP4::Item((int)metadata.bpm));
        } else {
            tag->removeItem("tmpo");
        }
        if (metadata.compilation) {
            tag->setItem("cpil", TagLib::MP4::Item(true));
        } else {
            tag->removeItem("cpil");
        }

        // iTunes-style explicit rating: 4 = explicit. Remove atom when not explicit.
        if (metadata.explicitContent) {
            tag->setItem("rtng", TagLib::MP4::Item(4));
        } else {
            tag->removeItem("rtng");
        }
        ApplyCustomFieldsToMP4Tag(tag, metadata.customFields);

        if (!ApplyPictureComplexProperties(tag,
                                           metadata,
                                           error,
                                           70,
                                           @"Unable to clear artwork from the MP4 tag",
                                           71,
                                           @"Unable to write artwork into the MP4 tag",
                                           [NSString stringWithFormat:@"MP4 '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!mp4File.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:17
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to MP4/M4A file" }];
            }
            TLog(@"TagLib save() failed for MP4 '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File flacFile(filePath);

        if (!flacFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:18
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open FLAC file for writing metadata" }];
            }
            TLog(@"Failed to open FLAC '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(flacFile, metadata);
        if (!ApplyPictureComplexProperties(&flacFile,
                                           metadata,
                                           error,
                                           72,
                                           @"Unable to clear artwork from the FLAC metadata blocks",
                                           73,
                                           @"Unable to write artwork into the FLAC metadata blocks",
                                           [NSString stringWithFormat:@"FLAC '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!flacFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:19
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to FLAC file" }];
            }
            TLog(@"TagLib save() failed for FLAC '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);

        if (!vorbisFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:118
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open Ogg Vorbis file for writing metadata" }];
            }
            TLog(@"Failed to open Ogg Vorbis '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(vorbisFile, metadata);
        if (!ApplyPictureComplexProperties(vorbisFile.tag(),
                                           metadata,
                                           error,
                                           120,
                                           @"Unable to clear artwork from the Ogg Vorbis comments",
                                           121,
                                           @"Unable to write artwork into the Ogg Vorbis comments",
                                           [NSString stringWithFormat:@"Ogg Vorbis '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!vorbisFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:119
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to Ogg Vorbis file" }];
            }
            TLog(@"TagLib save() failed for Ogg Vorbis '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File opusFile(filePath);

        if (!opusFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:122
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open Opus file for writing metadata" }];
            }
            TLog(@"Failed to open Opus '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(opusFile, metadata);
        if (!ApplyPictureComplexProperties(opusFile.tag(),
                                           metadata,
                                           error,
                                           124,
                                           @"Unable to clear artwork from the Opus comments",
                                           125,
                                           @"Unable to write artwork into the Opus comments",
                                           [NSString stringWithFormat:@"Opus '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!opusFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:123
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to Opus file" }];
            }
            TLog(@"TagLib save() failed for Opus '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File oggFlacFile(filePath);

        if (!oggFlacFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:126
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open Ogg FLAC file for writing metadata" }];
            }
            TLog(@"Failed to open Ogg FLAC '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(oggFlacFile, metadata);
        if (!ApplyPictureComplexProperties(oggFlacFile.tag(),
                                           metadata,
                                           error,
                                           128,
                                           @"Unable to clear artwork from the Ogg FLAC comments",
                                           129,
                                           @"Unable to write artwork into the Ogg FLAC comments",
                                           [NSString stringWithFormat:@"Ogg FLAC '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!oggFlacFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:127
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to Ogg FLAC file" }];
            }
            TLog(@"TagLib save() failed for Ogg FLAC '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File speexFile(filePath);

        if (!speexFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:130
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open Speex file for writing metadata" }];
            }
            TLog(@"Failed to open Speex '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(speexFile, metadata);
        if (!ApplyPictureComplexProperties(speexFile.tag(),
                                           metadata,
                                           error,
                                           132,
                                           @"Unable to clear artwork from the Speex comments",
                                           133,
                                           @"Unable to write artwork into the Speex comments",
                                           [NSString stringWithFormat:@"Speex '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!speexFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:131
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to Speex file" }];
            }
            TLog(@"TagLib save() failed for Speex '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File apeFile(filePath);

        if (!apeFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:134
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open APE file for writing metadata" }];
            }
            TLog(@"Failed to open APE '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(apeFile, metadata);
        if (!ApplyPictureComplexProperties(apeFile.APETag(true),
                                           metadata,
                                           error,
                                           136,
                                           @"Unable to clear artwork from the APE tag",
                                           137,
                                           @"Unable to write artwork into the APE tag",
                                           [NSString stringWithFormat:@"APE '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!apeFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:135
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to APE file" }];
            }
            TLog(@"TagLib save() failed for APE '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File wavPackFile(filePath);

        if (!wavPackFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:138
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open WavPack file for writing metadata" }];
            }
            TLog(@"Failed to open WavPack '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(wavPackFile, metadata);
        if (!ApplyPictureComplexProperties(wavPackFile.APETag(true),
                                           metadata,
                                           error,
                                           140,
                                           @"Unable to clear artwork from the WavPack tag",
                                           141,
                                           @"Unable to write artwork into the WavPack tag",
                                           [NSString stringWithFormat:@"WavPack '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!wavPackFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:139
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to WavPack file" }];
            }
            TLog(@"TagLib save() failed for WavPack '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File mpcFile(filePath);

        if (!mpcFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:142
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open Musepack file for writing metadata" }];
            }
            TLog(@"Failed to open Musepack '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(mpcFile, metadata);
        if (!ApplyPictureComplexProperties(mpcFile.APETag(true),
                                           metadata,
                                           error,
                                           144,
                                           @"Unable to clear artwork from the Musepack tag",
                                           145,
                                           @"Unable to write artwork into the Musepack tag",
                                           [NSString stringWithFormat:@"Musepack '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!mpcFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:143
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to Musepack file" }];
            }
            TLog(@"TagLib save() failed for Musepack '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File wavFile(filePath);

        if (!wavFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:20
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open WAV file for writing metadata" }];
            }
            TLog(@"Failed to open WAV '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(wavFile, metadata);
        if (!ApplyPictureComplexProperties(wavFile.ID3v2Tag(),
                                           metadata,
                                           error,
                                           146,
                                           @"Unable to clear artwork from the WAV ID3v2 tag",
                                           147,
                                           @"Unable to write artwork into the WAV ID3v2 tag",
                                           [NSString stringWithFormat:@"WAV '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!wavFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:21
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to WAV file" }];
            }
            TLog(@"TagLib save() failed for WAV '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File aiffFile(filePath);

        if (!aiffFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:22
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open AIFF file for writing metadata" }];
            }
            TLog(@"Failed to open AIFF '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(aiffFile, metadata);
        if (!ApplyPictureComplexProperties(aiffFile.tag(),
                                           metadata,
                                           error,
                                           148,
                                           @"Unable to clear artwork from the AIFF ID3v2 tag",
                                           149,
                                           @"Unable to write artwork into the AIFF ID3v2 tag",
                                           [NSString stringWithFormat:@"AIFF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!aiffFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:23
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to AIFF file" }];
            }
            TLog(@"TagLib save() failed for AIFF '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File ttaFile(filePath);

        if (!ttaFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:150
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open TrueAudio file for writing metadata" }];
            }
            TLog(@"Failed to open TrueAudio '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(ttaFile, metadata);
        if (!ApplyPictureComplexProperties(ttaFile.ID3v2Tag(true),
                                           metadata,
                                           error,
                                           152,
                                           @"Unable to clear artwork from the TrueAudio ID3v2 tag",
                                           153,
                                           @"Unable to write artwork into the TrueAudio ID3v2 tag",
                                           [NSString stringWithFormat:@"TrueAudio '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!ttaFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:151
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to TrueAudio file" }];
            }
            TLog(@"TagLib save() failed for TrueAudio '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatASF) {
        TagLib::ASF::File asfFile(filePath);

        if (!asfFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:154
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open ASF/WMA file for writing metadata" }];
            }
            TLog(@"Failed to open ASF/WMA '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(asfFile, metadata);
        if (!ApplyPictureComplexProperties(asfFile.tag(),
                                           metadata,
                                           error,
                                           156,
                                           @"Unable to clear artwork from the ASF/WMA tag",
                                           157,
                                           @"Unable to write artwork into the ASF/WMA tag",
                                           [NSString stringWithFormat:@"ASF/WMA '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!asfFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:155
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to ASF/WMA file" }];
            }
            TLog(@"TagLib save() failed for ASF/WMA '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatDSF) {
        TagLib::DSF::File dsfFile(filePath);

        if (!dsfFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:158
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open DSF file for writing metadata" }];
            }
            TLog(@"Failed to open DSF '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(dsfFile, metadata);
        if (!ApplyPictureComplexProperties(dsfFile.tag(),
                                           metadata,
                                           error,
                                           160,
                                           @"Unable to clear artwork from the DSF ID3v2 tag",
                                           161,
                                           @"Unable to write artwork into the DSF ID3v2 tag",
                                           [NSString stringWithFormat:@"DSF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!dsfFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:159
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to DSF file" }];
            }
            TLog(@"TagLib save() failed for DSF '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (format == AudioMatorTagFileFormatDSDIFF) {
        TagLib::DSDIFF::File dsdiffFile(filePath);

        if (!dsdiffFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:162
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open DSDIFF file for writing metadata" }];
            }
            TLog(@"Failed to open DSDIFF '%@' for writing", fileURL.lastPathComponent);
            return NO;
        }

        ApplyGenericPropertyMapToFile(dsdiffFile, metadata);
        if (!ApplyPictureComplexProperties(dsdiffFile.ID3v2Tag(true),
                                           metadata,
                                           error,
                                           164,
                                           @"Unable to clear artwork from the DSDIFF ID3v2 tag",
                                           165,
                                           @"Unable to write artwork into the DSDIFF ID3v2 tag",
                                           [NSString stringWithFormat:@"DSDIFF '%@'", fileURL.lastPathComponent])) {
            return NO;
        }

        if (!dsdiffFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:163
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to DSDIFF file" }];
            }
            TLog(@"TagLib save() failed for DSDIFF '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:11
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing metadata is currently supported for every format that AudioMator can edit metadata for" }];
        }
        return NO;
    }
    


    TLog(@"Successfully wrote metadata to '%@'", fileURL.lastPathComponent);
    return YES;
}

// Wipe (remove) all metadata from a file.
// Currently implemented for MP3 by stripping ID3v1/ID3v2/APE tags.
+ (BOOL)wipeMetadataFromURL:(NSURL *)fileURL
                      error:(NSError **)error
{
    if (!fileURL || ![fileURL isFileURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:30
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file URL" }];
        }
        return NO;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (!filePath) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:31
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Invalid file path" }];
        }
        return NO;
    }

    NSString *ext = fileURL.pathExtension.lowercaseString;

    // Metadata wipe has a full implementation for MP3, where we can strip all supported tag types.
    if (![ext isEqualToString:@"mp3"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:32
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Wiping metadata is currently supported only for MP3 files" }];
        }
        TLog(@"Wipe skipped for '%@' (extension '%@' not supported)", fileURL.lastPathComponent, ext);
        return NO;
    }

    TagLib::MPEG::File mpegFile(filePath);
    if (!mpegFile.isValid()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:33
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open file for wiping metadata" }];
        }
        TLog(@"Failed to open '%@' for wiping", fileURL.lastPathComponent);
        return NO;
    }

    // Remove all tag containers that TagLib can strip from MPEG files.
    // This typically removes ID3v1, ID3v2 and APE tags.
    mpegFile.strip(TagLib::MPEG::File::AllTags, true);

    if (!mpegFile.save()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:34
                                     userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save after wiping metadata" }];
        }
        TLog(@"TagLib save() failed after wiping for '%@'", fileURL.lastPathComponent);
        return NO;
    }

    TLog(@"Successfully wiped metadata for '%@'", fileURL.lastPathComponent);
    return YES;
}


#pragma mark - Raw Metadata Dump (GUI feature)

// Helpers for building a stable, user-facing dump.
static inline void AppendLine(NSMutableString *out, NSString *line) {
    if (!out || !line) return;
    [out appendString:line];
    [out appendString:@"\n"];
}

static inline NSString *NonNil(NSString *s) {
    return s ?: @"";
}

static inline void AppendSectionHeader(NSMutableString *out, NSString *title) {
    if (!out || !title) return;
    if (out.length > 0) {
        AppendLine(out, @"");
    }
    AppendLine(out, title);
}

static NSString *ByteVectorToNSString(const TagLib::ByteVector &data) {
    if (data.isEmpty()) {
        return @"";
    }

    NSString *text = [[NSString alloc] initWithBytes:data.data()
                                              length:data.size()
                                            encoding:NSUTF8StringEncoding];
    if (text.length > 0) {
        return text;
    }

    text = [[NSString alloc] initWithBytes:data.data()
                                    length:data.size()
                                  encoding:NSASCIIStringEncoding];
    if (text.length > 0) {
        return text;
    }

    return [NSString stringWithFormat:@"<%d bytes>", data.size()];
}

static void AppendPropertyMap(NSMutableString *out, const TagLib::PropertyMap &pm) {
    if (!out) return;

    if (pm.isEmpty()) {
        AppendLine(out, @"(none)");
        return;
    }

    bool appendedAnyEntry = false;

    // Iterate PropertyMap directly (portable across TagLib versions).
    for (auto it = pm.begin(); it != pm.end(); ++it) {
        const TagLib::String &k = it->first;
        const TagLib::StringList &vals = it->second;

        NSString *nsKey = TagStringToNSString(k);
        if (!nsKey) nsKey = @"";
        if (IsHiddenInternalMetadataFieldKey(nsKey)) {
            continue;
        }

        NSMutableArray<NSString *> *valueStrings = [NSMutableArray array];
        for (auto vit = vals.begin(); vit != vals.end(); ++vit) {
            NSString *v = TagStringToNSString(*vit);
            [valueStrings addObject:(v ?: @"")];
        }

        NSString *joined = valueStrings.count ? [valueStrings componentsJoinedByString:@"; "] : @"";
        AppendLine(out, [NSString stringWithFormat:@"%@ = %@", nsKey, joined]);
        appendedAnyEntry = true;
    }

    if (!appendedAnyEntry) {
        AppendLine(out, @"(none)");
    }
}

static NSString *MP4ItemToDisplayString(const TagLib::MP4::Item &item) {
    // Prefer string list (many atoms map cleanly here).
    TagLib::StringList sl = item.toStringList();
    if (!sl.isEmpty()) {
        return TagStringToNSString(sl.toString("; ")) ?: @"";
    }

    // Try common scalar representations.
    // Note: We intentionally avoid calling `isEmpty()` on MP4::Item (not available in some TagLib versions).
    // Also avoid throwing conversions by keeping them simple.
    @try {
        int v = item.toInt();
        return [NSString stringWithFormat:@"%d", v];
    } @catch (...) {
        // ignore
    }

    @try {
        TagLib::MP4::Item::IntPair p = item.toIntPair();
        return [NSString stringWithFormat:@"%d/%d", p.first, p.second];
    } @catch (...) {
        // ignore
    }

    @try {
        bool b = item.toBool();
        return b ? @"true" : @"false";
    } @catch (...) {
        // ignore
    }

    // Binary-like / artwork atoms: show a placeholder.
    @try {
        TagLib::MP4::CoverArtList arts = item.toCoverArtList();
        if (!arts.isEmpty()) {
            return [NSString stringWithFormat:@"<CoverArtList: %lu item(s)>", (unsigned long)arts.size()];
        }
    } @catch (...) {
        // ignore
    }

    return @"<unavailable>";
}

static void AppendID3v2FramesSection(NSMutableString *out,
                                     TagLib::ID3v2::Tag *tag,
                                     NSString *title)
{
    AppendSectionHeader(out, title);

    if (!tag) {
        AppendLine(out, @"(none)");
        return;
    }

    TagLib::ID3v2::FrameList frames = tag->frameList();
    if (frames.isEmpty()) {
        AppendLine(out, @"(none)");
        return;
    }

    for (auto fit = frames.begin(); fit != frames.end(); ++fit) {
        TagLib::ID3v2::Frame *frame = *fit;
        if (!frame) continue;

        TagLib::ByteVector frameIdBytes = frame->frameID();
        std::string idStr(frameIdBytes.data(), frameIdBytes.size());
        NSString *fid = idStr.empty() ? @"" : [NSString stringWithUTF8String:idStr.c_str()];
        NSString *val = TagStringToNSString(frame->toString()) ?: @"";

        if (auto userFrame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frame)) {
            NSString *desc = TagStringToNSString(userFrame->description()) ?: @"";
            if (desc.length > 0) {
                AppendLine(out, [NSString stringWithFormat:@"%@ (TXXX:%@) = %@", fid, desc, val]);
                continue;
            }
        }

        if (auto commFrame = dynamic_cast<TagLib::ID3v2::CommentsFrame *>(frame)) {
            NSString *desc = TagStringToNSString(commFrame->description()) ?: @"";
            NSString *lang = TagStringToNSString(commFrame->language()) ?: @"";
            if (desc.length > 0 || lang.length > 0) {
                AppendLine(out, [NSString stringWithFormat:@"%@ (COMM:%@ %@) = %@", fid, desc, lang, val]);
                continue;
            }
        }

        AppendLine(out, [NSString stringWithFormat:@"%@ = %@", fid, val]);
    }
}

static void AppendSimpleTagSection(NSMutableString *out,
                                   NSString *title,
                                   TagLib::Tag *tag)
{
    AppendSectionHeader(out, title);

    if (!tag || tag->isEmpty()) {
        AppendLine(out, @"(none)");
        return;
    }

    bool appended = false;

    NSString *value = TagStringToNSString(tag->title());
    if (value.length > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Title = %@", value]);
        appended = true;
    }

    value = TagStringToNSString(tag->artist());
    if (value.length > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Artist = %@", value]);
        appended = true;
    }

    value = TagStringToNSString(tag->album());
    if (value.length > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Album = %@", value]);
        appended = true;
    }

    value = TagStringToNSString(tag->comment());
    if (value.length > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Comment = %@", value]);
        appended = true;
    }

    value = TagStringToNSString(tag->genre());
    if (value.length > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Genre = %@", value]);
        appended = true;
    }

    if (tag->year() > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Year = %u", tag->year()]);
        appended = true;
    }

    if (tag->track() > 0) {
        AppendLine(out, [NSString stringWithFormat:@"Track = %u", tag->track()]);
        appended = true;
    }

    if (!appended) {
        AppendLine(out, @"(present but empty)");
    }
}

static NSString *APEItemTypeToString(TagLib::APE::Item::ItemTypes type)
{
    switch (type) {
        case TagLib::APE::Item::Text: return @"text";
        case TagLib::APE::Item::Binary: return @"binary";
        case TagLib::APE::Item::Locator: return @"locator";
    }
}

static void AppendAPEItemsSection(NSMutableString *out,
                                  TagLib::APE::Tag *tag,
                                  NSString *title)
{
    AppendSectionHeader(out, title);

    if (!tag) {
        AppendLine(out, @"(none)");
        return;
    }

    const TagLib::APE::ItemListMap &items = tag->itemListMap();
    if (items.isEmpty()) {
        AppendLine(out, @"(none)");
        return;
    }

    for (auto it = items.begin(); it != items.end(); ++it) {
        NSString *key = TagStringToNSString(it->first) ?: @"";
        const TagLib::APE::Item &item = it->second;

        if (item.type() == TagLib::APE::Item::Text) {
            NSMutableArray<NSString *> *values = [NSMutableArray array];
            TagLib::StringList textValues = item.values();
            for (auto vit = textValues.begin(); vit != textValues.end(); ++vit) {
                [values addObject:(TagStringToNSString(*vit) ?: @"")];
            }
            NSString *joined = values.count ? [values componentsJoinedByString:@"; "] : @"";
            AppendLine(out, [NSString stringWithFormat:@"%@ [%@] = %@",
                             key,
                             APEItemTypeToString(item.type()),
                             joined]);
        } else {
            AppendLine(out, [NSString stringWithFormat:@"%@ [%@] = <%d bytes>",
                             key,
                             APEItemTypeToString(item.type()),
                             item.binaryData().size()]);
        }
    }
}

static void AppendXiphCommentSection(NSMutableString *out,
                                     TagLib::Ogg::XiphComment *tag,
                                     NSString *title)
{
    AppendSectionHeader(out, title);

    if (!tag) {
        AppendLine(out, @"(none)");
        return;
    }

    NSString *vendor = TagStringToNSString(tag->vendorID()) ?: @"";
    if (vendor.length > 0) {
        AppendLine(out, [NSString stringWithFormat:@"VENDOR = %@", vendor]);
    }

    const TagLib::Ogg::FieldListMap &fields = tag->fieldListMap();
    if (fields.isEmpty()) {
        AppendLine(out, @"(none)");
        return;
    }

    for (auto it = fields.begin(); it != fields.end(); ++it) {
        NSString *key = TagStringToNSString(it->first) ?: @"";
        NSMutableArray<NSString *> *values = [NSMutableArray array];
        for (auto vit = it->second.begin(); vit != it->second.end(); ++vit) {
            [values addObject:(TagStringToNSString(*vit) ?: @"")];
        }
        NSString *joined = values.count ? [values componentsJoinedByString:@"; "] : @"";
        AppendLine(out, [NSString stringWithFormat:@"%@ = %@", key, joined]);
    }
}

static void AppendRIFFInfoSection(NSMutableString *out,
                                  TagLib::RIFF::Info::Tag *tag,
                                  NSString *title)
{
    AppendSectionHeader(out, title);

    if (!tag) {
        AppendLine(out, @"(none)");
        return;
    }

    TagLib::RIFF::Info::FieldListMap fields = tag->fieldListMap();
    if (fields.isEmpty()) {
        AppendLine(out, @"(none)");
        return;
    }

    for (auto it = fields.begin(); it != fields.end(); ++it) {
        NSString *key = ByteVectorToNSString(it->first);
        NSString *value = TagStringToNSString(it->second) ?: @"";
        AppendLine(out, [NSString stringWithFormat:@"%@ = %@", key, value]);
    }
}

// Return a best-effort, "raw" view of metadata as TagLib sees it.
// This is intended for displaying to users in a GUI, not for programmatic editing.
+ (nullable NSDictionary<NSString *, NSObject *> *)rawMetadataForURL:(NSURL *)fileURL
                                                              error:(NSError *_Nullable *_Nullable)error
{
    (void)error;

    // Always return a dictionary with stable keys so Swift UI can render predictably.
    NSMutableArray<NSDictionary<NSString *, NSObject *> *> *propertiesOut = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, NSObject *> *> *id3v2FramesOut = [NSMutableArray array];

    if (!fileURL || !fileURL.isFileURL) {
        return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
    }

    const char *filePath = fileURL.path.UTF8String;
    if (!filePath) {
        return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
    }

    NSString *ext = fileURL.pathExtension.lowercaseString;
    AudioMatorTagFileFormat format = DetectTagFileFormat(ext);

    // 1) Unified properties: use the same format-specific openers as the main read/write pipeline.
    if (format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC) {
        TagLib::MPEG::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
        }

        // 2) ID3v2 frames (when applicable)
        if (format == AudioMatorTagFileFormatMPEGID3 && f.isValid() && f.ID3v2Tag()) {
            TagLib::ID3v2::Tag *id3 = f.ID3v2Tag();
            TagLib::ID3v2::FrameList frames = id3->frameList();

            for (auto fit = frames.begin(); fit != frames.end(); ++fit) {
                TagLib::ID3v2::Frame *frame = *fit;
                if (!frame) continue;

                TagLib::ByteVector frameIdBytes = frame->frameID();
                std::string idStr(frameIdBytes.data(), frameIdBytes.size());
                NSString *frameID = idStr.empty() ? @"" : [NSString stringWithUTF8String:idStr.c_str()];

                NSString *value = TagStringToNSString(frame->toString()) ?: @"";

                NSMutableDictionary<NSString *, NSObject *> *item = [@{ @"id": frameID ?: @"", @"value": value } mutableCopy];

                if (auto userFrame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frame)) {
                    NSString *desc = TagStringToNSString(userFrame->description()) ?: @"";
                    if (desc.length) item[@"description"] = desc;
                }

                if (auto commFrame = dynamic_cast<TagLib::ID3v2::CommentsFrame *>(frame)) {
                    NSString *desc = TagStringToNSString(commFrame->description()) ?: @"";
                    if (desc.length) item[@"description"] = desc;
                    NSString *lang = TagStringToNSString(commFrame->language()) ?: @"";
                    if (lang.length) item[@"language"] = lang;
                }

                [id3v2FramesOut addObject:item];
            }
        }

        return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
    }

    if (format == AudioMatorTagFileFormatMP4) {
        TagLib::MP4::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
        }

        return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
    }

    if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatASF) {
        TagLib::ASF::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatDSF) {
        TagLib::DSF::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    } else if (format == AudioMatorTagFileFormatDSDIFF) {
        TagLib::DSDIFF::File f(filePath);
        if (f.isValid()) {
            AppendRawPropertyEntries(propertiesOut, f.properties());
            return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
        }
    }

    // Fallback: use FileRef properties only if the format-specific opener failed unexpectedly.
    TagLib::FileRef fileRef(filePath);
    if (!fileRef.isNull() && fileRef.file()) {
        AppendRawPropertyEntries(propertiesOut, fileRef.file()->properties());
    }

    return @{ @"properties": propertiesOut, @"id3v2Frames": id3v2FramesOut };
}

+ (nullable NSString *)dumpMetadataTextFromURL:(NSURL *)fileURL
                                       error:(NSError **)error
{
    if (!fileURL || !fileURL.isFileURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:20
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Invalid file URL" }];
        }
        return nil;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (!filePath) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:21
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Invalid file path" }];
        }
        return nil;
    }

    NSMutableString *out = [NSMutableString string];
    AppendLine(out, [NSString stringWithFormat:@"File: %@", NonNil(fileURL.lastPathComponent)]);
    AppendLine(out, [NSString stringWithFormat:@"Path: %@", NonNil(fileURL.path)]);

    NSString *ext = fileURL.pathExtension.lowercaseString;
    AudioMatorTagFileFormat format = DetectTagFileFormat(ext);
    TagLib::FileRef fileRef(filePath);

    // 1) Unified properties (as TagLib sees them)
    AppendSectionHeader(out, @"[TagLib Properties]");

    bool anyProperties = false;

    if (format == AudioMatorTagFileFormatMPEGID3 || format == AudioMatorTagFileFormatMPEGAAC) {
        TagLib::MPEG::File f(filePath);
        if (f.isValid()) {
            TagLib::PropertyMap pm = f.properties();
            anyProperties = !pm.isEmpty();
            AppendPropertyMap(out, pm);
        } else {
            AppendLine(out, @"(unable to open as MPEG)");
        }
    } else if (format == AudioMatorTagFileFormatMP4) {
        TagLib::MP4::File f(filePath);
        if (f.isValid()) {
            TagLib::PropertyMap pm = f.properties();
            anyProperties = !pm.isEmpty();
            AppendPropertyMap(out, pm);
        } else {
            AppendLine(out, @"(unable to open as MP4)");
        }
    } else {
        if (!fileRef.isNull() && fileRef.file()) {
            TagLib::PropertyMap pm = fileRef.file()->properties();
            anyProperties = !pm.isEmpty();
            AppendPropertyMap(out, pm);
        } else {
            AppendLine(out, @"(unable to open)");
        }
    }

    // 2) Format-specific raw structures (these are what helps with "same field, different names")

    if (format == AudioMatorTagFileFormatMPEGID3) {
        TagLib::MPEG::File f(filePath);
        if (f.isValid()) {
            AppendID3v2FramesSection(out, f.hasID3v2Tag() ? f.ID3v2Tag() : nullptr, @"[ID3v2 Frames]");
            AppendAPEItemsSection(out, f.hasAPETag() ? f.APETag() : nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendID3v2FramesSection(out, nullptr, @"[ID3v2 Frames]");
            AppendAPEItemsSection(out, nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    if (format == AudioMatorTagFileFormatMP4) {
        AppendSectionHeader(out, @"[MP4 ItemMap]");

        TagLib::MP4::File f(filePath);
        if (f.isValid() && f.tag()) {
            const TagLib::MP4::ItemMap &items = f.tag()->itemMap();
            if (items.isEmpty()) {
                AppendLine(out, @"(none)");
            } else {
                bool appendedAnyItem = false;
                for (auto it = items.begin(); it != items.end(); ++it) {
                    NSString *k = TagStringToNSString(it->first) ?: @"";
                    if (IsHiddenInternalMetadataFieldKey(k)) {
                        continue;
                    }
                    NSString *v = MP4ItemToDisplayString(it->second);
                    AppendLine(out, [NSString stringWithFormat:@"%@ = %@", k, v]);
                    appendedAnyItem = true;
                }
                if (!appendedAnyItem) {
                    AppendLine(out, @"(none)");
                }
            }
        } else {
            AppendLine(out, @"(unable to read MP4 tag)");
        }
    }

    if (format == AudioMatorTagFileFormatFLAC) {
        TagLib::FLAC::File f(filePath);
        if (f.isValid()) {
            AppendXiphCommentSection(out, f.hasXiphComment() ? f.xiphComment() : nullptr, @"[Xiph Comment]");
            AppendID3v2FramesSection(out, f.hasID3v2Tag() ? f.ID3v2Tag() : nullptr, @"[ID3v2 Frames]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendXiphCommentSection(out, nullptr, @"[Xiph Comment]");
            AppendID3v2FramesSection(out, nullptr, @"[ID3v2 Frames]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    if (format == AudioMatorTagFileFormatOggVorbis) {
        TagLib::Ogg::Vorbis::File f(filePath);
        AppendXiphCommentSection(out, f.isValid() ? f.tag() : nullptr, @"[Xiph Comment]");
    }

    if (format == AudioMatorTagFileFormatOggFlac) {
        TagLib::Ogg::FLAC::File f(filePath);
        AppendXiphCommentSection(out, f.isValid() ? f.tag() : nullptr, @"[Xiph Comment]");
    }

    if (format == AudioMatorTagFileFormatOggOpus) {
        TagLib::Ogg::Opus::File f(filePath);
        AppendXiphCommentSection(out, f.isValid() ? f.tag() : nullptr, @"[Xiph Comment]");
    }

    if (format == AudioMatorTagFileFormatOggSpeex) {
        TagLib::Ogg::Speex::File f(filePath);
        AppendXiphCommentSection(out, f.isValid() ? f.tag() : nullptr, @"[Xiph Comment]");
    }

    if (format == AudioMatorTagFileFormatAPE) {
        TagLib::APE::File f(filePath);
        AppendAPEItemsSection(out, (f.isValid() && f.hasAPETag()) ? f.APETag() : nullptr, @"[APE Items]");
    }

    if (format == AudioMatorTagFileFormatWAV) {
        TagLib::RIFF::WAV::File f(filePath);
        if (f.isValid()) {
            AppendRIFFInfoSection(out, f.hasInfoTag() ? f.InfoTag() : nullptr, @"[RIFF INFO]");
            AppendID3v2FramesSection(out, f.hasID3v2Tag() ? f.ID3v2Tag() : nullptr, @"[ID3v2 Frames]");
        } else {
            AppendRIFFInfoSection(out, nullptr, @"[RIFF INFO]");
            AppendID3v2FramesSection(out, nullptr, @"[ID3v2 Frames]");
        }
    }

    if (format == AudioMatorTagFileFormatAIFF) {
        TagLib::RIFF::AIFF::File f(filePath);
        AppendID3v2FramesSection(out, (f.isValid() && f.hasID3v2Tag()) ? f.tag() : nullptr, @"[ID3v2 Frames]");
    }

    if (format == AudioMatorTagFileFormatWavPack) {
        TagLib::WavPack::File f(filePath);
        if (f.isValid()) {
            AppendAPEItemsSection(out, f.hasAPETag() ? f.APETag() : nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendAPEItemsSection(out, nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    if (format == AudioMatorTagFileFormatMPC) {
        TagLib::MPC::File f(filePath);
        if (f.isValid()) {
            AppendAPEItemsSection(out, f.hasAPETag() ? f.APETag() : nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendAPEItemsSection(out, nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    if (format == AudioMatorTagFileFormatTTA) {
        TagLib::TrueAudio::File f(filePath);
        if (f.isValid()) {
            AppendID3v2FramesSection(out, f.hasID3v2Tag() ? f.ID3v2Tag() : nullptr, @"[ID3v2 Frames]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendID3v2FramesSection(out, nullptr, @"[ID3v2 Frames]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    // If absolutely nothing useful could be printed, provide a clear message.
    // (Avoid returning nil so the GUI always has something to show.)
    if (!anyProperties && out.length > 0) {
        // Keep as-is; the sections above already printed (none/unable...).
    }

    return out;
}

#pragma mark - Format Support

+ (BOOL)isSupportedFormat:(NSString *)fileExtension {
    return DetectTagFileFormat(fileExtension) != AudioMatorTagFileFormatUnknown;
}

+ (NSArray<NSString *> *)supportedExtensions {
    return @[
        // Lossy formats
        @"mp3", @"mp2",              // MPEG Audio
        @"m4a", @"m4b", @"m4p", @"mp4", @"aac", // AAC/MP4
        @"ogg",                      // Ogg Vorbis
        @"opus",                     // Opus
        @"mpc",                      // Musepack
        @"wma", @"asf",             // Windows Media Audio
        @"spx",                      // Speex
        
        // Lossless formats
        @"flac",                     // FLAC
        @"ape",                      // Monkey's Audio
        @"wv",                       // WavPack
        @"tta",                      // TrueAudio
        @"wav",                      // WAV
        @"aiff", @"aif",             // AIFF
        @"dsf",                      // DSF (DSD)
        @"dff",                      // DSDIFF (DSD)
        @"oga",                      // OGG FLAC
    ];
}


@end
