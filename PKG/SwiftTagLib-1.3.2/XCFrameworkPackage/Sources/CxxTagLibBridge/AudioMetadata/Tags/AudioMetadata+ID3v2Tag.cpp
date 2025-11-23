
#import <CxxTagLibBridge/AudioMetadata.hpp>
#import <taglib/id3v2frame.h>
#import <taglib/attachedpictureframe.h>
#import <taglib/popularimeterframe.h>
#import <taglib/textidentificationframe.h>
#import <string_view>
#import <taglib/unsynchronizedlyricsframe.h>
//#import <taglib/relativevolumeframe.h>

// MARK: - Keys
namespace MetadataKey {
    struct ID3v2 final {
        // album
//        static constexpr const char* albumV2_2 = "TAL";
//        static constexpr const char* albumV2_3 = "TALB";
        // artist
//        static constexpr const char* artist = "TPE1";
        // genre
//        static constexpr const char* genreV2_2 = "TCO";
//        static constexpr const char* genreV2_3 = "TCON";
        static constexpr const char* releaseDate = "TDRC";
        // comment
//        static constexpr const char* commentV2_2 = "COM";
//        static constexpr const char* commentV2_3 = "COMM";
        // title
//        static constexpr const char* titleV2_2 = "TT2";
//        static constexpr const char* titleV2_3 = "TIT2";
        static constexpr const char* track = "TRCK"; // both trackNumber & trackTotal
        static constexpr const char* disc = "TPOS"; // both discNumber & discTotal
        static constexpr const char* composer = "TCOM";
        static constexpr const char* albumArtist = "TPE2";
        static constexpr const char* bpm = "TBPM";
        static constexpr const char* rating = "POPM";
        static constexpr const char* lyrics = "USLT";
        static constexpr const char* compilation = "TCMP";
        static constexpr const char* isrc = "TSRC";
        static constexpr const char* mcn = "CATALOGNUMBER";
        static constexpr const char* musicBrainzReleaseID = "MusicBrainz Album Id";
        static constexpr const char* musicBrainzRecordingID = "MusicBrainz Track Id";
        static constexpr const char* pictures = "APIC";
    };
}

// MARK: - Read
/// constructor for `AudioMetadata` from `TagLib::ID3v2::Tag`.
AudioMetadata AudioMetadata::read_from_ID3v2_tag(const TagLib::ID3v2::Tag *tag, const MetadataReadingOptions options) {
    AudioMetadata metadata = AudioMetadata::read_from_tag(tag, options);
    metadata.tagSource |= TagSource::ID3v2;

    using Key = MetadataKey::ID3v2;
    using Type = AudioMetadata;

    auto none_if_empty = [] (const char* string) -> std::optional<std::string> {
        return (!std::string_view(string).empty()) ? std::optional<std::string>(string) : std::nullopt;
    };

    auto read_string = [&metadata, &tag] (const char* key, std::optional<std::string> Type:: *memberPointer, bool isUnicode = false) {
        auto frameList = tag->frameListMap()[key];
        if (!frameList.isEmpty()) {
            auto frame = frameList.front();
            std::string string = frame->toString().toCString(isUnicode);
            if (!string.empty()) {
                auto &property = metadata.*memberPointer;
                property = string;
            }
        }
    };

    auto read_int_pair = [&metadata, &tag] (const char* key, std::optional<int> Type:: *firstMemberPointer, std::optional<int> Type:: *secondMemberPointer) {
        auto frameList = tag->frameListMap()[key];
        if (!frameList.isEmpty()) {
            auto string = frameList.front()->toString();
            bool ok;
            auto pos = string.find("/", 0);
            if (-1 != pos) {
                auto upos = static_cast<unsigned int>(pos);
                int first = string.substr(0, upos).toInt(&ok);
                if (ok && first != 0) {
                    auto &firstProperty = metadata.*firstMemberPointer;
                    firstProperty = first;
                }
                int second = string.substr(upos + 1).toInt(&ok);
                if (ok && second != 0) {
                    auto &secondProperty = metadata.*secondMemberPointer;
                    secondProperty = second;
                }
            } else if (!string.isEmpty()) {
                int first = string.toInt(&ok);
                if (ok && first != 0) {
                    auto &firstProperty = metadata.*firstMemberPointer;
                    firstProperty = first;
                }
            }
        }
    };

    auto read_int = [&metadata, &tag] (const char* key, std::optional<int> Type:: *memberPointer) {
        auto frameList = tag->frameListMap()[key];
        if (!frameList.isEmpty()) {
            auto frame = frameList.front();
            bool ok;
            auto value = frame->toString().toInt(&ok);
            if (ok && value != 0) {
                auto &property = metadata.*memberPointer;
                property = value;
            }
        }
    };

    auto read_bool = [&metadata, &tag] (const char* key, std::optional<bool> Type:: *memberPointer) {
        auto frameList = tag->frameListMap()[key];
        if (!frameList.isEmpty()) {
            auto frame = frameList.front();
            bool ok;
            auto value = frame->toString().toInt(&ok);
            if (ok) {
                auto &property = metadata.*memberPointer;
                if (value == 0) {
                    property = std::optional<bool>(false);
                } else if (value == 1) {
                    property = std::optional<bool>(true);
                }
            }
        }
    };

    auto read_user_string = [&metadata, &tag] (const char* key, std::optional<std:: string> Type:: *memberPointer, bool isUnicode = true) {
        auto frame = TagLib::ID3v2::UserTextIdentificationFrame::find(tag, key);
        if (frame) {
            std::string string = frame->fieldList().back().toCString(isUnicode);
            if (!string.empty()) {
                auto &property = metadata.*memberPointer;
                property = string;
            }
        }
    };

    metadata.title = none_if_empty(tag->title().toCString(true));
    metadata.albumTitle = none_if_empty(tag->album().toCString(true));
    metadata.artist = none_if_empty(tag->artist().toCString(true));
    metadata.genre = none_if_empty(tag->genre().toCString(true));
    metadata.comment = none_if_empty(tag->comment().toCString(true));

    read_string(Key::releaseDate, &Type::releaseDate, true);
    read_int_pair(Key::track, &Type::trackNumber, &Type::trackTotal);
    read_int_pair(Key::disc, &Type::discNumber, &Type::discTotal);
    read_string(Key::composer, &Type::composer, false);
    read_string(Key::albumArtist, &Type::albumArtist, false);
    read_int(Key::bpm, &Type::beatPerMinute);

    /// well, yeah special case
    TagLib::ID3v2::PopularimeterFrame *popularimeter = nullptr;
    auto ratingFrameList = tag->frameListMap()[Key::rating];
    if (
        !ratingFrameList.isEmpty()
        && nullptr != (popularimeter = dynamic_cast<TagLib::ID3v2::PopularimeterFrame *>(ratingFrameList.front()))
    ) {
        auto value = popularimeter->rating();
        if (value != 0) {
            metadata.rating = value;
        }
    }

    read_string(Key::lyrics, &Type::lyrics, true);
    read_bool(Key::compilation, &Type::compilation);
    read_string(Key::isrc, &Type::internationalStandardRecordingCode);
    read_user_string(Key::mcn, &Type::mediaCatalogNumber);
    read_user_string(Key::musicBrainzReleaseID, &Type::musicBrainzReleaseID);
    read_user_string(Key::musicBrainzRecordingID, &Type::musicBrainzRecordingID);

    for (auto iterator: tag->frameListMap()[Key::pictures]) {
        TagLib::ID3v2::AttachedPictureFrame *frame = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(iterator);
        ++metadata.attachedPicturesCount;
        /// if theres no need to read pictures skip this step.
        if (options & MetadataReadingOptions::skipPictures) {
            continue;
        }
        auto picture = AudioMetadata::Picture::create_from_ID3v2Picture(frame);
        if (picture.has_value()) {
            metadata.attachedPictures.push_back(picture.value());
        } else {
            --metadata.attachedPicturesCount;
        }
    }
    return metadata;
}

// MARK: - Write
/// fills`TagLib::ID3v2::Tag` from `AudioMetadata`.
void AudioMetadata::write_to_ID3v2_tag(TagLib::ID3v2::Tag *tag, bool shouldWritePictures) const {
    using Key = MetadataKey::ID3v2;

    auto empty_if_none = [](std::optional<std::string> optional) -> TagLib::String {
        return optional.has_value() ? TagLib::String(optional.value()) : TagLib::String();
    };

    auto write_string = [&tag] (const char* key, std::optional<std::string> optional) {
        tag->removeFrames(key);
        if (optional.has_value()) {
            auto frame = new TagLib::ID3v2::TextIdentificationFrame(key, TagLib::String::Latin1);
            auto value = TagLib::String(optional.value(), TagLib::String::UTF8);
            frame->setText(value);
            tag->addFrame(frame);
        }
    };

    auto write_user_string = [&tag] (const char* key, std::optional<std::string> optioanl) {
        auto foundFrame = TagLib::ID3v2::UserTextIdentificationFrame::find(tag, key);
        if (foundFrame) {
            tag->removeFrame(foundFrame, true);
        }
        if (optioanl.has_value()) {
            auto frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
            frame->setDescription(key);
            frame->setText(TagLib::String(optioanl.value(), TagLib::String::Latin1));
            tag->addFrame(frame);
        }
    };

    auto write_int_pair = [&tag] (const char* key, std::optional<int> first, std::optional<int> second) {
        tag->removeFrames(key);
        if (first.has_value() && second.has_value()) {
            auto frame = new TagLib::ID3v2::TextIdentificationFrame(key, TagLib::String::Latin1);
            auto string = std::to_string(first.value()) + "/" + std::to_string(second.value());
            auto value = TagLib::String(string, TagLib::String::UTF8);
            frame->setText(value);
            tag->addFrame(frame);
        }
    };

    auto write_int = [&tag] (const char* key, std::optional<int> optional) {
        tag->removeFrames(key);
        if (optional.has_value()) {
            auto frame = new TagLib::ID3v2::TextIdentificationFrame(key, TagLib::String::Latin1);
            auto string = std::to_string(optional.value());
            auto value = TagLib::String(string, TagLib::String::UTF8);
            frame->setText(value);
            tag->addFrame(frame);
        }
    };

    auto write_bool = [&tag] (const char* key, std::optional<bool> optional) {
        tag->removeFrames(key);
        if (optional.has_value()) {
            auto frame = new TagLib::ID3v2::TextIdentificationFrame(key, TagLib::String::Latin1);
            auto flag = std::to_string(optional.value() ? 1 : 0);
            auto value = TagLib::String(flag);
            frame->setText(value);
            tag->addFrame(frame);
        }
    };


    /*
     The timestamp fields are based on a subset of ISO 8601. When being as
     precise as possible the format of a time string is
     yyyy-MM-ddTHH:mm:ss (year, "-", month, "-", day, "T", hour (out of
     24), ":", minutes, ":", seconds), but the precision may be reduced by
     removing as many time indicators as wanted. Hence valid timestamps
     are
     yyyy, yyyy-MM, yyyy-MM-dd, yyyy-MM-ddTHH, yyyy-MM-ddTHH:mm and
     yyyy-MM-ddTHH:mm:ss. All time stamps are UTC. For durations, use
     the slash character as described in 8601, and for multiple non-
     contiguous dates, use multiple strings, if allowed by the frame
     definition.
     */
    auto release_date_to_year_transfromer = [](std::optional<std::string> optional) -> unsigned int {
        if (optional.has_value()) {
            const std::string yearSubstring = optional.value().substr(0, 4);
            if (std::all_of(yearSubstring.begin(), yearSubstring.end(), isdigit)) {
                unsigned int year = static_cast<unsigned int>(std::stoul(yearSubstring));
                return year;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    };

    // Use UTF-8 as the default encoding
    TagLib::ID3v2::FrameFactory::instance()->setDefaultTextEncoding(TagLib::String::UTF8);

    tag->setTitle(empty_if_none(title));
    tag->setAlbum(empty_if_none(albumTitle));
    tag->setArtist(empty_if_none(artist));
    tag->setGenre(empty_if_none(genre));
    tag->setComment(empty_if_none(comment));
    write_string(Key::releaseDate, releaseDate);
    tag->setYear(release_date_to_year_transfromer(releaseDate));

    /// **beware**: sequence of operation is improtance here
    if (trackNumber.has_value() && trackTotal.has_value()) { /// both present, ok
        tag->setTrack(static_cast<unsigned int>(trackNumber.value()));
        write_int_pair(Key::track, trackNumber, trackTotal);
    } else if (trackNumber.has_value() && !trackTotal.has_value()) { /// only track number, try to set regardless
        tag->setTrack(static_cast<unsigned int>(trackNumber.value()));
        write_int_pair(Key::track, trackNumber, std::optional<int>(0));
    } else if (!trackNumber.has_value() && trackTotal.has_value()) { /// only track total, try to set ragerless
        tag->setTrack(0);
        write_int_pair(Key::track, std::optional<int>(0), trackTotal);
    } else { /// both missing, erase
        tag->removeFrames(Key::track);
        tag->setTrack(0);
    }

    if (discNumber.has_value() && discTotal.has_value()) { // noth present, ok
        write_int_pair(Key::disc, discNumber, discTotal);
    } else if (discNumber.has_value() && !discTotal.has_value()) { /// only disc number, try to set regardless
        write_int_pair(Key::disc, discNumber, std::optional<int>(0));
    } else if (!discNumber.has_value() && discTotal.has_value()) { /// only disc total, try to set regardless
        write_int_pair(Key::disc, std::optional<int>(0), discTotal);
    } else { /// both missing, erase
        tag->removeFrames(Key::disc);
    }

    write_string(Key::composer, composer);
    write_string(Key::albumArtist, albumArtist);
    write_int(Key::bpm, beatPerMinute);

    tag->removeFrames(Key::rating);
    if (rating.has_value()) {
        auto frame = new TagLib::ID3v2::PopularimeterFrame();
        frame->setRating(rating.value());
        tag->addFrame(frame);
    }

    tag->removeFrames(Key::lyrics);
    if (lyrics.has_value()) {
        auto frame = new TagLib::ID3v2::UnsynchronizedLyricsFrame(TagLib::String::UTF8);
        frame->setText(TagLib::String(lyrics.value(), TagLib::String::UTF8));
        tag->addFrame(frame);
    }

    write_bool(Key::compilation, compilation);
    write_string(Key::isrc, internationalStandardRecordingCode);
    write_user_string(Key::mcn, mediaCatalogNumber);
    write_user_string(Key::musicBrainzReleaseID, musicBrainzReleaseID);
    write_user_string(Key::musicBrainzRecordingID, musicBrainzRecordingID);

    // Album art
    tag->removeFrames(Key::pictures);
    if (shouldWritePictures && !attachedPictures.empty()) {
        for (auto picture: attachedPictures) {
            tag->addFrame(picture.convert_to_ID3v2Picture());
        }
    }
}
