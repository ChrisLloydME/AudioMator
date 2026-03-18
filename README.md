# AudioMator

<p align="center">
  <img src="AppIcon-1024x1024@1x.png" alt="AudioMator app icon" width="140" />
</p>

<p align="center">
  A local-first macOS audio metadata editor for inspecting, cleaning, and rewriting tags in files you choose.
</p>

<p align="center">
  <strong>SwiftUI</strong> · <strong>TagLib Bridge</strong> · <strong>AVFoundation</strong> · <strong>macOS</strong>
</p>

## Overview

AudioMator is currently a native three-pane macOS app with:

- a sidebar for session files and watched folders
- a center table for browsing and reordering tracks
- a right-side inspector for single-file edits, multi-file edits, artwork, and technical details

The app is local-first. It works on files and folders you explicitly choose, keeps watched folders on your machine, and writes metadata back to disk through the bundled TagLib bridge.

## Current Capabilities

### Library Workflow

- Import audio files into a temporary `Session Files` list
- Add persistent watched folders to the sidebar
- Automatically rescan watched folders when their contents change
- Switch between `Session Files`, `All Watched Files`, and individual watched folders
- Reorder the visible list with drag and drop
- Customize visible table columns from the middle-list header context menu
- Clear the session list without touching files on disk

### Metadata Inspection and Editing

- Single-file inspector editing
- Multi-file editing for shared text fields
- Raw metadata inspection through `Tag Inspector`
- Technical read-only fields such as duration, bitrate, sample rate, channels, and format
- Embedded artwork preview in the inspector
- Replace artwork from an image file or the clipboard
- Remove artwork for one file or many selected files
- Unsaved-change detection with discard confirmation
- Save feedback HUDs for success, warning, partial-save, and failure states

### Batch and Utility Tools

- Renumber track numbers by the current visible list order
- Renumber either the full list or only the current selection
- Choose ascending or descending numbering
- Set a custom starting number
- Optionally pad track numbers with leading zeros
- Import one metadata field from a text file into the selected rows
- Open selected files
- Reveal selected files in Finder
- Copy selected paths
- Copy selected filenames
- Erase supported metadata fields from selected files

## Editable Fields

AudioMator currently exposes these user-facing editable fields:

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

`Credits` are currently displayed as read-only data when available.

## Supported Formats

The current implementation advertises the same extension set for file import, metadata writing, and artwork writing through the TagLib bridge:

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
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -derivedDataPath .deriveddata \
  build
```

## Build Notes

- Project version: `1.1`
- Swift version: `5.0`
- Current deployment target: macOS `26.1`
- The checked-in project is configured with Apple code signing, so you may need to replace the signing team or certificate before local builds succeed

## Project Structure

- `AudioMator/`: app source, models, services, view models, and views
- `AudioMator/TagLibBridge/`: Swift and Objective-C++ bridge layer around TagLib
- `AudioMator.xcodeproj/`: Xcode project configuration
- `RELEASE_NOTES.md`: release-oriented feature summary

## Current Limitations

- Session file lists are temporary and are cleared when the app closes
- Manual file import is disabled while a watched-folder source is selected
- Multi-file editing only applies fields you explicitly change
- Raw metadata inspection is read-only
- No separate test target is currently checked into the repository

## Disclaimer

> This is still a small, evolving project. Review the code critically before relying on it for destructive metadata workflows or large-library cleanup.
