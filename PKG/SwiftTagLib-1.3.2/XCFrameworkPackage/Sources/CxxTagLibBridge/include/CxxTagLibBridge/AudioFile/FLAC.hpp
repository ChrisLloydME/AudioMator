
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/flacfile.h>

namespace AudioFile {
    struct FLAC final: public AbstractAudioFile<TagLib::FLAC::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::FLAC::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            if (file.hasID3v1Tag()) {
                metadata->overlay(AudioMetadata::read_from_ID3v1_tag(file.ID3v1Tag(), options), overlayStrategy);
            }
            if (file.hasID3v2Tag()) {
                metadata->overlay(AudioMetadata::read_from_ID3v2_tag(file.ID3v2Tag(), options), overlayStrategy);
            }
            if (file.hasXiphComment()) {
                metadata->overlay(AudioMetadata::read_from_XiphComment(file.xiphComment(), options), overlayStrategy);
            }
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            if (file.hasID3v1Tag()) {
                metadata->write_to_ID3v1_tag(file.ID3v1Tag());
            }
            if (file.hasID3v2Tag()) {
                metadata->write_to_ID3v2_tag(file.ID3v2Tag(), false);
            }
            metadata->write_to_XiphComment(file.xiphComment(), true);
            /// attaching pictures to the file itself
            file.removePictures();
            if (!metadata->attachedPictures.empty()) {
                for (auto picture: metadata->attachedPictures) {
                    file.addPicture(picture.convert_to_FLACPicture());
                }
            }
        }
    };
}
