
#import <CxxTagLibBridge/AudioMetadata.hpp>
#import <CoreFoundation/CoreFoundation.h>
#import <ImageIO/ImageIO.h>

/// Creates `AudioMetadata::Picture` from `CFDataRef data`, `std::string description` and `Kind kind`.
AudioMetadata::Picture AudioMetadata::Picture::create_from_CFData(
    CFDataRef data,
    std::string description,
    Kind kind
) {
    const UInt8 *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    auto buffer = Picture::Bytes(bytes, bytes + length);
    return {
        .bytes = std::move(buffer),
        .size = static_cast<unsigned int>(length),
        .description = description,
        .kind = kind
    };
}

/// Attempts to extract `MIME type` from raw image `bytes`, if fails returns empty string.
AudioMetadata::Picture::MIMEType AudioMetadata::Picture::mime_type() {
    auto data = CFDataCreate(kCFAllocatorDefault, reinterpret_cast<const UInt8*>(bytes.data()), size);
    auto imageSource = CGImageSourceCreateWithData(data, nullptr);
    std::string mimeType;
    if (imageSource) {
        CFStringRef imageType = CGImageSourceGetType(imageSource);
        if (imageType) {
            /// oversized just in case
            char buffer[256];
            CFStringGetCString(imageType, buffer, sizeof(buffer), kCFStringEncodingUTF8);
            mimeType = std::string(buffer);
            CFRelease(imageType);
        } else {
            mimeType = "";
        }
        CFRelease(imageSource);
    } else {
        mimeType = "";
    }
    CFRelease(data);
    return mimeType;
}

/// Attempts to extract `MIME type, pixel width & height, color depth` from raw image `bytes`,
/// if fails returns empty string and 0's.
AudioMetadata::Picture::Properties AudioMetadata::Picture::properties() {
    auto data = CFDataCreate(kCFAllocatorDefault, reinterpret_cast<const UInt8*>(bytes.data()), size);
    auto imageSource = CGImageSourceCreateWithData(data, nullptr);
    std::string mimeType;
    int width, height, depth;
    if (imageSource) {
        // mime type
        CFStringRef imageType = CGImageSourceGetType(imageSource);
        if (imageType) {
            /// oversized just in case
            char buffer[256];
            CFStringGetCString(imageType, buffer, sizeof(buffer), kCFStringEncodingUTF8);
            mimeType = std::string(buffer);
            CFRelease(imageType);
        } else {
            mimeType = "";
        }
        // properties
        auto properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nullptr);
        auto extract_value = [&properties] (const char* rawKey) -> int {
            CFStringRef key = CFStringCreateWithCString(nullptr, rawKey, kCFStringEncodingUTF8);
            CFNumberRef number = (CFNumberRef)CFDictionaryGetValue(properties, key);
            int value = 0;
            if (number) {
                auto ok = CFNumberGetValue(number, kCFNumberIntType, &value);
                if (!ok) {
                    value = 0;
                }
                CFRelease(number);
            }
            CFRelease(key);
            return value;
        };
        if (properties) {
            width = extract_value("PixelWidth");
            height = extract_value("PixelHeight");
            depth = extract_value("Depth");
            CFRelease(properties);
        }
        CFRelease(imageSource);
    } else {
        mimeType = "";
    }
    CFRelease(data);
    return std::make_tuple(mimeType, width, height, depth);
}
