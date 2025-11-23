
#import <CxxTagLibBridge/AudioMetadata.hpp>
#import <string_view>

/// constructor for `AudioMetadata` from **abstract** `TagLib::Tag`.
AudioMetadata AudioMetadata::read_from_tag(const TagLib::Tag *tag, const MetadataReadingOptions options) {
    auto optional_if_empty = [](const char* string) -> std::optional<std::string> {
        return (!std::string_view(string).empty()) ? std::optional<std::string>(string) : std::nullopt;
    };

    auto year = tag->year();
    std::optional<std::string> releaseDate = std::nullopt;
    if (year != 0) {
        releaseDate = std::to_string(year);
    }

    auto track = static_cast<int>(tag->track());
    std::optional<int> trackNumber = std::nullopt;
    if (track != 0) {
        trackNumber = track;
    }

    return {
        .tagSource = TagSource::Abstract,
        .title = optional_if_empty(tag->title().toCString(true)),
        .albumTitle = optional_if_empty(tag->album().toCString(true)),
        .artist = optional_if_empty(tag->artist().toCString(true)),
        .genre = optional_if_empty(tag->genre().toCString(true)),
        .comment = optional_if_empty(tag->comment().toCString(true)),
        .releaseDate = releaseDate,
        .trackNumber = trackNumber,
    };
}

#import <charconv>

/// fills **abstract** `TagLib::Tag` from `AudioMetadata`.
void AudioMetadata::write_to_tag(TagLib::Tag *tag) const {
    auto empty_if_otional = [](std::optional<std::string> optional) -> TagLib::String {
        return optional.has_value() ? TagLib::String(optional.value()) : TagLib::String();
    };

    tag->setTitle(empty_if_otional(title));
    tag->setAlbum(empty_if_otional(albumTitle));
    tag->setArtist(empty_if_otional(artist));
    tag->setGenre(empty_if_otional(genre));
    tag->setComment(empty_if_otional(comment));

    if (releaseDate.has_value()) {
        std::string releaseDate = releaseDate;
        if (!releaseDate.empty()) {
            unsigned int year;
            auto [unused, errorCode] = std::from_chars(releaseDate.data(), releaseDate.data() + releaseDate.size(), year);
            if (errorCode == std::errc()) {
                tag->setYear(year);
            }
        } else {
            tag->setYear(0);
        }
    }

    if (trackNumber.has_value()) {
        tag->setTrack(static_cast<unsigned int>(trackNumber.value()));
    } else {
        tag->setTrack(0);
    }
}
