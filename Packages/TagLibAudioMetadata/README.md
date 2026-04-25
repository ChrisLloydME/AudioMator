# TagLibAudioMetadata

Swift Package wrapper for the AudioMator TagLib metadata bridge.

## Usage

Add this package to a Swift project and import the Swift facade:

```swift
import TagLibAudioMetadata

let url = URL(fileURLWithPath: "/path/to/song.flac")

if let metadata = TagLibMetadataManager.readMetadata(from: url) {
    print(metadata.title)
}

var metadata = BasicMetadata.empty
metadata.title = "New title"
try TagLibMetadataManager.writeMetadata(metadata, to: url)
```

The package exposes:

- `TagLibMetadataManager`: Swift read/write facade.
- `BasicMetadata`, `RawMetadataDump`, and related Swift value models.
- `TagLibMetadataExtractor` and `TagLibAudioMetadata` through the underlying ObjC++ bridge module.

