# Acknowledgements & Privacy

AudioMator is built as a local-first metadata editor. The app reads and writes the audio files you choose on your device, and it only uses the network when you explicitly start a feature that needs an online service.

## Third-Party Foundations

### TagLib

- Project: <https://github.com/taglib/taglib>
- Website: <https://taglib.org/>
- Role in AudioMator: low-level audio metadata reading, writing, raw property-map inspection, format capability discovery, and artwork operations through the `TagLibAudioMetadata` Swift package.

TagLib is distributed under LGPL/MPL licensing terms. Review the upstream licenses before redistributing AudioMator or reusing the underlying TagLib-based metadata path in another product.

### TagLibAudioMetadata

- Project: <https://github.com/ChrisLloydME/TagLibAudioMetadata.git>
- Role in AudioMator: Swift Package Manager dependency that exposes the TagLib-powered metadata manager used by the application pipeline.

AudioMator relies on this package instead of vendoring TagLib source directly into this repository.

### iTunes Artwork Finder inspiration

- Project: <https://github.com/bendodson/itunes-artwork-finder>
- Role in AudioMator: inspiration for the album artwork lookup workflow and result transformation approach.

AudioMator's current artwork lookup implementation is written in Swift in this repository. It does not require keeping a copied `.tmp` source tree in source control.

### Sparkle

- Project: <https://github.com/sparkle-project/Sparkle>
- Website: <https://sparkle-project.org/>
- Role in AudioMator: dormant macOS update infrastructure.

Sparkle update checking is currently disabled in the app. The package reference and appcast-related project settings are kept in place, but the app target does not link Sparkle by default.

## Local-First Behavior

AudioMator is designed to work directly on local files.

- Metadata reading happens on-device.
- Metadata writing happens on-device.
- Artwork replacement from local images or clipboard data happens on-device.
- Track renumbering, filename-to-metadata extraction, metadata-to-filename renaming, raw property-map editing, and metadata dump inspection run locally.
- The app does not upload your audio files for ordinary editing.
- The app does not upload embedded artwork from your files as part of routine editing.

## Platform-Specific File Access

### macOS

- Supports session imports for one-off work.
- Supports persistent watched folders.
- Uses security-scoped bookmarks for persistent folder access where needed.
- Can reveal files in Finder.
- Can open files with the default system app.
- Can copy file paths for desktop workflows.

### iPadOS

- Uses session-scoped document picking.
- Does not keep a watched-folder model.
- Does not expose desktop-style folder monitoring.
- Keeps imported files inside the active editing session model.
- Presents secondary tools as sheets instead of separate desktop windows.

## Network Activity

AudioMator only uses the network for optional features that you explicitly invoke.

### MusicBrainz

- Host: `musicbrainz.org`
- Purpose: search, metadata reference, release lookup, track lookup, relationship lookup, and tag-assist workflows.
- Typical data sent: query terms derived from metadata fields or user input, such as title, artist, album, album artist, track/disc information, duration, release identifiers, ISRC, barcode, pasted MusicBrainz links, or manually entered search text.
- Typical data received: recordings, releases, release groups, media/track listings, artist credits, identifiers, dates, labels, catalog numbers, countries, genres, tags, ratings, and relationship metadata.

### iTunes artwork lookup

- Hosts: `itunes.apple.com`, `is5-ssl.mzstatic.com`, `a5.mzstatic.com`, and related Apple artwork endpoints.
- Purpose: search for and download album artwork candidates.
- Typical data sent: lookup terms such as album name, artist name, title, iTunes Album ID, or manually entered artwork search terms.
- Typical data received: candidate artwork metadata and image files selected for preview or application.

### Release notes

- Host: `api.github.com`
- Purpose: fetch published release notes for AudioMator when the app asks for release information.
- Typical data sent: a standard release-list request for the repository, not your media files.

### Software updates

- Host: `chrislloydme.github.io`
- Purpose: reserved for Sparkle appcast and update archives if macOS update checking is enabled later.
- Typical data sent: none while Sparkle update checking remains disabled.

## What AudioMator Does Not Send

- It does not upload local audio files for ordinary metadata editing.
- It does not upload embedded album artwork from your files as part of routine editing.
- It does not require network access for local editing, raw inspection, renaming, track/disc number maintenance, or text-file metadata import.
- It does not use watched folders on iPadOS.
- It does not run Sparkle update checks while the current update flow remains disabled.

## Practical Privacy Summary

If you stay inside local editing features, AudioMator stays offline.

If you use MusicBrainz, iTunes artwork lookup, release-note lookup, or a future software-update flow, only the request information needed for that feature is sent. The audio file contents themselves remain local.
