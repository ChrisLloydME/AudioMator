# FAQ

## Does AudioMator upload my audio files?

Not for ordinary local editing. Metadata reading, metadata writing, local artwork replacement, track renumbering, filename tools, raw inspection, and metadata dump inspection run on the device.

Online lookup features may send search terms or identifiers such as title, artist, album, duration, ISRC, barcode, MusicBrainz links, Apple Music/iTunes links, or storefront country.

## Is the iPadOS app the same as the macOS app?

No. The macOS app is the full desktop workflow with watched folders, a three-pane window, Finder-style actions, and separate tool windows. The iPadOS app is session-only, uses document picking, and presents tools as sheets.

## Which audio formats are supported?

AudioMator asks `TagLibAudioMetadata` for readable and writable extensions at runtime. Actual field read/write behavior depends on TagLib support and the underlying container. The committed test fixtures currently cover `mp3`, `m4a`, `flac`, `aac`, `ogg`, and `wav`.

## Why did track or disc text change after writing?

Containers store track/disc values differently. AudioMator separates numeric intent from user-facing text intent. For example, `02/09` may be normalized by a container into number `2` and total `9`. Post-write verification tries to distinguish harmless normalization from a real write failure.

## What are MusicBrainz, iTunes, and LRCLIB used for?

MusicBrainz is used for music metadata and MusicBrainz IDs. iTunes Search API is used for Apple catalog metadata, UPC/link/store ID lookup, and artwork candidates. LRCLIB is used for lyrics candidates, especially synced lyrics.

## Are automatic updates enabled?

The macOS app has a lightweight manual update check. It queries GitHub Releases and opens the GitHub Releases page when a newer version is available.

## Why does the Codex build script sometimes skip xcodebuild?

`scripts/codex-build.sh` checks for build-relevant changes. If none are present, it skips `xcodebuild` and suggests `--force` for a full validation build.

## How can I contact the project author?

Use `AudioMator@lloydME.com`.
