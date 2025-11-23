
#import <CxxTagLibBridge/AudioMetadata.hpp>

/// convenience method to combine `AudioMetadata` as layers.
void AudioMetadata::overlay(const AudioMetadata layer, const MetadataOverlayStrategy strategy) {
    using Type = AudioMetadata;
    tagSource |= layer.tagSource;

    auto overlay_optional = [this, &layer, &strategy](auto Type:: *memberPointer) {
        auto &property = this->*memberPointer;
        const auto &overlayProperty = layer.*memberPointer;
        switch (strategy) {
            default:
            case MetadataOverlayStrategy::graceful:
                if (!property.has_value() && overlayProperty.has_value()) {
                    property = overlayProperty;
                }
                break;
            case MetadataOverlayStrategy::override:
                if (overlayProperty.has_value()) {
                    property = overlayProperty;
                }
                break;
            case MetadataOverlayStrategy::regardless:
                property = overlayProperty;
                break;;
        }
    };

    // MARK: - Properties: std::optional<std::string>
    for (auto property: {
        &Type::title,
        &Type::albumTitle,
        &Type::artist,
        &Type::genre,
        &Type::comment,
        &Type::releaseDate,
        &Type::composer,
        &Type::albumArtist,
        &Type::lyrics,
        &Type::internationalStandardRecordingCode,
        &Type::mediaCatalogNumber,
        &Type::musicBrainzReleaseID,
        &Type::musicBrainzRecordingID,
    }) {
        overlay_optional(property);
    }

    // MARK: - Properties: std::optional<int>
    for (auto property: {
        &Type::trackNumber,
        &Type::trackTotal,
        &Type::discNumber,
        &Type::discTotal,
        &Type::beatPerMinute,
        &Type::rating,
    }) {
        overlay_optional(property);
    }

    overlay_optional(&Type::compilation);

    // MARK: - Attached Pictures
    if (!layer.attachedPictures.empty()) {
        attachedPictures.insert(
            attachedPictures.end(),
            std::make_move_iterator(layer.attachedPictures.begin()),
            std::make_move_iterator(layer.attachedPictures.end())
        );
    }
    attachedPicturesCount += layer.attachedPicturesCount;

    // MARK: - Additional Metadata
    if (!layer.additional.empty()) {
        additional.insert(
            additional.end(),
            std::make_move_iterator(layer.additional.begin()),
            std::make_move_iterator(layer.additional.end())
        );
    }
}
