# AudioMator

<p align="center">
  <img src="AppIcon-1024x1024@1x.png" alt="AudioMator app icon" width="140" />
</p>

<p align="center">
  A SwiftUI-based macOS audio metadata editor for inspecting, organizing, and updating tags in local audio files.
</p>

<p align="center">
  <strong>SwiftUI</strong> · <strong>TagLib Bridge</strong> · <strong>AVFoundation</strong> · <strong>macOS</strong>
</p>

## Overview

AudioMator is a desktop tool for browsing a local audio library, inspecting metadata, editing common tag fields, and writing changes back to disk. The current app focuses on practical single-file editing, metadata inspection, and a few workflow-oriented bulk actions.

## Features

- Import local audio files and browse them in a table view
- Inspect and edit single-file metadata in the right-side inspector
- Show a merged metadata view when multiple files are selected
- Save edits through the TagLib-backed write path
- Batch-renumber track numbers by current list order
- View raw metadata text through the tag inspector / metadata dump
- Use context menu actions to open files, reveal them in Finder, copy paths, or erase all tags

## Supported Formats

| Capability | Formats |
| --- | --- |
| Import / read | `mp3`, `m4a`, `mp4`, `wav`, `aiff` |
| Tag writing | `mp3`, `m4a`, `m4b`, `m4p`, `mp4` |

`wav` and `aiff` are currently used mainly for reading and display. Writing is skipped for those formats in the current implementation.

## Quick Start

### Open in Xcode

```bash
open AudioMator.xcodeproj
```

### Run

1. Select the `AudioMator` scheme.
2. Use the `Debug` configuration for development.
3. Press Run in Xcode.

### Optional command-line build

```bash
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug build
```

## Development Notes

- UI: SwiftUI
- Audio metadata / technical info: AVFoundation
- Metadata read/write bridge: TagLib Bridge
- Language / toolchain: Swift 5
- Deployment target: `26.1` in [AudioMator.xcodeproj/project.pbxproj](/Users/lloyd/Developer/Xcode/AudioMator/AudioMator.xcodeproj/project.pbxproj)

If your local Xcode or macOS version does not match the deployment target, adjust the project settings before building.

## Project Structure

- `AudioMator/`: SwiftUI app source, models, view models, and views
- `AudioMator/TagLibBridge/`: Swift + Objective-C++ bridge layer around TagLib
- `AudioMator.xcodeproj/`: Xcode project configuration

## Interaction Notes

- Drag-and-drop reordering in the middle list affects batch track renumbering order
- The `Save` button applies to the currently selected single-file edit model
- `Erase All Tags` is destructive and cannot be undone

## Disclaimer

> This is a student project. Code quality is not guaranteed, test coverage is limited, and the current test surface is small. The project has not been thoroughly audited for safety or security risks. Review the code critically and use it with caution.

## Possible Next Improvements

- Add write support for more formats such as `wav` and `aiff`
- Add batch editing for shared fields such as `Artist` and `Album`
- Add automated renaming rules and exportable reports
