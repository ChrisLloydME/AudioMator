//
//#import "AbstractAudioFile.hpp"
//#import <taglib/itfile.h>
//
//namespace AudioFile {
//    struct ImpulseTrackerModule final: public AbstractAudioFile<TagLib::IT::File> {
//    public:
//        using AbstractAudioFile::AbstractAudioFile;
//    protected:
//        using FileType = TagLib::IT::File;
//
//        void readMetadataImplementation(FileType &file, AudioMetadata *metadata) const {
//            if (file.tag()) {
//                metadata->overlay(AudioMetadata::fromTag(file.tag()));
//            }
//        }
//
//        void writeMetadataImplementation(FileType &file, AudioMetadata *metadata) const {
//            if (file.tag()) {
//                metadata->fillTag(file.tag());
//            }
//        }
//    };
//}
