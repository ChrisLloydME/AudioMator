# Project Overview

AudioMator is a native SwiftUI-first audio metadata editor for macOS and iPadOS. The project uses `AudioMator.xcodeproj` and the `AudioMator` scheme. Its metadata read/write path is powered by the `TagLibAudioMetadata` Swift package, which exposes TagLib-backed audio metadata operations to the app.

## Product Scope

AudioMator is built for local music-library cleanup. Users can import audio files into the current session or use watched folders on macOS, inspect tags, edit common fields, replace artwork, clean text fields in batches, renumber tracks by list order, extract metadata from filenames or structured text, generate filenames from existing metadata, and inspect raw tag data.

It is not a cloud music manager. The ordinary editing path does not upload audio files. Online services are used only for user-triggered metadata, artwork, lyrics, release-note, or update-check workflows.

## Platform Model

The macOS app is the full desktop workflow. It includes persistent watched folders, a native three-pane main window, file-path display, Finder-style actions, configurable toolbar buttons, configurable list columns, Settings tabs, and separate tool windows for online metadata, filename/metadata conversion, and advanced metadata editing.

The iPadOS app uses a session-only workflow. It does not have persistent watched folders, does not expose desktop-style folder monitoring, and presents secondary tools as sheets.

## Current Version Signals

The app target currently uses:

- `MARKETING_VERSION = 2.5`
- `CURRENT_PROJECT_VERSION = 26601`
- macOS app deployment target: `26.0`
- iOS/iPadOS app deployment target: `26.0`

## Main Dependencies

- `TagLibAudioMetadata`: Swift Package Manager dependency that exposes the TagLib-powered metadata manager consumed by the app pipeline.
- TagLib: low-level audio metadata library used through `TagLibAudioMetadata`.
- Sparkle: package reference present in the Xcode project. The active update-check code path uses GitHub Releases through `GitHubUpdateReleaseClient` and `UpdateChecker`.
- MusicBrainz, Apple iTunes Search API, LRCLIB, and GitHub Releases: user-triggered network service boundaries.
