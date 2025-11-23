
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/dsdifffile.h>

namespace AudioFile {
    struct DSDIFF final: public AbstractAudioFile<TagLib::DSDIFF::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::DSDIFF::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            if (file.hasDIINTag()) {
                metadata->overlay(AudioMetadata::read_from_tag(file.DIINTag(), options), overlayStrategy);
            }
            if (file.hasID3v2Tag()) {
                metadata->overlay(AudioMetadata::read_from_ID3v2_tag(file.ID3v2Tag(), options), overlayStrategy);
            }
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            metadata->write_to_tag(file.tag());
            metadata->write_to_ID3v2_tag(file.ID3v2Tag());
        }
    };
}
