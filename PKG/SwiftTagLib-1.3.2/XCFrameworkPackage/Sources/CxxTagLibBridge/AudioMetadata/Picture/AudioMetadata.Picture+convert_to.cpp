
#import <CxxTagLibBridge/AudioMetadata.hpp>

// MARK: - Format specific picture builders
/// Build `TagLib::FLAC::Picture` and returns it wrapped in `std::unique_ptr`.
AudioMetadata::Picture::FLACPicture AudioMetadata::Picture::convert_to_FLACPicture() {
    TagLib::FLAC::Picture *picture = new TagLib::FLAC::Picture();
    picture->setData(TagLib::ByteVector(bytes.data(), size));
    picture->setType(static_cast<TagLib::FLAC::Picture::Type>(kind));
    if (!description.empty()) {
        picture->setDescription(TagLib::String(description));
    }
    auto [mimeType, width, height, colorDepth] = properties();
    if (!mimeType.empty()) {
        picture->setMimeType(TagLib::String(mimeType));
    }
    if (width) {
        picture->setWidth(width);
    }
    if (height) {
        picture->setHeight(height);
    }
    if (colorDepth) {
        picture->setColorDepth(colorDepth);
    }
    return picture;
}

/// Builds `TagLib::MP4::CoverArt`.
AudioMetadata::Picture::MP4Picture AudioMetadata::Picture::convert_to_MP4Picture() {
    auto mimeType = this->mime_type();
    auto format = TagLib::MP4::CoverArt::CoverArt::Unknown;
    if (!mimeType.empty()) {
        if (strcasecmp("com.microsoft.bmp", mimeType.c_str())) {
            format = TagLib::MP4::CoverArt::CoverArt::BMP;
        } else if (strcasecmp("public.png", mimeType.c_str())) {
            format = TagLib::MP4::CoverArt::CoverArt::PNG;
        } else if (strcasecmp("com.compuserve.gif", mimeType.c_str())) {
            format = TagLib::MP4::CoverArt::CoverArt::GIF;
        } else if (strcasecmp("public.jpeg", mimeType.c_str())) {
            format = TagLib::MP4::CoverArt::CoverArt::JPEG;
        }
    }
    return TagLib::MP4::CoverArt(format, TagLib::ByteVector(bytes.data(), size));
}

/// Builds `TagLib::ID3v2::AttachedPictureFrame`  and returns it wrapped in `std::unique_ptr`.
AudioMetadata::Picture::ID3v2Picture AudioMetadata::Picture::convert_to_ID3v2Picture() {
    #warning possible memory leak
    TagLib::ID3v2::AttachedPictureFrame *frame = new TagLib::ID3v2::AttachedPictureFrame();
    auto mimeType = this->mime_type();
    if (!mimeType.empty()) {
        frame->setMimeType(TagLib::String(mimeType));
    }
    frame->setPicture(TagLib::ByteVector(bytes.data(), size));
    frame->setType((TagLib::ID3v2::AttachedPictureFrame::Type)kind);
    if (!description.empty()) {
        frame->setDescription(TagLib::String(description));
    }
    return frame;
}

/// Builds `TagLib::ByteVector` for `TagLib::APE::Tag` and returns it alongside with a `key` for it
/// wrapped in `std::optional<std::tuple>`.
AudioMetadata::Picture::APEPicture AudioMetadata::Picture::convert_to_APEPicture() {
    if (kind == AudioMetadata::Picture::Kind::frontCover
        || kind == AudioMetadata::Picture::Kind:: backCover
    ) {
        TagLib::ByteVector data;
        if (!description.empty()) {
            data.append(TagLib::String(description.c_str()).data(TagLib::String::UTF8));
        }
        data.append('\0');
        data.append(TagLib::ByteVector(bytes.data(), size));
        auto key = kind == AudioMetadata::Picture::Kind::frontCover ? "Cover Art (Front)" : "Cover Art (Back)";
        return std::make_tuple(key, data);
    } else {
        return std::nullopt;
    }
}
