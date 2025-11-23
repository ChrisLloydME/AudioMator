
#import <CxxTagLibBridge/AbstractAudioFile.hpp>
#import <taglib/wavfile.h>

namespace AudioFile {
    struct WAVE final: public AbstractAudioFile<TagLib::RIFF::WAV::File> {
    public:
        using AbstractAudioFile::AbstractAudioFile;
    protected:
        using FileType = TagLib::RIFF::WAV::File;

        void read_metadata_implementation(
            FileType &file,
            AudioMetadata *metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const {
            if (file.hasInfoTag()) {
                metadata->overlay(AudioMetadata::read_from_tag(file.InfoTag(), options), overlayStrategy);
            }
            if (file.hasID3v2Tag()) {
                metadata->overlay(AudioMetadata::read_from_ID3v2_tag(file.ID3v2Tag(), options), overlayStrategy);
            }
        }

        void write_metadata_implementation(FileType &file, AudioMetadata *metadata) const {
            if (file.hasInfoTag()) {
                metadata->write_to_tag(file.InfoTag());
            }
            metadata->write_to_ID3v2_tag(file.ID3v2Tag());
        }
    };
}
