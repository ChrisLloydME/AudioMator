
#import <CxxTagLibBridge/AudioMetadata.hpp>

std::optional<AudioMetadata::Picture> AudioMetadata::Picture::create_from_byte_vector(const TagLib::ByteVector *bytes) {
    if (!bytes) {
        return std::nullopt;
    }
    auto start = bytes->begin();
    auto end = bytes->end();
    auto size = bytes->size();
    /// `ByteVector` must not be:
    /// **empty**,        **overflown**,   **inversed**,  **corruputed**
    if (bytes->isEmpty() || start > end || size <= 0 || start + size != end) {
        return std::nullopt;
    }
    return AudioMetadata::Picture {
        .bytes = std::vector<char>(start, end),
        .size = size
    };
};

/// builds `AudioMetadata::Picture` from `TagLib::FLAC::Picture`.
std::optional<AudioMetadata::Picture> AudioMetadata::Picture::create_from_FLACPicture(const TagLib::FLAC::Picture *flacPicture) {
    if (!flacPicture) {
        return std::nullopt;
    }
    auto bytes = flacPicture->data();
    auto maybePicture = AudioMetadata::Picture::create_from_byte_vector(&bytes);
    if (maybePicture.has_value()) {
        auto picture = maybePicture.value();
        if (!flacPicture->description().isEmpty()) {
            picture.description = flacPicture->description().toCString(true);
        }
        picture.kind = static_cast<Kind>(flacPicture->type());
        return picture;
    } else {
        return maybePicture;
    }
};

/// builds `AudioMetadata::Picture` from `TagLib::MP4::CoverArt`.
std::optional<AudioMetadata::Picture> AudioMetadata::Picture::create_from_MP4Picture(const TagLib::MP4::CoverArt *coverArt) {
    if (!coverArt) {
        return std::nullopt;
    }
    auto bytes = coverArt->data();
    return create_from_byte_vector(&bytes);
}

/// builds `AudioMetadata::Picture` from `TagLib::ID3v2::AttachedPictureFrame *`.
std::optional<AudioMetadata::Picture> AudioMetadata::Picture::create_from_ID3v2Picture(const TagLib::ID3v2::AttachedPictureFrame *frame) {
    if (!frame) {
        return std::nullopt;
    }
    auto bytes = frame->picture();
    auto maybePicture = AudioMetadata::Picture::create_from_byte_vector(&bytes);
    if (maybePicture.has_value()) {
        auto picture = maybePicture.value();
        if (!frame->description().isEmpty()) {
            picture.description = frame->description().toCString(true);
        }
        return picture;
    } else {
        return maybePicture;
    }
}

/// maybe builds `AudioMetadata::Picture` from `const TagLib::APE::Item item` and `const char* key` return wrapped in `std::optional`.
std::optional<AudioMetadata::Picture> AudioMetadata::Picture::create_from_APEPicture(const TagLib::APE::Item *item, const char* key) {
    // From http://www.hydrogenaudio.org/forums/index.php?showtopic=40603&view=findpost&p=504669
    /*
     <length> 32 bit
     <flags with binary bit set> 32 bit
     <field name> "Cover Art (Front)"|"Cover Art (Back)"
     0x00
     <description> UTF-8 string (needs to be a file name to be recognized by AudioShell - meh)
     0x00
     <cover data> binary
     */
    if (!item) {
        return std::nullopt;
    }
    auto binaryData = item->binaryData();
    auto pos = binaryData.find('\0');
    if (-1 != pos && 3 < binaryData.size()) {
        auto upos = static_cast<unsigned int>(pos);
        auto pointer = binaryData.mid(upos + 1).data();
        auto size = (binaryData.size() - upos - 1);
        if (!pointer || size <= 0) {
            return std::nullopt;
        }
        auto description = TagLib::String(binaryData.mid(0, upos), TagLib::String::UTF8).toCString(true);
        auto type = strcasecmp(key, "Cover Art (Front)")
            ? AudioMetadata::Picture::Kind::frontCover
            : AudioMetadata::Picture::Kind::backCover;
        auto picture = AudioMetadata::Picture {
            .bytes = std::vector<char>(pointer, pointer + size),
            .size = size,
            .description = description,
            .kind = type
        };
        return picture;
    } else {
        return std::nullopt;
    }
}
