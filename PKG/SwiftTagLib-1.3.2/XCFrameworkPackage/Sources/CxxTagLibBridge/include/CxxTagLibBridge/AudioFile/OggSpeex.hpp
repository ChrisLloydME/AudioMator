
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/speexfile.h>

namespace AudioFile {
    struct OggSpeex final: public AbstractAudioFile<TagLib::Ogg::Speex::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::Ogg::Speex::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            if (file.tag()) {
                metadata->overlay(AudioMetadata::read_from_XiphComment(file.tag(), options), overlayStrategy);
            }
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            metadata->write_to_XiphComment(file.tag());
        }
    };
}
