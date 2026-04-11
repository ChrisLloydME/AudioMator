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

The app is local-first by default. Audio files stay on your Mac, watched folders are stored locally, and metadata writes happen through the bundled TagLib bridge. The only network-backed feature is the optional `MusicBrainz Browser`.

## Current Capabilities

### Library and File Workflow

- Import local audio files into a temporary `Current Session`
- Add persistent watched folders that stay available across launches
- Automatically rescan watched folders when their contents change
- Switch between quick-import work and watched-folder browsing
- View either `All Watched Files` or a specific watched folder
- Reorder the visible list with drag and drop
- Sort by any column with a click on the column header
- Customize visible middle-list columns from the table header context menu or Settings
- Clear the current session list without touching files on disk

### Metadata Inspection

- Inspect a single file in the right-side inspector
- Compare shared values across multiple selected files
- Open `Tag Inspector` to review raw TagLib properties, ID3v2 frames, and AVFoundation metadata output
- Review technical fields such as duration, bitrate, sample rate, channels, and format
- Preview embedded artwork
- Review additional metadata such as `ISRC`, `Barcode`, MusicBrainz IDs, and `Credits` when present

### Metadata Editing

The inspector supports editing these fields for one or multiple selected files:

| `Title` | `Artist` | `Album` | `Album Artist` | `Composer` |
|---|---|---|---|---|
| `Genre` | `Year` | `Track Number` | `Disc Number` | `Release Date` |
| `Comment` | `Publisher` | `Copyright` | `Explicit` | `Artwork` |

Editing behavior currently includes:

- single-file editing in the inspector
- multi-file editing for shared text fields
- keep-unchanged behavior for untouched fields during multi-file edits
- mixed-value placeholders when the current selection differs
- unsaved-change detection with discard confirmation
- quick-edit sheets for longer text fields with hidden-character preview
- success, warning, partial-save, and failure HUD feedback after writes

### Metadata Editor Window

A dedicated `Metadata Editor` window provides direct access to the raw TagLib property map for one or more selected files:

- Add, edit, or delete any named property field
- Multi-file editing with mixed-value indicators
- Unsaved-changes badge and discard-on-close behavior
- Changes are written directly to the file's property map via the TagLib bridge

### Artwork Support

- Preview existing embedded artwork
- Replace artwork from an image file
- Import artwork from the clipboard
- Remove artwork from one file or many selected files
- Apply artwork changes across multi-file selections

### Batch and Utility Tools

- Renumber tracks from the current visible list order
- Apply renumbering to the full list or only the current selection
- Choose ascending or descending numbering, custom start number, and optional leading-zero padding
- Import one metadata field from plain text using configurable delimiters (newline, `,` `;` `，` `；`)
- Rename selected files from a metadata token template while preserving file extensions
- Extract metadata values from filenames using a match template (`Filename & Metadata` tool)
- Open, reveal in Finder, copy path, or copy filename for selected files
- Erase supported metadata fields from selected files

### MusicBrainz Browser

- Open a dedicated `MusicBrainz Browser` window from the toolbar or menu commands
- Search by track, album, selected file metadata, or direct MusicBrainz link
- Seed searches from the current AudioMator selection
- Review result details for recordings, releases, and tracks
- Use MusicBrainz as an optional reference workflow while keeping local editing in AudioMator

### MusicBrainz Tagging Workbench

When viewing a release or track detail in the MusicBrainz Browser, open the tagging workbench to apply MusicBrainz metadata to local files:

- Select which fields to write from the matched release

  | `Title` | `Artist` | `Album Artist` | `Album` | `Track Number` | `Disc Number` | `Release Date` | `Publisher` | `Composer` |
  |---|---|---|---|---|---|---|---|---|

- Assign each loaded AudioMator file to a specific MusicBrainz release track
- Preview a full diff of current tag values versus the proposed MusicBrainz values before committing
- Composer credits are loaded asynchronously from MusicBrainz recording relationship data

### Settings

A `Settings` window (⌘,) provides app-wide preferences across four tabs:

- **General** — toggle the welcome screen on launch; toggle the unsaved-inspector-edits warning
- **Toolbar** — show or hide individual toolbar buttons
- **Columns** — show or hide individual middle-list columns; restore defaults
- **About** — version and build info, in-app release notes viewer, acknowledgements

### Welcome and App Experience

- Show a multi-page welcome screen on first launch
- Reopen the welcome screen from the Help menu or Settings
- Toggle the inspector from the toolbar or menu commands

## Supported Formats

All 23 extensions use the same set for file import, metadata writing, and artwork writing:

| `mp3` | `mp2` | `m4a` | `m4b` | `m4p` | `mp4` |
|---|---|---|---|---|---|
| `aac` | `ogg` | `opus` | `mpc` | `wma` | `asf` |
| `spx` | `flac` | `ape` | `wv` | `tta` | `wav` |
| `aiff` | `aif` | `dsf` | `dff` | `oga` | |

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
- Multi-file editing in the inspector only applies fields you explicitly change
- Raw metadata inspection in the `Tag Inspector` is read-only
- `Credits` are read-only (visible in the inspector and the middle-list column, but not writable through the inspector)
- MusicBrainz lookup and tagging workbench depend on network access and the external MusicBrainz service
- No separate test target is currently checked into the repository

## Disclaimer

> Review the code critically before relying on it for destructive metadata workflows or large-library cleanup.
