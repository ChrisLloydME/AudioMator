//
//#import "AbstractAudioFile.hpp"
//#import <taglib/modfile.h>
//
//namespace AudioFile {
//    struct ProTrackerModule final: public AbstractAudioFile<TagLib::Mod::File> {
//    public:
//        using AbstractAudioFile::AbstractAudioFile;
//    protected:
//        using FileType = TagLib::Mod::File;
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
