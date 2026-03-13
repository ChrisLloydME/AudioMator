//
//  TagLibMetadataExtractor.mm
//  HiFidelity
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
static inline void TLog(NSString *format, ...) {
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

static NSString * _Nullable TrimmedStringOrNil(NSString * _Nullable value) {
    if (!value) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

static bool IsMP4LikeExtension(NSString * _Nullable ext) {
    if (!ext) return false;
    NSString *lower = ext.lowercaseString;
    return [lower isEqualToString:@"m4a"] ||
           [lower isEqualToString:@"m4b"] ||
           [lower isEqualToString:@"m4p"] ||
           [lower isEqualToString:@"mp4"];
}

static bool IsMPEGLikeExtension(NSString * _Nullable ext) {
    if (!ext) return false;
    NSString *lower = ext.lowercaseString;
    return [lower isEqualToString:@"mp3"] ||
           [lower isEqualToString:@"mp2"] ||
           [lower isEqualToString:@"aac"];
}

static bool IsAIFFLikeExtension(NSString * _Nullable ext) {
    if (!ext) return false;
    NSString *lower = ext.lowercaseString;
    return [lower isEqualToString:@"aiff"] ||
           [lower isEqualToString:@"aif"];
}

static bool IsPropertyMapWritableExtension(NSString * _Nullable ext) {
    if (!ext) return false;
    NSString *lower = ext.lowercaseString;
    return [lower isEqualToString:@"flac"] ||
           [lower isEqualToString:@"wav"] ||
           IsAIFFLikeExtension(lower);
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

        BOOL explicitValue = metadata.explicitContent;
        if (ParseExplicitTagValue(properties[key].front(), explicitValue)) {
            metadata.explicitContent = explicitValue;
            return;
        }
    }
}

static TagLib::PropertyMap BuildGenericPropertyMap(TagLibAudioMetadata *metadata)
{
    TagLib::PropertyMap properties;
    if (!metadata) return properties;

    SetPropertyMapString(properties, "TITLE", metadata.title);
    SetPropertyMapString(properties, "ARTIST", metadata.artist);
    SetPropertyMapString(properties, "ALBUM", metadata.album);
    SetPropertyMapString(properties, "COMPOSER", metadata.composer);
    SetPropertyMapString(properties, "GENRE", metadata.genre);
    SetPropertyMapString(properties, "COMMENT", metadata.comment);
    SetPropertyMapString(properties, "ALBUMARTIST", metadata.albumArtist);
    SetPropertyMapString(properties, "DATE", metadata.releaseDate.length > 0 ? metadata.releaseDate : metadata.year);
    SetPropertyMapString(properties, "COPYRIGHT", metadata.copyright);
    SetPropertyMapString(properties, "LABEL", metadata.label);
    SetPropertyMapString(properties, "ITUNESADVISORY", metadata.explicitContent ? @"1" : @"0");

    if (metadata.trackNumber > 0 || metadata.totalTracks > 0) {
        NSString *trackText = nil;
        if (metadata.trackNumber > 0 && metadata.totalTracks > 0) {
            trackText = [NSString stringWithFormat:@"%ld/%ld",
                         (long)metadata.trackNumber,
                         (long)metadata.totalTracks];
        } else if (metadata.trackNumber > 0) {
            trackText = [NSString stringWithFormat:@"%ld", (long)metadata.trackNumber];
        }
        SetPropertyMapNumberText(properties, "TRACKNUMBER", trackText);
    } else {
        properties.erase("TRACKNUMBER");
    }

    if (metadata.discNumber > 0 || metadata.totalDiscs > 0) {
        NSString *discText = nil;
        if (metadata.discNumber > 0 && metadata.totalDiscs > 0) {
            discText = [NSString stringWithFormat:@"%ld/%ld",
                        (long)metadata.discNumber,
                        (long)metadata.totalDiscs];
        } else if (metadata.discNumber > 0) {
            discText = [NSString stringWithFormat:@"%ld", (long)metadata.discNumber];
        }
        SetPropertyMapNumberText(properties, "DISCNUMBER", discText);
    } else {
        properties.erase("DISCNUMBER");
    }

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

// Ensure an ID3v2 text frame exists and set its text
static void SetID3v2TextFrame(TagLib::ID3v2::Tag *tag,
                              const char *frameID,
                              NSString * _Nullable value) {
    if (!tag || !frameID) {
        return;
    }
    if (!value || value.length == 0) {
        // For now, do not remove frames when the value is empty.
        return;
    }
    
    TagLib::ID3v2::FrameList frames = tag->frameList(frameID);
    TagLib::ID3v2::TextIdentificationFrame *textFrame = nullptr;
    
    if (!frames.isEmpty()) {
        textFrame = dynamic_cast<TagLib::ID3v2::TextIdentificationFrame *>(frames.front());
    }
    
    TagLib::String tValue(value.UTF8String, TagLib::String::UTF8);
    
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

static NSString * _Nullable FirstStringFromProperty(const TagLib::PropertyMap &properties,
                                                    std::initializer_list<const char *> keys)
{
    for (const char *key : keys) {
        if (!key) continue;
        if (properties.contains(key) && !properties[key].isEmpty()) {
            return TagStringToNSString(properties[key].front());
        }
    }
    return nil;
}

static void ApplyGenericPropertyMapMetadata(const TagLib::PropertyMap &properties,
                                            TagLibAudioMetadata *metadata)
{
    if (!metadata || properties.isEmpty()) return;

    metadata.title = FirstStringFromProperty(properties, {"TITLE"}) ?: metadata.title;
    metadata.artist = FirstStringFromProperty(properties, {"ARTIST", "ARTISTS"}) ?: metadata.artist;
    metadata.album = FirstStringFromProperty(properties, {"ALBUM"}) ?: metadata.album;
    metadata.comment = FirstStringFromProperty(properties, {"COMMENT"}) ?: metadata.comment;
    metadata.genre = FirstStringFromProperty(properties, {"GENRE"}) ?: metadata.genre;
    metadata.composer = FirstStringFromProperty(properties, {"COMPOSER"}) ?: metadata.composer;
    metadata.albumArtist = FirstStringFromProperty(properties, {"ALBUMARTIST"}) ?: metadata.albumArtist;

    NSString *dateValue = FirstStringFromProperty(properties, {"RELEASEDATE", "DATE"});
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

    if (properties.contains("TRACKNUMBER") && !properties["TRACKNUMBER"].isEmpty()) {
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(properties["TRACKNUMBER"].front(), trackNum, trackTotal);
        if (trackNum > 0) metadata.trackNumber = trackNum;
        if (trackTotal > 0) metadata.totalTracks = trackTotal;
    }

    if (properties.contains("DISCNUMBER") && !properties["DISCNUMBER"].isEmpty()) {
        NSInteger discNum = 0, discTotal = 0;
        ParseNumberPair(properties["DISCNUMBER"].front(), discNum, discTotal);
        if (discNum > 0) metadata.discNumber = discNum;
        if (discTotal > 0) metadata.totalDiscs = discTotal;
    }

    NSString *copyrightValue = FirstStringFromProperty(properties, {"COPYRIGHT"});
    if (copyrightValue.length > 0) metadata.copyright = copyrightValue;

    NSString *lyricsValue = FirstStringFromProperty(properties, {"LYRICS"});
    if (lyricsValue.length > 0) metadata.lyrics = lyricsValue;

    NSString *labelValue = FirstStringFromProperty(properties, {"LABEL"});
    if (labelValue.length > 0) metadata.label = labelValue;

    NSString *isrcValue = FirstStringFromProperty(properties, {"ISRC"});
    if (isrcValue.length > 0) metadata.isrc = isrcValue;

    NSString *encodedByValue = FirstStringFromProperty(properties, {"ENCODEDBY", "ENCODING"});
    if (encodedByValue.length > 0) metadata.encodedBy = encodedByValue;

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

    NSString *groupingValue = FirstStringFromProperty(properties, {"GROUPING"});
    if (groupingValue.length > 0) metadata.grouping = groupingValue;

    NSString *subtitleValue = FirstStringFromProperty(properties, {"SUBTITLE"});
    if (subtitleValue.length > 0) metadata.subtitle = subtitleValue;

    NSString *lyricistValue = FirstStringFromProperty(properties, {"LYRICIST"});
    if (lyricistValue.length > 0) metadata.lyricist = lyricistValue;

    NSString *conductorValue = FirstStringFromProperty(properties, {"CONDUCTOR"});
    if (conductorValue.length > 0) metadata.conductor = conductorValue;

    NSString *remixerValue = FirstStringFromProperty(properties, {"REMIXER"});
    if (remixerValue.length > 0) metadata.remixer = remixerValue;

    NSString *producerValue = FirstStringFromProperty(properties, {"PRODUCER"});
    if (producerValue.length > 0) metadata.producer = producerValue;

    NSString *engineerValue = FirstStringFromProperty(properties, {"ENGINEER"});
    if (engineerValue.length > 0) metadata.engineer = engineerValue;

    NSString *moodValue = FirstStringFromProperty(properties, {"MOOD"});
    if (moodValue.length > 0) metadata.mood = moodValue;

    NSString *languageValue = FirstStringFromProperty(properties, {"LANGUAGE"});
    if (languageValue.length > 0) metadata.language = languageValue;

    NSString *releaseTypeValue = FirstStringFromProperty(properties, {"RELEASETYPE"});
    if (releaseTypeValue.length > 0) metadata.releaseType = releaseTypeValue;

    NSString *barcodeValue = FirstStringFromProperty(properties, {"BARCODE", "UPC", "EAN"});
    if (barcodeValue.length > 0) metadata.barcode = barcodeValue;

    NSString *catalogValue = FirstStringFromProperty(properties, {"CATALOGNUMBER"});
    if (catalogValue.length > 0) metadata.catalogNumber = catalogValue;

    NSString *releaseCountryValue = FirstStringFromProperty(properties, {"RELEASECOUNTRY"});
    if (releaseCountryValue.length > 0) metadata.releaseCountry = releaseCountryValue;

    if (properties.contains("BPM") && !properties["BPM"].isEmpty()) {
        metadata.bpm = ExtractNumber(properties["BPM"].front());
    }

    if (properties.contains("COMPILATION") && !properties["COMPILATION"].isEmpty()) {
        TagLib::String comp = properties["COMPILATION"].front();
        metadata.compilation = (comp == "1" || comp.upper() == "TRUE");
    }

    ApplyExplicitPropertyKeys(properties, metadata);
}

#pragma mark - Format-Specific Extraction

// Extract ID3v2 metadata (MP3)
static void ExtractID3v2Metadata(TagLib::ID3v2::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    const TagLib::ID3v2::FrameList& frames = tag->frameList();
    
    for (auto it = frames.begin(); it != frames.end(); ++it) {
        TagLib::ID3v2::Frame* frame = *it;
        TagLib::ByteVector frameID = frame->frameID();
        std::string frameIDStr(frameID.data(), frameID.size());
        
        // Text identification frames
        if (auto textFrame = dynamic_cast<TagLib::ID3v2::TextIdentificationFrame*>(frame)) {
            TagLib::StringList fieldList = textFrame->fieldList();
            if (fieldList.isEmpty()) continue;
            
            TagLib::String value = fieldList.toString(", ");
            
            // Track number
            if (frameIDStr == "TRCK") {
                NSInteger trackNum = 0, trackTotal = 0;
                ParseNumberPair(value, trackNum, trackTotal);
                metadata.trackNumber = trackNum;
                metadata.totalTracks = trackTotal;
            }
            // Disc number
            else if (frameIDStr == "TPOS") {
                NSInteger discNum = 0, discTotal = 0;
                ParseNumberPair(value, discNum, discTotal);
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
            // Compilation flag
            else if (frameIDStr == "TCMP") {
                metadata.compilation = (value == "1");
            }
        }
        // User-defined text frames (TXXX) - for extended metadata
        else if (auto userFrame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame*>(frame)) {
            TagLib::String description = userFrame->description();
            TagLib::StringList userFields = userFrame->fieldList();
            if (userFields.isEmpty()) {
                continue;
            }
            TagLib::String userValue = userFields.back();
            std::string descStr = description.upper().to8Bit(true);
            
            if (descStr == "RELEASETYPE" || descStr == "MUSICBRAINZ ALBUM TYPE") {
                metadata.releaseType = TagStringToNSString(userValue);
            }
            else if (descStr == "BARCODE" || descStr == "UPC" || descStr == "EAN") {
                metadata.barcode = TagStringToNSString(userValue);
            }
            else if (descStr == "CATALOGNUMBER" || descStr == "CATALOG NUMBER") {
                metadata.catalogNumber = TagStringToNSString(userValue);
            }
            else if (descStr == "RELEASECOUNTRY" || descStr == "MUSICBRAINZ ALBUM RELEASE COUNTRY") {
                metadata.releaseCountry = TagStringToNSString(userValue);
            }
            else if (descStr == "ARTISTTYPE" || descStr == "MUSICBRAINZ ARTIST TYPE") {
                metadata.artistType = TagStringToNSString(userValue);
            }
            else if (descStr == "ITUNESADVISORY") {
                BOOL explicitValue = metadata.explicitContent;
                if (ParseExplicitTagValue(userValue, explicitValue)) {
                    metadata.explicitContent = explicitValue;
                }
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
    
    // Track number
    if (items.contains("trkn")) {
        TagLib::MP4::Item::IntPair trackPair = items["trkn"].toIntPair();
        metadata.trackNumber = trackPair.first;
        metadata.totalTracks = trackPair.second;
    }
    
    // Disc number
    if (items.contains("disk")) {
        TagLib::MP4::Item::IntPair discPair = items["disk"].toIntPair();
        metadata.discNumber = discPair.first;
        metadata.totalDiscs = discPair.second;
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
}

// Extract Xiph Comment metadata (FLAC, OGG Vorbis, Opus, etc.)
static void ExtractXiphCommentMetadata(TagLib::Ogg::XiphComment* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    const TagLib::PropertyMap& properties = tag->properties();
    
    // Track/Disc numbers
    if (properties.contains("TRACKNUMBER")) {
        TagLib::String trackStr = properties["TRACKNUMBER"].front();
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(trackStr, trackNum, trackTotal);
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
    
    const TagLib::APE::ItemListMap& items = tag->itemListMap();
    
    // Track/Disc numbers
    if (items.contains("TRACK")) {
        TagLib::String trackStr = items["TRACK"].values().front();
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(trackStr, trackNum, trackTotal);
        metadata.trackNumber = trackNum;
        if (trackTotal > 0) metadata.totalTracks = trackTotal;
    }
    if (items.contains("DISC")) {
        TagLib::String discStr = items["DISC"].values().front();
        NSInteger discNum = 0, discTotal = 0;
        ParseNumberPair(discStr, discNum, discTotal);
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
    std::string ext = [[fileURL pathExtension].lowercaseString UTF8String];

    // Create FileRef for best-effort basic metadata. Some MP4/M4A files expose
    // richer metadata only through the format-specific API, so do not fail early
    // when FileRef or its generic tag view is unavailable.
    TagLib::FileRef fileRef(filePath);
    
    TagLibAudioMetadata* metadata = [[TagLibAudioMetadata alloc] init];
    TLog(@"Created TagLibAudioMetadata object for '%@'", fileURL.lastPathComponent);
    
    // Extract basic tag information
    TagLib::Tag* tag = fileRef.isNull() ? nullptr : fileRef.tag();
    if (tag) {
        metadata.title = TagStringToNSString(tag->title());
        metadata.artist = TagStringToNSString(tag->artist());
        metadata.album = TagStringToNSString(tag->album());
        metadata.genre = TagStringToNSString(tag->genre());
        metadata.comment = TagStringToNSString(tag->comment());
        
        if (tag->year() > 0) {
            metadata.year = [NSString stringWithFormat:@"%u", tag->year()];
        }
        
        if (tag->track() > 0) {
            metadata.trackNumber = tag->track();
        }
    }

    // FileRef's PropertyMap is broader than the legacy Tag view for several containers
    // (for example APE-on-MPEG and many non-core fields), so use it as the first
    // normalization pass before format-specific extraction.
    if (!fileRef.isNull() && fileRef.file()) {
        ApplyGenericPropertyMapMetadata(fileRef.file()->properties(), metadata);
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
    
    // Extract audio properties
    TagLib::AudioProperties* properties = fileRef.isNull() ? nullptr : fileRef.audioProperties();
    if (properties) {
        metadata.duration = properties->lengthInSeconds();
        metadata.bitrate = properties->bitrate();
        metadata.sampleRate = properties->sampleRate();
        metadata.channels = properties->channels();
    }
    
    TLog(@"Audio props for '%@': duration=%.1f s, bitrate=%ld kbps, sampleRate=%ld Hz, channels=%ld",
         fileURL.lastPathComponent,
         metadata.duration,
         (long)metadata.bitrate,
         (long)metadata.sampleRate,
         (long)metadata.channels);
    
    // Extract format-specific metadata
    // MP3
    if (ext == "mp3" || ext == "mp2" || ext == "aac") {
        TagLib::MPEG::File mpegFile(filePath);
        if (mpegFile.isValid()) {
            if (ext == "aac") {
                metadata.codec = @"AAC";
            } else if (ext == "mp2") {
                metadata.codec = @"MP2";
            } else {
                metadata.codec = @"MP3";
            }
            
            if (mpegFile.ID3v2Tag()) {
                ExtractID3v2Metadata(mpegFile.ID3v2Tag(), metadata);
            }

            if (mpegFile.APETag()) {
                ExtractAPEMetadata(mpegFile.APETag(), metadata);
            }

            if (mpegFile.ID3v1Tag()) {
                ApplyGenericPropertyMapMetadata(mpegFile.ID3v1Tag()->properties(), metadata);
            }
        }
    }
    // MP4/M4A
    else if (ext == "m4a" || ext == "m4b" || ext == "m4p" || ext == "mp4") {
        TagLib::MP4::File mp4File(filePath);
        if (mp4File.isValid()) {
            metadata.codec = @"AAC";
            
            if (mp4File.tag()) {
                ExtractMP4Metadata(mp4File.tag(), metadata);
            }
        }
    }
    // FLAC
    else if (ext == "flac") {
        TagLib::FLAC::File flacFile(filePath);
        if (flacFile.isValid()) {
            metadata.codec = @"FLAC";
            
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
    else if (ext == "ogg") {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);
        if (vorbisFile.isValid()) {
            metadata.codec = @"Vorbis";
            
            if (vorbisFile.tag()) {
                ExtractXiphCommentMetadata(vorbisFile.tag(), metadata);
            }
        }
    }
    // Opus
    else if (ext == "opus") {
        TagLib::Ogg::Opus::File opusFile(filePath);
        if (opusFile.isValid()) {
            metadata.codec = @"Opus";
            
            if (opusFile.tag()) {
                ExtractXiphCommentMetadata(opusFile.tag(), metadata);
            }
        }
    }
    // OGG FLAC
    else if (ext == "oga") {
        TagLib::Ogg::FLAC::File oggFlacFile(filePath);
        if (oggFlacFile.isValid()) {
            metadata.codec = @"OGG FLAC";
            
            if (oggFlacFile.tag()) {
                ExtractXiphCommentMetadata(oggFlacFile.tag(), metadata);
            }
        }
    }
    // APE (Monkey's Audio)
    else if (ext == "ape") {
        TagLib::APE::File apeFile(filePath);
        if (apeFile.isValid()) {
            metadata.codec = @"APE";
            
            if (apeFile.APETag()) {
                ExtractAPEMetadata(apeFile.APETag(), metadata);
            }
        }
    }
    // WavPack
    else if (ext == "wv") {
        TagLib::WavPack::File wvFile(filePath);
        if (wvFile.isValid()) {
            metadata.codec = @"WavPack";
            
            if (wvFile.APETag()) {
                ExtractAPEMetadata(wvFile.APETag(), metadata);
            }
        }
    }
    // WAV
    else if (ext == "wav") {
        TagLib::RIFF::WAV::File wavFile(filePath);
        if (wavFile.isValid()) {
            metadata.codec = @"WAV";

            if (wavFile.InfoTag()) {
                ApplyGenericPropertyMapMetadata(wavFile.InfoTag()->properties(), metadata);
            }
            
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
    else if (ext == "aiff" || ext == "aif") {
        TagLib::RIFF::AIFF::File aiffFile(filePath);
        if (aiffFile.isValid()) {
            metadata.codec = @"AIFF";
            
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
    else if (ext == "tta") {
        TagLib::TrueAudio::File ttaFile(filePath);
        if (ttaFile.isValid()) {
            metadata.codec = @"TrueAudio";
            
            if (ttaFile.ID3v2Tag()) {
                ExtractID3v2Metadata(ttaFile.ID3v2Tag(), metadata);
            }

            if (ttaFile.ID3v1Tag()) {
                ApplyGenericPropertyMapMetadata(ttaFile.ID3v1Tag()->properties(), metadata);
            }
            
            // Extract bit depth
            if (ttaFile.audioProperties()) {
                metadata.bitDepth = ttaFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // Musepack
    else if (ext == "mpc") {
        TagLib::MPC::File mpcFile(filePath);
        if (mpcFile.isValid()) {
            metadata.codec = @"Musepack";
            
            if (mpcFile.APETag()) {
                ExtractAPEMetadata(mpcFile.APETag(), metadata);
            }
        }
    }
    // Speex
    else if (ext == "spx") {
        TagLib::Ogg::Speex::File speexFile(filePath);
        if (speexFile.isValid()) {
            metadata.codec = @"Speex";
            
            if (speexFile.tag()) {
                ExtractXiphCommentMetadata(speexFile.tag(), metadata);
            }
        }
    }
    // ASF/WMA
    else if (ext == "wma" || ext == "asf") {
        TagLib::ASF::File asfFile(filePath);
        if (asfFile.isValid()) {
            metadata.codec = @"WMA";
            ApplyGenericPropertyMapMetadata(asfFile.properties(), metadata);
        }
    }
    // DSF
    else if (ext == "dsf") {
        TagLib::DSF::File dsfFile(filePath);
        if (dsfFile.isValid()) {
            metadata.codec = @"DSF";
            
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
    else if (ext == "dff") {
        TagLib::DSDIFF::File dsdiffFile(filePath);
        if (dsdiffFile.isValid()) {
            metadata.codec = @"DSDIFF";
            // DSDIFF metadata is minimal
        }
    }
    
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

    if (fileRef.isNull() && !hasReadableMetadata && metadata.duration <= 0.0 && metadata.bitrate <= 0) {
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
    if (!IsMPEGLikeExtension(ext) && !IsMP4LikeExtension(ext) && !IsPropertyMapWritableExtension(ext)) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:41
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing track numbers is currently supported for MPEG, MP4/M4A, FLAC, WAV and AIFF files" }];
        }
        TLog(@"Track renumber skipped for '%@' (extension '%@' not supported)", fileURL.lastPathComponent, ext);
        return NO;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (IsMPEGLikeExtension(ext)) {
        TagLib::MPEG::File mpegFile(filePath);

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
        if (id3v2Tag) {
            NSString *trck = BuildTRCKString(trackNumber, totalTracks, padWidth);
            if (trck.length > 0) {
                SetID3v2TextFrame(id3v2Tag, "TRCK", trck);
            }
        }

        if (!mpegFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:44
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save after writing track numbers" }];
            }
            TLog(@"TagLib save() failed after track renumbering for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if (IsMP4LikeExtension(ext)) {
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
    } else if ([ext isEqualToString:@"flac"]) {
        TagLib::FLAC::File flacFile(filePath);

        if (!flacFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:48
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open FLAC file for writing track numbers" }];
            }
            TLog(@"Failed to open FLAC '%@' for track renumbering", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::PropertyMap properties = flacFile.properties();
        NSString *trackText = BuildTRCKString(trackNumber, totalTracks, padWidth);
        SetPropertyMapNumberText(properties, "TRACKNUMBER", trackText);
        flacFile.setProperties(properties);

        if (!flacFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:49
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save FLAC track numbers" }];
            }
            TLog(@"TagLib save() failed after FLAC track renumbering for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if ([ext isEqualToString:@"wav"]) {
        TagLib::RIFF::WAV::File wavFile(filePath);

        if (!wavFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:60
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open WAV file for writing track numbers" }];
            }
            TLog(@"Failed to open WAV '%@' for track renumbering", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::PropertyMap properties = wavFile.properties();
        NSString *trackText = BuildTRCKString(trackNumber, totalTracks, padWidth);
        SetPropertyMapNumberText(properties, "TRACKNUMBER", trackText);
        wavFile.setProperties(properties);

        if (!wavFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:61
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save WAV track numbers" }];
            }
            TLog(@"TagLib save() failed after WAV track renumbering for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else {
        TagLib::RIFF::AIFF::File aiffFile(filePath);

        if (!aiffFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:62
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open AIFF file for writing track numbers" }];
            }
            TLog(@"Failed to open AIFF '%@' for track renumbering", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::PropertyMap properties = aiffFile.properties();
        NSString *trackText = BuildTRCKString(trackNumber, totalTracks, padWidth);
        SetPropertyMapNumberText(properties, "TRACKNUMBER", trackText);
        aiffFile.setProperties(properties);

        if (!aiffFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:63
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save AIFF track numbers" }];
            }
            TLog(@"TagLib save() failed after AIFF track renumbering for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    }

    TLog(@"Successfully wrote track numbers to '%@' (track=%ld, total=%ld, padWidth=%ld)",
         fileURL.lastPathComponent,
         (long)trackNumber,
         (long)totalTracks,
         (long)padWidth);

    return YES;
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
    if (!IsMPEGLikeExtension(ext) && !IsMP4LikeExtension(ext) && !IsPropertyMapWritableExtension(ext)) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:51
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing track/disc numbers is currently supported for MPEG, MP4/M4A, FLAC, WAV and AIFF files" }];
        }
        TLog(@"Track/disc write skipped for '%@' (extension '%@' not supported)", fileURL.lastPathComponent, ext);
        return NO;
    }

    const char *filePath = fileURL.path.UTF8String;
    if (IsMPEGLikeExtension(ext)) {
        TagLib::MPEG::File mpegFile(filePath);

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

        // Track
        if (trackNumberText.length > 0) {
            NSInteger trackNumber = 0;
            NSInteger totalTracks = 0;
            NSInteger padWidth = 0;
            ParseNumberPairFromNSString(trackNumberText, trackNumber, totalTracks, padWidth);

            if (trackNumber > 0) {
                tag->setTrack((unsigned int)trackNumber);
            }

            if (id3v2Tag) {
                // Preserve caller-provided formatting (including padding and "/total"),
                // but also ensure we can generate a consistent string when only a number is provided.
                NSString *trimmed = [trackNumberText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *trckToWrite = trimmed;

                // Rebuild from parsed numbers to normalize whitespace and keep padding semantics.
                NSString *rebuilt = BuildTRCKString(trackNumber, totalTracks, padWidth);
                if (rebuilt.length > 0) {
                    trckToWrite = rebuilt;
                }

                if (trckToWrite.length > 0) {
                    SetID3v2TextFrame(id3v2Tag, "TRCK", trckToWrite);
                }
            }
        }

        // Disc (ID3v2 only; TagLib::Tag has no disc setter)
        if (discNumberText.length > 0 && id3v2Tag) {
            // We keep disc text as provided (after trimming). Most software uses TPOS like "1/2".
            NSString *trimmed = [discNumberText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                SetID3v2TextFrame(id3v2Tag, "TPOS", trimmed);
            }
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
    } else if (IsMP4LikeExtension(ext)) {
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

        if (trackNumberText.length > 0) {
            NSInteger trackNumber = 0;
            NSInteger totalTracks = 0;
            NSInteger padWidth = 0;
            ParseNumberPairFromNSString(trackNumberText, trackNumber, totalTracks, padWidth);
            (void)padWidth;
            SetMP4IntPairItem(mp4Tag, "trkn", trackNumber, totalTracks);
            mp4Tag->setTrack(trackNumber > 0 ? (unsigned int)trackNumber : 0);
        }

        if (discNumberText.length > 0) {
            NSInteger discNumber = 0;
            NSInteger totalDiscs = 0;
            NSInteger padWidth = 0;
            ParseNumberPairFromNSString(discNumberText, discNumber, totalDiscs, padWidth);
            (void)padWidth;
            SetMP4IntPairItem(mp4Tag, "disk", discNumber, totalDiscs);
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
    } else if ([ext isEqualToString:@"flac"]) {
        TagLib::FLAC::File flacFile(filePath);

        if (!flacFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:58
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open FLAC file for writing track/disc numbers" }];
            }
            TLog(@"Failed to open FLAC '%@' for track/disc write", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::PropertyMap properties = flacFile.properties();
        if (trackNumberText.length > 0) {
            SetPropertyMapNumberText(properties, "TRACKNUMBER", trackNumberText);
        }
        if (discNumberText.length > 0) {
            SetPropertyMapNumberText(properties, "DISCNUMBER", discNumberText);
        }
        flacFile.setProperties(properties);

        if (!flacFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:59
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save FLAC track/disc numbers" }];
            }
            TLog(@"TagLib save() failed after FLAC track/disc write for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else if ([ext isEqualToString:@"wav"]) {
        TagLib::RIFF::WAV::File wavFile(filePath);

        if (!wavFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:64
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open WAV file for writing track/disc numbers" }];
            }
            TLog(@"Failed to open WAV '%@' for track/disc write", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::PropertyMap properties = wavFile.properties();
        if (trackNumberText.length > 0) {
            SetPropertyMapNumberText(properties, "TRACKNUMBER", trackNumberText);
        }
        if (discNumberText.length > 0) {
            SetPropertyMapNumberText(properties, "DISCNUMBER", discNumberText);
        }
        wavFile.setProperties(properties);

        if (!wavFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:65
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save WAV track/disc numbers" }];
            }
            TLog(@"TagLib save() failed after WAV track/disc write for '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else {
        TagLib::RIFF::AIFF::File aiffFile(filePath);

        if (!aiffFile.isValid()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:66
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Unable to open AIFF file for writing track/disc numbers" }];
            }
            TLog(@"Failed to open AIFF '%@' for track/disc write", fileURL.lastPathComponent);
            return NO;
        }

        TagLib::PropertyMap properties = aiffFile.properties();
        if (trackNumberText.length > 0) {
            SetPropertyMapNumberText(properties, "TRACKNUMBER", trackNumberText);
        }
        if (discNumberText.length > 0) {
            SetPropertyMapNumberText(properties, "DISCNUMBER", discNumberText);
        }
        aiffFile.setProperties(properties);

        if (!aiffFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:67
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save AIFF track/disc numbers" }];
            }
            TLog(@"TagLib save() failed after AIFF track/disc write for '%@'", fileURL.lastPathComponent);
            return NO;
        }
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
    
    bool isMPEG = IsMPEGLikeExtension(ext);
    bool isMP4Like = IsMP4LikeExtension(ext);
    bool isPropertyMapWritable = IsPropertyMapWritableExtension(ext);

    if (!isMPEG && !isMP4Like && !isPropertyMapWritable) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:11
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Writing metadata is currently supported for MPEG, MP4/M4A, FLAC, WAV and AIFF files" }];
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
            // Album artist (TPE2)
            if (metadata.albumArtist) {
                SetID3v2TextFrame(id3v2Tag, "TPE2", metadata.albumArtist);
            }

            // Composer (TCOM)
            if (metadata.composer) {
                SetID3v2TextFrame(id3v2Tag, "TCOM", metadata.composer);
            }

            // Track number / total (TRCK)
            if (metadata.trackNumber > 0 || metadata.totalTracks > 0) {
                NSString *trackString = nil;
                if (metadata.trackNumber > 0 && metadata.totalTracks > 0) {
                    trackString = [NSString stringWithFormat:@"%ld/%ld",
                                   (long)metadata.trackNumber,
                                   (long)metadata.totalTracks];
                } else if (metadata.trackNumber > 0) {
                    trackString = [NSString stringWithFormat:@"%ld", (long)metadata.trackNumber];
                }
                if (trackString.length > 0) {
                    SetID3v2TextFrame(id3v2Tag, "TRCK", trackString);
                }
            }

            // Disc number / total (TPOS)
            if (metadata.discNumber > 0 || metadata.totalDiscs > 0) {
                NSString *discString = nil;
                if (metadata.discNumber > 0 && metadata.totalDiscs > 0) {
                    discString = [NSString stringWithFormat:@"%ld/%ld",
                                  (long)metadata.discNumber,
                                  (long)metadata.totalDiscs];
                } else if (metadata.discNumber > 0) {
                    discString = [NSString stringWithFormat:@"%ld", (long)metadata.discNumber];
                }
                if (discString.length > 0) {
                    SetID3v2TextFrame(id3v2Tag, "TPOS", discString);
                }
            }

            // Release date (TDRL) – prefer explicit releaseDate, fallback to year
            if (metadata.releaseDate.length > 0) {
                SetID3v2TextFrame(id3v2Tag, "TDRL", metadata.releaseDate);
            } else if (metadata.year.length > 0) {
                SetID3v2TextFrame(id3v2Tag, "TDRL", metadata.year);
            }

            // Copyright (TCOP)
            if (metadata.copyright.length > 0) {
                SetID3v2TextFrame(id3v2Tag, "TCOP", metadata.copyright);
            }

            // Publisher / label (TPUB)
            if (metadata.label.length > 0) {
                SetID3v2TextFrame(id3v2Tag, "TPUB", metadata.label);
            }

            // Explicit advisory (TXXX:ITUNESADVISORY, 0 = none, 1 = explicit, 2 = clean)
            // Here we treat `explicitContent == YES` as advisory = 1, otherwise 0.
            if (metadata.explicitContent) {
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESADVISORY", @"1");
            } else {
                // If you prefer to completely remove the advisory when non-explicit,
                // you can change @"0" to nil.
                SetID3v2UserTextFrame(id3v2Tag, "ITUNESADVISORY", @"0");
            }

            if (metadata.removeArtwork) {
                if (!id3v2Tag->setComplexProperties("PICTURE", TagLib::List<TagLib::VariantMap>())) {
                    if (error) {
                        *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                     code:68
                                                 userInfo:@{ NSLocalizedDescriptionKey : @"Unable to clear artwork from the ID3v2 tag" }];
                    }
                    TLog(@"Failed to clear artwork for '%@' via ID3v2 complex properties", fileURL.lastPathComponent);
                    return NO;
                }
            } else if (metadata.artworkData.length > 0) {
                if (!id3v2Tag->setComplexProperties("PICTURE", BuildPictureComplexProperties(metadata))) {
                    if (error) {
                        *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                     code:69
                                                 userInfo:@{ NSLocalizedDescriptionKey : @"Unable to write artwork into the ID3v2 tag" }];
                    }
                    TLog(@"Failed to write artwork for '%@' via ID3v2 complex properties", fileURL.lastPathComponent);
                    return NO;
                }
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

        // Publisher/label convention for MP4 freeform atoms.
        SetMP4TextItem(tag, "----:com.apple.iTunes:LABEL", metadata.label);
        SetMP4TextItem(tag, "----:com.apple.iTunes:ITUNESADVISORY", metadata.explicitContent ? @"1" : @"0");

        SetMP4IntPairItem(tag, "trkn", metadata.trackNumber, metadata.totalTracks);
        SetMP4IntPairItem(tag, "disk", metadata.discNumber, metadata.totalDiscs);

        // iTunes-style explicit rating: 4 = explicit. Remove atom when not explicit.
        if (metadata.explicitContent) {
            tag->setItem("rtng", TagLib::MP4::Item(4));
        } else {
            tag->removeItem("rtng");
        }

        if (metadata.removeArtwork) {
            if (!tag->setComplexProperties("PICTURE", TagLib::List<TagLib::VariantMap>())) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:70
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Unable to clear artwork from the MP4 tag" }];
                }
                TLog(@"Failed to clear artwork for MP4 '%@'", fileURL.lastPathComponent);
                return NO;
            }
        } else if (metadata.artworkData.length > 0) {
            if (!tag->setComplexProperties("PICTURE", BuildPictureComplexProperties(metadata))) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:71
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Unable to write artwork into the MP4 tag" }];
                }
                TLog(@"Failed to write artwork for MP4 '%@'", fileURL.lastPathComponent);
                return NO;
            }
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
    } else if ([ext isEqualToString:@"flac"]) {
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

        TagLib::PropertyMap properties = BuildGenericPropertyMap(metadata);
        flacFile.setProperties(properties);

        if (metadata.removeArtwork) {
            if (!flacFile.setComplexProperties("PICTURE", TagLib::List<TagLib::VariantMap>())) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:72
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Unable to clear artwork from the FLAC metadata blocks" }];
                }
                TLog(@"Failed to clear artwork for FLAC '%@'", fileURL.lastPathComponent);
                return NO;
            }
        } else if (metadata.artworkData.length > 0) {
            if (!flacFile.setComplexProperties("PICTURE", BuildPictureComplexProperties(metadata))) {
                if (error) {
                    *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                                 code:73
                                             userInfo:@{ NSLocalizedDescriptionKey : @"Unable to write artwork into the FLAC metadata blocks" }];
                }
                TLog(@"Failed to write artwork for FLAC '%@'", fileURL.lastPathComponent);
                return NO;
            }
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
    } else if ([ext isEqualToString:@"wav"]) {
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

        TagLib::PropertyMap properties = BuildGenericPropertyMap(metadata);
        wavFile.setProperties(properties);

        if (!wavFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:21
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to WAV file" }];
            }
            TLog(@"TagLib save() failed for WAV '%@'", fileURL.lastPathComponent);
            return NO;
        }
    } else {
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

        TagLib::PropertyMap properties = BuildGenericPropertyMap(metadata);
        aiffFile.setProperties(properties);

        if (!aiffFile.save()) {
            if (error) {
                *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                             code:23
                                         userInfo:@{ NSLocalizedDescriptionKey : @"TagLib failed to save metadata to AIFF file" }];
            }
            TLog(@"TagLib save() failed for AIFF '%@'", fileURL.lastPathComponent);
            return NO;
        }
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

    // For now, implement a robust wipe for MP3 by stripping all supported tag types.
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

    // Iterate PropertyMap directly (portable across TagLib versions).
    for (auto it = pm.begin(); it != pm.end(); ++it) {
        const TagLib::String &k = it->first;
        const TagLib::StringList &vals = it->second;

        NSString *nsKey = TagStringToNSString(k);
        if (!nsKey) nsKey = @"";

        NSMutableArray<NSString *> *valueStrings = [NSMutableArray array];
        for (auto vit = vals.begin(); vit != vals.end(); ++vit) {
            NSString *v = TagStringToNSString(*vit);
            [valueStrings addObject:(v ?: @"")];
        }

        NSString *joined = valueStrings.count ? [valueStrings componentsJoinedByString:@"; "] : @"";
        AppendLine(out, [NSString stringWithFormat:@"%@ = %@", nsKey, joined]);
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

    // 1) Unified properties: prefer format-specific File classes when possible.
    std::string ext = [[fileURL pathExtension].lowercaseString UTF8String];

    if (ext == "mp3") {
        TagLib::MPEG::File f(filePath);
        if (f.isValid()) {
            TagLib::PropertyMap pm = f.properties();
            for (auto pit = pm.begin(); pit != pm.end(); ++pit) {
                NSString *nsKey = TagStringToNSString(pit->first) ?: @"";
                NSMutableArray<NSString *> *values = [NSMutableArray array];
                for (auto vit = pit->second.begin(); vit != pit->second.end(); ++vit) {
                    [values addObject:(TagStringToNSString(*vit) ?: @"")];
                }
                NSString *joined = values.count ? [values componentsJoinedByString:@"; "] : @"";
                [propertiesOut addObject:@{ @"key": nsKey, @"value": joined, @"values": values, @"count": @(values.count) }];
            }
        }

        // 2) ID3v2 frames (when applicable)
        if (f.isValid() && f.ID3v2Tag()) {
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

    // Fallback: use FileRef properties for other formats.
    TagLib::FileRef fileRef(filePath);
    if (!fileRef.isNull() && fileRef.file()) {
        TagLib::PropertyMap pm = fileRef.file()->properties();
        for (auto pit = pm.begin(); pit != pm.end(); ++pit) {
            NSString *nsKey = TagStringToNSString(pit->first) ?: @"";
            NSMutableArray<NSString *> *values = [NSMutableArray array];
            for (auto vit = pit->second.begin(); vit != pit->second.end(); ++vit) {
                [values addObject:(TagStringToNSString(*vit) ?: @"")];
            }
            NSString *joined = values.count ? [values componentsJoinedByString:@"; "] : @"";
            [propertiesOut addObject:@{ @"key": nsKey, @"value": joined, @"values": values, @"count": @(values.count) }];
        }
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

    std::string ext = [[fileURL pathExtension].lowercaseString UTF8String];
    TagLib::FileRef fileRef(filePath);

    // 1) Unified properties (as TagLib sees them)
    AppendSectionHeader(out, @"[TagLib Properties]");

    bool anyProperties = false;

    if (IsMPEGLikeExtension(fileURL.pathExtension)) {
        TagLib::MPEG::File f(filePath);
        if (f.isValid()) {
            TagLib::PropertyMap pm = f.properties();
            anyProperties = !pm.isEmpty();
            AppendPropertyMap(out, pm);
        } else {
            AppendLine(out, @"(unable to open as MPEG)");
        }
    } else if (ext == "m4a" || ext == "m4b" || ext == "m4p" || ext == "mp4") {
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

    if (IsMPEGLikeExtension(fileURL.pathExtension)) {
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

    if (ext == "m4a" || ext == "m4b" || ext == "m4p" || ext == "mp4") {
        AppendSectionHeader(out, @"[MP4 ItemMap]");

        TagLib::MP4::File f(filePath);
        if (f.isValid() && f.tag()) {
            const TagLib::MP4::ItemMap &items = f.tag()->itemMap();
            if (items.isEmpty()) {
                AppendLine(out, @"(none)");
            } else {
                for (auto it = items.begin(); it != items.end(); ++it) {
                    NSString *k = TagStringToNSString(it->first) ?: @"";
                    NSString *v = MP4ItemToDisplayString(it->second);
                    AppendLine(out, [NSString stringWithFormat:@"%@ = %@", k, v]);
                }
            }
        } else {
            AppendLine(out, @"(unable to read MP4 tag)");
        }
    }

    if (ext == "flac") {
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

    if (ext == "ogg" || ext == "oga") {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);
        if (vorbisFile.isValid()) {
            AppendXiphCommentSection(out, vorbisFile.tag(), @"[Xiph Comment]");
        } else {
            TagLib::Ogg::FLAC::File oggFlacFile(filePath);
            if (oggFlacFile.isValid()) {
                AppendXiphCommentSection(out, oggFlacFile.tag(), @"[Xiph Comment]");
            } else {
                AppendXiphCommentSection(out, nullptr, @"[Xiph Comment]");
            }
        }
    }

    if (ext == "opus") {
        TagLib::Ogg::Opus::File f(filePath);
        AppendXiphCommentSection(out, f.isValid() ? f.tag() : nullptr, @"[Xiph Comment]");
    }

    if (ext == "spx") {
        TagLib::Ogg::Speex::File f(filePath);
        AppendXiphCommentSection(out, f.isValid() ? f.tag() : nullptr, @"[Xiph Comment]");
    }

    if (ext == "ape") {
        TagLib::APE::File f(filePath);
        AppendAPEItemsSection(out, (f.isValid() && f.hasAPETag()) ? f.APETag() : nullptr, @"[APE Items]");
    }

    if (ext == "wav") {
        TagLib::RIFF::WAV::File f(filePath);
        if (f.isValid()) {
            AppendRIFFInfoSection(out, f.hasInfoTag() ? f.InfoTag() : nullptr, @"[RIFF INFO]");
            AppendID3v2FramesSection(out, f.hasID3v2Tag() ? f.ID3v2Tag() : nullptr, @"[ID3v2 Frames]");
        } else {
            AppendRIFFInfoSection(out, nullptr, @"[RIFF INFO]");
            AppendID3v2FramesSection(out, nullptr, @"[ID3v2 Frames]");
        }
    }

    if (IsAIFFLikeExtension(fileURL.pathExtension)) {
        TagLib::RIFF::AIFF::File f(filePath);
        AppendID3v2FramesSection(out, (f.isValid() && f.hasID3v2Tag()) ? f.tag() : nullptr, @"[ID3v2 Frames]");
    }

    if (ext == "wv") {
        TagLib::WavPack::File f(filePath);
        if (f.isValid()) {
            AppendAPEItemsSection(out, f.hasAPETag() ? f.APETag() : nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendAPEItemsSection(out, nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    if (ext == "mpc") {
        TagLib::MPC::File f(filePath);
        if (f.isValid()) {
            AppendAPEItemsSection(out, f.hasAPETag() ? f.APETag() : nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", f.hasID3v1Tag() ? f.ID3v1Tag() : nullptr);
        } else {
            AppendAPEItemsSection(out, nullptr, @"[APE Items]");
            AppendSimpleTagSection(out, @"[ID3v1 Tag]", nullptr);
        }
    }

    if (ext == "tta") {
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
    NSArray<NSString *>* supported = [self supportedExtensions];
    return [supported containsObject:[fileExtension lowercaseString]];
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
