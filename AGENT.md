# AGENT.md

This file provides guidance for AI coding agents (such as OpenAI Codex) working in this repository.

## Repository overview

AudioMator is a native SwiftUI app for macOS and iPadOS that edits audio file metadata. It is built with Swift and uses the `TagLibAudioMetadata` Swift package (which wraps a TagLib C++ bridge) for reading and writing tags.

## Build

### Standard build (macOS)

```bash
bash scripts/codex-build.sh
```

This script runs `xcodebuild` with `CODE_SIGNING_ALLOWED=NO` and writes derived data to `.deriveddata-codex/`. It treats the known `actool`/`ibtoold` crash on the `AppIcon.icon` asset as a false-positive environment limitation and exits 0 for that specific failure.

### Manual xcodebuild invocations

```bash
# macOS
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug CODE_SIGNING_ALLOWED=NO build

# iPadOS (generic device)
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Deployment targets are **macOS 26.0** and **iOS/iPadOS 26.0**.

### TagLib bridge smoke tool

Used for low-level bridge debugging only (track/disc totals, MP4 `trkn`/`disk` behaviour, text-preservation, raw property maps). This tool requires the TagLib bridge source to be present in the checkout.

```bash
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke read path/to/file.m4a
./.tmp/taglib_bridge_smoke raw path/to/file.m4a
./.tmp/taglib_bridge_smoke write-track path/to/file.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke write-roundtrip path/to/file.m4a
```

## Repository layout

```
AudioMator.xcodeproj        Xcode project
AudioMator/
  App/                      App entry point, commands, notifications, platform delegates
  Core/
    Audio/                  Audio format support
    Network/                Shared networking utilities
    Platform/               Platform detection and abstractions
  Domain/
    AudioFiles/             Audio file models
    FileSources/            File source abstractions (watched folders, sessions)
    MetadataEditing/        Metadata pipeline (AudioMetadataPipeline)
    Rename/                 Filename ↔ metadata templates
    TrackRenumber/          Track renumbering logic
    UIState/                Observable UI state models
  Features/
    Main/                   Three-pane main window (macOS)
    iPad/                   iPad workspace layout
    MetadataEditor/         Batch metadata editing UI
    MetadataFilenameTool/   Metadata ↔ filename import/export tool
    MetadataInspector/      Single-file inspector panel
    MusicBrainzBrowser/     MusicBrainz lookup and tagging UI
    Settings/               Settings and About flow
    Welcome/                Welcome / onboarding flow
  Infrastructure/
    FileSystem/             File-system services
    GitHub/                 GitHub release-note fetching
    MediaServices/          iTunes artwork lookup
    MusicBrainz/            MusicBrainz API client
scripts/
  codex-build.sh            Primary build helper for Codex
  build-taglib-bridge-smoke.sh  Bridge smoke-test builder
  taglib_bridge_smoke.mm    Bridge smoke-test source
README.md
AGENT.md                    This file
```

## Architecture notes

- **SwiftUI-first**: All UI is SwiftUI. Platform differences (macOS vs iPadOS) are handled through conditional compilation (`#if os(macOS)`) and separate feature-area views under `Features/iPad/` and `Features/Main/`.
- **TagLib bridge**: Metadata reads and writes go through the `TagLibAudioMetadata` Swift package. The bridge exposes an Objective-C++ layer (`TagLibMetadataExtractor.mm`) consumed by Swift via the bridging header (`AudioMator-Bridging-Header.h`).
- **Metadata pipeline**: `AudioMetadataPipeline` in `Domain/MetadataEditing/` is the central coordinator for reading, editing, and writing metadata.
- **Track/disc numbers**: Treated as four first-class structured values (`trackNumber`, `totalTracks`, `discNumber`, `totalDiscs`). Do not collapse them into freeform text strings.
- **Local-first**: Network access (MusicBrainz, iTunes artwork, GitHub release notes) only happens on explicit user action.
- **Platform model**:
  - macOS: persistent watched folders, multi-window tools, file-path display.
  - iPadOS: session-only, no watched folders, tools open as sheets, no file-path display.

## Coding conventions

- Swift 6 / strict concurrency where possible; use `@MainActor` for UI state.
- No third-party Swift packages beyond `TagLibAudioMetadata`.
- Prefer small, focused files scoped to a single type.
- Avoid force-unwraps in new code; prefer `guard`/`if let`.
- Match the surrounding file's comment style when adding comments.

## Common tasks

| Task | Where to look |
|---|---|
| Add or change a metadata field | `Domain/MetadataEditing/AudioMetadataPipeline.swift` and the TagLib bridge |
| Change inspector UI | `Features/MetadataInspector/` |
| Change batch editor UI | `Features/MetadataEditor/` |
| Add a rename template token | `Domain/Rename/` |
| Add a MusicBrainz field | `Infrastructure/MusicBrainz/` and `Features/MusicBrainzBrowser/` |
| Add a new macOS-only feature | `Features/Main/` (guard with `#if os(macOS)`) |
| Add a new iPad-only feature | `Features/iPad/` |
| Debug bridge-level read/write | `scripts/build-taglib-bridge-smoke.sh` + `taglib_bridge_smoke.mm` |
