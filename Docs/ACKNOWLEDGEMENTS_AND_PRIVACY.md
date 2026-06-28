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

### Apple iTunes Search API

- Documentation: <https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/>
- Role in AudioMator: optional Apple catalog search for album and track metadata, link/UPC/store-ID lookup, metadata comparison, selected tag writing, and artwork candidate discovery.

The iTunes Search API is an Apple web service, not source code bundled with AudioMator. AudioMator uses it only when you explicitly start iTunes metadata or artwork lookup features.

### Sparkle

- Project: <https://github.com/sparkle-project/Sparkle>
- Website: <https://sparkle-project.org/>
- Role in AudioMator: dormant macOS update infrastructure.

Sparkle update checking is currently disabled in the app. The package reference and appcast-related project settings are kept in place, but the app target does not link Sparkle by default.

### GitHub Releases

- Releases: <https://github.com/ChrisLloydME/AudioMator/releases>
- Role in AudioMator: source of truth for published AudioMator release metadata and manual macOS update checks.

On macOS, AudioMator can ask GitHub Releases for the latest release tag, compare it with the current app version, and open the GitHub Releases page when you choose to download an update. AudioMator expects release tags in the form `V<version>B<build>`, for example `V2.3B26512`. The update check compares only the version part before `B`; the build number is not used to decide whether an update exists.

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

### iTunes Search API and artwork lookup

- Hosts: `itunes.apple.com`, `is5-ssl.mzstatic.com`, `a5.mzstatic.com`, and related Apple artwork endpoints.
- Purpose: search Apple catalog metadata, inspect album and track results, prepare selected tag writes, and find/download album artwork candidates.
- Typical data sent: lookup terms derived from metadata fields or user input, such as title, artist, album, album artist, track/disc information, duration, UPC/barcode, iTunes Album ID, iTunes Artist ID, iTunes track catalog ID, pasted Apple Music or iTunes links, storefront country, or manually entered search text.
- Typical data received: album and track metadata, release dates, genres, explicit-content flags, copyright text, Apple/iTunes IDs, candidate artwork metadata, and image files selected for preview or application.

### LRCLIB

- Host: `lrclib.net`
- Purpose: search and preview candidate synced lyrics for a selected track.
- Typical data sent: lookup terms derived from metadata fields or filename fallback, such as title, artist, album, and duration.
- Typical data received: candidate track, artist, album, duration, plain lyrics availability, and synced lyrics text selected for preview or application.

### Release notes

- Host: `api.github.com`
- Purpose: fetch published release notes for AudioMator when the app asks for release information.
- Typical data sent: a standard release-list request for the repository, not your media files.

### Software updates

- Hosts: `api.github.com`, `github.com`
- Purpose: check GitHub Releases for the latest published AudioMator version and open the GitHub Releases page for manual download.
- Typical data sent: a standard latest-release request for the repository, not your media files.
- Installation behavior: AudioMator does not silently install updates, download update archives in the background, or use Sparkle automatic installation in this lightweight flow.

## What AudioMator Does Not Send

- It does not upload local audio files for ordinary metadata editing.
- It does not upload embedded album artwork from your files as part of routine editing.
- It does not require network access for local editing, raw inspection, renaming, track/disc number maintenance, or text-file metadata import.
- It does not use watched folders on iPadOS.
- It does not run Sparkle update checks or install updates automatically.

## Practical Privacy Summary

If you stay inside local editing features, AudioMator stays offline.

If you use MusicBrainz, iTunes metadata/artwork lookup, LRCLIB lyrics lookup, release-note lookup, or the manual macOS update check, only the request information needed for that feature is sent. The audio file contents themselves remain local.
