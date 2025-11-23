
## Differences from [`SFBAudioEngine`](https://github.com/sbooth/SFBAudioEngine/) and explanation of how things work.

> This file is somewhat outdated!

### taglib
[`taglib`](https://github.com/taglib/taglib) `v2.0.2` integrated directly as **git submodule** into it's own target which also includes [`utfcpp`](https://github.com/nemtrif/utfcpp) `v4.0.6` as **git submodule**.

### CxxTagLibBridge
- Instead of reading metadata into dictionary, for each kind of `Tag` in file a new instance of [`AudioMetadata`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioMetadata.hpp#L15) is created from that `Tag` and then overlayed with [`void AudioMetadata::overlay(const AudioMetadata layer)`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/AudioMetadata%2Boverlay.cpp#L17).
- [`AbstractAudioFile`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AbstractAudioFile.hpp#L41) serves as **generic interface** for files requiring:
  -  that `FileType` is a subclass of `TagLib::File`,
  - implementation for `void read_metadata_implementation(FileType &file, AudioMetadata *metadata)`,
  - implementation for ` void write_metadata_implementation(FileType &file, AudioMetadata *metadata)`.
  > this allows for somewhat streamlined and simple implementation of each AudioFile itself, while the interface exposed to `Swift` looks like this:
  -  `MetadataReadingOutcome readMetadata(AudioMetadata *metadata, AudioProperties *properties, std::string *errorDescription)`
  - `MetadataWritingOutcome writeMetadata(AudioMetadata *metadata, std::string *errorDescription)`
- [`AudioFile.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioFile.hpp) is just and **import umbrella** for audio file **implementations** (all of them are `struct`'s):
  - [`AIFF.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AIFF.hpp), [`DSDIFF.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/DSDIFF.hpp), [`DSF.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/DSF.hpp),  [`FLAC.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/FLAC.hpp), [`MP3.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/MP3.hpp), [`MP4.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/MP4.hpp), [`MonkeyAudio.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/MonkeyAudio.hpp), [`Musepack.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/Musepack.hpp), [`OggFLAC.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/OggFLAC.hpp), [`OggOpus.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/OggOpus.hpp), [`OggSpeex.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/OggSpeex.hpp), [`OggVorbis.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/OggVorbis.hpp), [`TrueAudio.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/TrueAudio.hpp), [`WAVE.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/WAVE.hpp), [`WavPack.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/WavPack.hpp).
- `AudioFile` aside from field also holds `using AttachedPictures = std::vector<Picture>` and `using AdditionalMetadataPair = std::pair<std::string, std::string>`.
- Interaction with `Tag`'s happens much alike in `SFBAudioEngine` in categories on `AudioMetadata`:
  - [`AudioMetadata+AbstractTag.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Tags/AudioMetadata%2BAbstractTag.cpp)
  - [`AudioMetadata+ID3v1Tag.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Tags/AudioMetadata%2BID3v1Tag.cpp)
  - [`AudioMetadata+D3v2Tag.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Tags/AudioMetadata%2BID3v2Tag.cpp)
  - [`AudioMetadata+MP4Tag.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Tags/AudioMetadata%2BMP4Tag.cpp)
  - [`AudioMetadata+APETag.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Tags/AudioMetadata%2BAPETag.cpp)
  - [`AudioMetadata+XIPHComment.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Tags/AudioMetadata%2BXIPHComment.cpp) 
- The `AudioMetadata.Picture` also has bunch of categories for converting images:
  - [`AudioMetadata.Picture+ImageIO.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Picture/AudioMetadata.Picture%2BImageIO.cpp)
  - [`AudioMetadata.Picture+convert_to.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Picture/AudioMetadata.Picture%2Bconvert_to.cpp)
  - [`AudioMetadata.Picture+create_from.cpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/AudioMetadata/Picture/AudioMetadata.Picture%2Bcreate_from.cpp)

### SwiftTagLib

- On the `Swift` side of things [`AudioFileImplementation`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Abstract/AudioFileImplementation.swift#L5) serves as common interface for all those audio files which inherit from [`AbstractAudioFile.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AbstractAudioFile.hpp#L41)  in `CxxTagLibBridge` and conformances are defined after the fact.
```swift
protocol AudioFileImplementation {
    init(_ fileName: std.string)

    func readMetadata(
        _ metadata: UnsafeMutablePointer<AudioMetadata>!,
        _ properties: UnsafeMutablePointer<AudioProperties>!,
        _ errorDescription: UnsafeMutablePointer<std.string>!
    ) -> MetadataReadingOutcome

    func writeMetadata(
        _ metadata: UnsafeMutablePointer<AudioMetadata>!,
        _ errorDescription: UnsafeMutablePointer<std.string>!
    ) -> MetadataWritingOutcome
}
```

- [`AudioFile.Properties`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Properties.swift#L7) is a `Swift` equivalent of [`AudioProperties.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioProperties.hpp).
- [`AudioFile.Metadata`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Metadata.swift#L7) is a `Swift` equivalent of [`AudioMetadata.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioMetadata.hpp#L15).
- [`AudioFile.Metadata.AttachedPicture.hpp`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AttachedPicture.swift#L7) is `Swift` equivalent of [`AudioMetadata.Picture`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioMetadata.hpp#L61).
- [`AudioFile.Metadata.AdditionalMetadataPair`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AdditionalMetadataPair.swift#L6) is `Swift` equivalent of [`using AdditionalMetadataPair = std::pair<std::string, std::string>`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioMetadata.hpp#L140).

All of the equivalent types in `Swift` conform to [`CxxRepresentable`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Abstract/CxxRepresentable.swift) `protocol`:
```swift
protocol CxxRepresentable {
    associatedtype CxxRepresentation
    init(cxxRepresentation: CxxRepresentation)
    var cxxRepresentation: CxxRepresentation { get }
}
```

`AudioMetadata.hpp` also stores a bitmask of it's [`TagSource`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/CxxTagLibBridge/include/AudioMetadata.hpp#L25) with `Swift` equivalent `OptionSet` [`TagSource`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/TagSource.swift#L4).
  > `TagSource` was quite useful during testing to understand the common errors when reading from or writing to `Tag`'s.

Format detection is done only in `Swift` as this doesn't really touch `taglib` or require `Objective-C` or `C++`.
There's [`AudioFile`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Abstract/AudioFormat.swift#L6) `protocol`:
```swift
protocol AudioFormat {
    static var supportedPathExtensions: Set<String> { get }
    static var supportedMIMETypes: Set<String> { get }
    static func isFormatSupported(_ fileHandle: FileHandle) -> Bool

    /// import escaping.
    typealias ImplementationClass = CxxTagLibBridge.AudioFile
    associatedtype Implementation: AudioFileImplementation
}

extension AudioFormat {
    static var implementationMetatype: Implementation.Type { Implementation.self }
}
```

And [`AudioFile.Format`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Format.swift#L4) `enum` which provides us with:
```swift
var formatMetatype: any AudioFormat.Type { ... }
var implementationMetatype: AudioFileImplementation.Type { formatMetatype.implementationMetatype }
```

The detection of format is done much alike in `SFBAudioEngine` by calculating the score for each one in [`AudioFile.Format.Detector`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Utility/Format.Detector.swift#L7).

There's just 3 types protocols for file header format/layout defined: [`BasicHeader Layout/Format`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Abstract/HeaderFormat/BasicHeaderFormat.swift), [`CompositeHeader Layout/Format`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Abstract/HeaderFormat/CompositeHeaderFormat.swift) and [`CustomHeader Layout/Format`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Abstract/HeaderFormat/CustomHeaderFormat.swift).

There's also two helper structs for this to work: 
- [`BinaryData`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Utility/BinaryData.swift#L6) struct to read `UTF8` `String`'s easily from data obtained from `FileHandle`.
- [`ID3v2ShallowHeader`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/Utility/ID3v2ShallowHeader.swift#L5C8-L5C26) to check for `ID3v2`, this mostly exact copy from `SFBAudioEngine` but done in `Swift`.

File header format/layout by categories:
- `BasicHeader`:
  - [`FLAC.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/BasicHeader/FLAC.swift#L2)
  - [`MP4.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/BasicHeader/MP4.swift#L2)
  - [`MonkeyAudio.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/BasicHeader/MonkeyAudio.swift#L2)
  - [`TrueAudio.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/BasicHeader/TrueAudio.swift#L2)
  - [`WavPack.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/BasicHeader/WavPack.swift#L2)
- `CompositeHeader`:
  - [`AIFF.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/AIFF.swift#L2)
  - [`DSDIFF.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/DSDIFF.swift#L2)
  - [`DSF.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/DSF.swift#L2)
  - [`OggFLAC.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/OggFLAC.swift#L2)
  - [`OggOpus.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/OggOpus.swift#L2)
  - [`OggSpeex.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/OggSpeex.swift#L2)
  - [`OggVorbis.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/OggVorbis.swift#L2)
  - [`WAVE.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CompositeHeader/WAVE.swift#L2)
- `CustomHeader`:
  - [`MP3.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CustomHeader/MP3.swift#L2)
  - [`Musepack.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Sources/SwiftTagLib/AudioFormats/CustomHeader/Musepack.swift#L2)

### Tests

There's some audio file samples in repository and **Tests** are executed using them.
- [`LanguageBarrierTraversalTest.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Tests/SwiftTagLibTests/LanguageBarrierTraversalTest.swift) is a suite of a sanity checks that we can go from `Swift` to `C++` type and back and it behaves as expected.
- [`AudioFileTests.swift`](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Tests/SwiftTagLibTests/AudioFileTests.swift) is a suite of test check that interaction operations with metadata behave as expected with some caveats.
  - [Reading metadata](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Tests/SwiftTagLibTests/AudioFileTests.swift#L9) expects that metadata read from file doesn't differ between reads.
  - [Same self overwrite](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Tests/SwiftTagLibTests/AudioFileTests.swift#L33) expects that writing metadata read from file to copy of that file produces same metadata when read again after writing.
  - [Writing metadata](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Tests/SwiftTagLibTests/AudioFileTests.swift#L71) expects that semi-random metadata is written to file when read again after writing.
  - [Erasing metadata](https://github.com/Volodymyr-13/SwiftTagLib/blob/a720f9d558aa77f294a995129e213fe66aee13a9/XCFrameworkPackage/Tests/SwiftTagLibTests/AudioFileTests.swift#L111) expects that erased metadata isn't there when read again after writing.

### Not everything is reproduced
- Not all metadata fields are covered/supported, i ignored supporting `ReplayGain` and `Sorting`/`Grouping` metadata entries, here's the [Issue](https://github.com/Volodymyr-13/SwiftTagLib/issues/1) for that.
