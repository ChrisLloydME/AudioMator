
#import <CxxTagLibBridge/AudioMetadata.hpp>

// MARK: - Keys
namespace MetadataKey {
    struct MP4 final {
        static constexpr const char* title = "\251nam";
        static constexpr const char* album = "\251ALB";
        static constexpr const char* artist = "\251ART";
        static constexpr const char* genre = "\251gen";
        static constexpr const char* releaseDate = "\251day";
        static constexpr const char* comment = "\251cmt";
        static constexpr const char* track = "trkn"; // both trackNumber & trackTotal
        static constexpr const char* disc = "disk"; // both discNumber & discTotal
        static constexpr const char* composer = "\251wrt";
        static constexpr const char* albumArtist = "aART";
        static constexpr const char* bpm = "tmpo";
        static constexpr const char* rating = "rtng";
        static constexpr const char* lyrics = "\251lyr";
        static constexpr const char* compilation = "cpil";
        static constexpr const char* isrc = "----:com.apple.iTunes:ISRC";
        static constexpr const char* mcn = "----:com.apple.iTunes:MCN";
        static constexpr const char* musicBrainzReleaseID = "----:com.apple.iTunes:MusicBrainz Album Id";
        static constexpr const char* musicBrainzRecordingID = "----:com.apple.iTunes:MusicBrainz Track Id";
        static constexpr const char* pictures = "covr";
    };
}

// MARK: - Read
/// constructor for `AudioMetadata` from `TagLib::MP4::Tag`.
AudioMetadata AudioMetadata::read_from_MP4_tag(const TagLib::MP4::Tag *tag, const MetadataReadingOptions options) {
    AudioMetadata metadata = AudioMetadata::read_from_tag(tag, options);
    metadata.tagSource |= TagSource::MP4;

    using Key = MetadataKey::MP4;
    using Type = AudioMetadata;

    auto read_string = [&metadata, &tag] (const char* key, std::optional<std::string> Type:: *memberPointer, bool isUnicode = true) {
        if (tag->contains(key)) {
            auto item = tag->item(key);
            std::string string = item.toStringList().toString().toCString(isUnicode);
            if (!string.empty()) {
                auto &property = metadata.*memberPointer;
                property = string;
            }
        }
    };

    auto read_int_pair = [&metadata, &tag] (const char* key, std::optional<int> Type:: *firstMemberPointer, std::optional<int> Type:: *secondMemberPointer) {
        if (tag->contains(key)) {
            auto item = tag->item(key);
            auto pair = item.toIntPair();
            if (pair.first) {
                auto &firstProperty = metadata.*firstMemberPointer;
                firstProperty = pair.first;
            }
            if (pair.second) {
                auto &secondProperty = metadata.*secondMemberPointer;
                secondProperty = pair.second;
            }
        }
    };

    auto read_int = [&metadata, &tag] (const char* key, std::optional<int> Type:: *memberPointer) {
        if (tag->contains(key)) {
            auto item = tag->item(key);
            auto value = item.toInt();
            if (value != 0) {
                auto &property = metadata.*memberPointer;
                property = value;
            }
        }
    };

    auto read_bool = [&metadata, &tag] (const char* key, std::optional<bool> Type:: *memberPointer) {
        if (tag->contains(key)) {
            auto item = tag->item(key);
            auto &property = metadata.*memberPointer;
            bool flag = item.toBool();
            property = flag;
        }
    };

    read_string(Key::title, &Type::title);
    read_string(Key::album, &Type::albumTitle);
    read_string(Key::artist, &Type::artist);
    read_string(Key::genre, &Type::genre);
    read_string(Key::comment, &Type::comment);
    read_string(Key::releaseDate, &Type::releaseDate);
    read_int_pair(Key::track, &Type::trackNumber, &Type::trackTotal);
    read_int_pair(Key::disc, &Type::discNumber, &Type::discTotal);
    read_string(Key::composer, &Type::composer);
    read_string(Key::albumArtist, &Type::albumArtist);
    read_int(Key::bpm, &Type::beatPerMinute);
    read_int(Key::rating, &Type::rating);
    read_string(Key::lyrics, &Type::lyrics);
    read_bool(Key::compilation, &Type::compilation);
    read_string(Key::isrc, &Type::internationalStandardRecordingCode);
    read_string(Key::mcn, &Type::mediaCatalogNumber);
    read_string(Key::musicBrainzReleaseID, &Type::musicBrainzReleaseID);
    read_string(Key::musicBrainzRecordingID, &Type::musicBrainzRecordingID);

    // Album art
    if (tag->contains(Key::pictures)) {
        auto art = tag->item(Key::pictures).toCoverArtList();
        for (auto iterator: art) {
            ++metadata.attachedPicturesCount;
            /// if theres no need to read pictures skip this step.
            if (options & MetadataReadingOptions::skipPictures) {
                continue;
            }
            auto picture = AudioMetadata::Picture::create_from_MP4Picture(&iterator);
            if (picture.has_value()) {
                metadata.attachedPictures.push_back(picture.value());
            } else {
                --metadata.attachedPicturesCount;
            }
        }
    }
    
    return metadata;
}

// MARK: - Write
/// fills`TagLib::MP4::Tag` from `AudioMetadata`.
void AudioMetadata::write_to_MP4_tag(TagLib::MP4::Tag *tag, bool shouldWritePictures) const {
    using Key = MetadataKey::MP4;
    
    auto write_string = [&tag] (const char* key, std::optional<std::string> optional) {
        tag->removeItem(key);
        if (optional.has_value()) {
            auto value = TagLib::String(optional.value(), TagLib::String::UTF8);
            auto item = TagLib::MP4::Item(value);
            tag->setItem(key, item);
        }
    };

    auto write_int_pair = [&tag] (const char* key, std::optional<int> first, std::optional<int> second) {
        tag->removeItem(key);
        if (first.has_value() && second.has_value()) {
            auto item = TagLib::MP4::Item(first.value(), second.value());
            tag->setItem(key, item);
        }
    };

    auto write_int = [&tag] (const char* key, std::optional<int> optional) {
        tag->removeItem(key);
        if (optional.has_value()) {
            auto item = TagLib::MP4::Item(optional.value());
            tag->setItem(key, item);
        }
    };
    
    auto wrtie_bool = [&tag] (const char* key, std::optional<bool> optional) {
        tag->removeItem(key);
        if (optional.has_value()) {
            auto flag = optional.value() ? 1 : 0;
            auto item = TagLib::MP4::Item(flag);
            tag->setItem(key, item);
        }
    };

    write_string(Key::title, title);
    /// for some reason setting album as item fails?
    auto albumTitle = this->albumTitle.has_value() ? TagLib::String(this->albumTitle.value()) : TagLib::String();
    tag->setAlbum(albumTitle);
    write_string(Key::artist, artist);
    write_string(Key::genre, genre);
    write_string(Key::comment, comment);
    write_string(Key::releaseDate, releaseDate);

    /// **beware**: sequence of operation is improtance here
    if (trackNumber.has_value() && trackTotal.has_value()) { /// both present, ok
        tag->setTrack(static_cast<unsigned int>(trackNumber.value()));
        write_int_pair(Key::track, trackNumber, trackTotal);
    } else if (trackNumber.has_value() && !trackTotal.has_value()) { /// only track number, try to set regardless
        tag->setTrack(static_cast<unsigned int>(trackNumber.value()));
        write_int_pair(Key::track, trackNumber, std::optional<int>(0));
    } else if (!trackNumber.has_value() && trackTotal.has_value()) { /// only track total, try to set regardless
        tag->setTrack(0);
        write_int_pair(Key::track, std::optional<int>(0), trackTotal);
    } else { /// both missing, erase
        tag->removeItem(Key::track);
        tag->setTrack(0);
    }

    if (discNumber.has_value() && discTotal.has_value()) { // noth present, ok
        write_int_pair(Key::disc, discNumber, discTotal);
    } else if (discNumber.has_value() && !discTotal.has_value()) { /// only disc number, try to set regardless
        write_int_pair(Key::disc, discNumber, std::optional<int>(0));
    } else if (!discNumber.has_value() && discTotal.has_value()) { /// only disc total, try to set regardless
        write_int_pair(Key::disc, std::optional<int>(0), discTotal);
    } else { /// both missing, erase
        tag->removeItem(Key::disc);
    }

    write_string(Key::composer, composer);
    write_string(Key::albumArtist, albumArtist);
    write_int(Key::bpm, beatPerMinute);
    write_int(Key::rating, rating);
    write_string(Key::lyrics, lyrics);
    wrtie_bool(Key::compilation, compilation);
    write_string(Key::isrc, internationalStandardRecordingCode);
    write_string(Key::mcn, mediaCatalogNumber);
    write_string(Key::musicBrainzReleaseID, musicBrainzReleaseID);
    write_string(Key::musicBrainzRecordingID, musicBrainzRecordingID);

    // Album Art
    /// this might be reudndant
    tag->removeItem(Key::pictures);

    if (shouldWritePictures && !attachedPictures.empty()) {
        auto list = TagLib::MP4::CoverArtList();
        for (auto picture: attachedPictures) {
            list.append(picture.convert_to_MP4Picture());
        }
        tag->setItem(Key::pictures, list);
    } else {
        tag->removeItem(Key::pictures);
    }
}
