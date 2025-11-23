
#import <swift/bridging>
#import <taglib/audioproperties.h>

struct AudioProperties final {
public:
    // MARK: - Properties
    int lengthInSeconds;
    int channels;
    int sampleRate;
    int bitrate;
    // MARK: - Utility
    void fillFromProperties(const TagLib::AudioProperties &properties) {
        lengthInSeconds = properties.lengthInSeconds();
        channels = properties.channels();
        sampleRate = properties.sampleRate();
        bitrate = properties.bitrate();
    }
};
