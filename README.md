# AudioMator

AudioMator is a native **macOS SwiftUI** app for reading, editing, and writing audio metadata through a bundled **TagLib bridge** with additional inspection support from **AVFoundation**.

The app is designed around local files you explicitly load, plus optional online lookup workflows (MusicBrainz and iTunes artwork).

## What the app does

### 1) Load and organize files

AudioMator has two file-source modes:

- **Current Session (Quick Import)**: ad-hoc files you add manually
- **Watched Folders**: persistent folders restored across launches and auto-rescanned when filesystem changes are detected

The main window uses a three-pane layout:

- **Sidebar**: session, all watched files, and individual watched folders
- **Center table**: sortable/reorderable track list with configurable columns
- **Inspector**: single-file or multi-file metadata editing

### 2) Inspect metadata deeply

AudioMator supports both normalized and raw inspection:

- Normalized metadata in the inspector (title/artist/album/etc.)
- Technical fields (duration, bitrate, sample rate, channels, format)
- Artwork preview
- **Tag Inspector** sheet for raw TagLib properties, ID3v2 frame details, and AVFoundation metadata dumps

### 3) Edit and write metadata

Write operations are done through the TagLib bridge with per-file and batch feedback.

- Single-file edits from the inspector
- Multi-file edits with mixed-value handling and selective-field application
- Explicit-content editing
- Artwork replace/remove/keep behavior
- Bulk operations with progress + success/warning/failure HUD states

### 4) Batch tools

- **Renumber Tracks** (ascending/descending, custom start, optional zero-padding)
- **Import Field from Text** (delimiter-based bulk value import)
- **Filename & Metadata** window:
  - Metadata → filename rename via token templates
  - Filename → metadata extraction and write-back via matching templates
- **Metadata Editor** window:
  - Direct property-map editing (add/edit/delete arbitrary key/value tags)
- File actions: open, reveal in Finder, copy path/name, remove from list
- Erase-all metadata action (best effort via TagLib clear/write)

### 5) Optional online enrichment

- **MusicBrainz Browser** window:
  - Search by track, album, file-derived query, or direct MusicBrainz link
  - View recording/release/track detail
- **MusicBrainz Tagging Workbench**:
  - Match selected local files to release tracks
  - Choose which fields to write
  - Preview local vs remote diffs before applying
  - Optional recording-level credits (composer/lyricist/producer/engineer/remixer/copyright)
- **iTunes Artwork lookup** for album-art search/download and application

## Metadata coverage (implemented fields)

Core fields available across inspector/workbench/tooling include:

- Title, Artist, Album, Album Artist, Composer, Genre
- Year, Track Number, Disc Number, Release Date
- Comment, Publisher, Copyright, Explicit
- ISRC, Barcode
- MusicBrainz IDs (artist/album/track/release-group)
- Lyricist, Remixer, Producer, Engineer
- Language, Media Type, Release Type, Catalog Number, Release Country
- Artwork

Additional raw/custom fields are available through the Metadata Editor and TagLib property-map workflow.

## Supported formats

Supported extensions are defined by the TagLib bridge and currently include:

`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`, `flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`

These extensions are used for import/read and are also the app’s configured metadata/artwork write target set.

## Privacy and network behavior

- Local-first by default: files are read/written on your machine
- Persistent watched-folder access uses security-scoped bookmarks
- Network is only used for optional features:
  - MusicBrainz search/detail/tagging support
  - iTunes artwork search/download
  - GitHub release-notes fetch in Settings → About

## Build and run

### Open in Xcode

```bash
open /home/runner/work/AudioMator/AudioMator/AudioMator.xcodeproj
```

### Build from CLI

```bash
/home/runner/work/AudioMator/AudioMator/scripts/codex-build.sh
```

Notes from project configuration:

- Scheme: `AudioMator`
- Swift: `5.0`
- Marketing version: `1.6.1`
- Project build version: `264133`
- Deployment target: macOS `26.1`
- The repo currently has one app target (no separate test target configured)

## Project structure

- `/home/runner/work/AudioMator/AudioMator/AudioMator/` — app source
  - `Models/` — metadata/file/source/domain models
  - `Services/` — MusicBrainz/iTunes/release-notes clients, folder persistence, directory monitor
  - `ViewModels/` — app and workflow state (main editing + MusicBrainz)
  - `Views/` — main UI panes, tools, settings, and secondary windows
  - `TagLibBridge/` — Swift + Objective-C++ bridge and bundled TagLib sources
- `/home/runner/work/AudioMator/AudioMator/AudioMator.xcodeproj/` — project settings
- `/home/runner/work/AudioMator/AudioMator/scripts/` — CLI build helper(s)
- `/home/runner/work/AudioMator/AudioMator/THIRD_PARTY_NOTICES.md` — licensing/compliance notes

## Current constraints to be aware of

- Quick Import is session-oriented; workflow differs from watched folders
- Metadata support depth can vary by container/tag implementation even when extension is supported
- Erase-all metadata is best effort through TagLib write paths
- MusicBrainz/iTunes features depend on external network services
