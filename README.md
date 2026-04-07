# AudioMator

<p align="center">
  <img src="AppIcon-1024x1024@1x.png" alt="AudioMator app icon" width="140" />
</p>

<p align="center">
  A local-first macOS audio metadata editor for inspecting, cleaning, renaming, and rewriting tags in files you choose.
</p>

<p align="center">
  <strong>SwiftUI</strong> · <strong>TagLib Bridge</strong> · <strong>AVFoundation</strong> · <strong>MusicBrainz</strong> · <strong>macOS</strong>
</p>

## Overview

AudioMator is a native macOS app built around a three-pane workflow:

- a sidebar for `Current Session`, `All Watched Files`, and individual watched folders
- a center table for browsing, selecting, and reordering tracks
- a right-side inspector for single-file edits, multi-file edits, artwork, and technical details

The app is local-first by default. Audio files stay on your Mac, watched folders are stored locally, and metadata writes happen through the bundled TagLib bridge. The only network-backed feature in the current app is the optional `MusicBrainz Browser`.

## Current Capabilities

### Library and File Workflow

- Import local audio files into a temporary `Current Session`
- Add persistent watched folders that stay available across launches
- Automatically rescan watched folders when their contents change
- Switch between quick-import work and watched-folder browsing
- View either `All Watched Files` or a specific watched folder
- Reorder the visible list with drag and drop
- Customize visible middle-list columns from the table header context menu
- Clear the current session list without touching files on disk

### Metadata Inspection

- Inspect a single file in the right-side inspector
- Compare shared values across multiple selected files
- Open `Tag Inspector` to review raw TagLib properties, ID3v2 frames, and AVFoundation metadata output
- Review technical fields such as duration, bitrate, sample rate, channels, and format
- Preview embedded artwork
- Review additional metadata such as `ISRC`, `Barcode`, MusicBrainz IDs, and `Credits` when present

### Metadata Editing

AudioMator currently supports editing these user-facing fields:

- `Title`
- `Artist`
- `Album`
- `Composer`
- `Genre`
- `Year`
- `Track Number`
- `Disc Number`
- `Comment`
- `Album Artist`
- `Release Date`
- `Publisher`
- `Copyright`
- `Explicit`
- `Artwork`

Editing behavior currently includes:

- single-file editing in the inspector
- multi-file editing for shared text fields
- keep-unchanged behavior for untouched fields during multi-file edits
- mixed-value placeholders when the current selection differs
- unsaved-change detection with discard confirmation
- success, warning, partial-save, and failure HUD feedback after writes

### Artwork Support

- Preview existing embedded artwork
- Replace artwork from an image file
- Import artwork from the clipboard
- Remove artwork from one file or many selected files
- Apply artwork changes across multi-file selections

### Batch and Utility Tools

- Renumber tracks from the current visible list order
- Apply renumbering to the full list or only the current selection
- Choose ascending or descending numbering
- Set a custom starting number
- Optionally pad numbers with leading zeros
- Import one metadata field from a plain-text file in row order
- Rename selected files from metadata tokens while preserving file extensions
- Open selected files
- Reveal selected files in Finder
- Copy selected file paths
- Copy selected filenames
- Erase supported metadata fields from selected files

### MusicBrainz Browser

- Open a dedicated `MusicBrainz Browser` window from the toolbar or menu commands
- Search by track, album, selected file metadata, or direct MusicBrainz link
- Seed searches from the current AudioMator selection
- Review result details for recordings, releases, and tracks
- Use MusicBrainz as an optional reference workflow while keeping local editing in AudioMator

### Welcome and App Experience

- Show a multi-page welcome screen on first launch
- Reopen the welcome screen later from the Help menu
- Toggle the inspector from the toolbar or menu commands
- Use quick-edit sheets for longer text fields with hidden-character preview

## Supported Formats

The current implementation exposes the same extension set for file import, metadata writing, and artwork writing:

- `mp3`
- `mp2`
- `m4a`
- `m4b`
- `m4p`
- `mp4`
- `aac`
- `ogg`
- `opus`
- `mpc`
- `wma`
- `asf`
- `spx`
- `flac`
- `ape`
- `wv`
- `tta`
- `wav`
- `aiff`
- `aif`
- `dsf`
- `dff`
- `oga`

Practical metadata coverage can still vary by container and tag layout. `Erase All Tags` should be treated as a best-effort metadata-clearing action, not a guaranteed deep wipe for every format.

## Quick Start

### Open in Xcode

```bash
open AudioMator.xcodeproj
```

### Run

1. Open the `AudioMator` scheme in Xcode.
2. Review signing settings for your local machine or team.
3. Build and run from Xcode.

### Command-Line Build

```bash
./scripts/codex-build.sh
```

## Build Notes

- Marketing version: `1.3`
- Current project version: `26451`
- Swift version: `5.0`
- Deployment target: macOS `26.1`
- The checked-in project uses Apple code signing settings, so you may need to replace the signing team or certificate before local builds succeed
- `AudioMator/AppIcon.icon` uses Apple's newer `.icon` format. In the Codex CLI sandbox, `actool` can crash while compiling it even when the same project builds correctly in the full Xcode app.
- `./scripts/codex-build.sh` keeps code signing disabled for CLI checks and treats that specific `.icon` `actool` crash as an environment limitation instead of a project configuration error.
- For final release validation of the app icon itself, build from Xcode on the local desktop.

## Project Structure

- `AudioMator/`: app source, models, services, view models, and views
- `AudioMator/TagLibBridge/`: Swift and Objective-C++ bridge layer around TagLib
- `AudioMator.xcodeproj/`: Xcode project configuration
- `RELEASE_NOTES.md`: release-oriented feature summary

## Current Limitations

- Session file lists are temporary and are cleared when the app closes
- Manual file import is only available while `Current Session` is selected
- Multi-file editing only applies fields you explicitly change
- Raw metadata inspection is read-only
- `Credits` are currently read-only when available
- MusicBrainz lookup depends on network access and the external MusicBrainz service
- No separate test target is currently checked into the repository

## Disclaimer

> Review the code critically before relying on it for destructive metadata workflows or large-library cleanup.
