# Acknowledgements & Privacy

## Third-party foundations

### TagLib

- Project: <https://github.com/taglib/taglib>
- Website: <https://taglib.org/>
- AudioMator uses TagLib through a local Objective-C++ bridge for metadata reading, writing, raw property-map inspection, and most artwork operations.

TagLib is distributed under LGPL and MPL terms. Review the upstream licenses before reusing or redistributing it in another product.

### iTunes Artwork Finder inspiration

- Project: <https://github.com/bendodson/itunes-artwork-finder>

AudioMator's artwork lookup implementation is written in Swift, but the lookup workflow was originally informed by this project.

## Local-first behavior

AudioMator is designed to work on local files.

- Metadata reading happens on-device.
- Metadata writing happens on-device.
- Your audio files are not uploaded as part of normal editing.
- The TagLib bridge, raw metadata inspector, filename tools, and batch editing workflows all run locally.

## Platform-specific file access

### macOS

- Supports session imports and persistent watched folders
- Uses security-scoped bookmarks for persistent folder access where needed
- Can reveal files back into the desktop file system workflow

### iPadOS

- Uses session-scoped document picking
- Does not keep a watched-folder model
- Does not expose desktop-style folder monitoring
- Keeps imported files inside the current editing session model

## Network activity

AudioMator only uses the network for optional features that you explicitly invoke.

### MusicBrainz

- Host: `musicbrainz.org`
- Purpose: search, metadata reference, release lookup, tag-assist workflows
- Typical data sent: query terms derived from metadata fields you choose to search with, such as title, artist, album, track/disc information, duration bucket, ISRC, barcode, or pasted MusicBrainz identifiers

### iTunes artwork lookup

- Hosts: `itunes.apple.com`, `mzstatic.com` image endpoints
- Purpose: search for and download album artwork
- Typical data sent: lookup terms such as album name, artist name, or iTunes IDs

### Release notes

- Host: `api.github.com`
- Purpose: fetch published release notes for AudioMator
- Typical data sent: a standard release-list request, not your media files

## What AudioMator does not send

- It does not upload your local audio files for ordinary metadata editing.
- It does not upload album artwork embedded in your files as part of routine editing.
- It does not require network access for core local editing, raw inspection, renaming, or track/disc number maintenance.

## Practical privacy summary

If you stay inside local editing features, AudioMator stays offline.

If you use MusicBrainz, iTunes artwork, or release-note lookup, only the query information needed for that feature is sent, and the audio file contents remain local.
