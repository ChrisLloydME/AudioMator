//
//#import "AbstractAudioFile.hpp"
//#import <taglib/xmfile.h>
//
//namespace AudioFile {
//    struct ExtendedModule final: public AbstractAudioFile<TagLib::XM::File> {
//    public:
//        using AbstractAudioFile::AbstractAudioFile;
//    protected:
//        using FileType = TagLib::XM::File;
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
