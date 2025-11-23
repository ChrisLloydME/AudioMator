
#import <CxxTagLibBridge/AudioMetadata.hpp>
#import <unordered_map>
#import <cstring>
#import <string>
#import <string_view>

// MARK: - Keys
namespace MetadataKey {
    struct APE final {
        static constexpr std::string title = "TITLE";
        static constexpr std::string album = "ALBUM";
        static constexpr std::string artist = "ARTIST";
        static constexpr std::string genre = "GENRE";
        static constexpr std::string releaseDate = "DATE";
        static constexpr std::string comment = "DESCRIPTION";
        static constexpr std::string trackNumber = "TRACKNUMBER";
        static constexpr std::string trackTotal = "TRACKTOTAL";
        static constexpr std::string discNumber = "DISCNUMBER";
        static constexpr std::string discTotal = "DISCTOTAL";
        static constexpr std::string composer = "COMPOSER";
        static constexpr std::string albumArtist = "ALBUMARTIST";
        static constexpr std::string bpm = "BPM";
        static constexpr std::string rating = "RATING";
        static constexpr std::string lyrics = "LYRICS";
        static constexpr std::string compilation = "COMPILATION";
        static constexpr std::string isrc = "ISRC";
        static constexpr std::string mcn = "MCN";
        static constexpr std::string musicBrainzReleaseID = "MUSICBRAINZ_ALBUMID";
        static constexpr std::string musicBrainzRecordingID = "MUSICBRAINZ_TRACKID";
        static constexpr std::string coverArtFront = "COVER ART (FRONT)";
        static constexpr std::string coverArtBack = "COVER ART (BACK)";

        using StringProperty = std::optional<std::string> AudioMetadata::*;
        static std::unordered_map<std::string, StringProperty, std::hash<std::string>> stringPropertiesByKeys() {
            return {
                {APE::title, &AudioMetadata::title},
                {APE::album, &AudioMetadata::albumTitle},
                {APE::artist, &AudioMetadata::artist},
                {APE::genre, &AudioMetadata::genre},
                {APE::comment, &AudioMetadata::comment},
                {APE::releaseDate, &AudioMetadata::releaseDate},
                {APE::composer, &AudioMetadata::composer},
                {APE::albumArtist, &AudioMetadata::albumArtist},
                {APE::lyrics, &AudioMetadata::lyrics},
                {APE::isrc, &AudioMetadata::internationalStandardRecordingCode},
                {APE::mcn, &AudioMetadata::mediaCatalogNumber},
                {APE::musicBrainzReleaseID, &AudioMetadata::musicBrainzReleaseID},
                {APE::musicBrainzRecordingID, &AudioMetadata::musicBrainzRecordingID},
            };
        }

        using IntProperty = std::optional<int> AudioMetadata::*;
        static std::unordered_map<std::string, IntProperty, std::hash<std::string>> intPropertiesByKeys() {
            return {
                {APE::trackNumber, &AudioMetadata::trackNumber},
                {APE::trackTotal, &AudioMetadata::trackTotal},
                {APE::discNumber, &AudioMetadata::discNumber},
                {APE::discTotal, &AudioMetadata::discTotal},
                {APE::bpm, &AudioMetadata::beatPerMinute},
                {APE::rating, &AudioMetadata::rating},
            };
        }
    };
}

// MARK: - Read
/// constructor for `AudioMetadata` from `TagLib::APE::Tag`.
AudioMetadata AudioMetadata::read_from_APE_tag(const TagLib::APE::Tag *tag, const MetadataReadingOptions options) {
    auto metadata = AudioMetadata();
    if (tag->isEmpty()) {
        return metadata;
    }
    metadata.tagSource |= TagSource::APE;
    auto additionalMetadata = AudioMetadata::AdditionalMetadata();
    using Key = MetadataKey::APE;

    auto none_if_empty = [](const char* string) -> std::optional<std::string> {
        return (!std::string_view(string).empty()) ? std::optional<std::string>(string) : std::nullopt;
    };

    auto none_if_zero = [](int number) -> std::optional<int> {
        return number != 0 ? std::optional<int>(number) : std::nullopt;
    };

    auto string_to_optional_bool = [](char const * value) -> std::optional<bool> {
        auto lookupValue = std::string(value);
        std::transform(lookupValue.begin(), lookupValue.end(), lookupValue.begin(), ::tolower);
        if (lookupValue == "true") {
            return true;
        } else if (lookupValue == "false") {
            return false;
        } else {
            int number = std::atoi(value);
            if (number == 0) {
                return false;
            } else if (number == 1) {
                return true;
            } else {
                return std::nullopt;
            }
        }
    };

    auto stringPropertiesByKeys = MetadataKey::APE::stringPropertiesByKeys();
    auto intPropertiesByKeys = MetadataKey::APE::intPropertiesByKeys();

    for (auto iterator: tag->itemListMap()) {
        auto item = iterator.second;
        if (item.isEmpty()) { continue; }
        auto key = item.key().toCString(true);
        auto value = item.toString().toCString(true);

        if (TagLib::APE::Item::Text == item.type()) {
            bool hasHandledValue = false;
            auto lookupKey = std::string(key);
            std::transform(lookupKey.begin(), lookupKey.end(), lookupKey.begin(), ::toupper);

            auto stringPropertyIterator = stringPropertiesByKeys.find(lookupKey);
            if (stringPropertyIterator != stringPropertiesByKeys.end()) {
                auto memberPointer = stringPropertyIterator->second; /// maybe `auto&`
                metadata.*memberPointer = none_if_empty(value);
                hasHandledValue = true;
            }
            if (hasHandledValue) { continue; }

            auto intPropertyIterator = intPropertiesByKeys.find(lookupKey);
            if (intPropertyIterator != intPropertiesByKeys.end()) {
                auto memberPointer = intPropertyIterator->second; /// maybe `auto&`
                try {
                    auto number = std::stoi(value);
                    metadata.*memberPointer = none_if_zero(number);
                    hasHandledValue = true;
                } catch (const std::invalid_argument &exception) {}
            }
            if (hasHandledValue) { continue; }

            if (lookupKey == Key::compilation) {
                metadata.compilation = string_to_optional_bool(value);
                if (metadata.compilation.has_value()) {
                    hasHandledValue = true;
                }
            }
            if (hasHandledValue) { continue; }

            if (!hasHandledValue) {
                additionalMetadata.push_back(std::pair<std::string, std:: string>(key, value));
                continue;;
            }
        } else if(TagLib::APE::Item::Binary == item.type()) {
            if (key == Key::coverArtFront || key == Key::coverArtBack) {
                ++metadata.attachedPicturesCount;
                /// if theres no need to read pictures skip this step.
                if (options & MetadataReadingOptions::skipPictures) {
                    continue;
                }
                auto picture = AudioMetadata::Picture::create_from_APEPicture(&item, key);
                if (picture.has_value()) {
                    metadata.attachedPictures.push_back(picture.value());
                } else {
                    --metadata.attachedPicturesCount;
                }
            } else {
                continue;
            }
        }
    }

    if (!additionalMetadata.empty()) {
        metadata.additional = additionalMetadata;
    }

    return metadata;
}

// MARK: - Write
/// fills`TagLib::APE::Tag` from `AudioMetadata`.
void AudioMetadata::write_to_APE_tag(TagLib::APE::Tag * tag, bool shouldWritePictures) const {
    using Key = MetadataKey::APE;

    #warning there's a chance where TagLib::String() used it needs to be called below with .toCString()
    auto write_string = [&tag] (const std::string key, std::optional<std::string> optional) {
        tag->removeItem(key);
        if (optional.has_value()) {
            auto string = optional.value();
            tag->addValue(key, TagLib::String(string.c_str()));
        }
    };

    auto write_int = [&tag] (const std::string key, std::optional<int> optional) {
        tag->removeItem(key.c_str());
        if (optional.has_value()) {
            auto number = std::to_string(optional.value());
            tag->addValue(key.c_str(), TagLib::String(number.c_str()));
        }
    };

    auto write_bool = [&tag] (const std::string key, std::optional<bool> optional) {
        tag->removeItem(key.c_str());
        if (optional.has_value()) {
            auto flag = std::to_string(optional.value() ? 1 : 0);
            tag->addValue(key.c_str(), TagLib::String(flag.c_str()));
        }
    };

    write_string(Key::title, title);
    write_string(Key::album, albumTitle);
    write_string(Key::artist, artist);
    write_string(Key::genre, genre);
    write_string(Key::comment, comment);
    write_string(Key::releaseDate, releaseDate);
    write_int(Key::trackNumber, trackNumber);
    write_int(Key::trackTotal, trackTotal);
    write_int(Key::discNumber, discNumber);
    write_int(Key::discTotal, discTotal);
    write_string(Key::composer, composer);
    write_string(Key::albumArtist, albumArtist);
    write_int(Key::bpm, beatPerMinute);
    write_int(Key::rating, rating);
    write_string(Key::lyrics, lyrics);
    write_bool(Key::compilation, compilation);
    write_string(Key::isrc, internationalStandardRecordingCode);
    write_string(Key::mcn, mediaCatalogNumber);
    write_string(Key::musicBrainzReleaseID, musicBrainzReleaseID);
    write_string(Key::musicBrainzRecordingID, musicBrainzRecordingID);

    // Additional metadata
    if (!additional.empty()) {
        for (auto item: additional) {
            auto key = item.first.c_str();
            auto value = item.second.c_str();
            tag->removeItem(key);
            tag->addValue(key, TagLib::String(value));
        }
    }

    // Album art
    tag->removeItem(Key::coverArtFront.c_str());
    tag->removeItem(Key::coverArtBack.c_str());

    if (shouldWritePictures && !attachedPictures.empty()) {
        for (auto picture: attachedPictures) {
            auto coverData = picture.convert_to_APEPicture();
            if (coverData) {
                auto& [key, data] = *coverData;
                tag->setData(key, data);
            }
        }
    }
}
