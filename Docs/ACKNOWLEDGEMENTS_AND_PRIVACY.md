# Acknowledgements & Privacy

AudioMator is a local-first metadata editor. It reads and writes the audio files
you choose on your Mac and uses the network only when you explicitly start an
online feature.

This disclosure describes the current implementation. The in-app Privacy sheet is
generated from `NetworkServiceDisclosure`; both should be updated together when
network behavior changes.

## Third-Party Foundations

### TagLib

- Project: <https://github.com/taglib/taglib>
- Website: <https://taglib.org/>
- Role: low-level audio metadata parsing, writing, raw property-map inspection,
  format capability discovery, and artwork operations, used through the
  `TagLibAudioMetadata` Swift package.

TagLib is distributed under LGPL/MPL terms. Review the upstream licenses before
redistributing AudioMator.

### TagLibAudioMetadata

- Project: <https://github.com/ChrisLloydME/TagLibAudioMetadata>
- Role: Swift Package Manager dependency that exposes the TagLib-backed metadata
  manager used by AudioMator.

The app resolves this package as an external dependency pinned to an exact
version. It does **not** vendor, trim, or bundle a local copy of TagLib source in
this repository.

### iTunes Artwork Finder inspiration

- Project: <https://github.com/bendodson/itunes-artwork-finder>
- Role: inspiration for the album artwork lookup approach.

AudioMator's current artwork implementation is written in Swift in this
repository.

### Apple iTunes Search API

- Documentation:
  <https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/>
- Role: optional Apple catalog search, link/UPC/store-ID lookup, metadata
  comparison, selected tag writing, and artwork candidate discovery.

The iTunes Search API is an Apple web service, not source code bundled with
AudioMator.

### GitHub Releases

- Releases: <https://github.com/ChrisLloydME/AudioMator/releases>
- Role: published release metadata, release notes, and manual update checks.

AudioMator expects release tags in the form `V<version>B<build>`, for example
`V2.7B2697`.

## Local-First Behavior

- Metadata reading and writing happen on device.
- Artwork replacement from local images or clipboard data happens on device.
- Track renumbering, filename metadata extraction, metadata-to-filename
  conversion, raw property-map editing, and metadata dump inspection run locally.
- The app does not upload audio file contents.
- The app does not upload embedded artwork from your files as part of editing.
- The app does not include telemetry, analytics, or crash reporting.

## File Access

- Current Session imports are session-only.
- Watched folders are persisted with security-scoped bookmarks.
- AudioMator explains sandbox file access during onboarding and can request the
  exact folder needed for a transactional save.
- It does not scan an authorized save folder unless you add it as a watched
  folder or import from it.
- It can reveal files in Finder, open them with the default app, and copy paths.
- Folder bookmarks and preferences are stored locally in app preferences. The
  save issue log is stored locally in Application Support.

## Network Activity

Network requests occur only for features you explicitly invoke. All requests are
HTTP GETs; no audio file bytes are uploaded.

### MusicBrainz

- Host: `musicbrainz.org`
- Purpose: search, metadata reference, release/recording lookup, relationship
  lookup, and tag-assist workflows.
- Data sent: query terms and identifiers derived from tags, filenames, or parent
  directory names, such as title, artist, album, album artist, track number,
  duration, release identifiers, ISRC, barcode, MusicBrainz IDs, or manually
  entered search text.
- Data received: recordings, releases, release groups, media/track listings,
  credits, identifiers, dates, labels, catalog numbers, countries, genres, tags,
  ratings, and relationship metadata.
- The app sends a descriptive `User-Agent` and spaces requests at roughly one per
  1.1 seconds.

### iTunes Search API and artwork lookup

- Hosts requested by the app:
  - `itunes.apple.com` for search/lookup,
  - `is5-ssl.mzstatic.com` and `a5.mzstatic.com` for rewritten artwork URLs,
  - the host in Apple's returned `artworkUrl100` for thumbnail/standard artwork.
- Purpose: Apple catalog metadata search, UPC/link/store-ID lookup, selected tag
  writing, and artwork candidate discovery/download.
- Data sent: search terms derived from tags or filename/path fallback, storefront
  country, media/entity/limit, an iTunes album or track ID, or a UPC. Track
  number, disc number, duration, artist ID, and catalog ID are used locally and
  are not URL parameters.
- Data received: album and track metadata, dates, genres, explicit flags,
  copyright, Apple IDs, artwork URLs, and image files selected for preview.
- The app does not restrict artwork downloads to a fixed host list; Apple-returned
  URLs can reference other Apple artwork hosts.

### LRCLIB

- Host: `lrclib.net`
- Purpose: search and preview synced lyrics for a selected track.
- Data sent: track name, artist name, album name, and duration derived from tags
  or filename fallback.
- Data received: candidate track/artist/album/duration, synced/plain lyrics
  availability, and lyrics text selected for preview or application.

### Release notes and updates

- Host: `api.github.com`
- Purpose: fetch published release notes and check the latest release version.
- Data sent: standard GitHub API requests for the AudioMator repository; no media
  files and no credentials.
- The app opens `github.com` release pages in your default browser; it does not
  request `github.com` itself.

### Embedded web pages

MusicBrainz release/recording pages and Apple-provided track/collection pages can
be displayed in an embedded `WKWebView`. These pages are loaded from the service
and may load their own subresources or cookies. The app does not maintain a host
allow-list for these pages.

## What AudioMator Does Not Send

- Local audio file contents.
- Embedded artwork from your files as part of routine reading/writing.
- Telemetry, analytics, or crash reports.
- Credentials or API tokens (the app stores none).
- Automatic background queries. Online features require an explicit search or
  lookup action.

## Update Checks

The manual check asks GitHub for the latest published release, compares its tag
with the running version and build, and offers to open the GitHub Releases page.
It does not download, install, or stage an update, and it does not run
automatically at launch.

## Practical Privacy Summary

If you stay inside local editing features, AudioMator stays offline. If you use
MusicBrainz, iTunes metadata/artwork lookup, LRCLIB lyrics lookup, release notes,
or the manual update check, only the request information needed for that feature
is sent. The audio file contents remain local.

## Contact

E-mail: AudioMator@lloydME.com

See [Security and Data Integrity](Security/SECURITY_AND_DATA_INTEGRITY.md) for
security limitations and vulnerability reporting.
