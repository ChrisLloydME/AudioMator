
#import <stdint.h>

// MARK: - Outcomes
/// Tells the API consumer the outcome of `readMetadata` method.
enum class MetadataReadingOutcome: uint8_t {
    fileIsNotOpen,
    invalidFile,
    runtimeError,
    exception,
    unknownException,
    success
};

/// Tells the API consumer the outcome of `writeMetadata` method.
enum class MetadataWritingOutcome: uint8_t {
    fileIsNotOpen,
    invalidFile,
    saveError,
    runtimeError,
    exception,
    unknownException,
    success
};

// MARK: - Reading Options
/// Influences how `AudioMetadata` is read.
enum MetadataReadingOptions: uint32_t {
    skipPictures = 1 << 0
};

// MARK: - Overlay Strategy
/// Influences how duplicate fields are being handled when overlaying one `AudioMetadata` with another.
enum class MetadataOverlayStrategy: uint8_t {
    /// checks if value is already read, and if not replaces only with new if its not `std::nullopt`.
    graceful = 0,
    /// does not check if value is already read, replaces when new if its not `std::nullopt`.
    override = 1,
    /// no checks, newest value is written
    regardless = 2
};
