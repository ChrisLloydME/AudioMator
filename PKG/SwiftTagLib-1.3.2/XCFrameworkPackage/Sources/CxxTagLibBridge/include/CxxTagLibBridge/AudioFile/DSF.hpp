
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/dsffile.h>

namespace AudioFile {
    struct DSF final: public AbstractAudioFile<TagLib::DSF::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::DSF::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            metadata->overlay(AudioMetadata::read_from_ID3v2_tag(file.tag(), options), overlayStrategy);
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            metadata->write_to_ID3v2_tag(file.tag());
        }
    };
}
