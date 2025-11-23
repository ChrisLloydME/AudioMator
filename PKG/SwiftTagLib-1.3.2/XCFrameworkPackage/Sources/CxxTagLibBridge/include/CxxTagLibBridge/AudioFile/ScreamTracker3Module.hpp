//
//#import "AbstractAudioFile.hpp"
//#import <taglib/s3mfile.h>
//
//namespace AudioFile {
//    struct ScreamTracker3Module final: public AbstractAudioFile<TagLib::S3M::File> {
//    public:
//        using AbstractAudioFile::AbstractAudioFile;
//    protected:
//        using FileType = TagLib::S3M::File;
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
