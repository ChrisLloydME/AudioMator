
#import "InterfaceEnums.hpp"
#import "AudioMetadata.hpp"
#import "AudioProperties.hpp"
#import "Logging.hpp"
#import <taglib/tfilestream.h>
#import <taglib/tfile.h>
#import <stdexcept>
#import <exception>

namespace AudioFile {
    /// Abstracts away specific interaction with `TagLib::FileStream` type for descendants while requiring them to
    /// specify `FileType`(which must inherit from `TagLib::File`) and allows to manipulate file directly
    /// when `reading/writing` metadata within `protected virtual` methods.
    template <typename FileType>
        requires std::is_base_of_v<TagLib::File, FileType>
    struct AbstractAudioFile {
    protected:
        std::string fileName;
    public:
        /// Designated constructor.
        explicit AbstractAudioFile(std::string fileName): fileName(std::move(fileName)) {}
        /// Destructor.
        virtual ~AbstractAudioFile() = default;
        /// Reads `AudioMetadata` & `AudioProperties` from file.
        MetadataReadingOutcome readMetadata(
            AudioMetadata * _Nonnull metadata,
            AudioProperties * _Nonnull properties,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy,
            std::string * _Nonnull errorDescription
        ) const {
            try {
                TagLib::FileStream stream(fileName.c_str(), true);
                if (!stream.isOpen()) {
                    taglib_bridge_log(Error, "file is not open: %s", fileName.c_str());
                    return MetadataReadingOutcome::fileIsNotOpen;
                }
                FileType file(&stream);
                if (!file.isValid()) {
                    taglib_bridge_log(Error, "file is not valid: %s", fileName.c_str());
                    return MetadataReadingOutcome::invalidFile;
                }
                read_metadata_implementation(file, metadata, options, overlayStrategy);
                if (file.audioProperties()) {
                    properties->fillFromProperties(*file.audioProperties());
                }
                taglib_bridge_log(Info, "metadata read successfully, file: %s", fileName.c_str());
            } catch (const std::runtime_error &error) {
                taglib_bridge_log(Error, "caught runtime error: %s", error.what());
                std::string message = error.what();
                errorDescription = &message;
                return MetadataReadingOutcome::runtimeError;
            } catch (const std::exception &exception) {
                taglib_bridge_log(Error, "caught exception: %s", exception.what());
                std::string message = exception.what();
                errorDescription = &message;
                return MetadataReadingOutcome::exception;
            } catch (...) {
                taglib_bridge_log(Error, "caught unknown exception");
                return MetadataReadingOutcome::unknownException;
            }
            return MetadataReadingOutcome::success;
        }
        /// Writes `AudioMetadata` to the file.
        MetadataWritingOutcome writeMetadata(
            AudioMetadata * _Nonnull metadata,
            std::string * _Nonnull errorDescription
        ) const {
            try {
                TagLib::FileStream stream(fileName.c_str());
                if (!stream.isOpen()) {
                    taglib_bridge_log(Error, "file is not open: %s", fileName.c_str());
                    return MetadataWritingOutcome::fileIsNotOpen;
                }
                FileType file(&stream, false);
                if (!file.isValid()) {
                    taglib_bridge_log(Error, "file is not valid: %s", fileName.c_str());
                    return MetadataWritingOutcome::invalidFile;
                }
                write_metadata_implementation(file, metadata);
                if (!file.save()) {
                    taglib_bridge_log(Error, "error while saving file: %s", fileName.c_str());
                    return MetadataWritingOutcome::saveError;
                }
                taglib_bridge_log(Info, "metadata written successfully, file: %s", fileName.c_str());
            } catch (const std::runtime_error &error) {
                taglib_bridge_log(Error, "caught runtime error: %s", error.what());
                std::string message = error.what();
                errorDescription = &message;
                return MetadataWritingOutcome::runtimeError;
            } catch (const std::exception &exception) {
                taglib_bridge_log(Error, "caught exception: %s", exception.what());
                std::string message = exception.what();
                errorDescription = &message;
                return MetadataWritingOutcome::exception;
            } catch (...) {
                taglib_bridge_log(Error, "caught unknown exception");
                return MetadataWritingOutcome::unknownException;
            }
            return MetadataWritingOutcome::success;
        }
    protected:
        /// Format specific internal `read` metadata implementation.
        virtual void read_metadata_implementation(
            FileType &file,
            AudioMetadata * _Nonnull metadata,
            const MetadataReadingOptions options,
            const MetadataOverlayStrategy overlayStrategy
        ) const = 0;
        /// Format specific internal `write` metadata implementation.
        virtual void write_metadata_implementation(
            FileType &file,
            AudioMetadata * _Nonnull metadata
        ) const = 0;
    };
}
