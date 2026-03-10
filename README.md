# AudioMator

AudioMator is a SwiftUI-based macOS audio metadata editor for inspecting and organizing tags in local audio files.

## Features

- Import local audio files and view them in a table
- Inspect and edit single-file metadata in the right-side Inspector
- Show merged metadata view when multiple files are selected
- Save current edits with one click (written via TagLib)
- Batch renumber Track Number by middle-list order (start value, ascending/descending, zero padding)
- View raw metadata text (Tag Inspector / metadata dump)
- Context menu actions: open file, reveal in Finder, copy path/filename, erase all tags

## Supported Formats

- Import: `mp3`, `m4a/mp4`, `wav`, `aiff`
- Tag writing (current implementation): `mp3`, `m4a`, `m4b`, `m4p`, `mp4`

Note: `wav/aiff` are currently used mainly for reading/display. Tag writing is skipped for them.

## Tech Stack

- SwiftUI (UI)
- AVFoundation (technical audio info + part of metadata reading)
- TagLib Bridge (core metadata read/write)

## Development Environment

- Xcode (with `AudioMator` scheme configured)
- Swift 5
- macOS Deployment Target: `26.1` (see `AudioMator.xcodeproj/project.pbxproj`)

If your local Xcode or macOS version does not match the deployment target, adjust the project settings before building.

## Quick Start

### 1. Open the project in Xcode

```bash
open AudioMator.xcodeproj
```

### 2. Run

- Select scheme: `AudioMator`
- Build configuration: `Debug` (default for development)
- Press Run

### 3. Build from command line (optional)

```bash
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug build
```

## Project Structure

- `AudioMator/`: app source code (SwiftUI views, view models, models)
- `AudioMator/TagLibBridge/`: TagLib bridge layer (Swift + Objective-C++)
- `AudioMator.xcodeproj/`: Xcode project settings

## Interaction Notes

- The middle list supports drag-and-drop reordering; batch Track Renumber follows this order
- The `Save` button applies to the currently selected single-file edit model
- `Erase All Tags` is destructive and cannot be undone

## Possible Next Improvements

- Add write support for more formats (for example `WAV/AIFF`)
- Add batch editing for shared fields (`Artist`, `Album`, etc.)
- Add automated renaming rules and export reports
