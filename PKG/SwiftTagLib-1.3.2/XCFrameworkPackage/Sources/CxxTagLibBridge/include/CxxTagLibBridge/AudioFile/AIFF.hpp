
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/aifffile.h>

namespace AudioFile {
    struct AIFF final: public AbstractAudioFile<TagLib::RIFF::AIFF::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::RIFF::AIFF::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            if (file.tag()) {
                metadata->overlay(AudioMetadata::read_from_ID3v2_tag(file.tag(), options), overlayStrategy);
            }
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            metadata->write_to_ID3v2_tag(file.tag());
        }
    };
}
