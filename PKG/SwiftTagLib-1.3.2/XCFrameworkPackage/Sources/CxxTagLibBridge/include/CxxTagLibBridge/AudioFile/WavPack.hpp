
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/wavpackfile.h>

namespace AudioFile {
    struct WavPack final: public AbstractAudioFile<TagLib::WavPack::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::WavPack::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            if (file.hasID3v1Tag()) {
                metadata->overlay(AudioMetadata::read_from_ID3v1_tag(file.ID3v1Tag(), options), overlayStrategy);
            }
            if (file.hasAPETag()) {
                metadata->overlay(AudioMetadata::read_from_APE_tag(file.APETag(), options), overlayStrategy);
            }
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            if (file.hasID3v1Tag()) {
                metadata->write_to_ID3v1_tag(file.ID3v1Tag());
            }
            metadata->write_to_APE_tag(file.APETag(true));
        }
    };
}
