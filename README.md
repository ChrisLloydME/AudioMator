<p align="center">
  <img src="AppIcon-1024x1024@1x.png" alt="AudioMator app icon" width="320">
</p>

<h1 align="center">AudioMator</h1>

<hr>

<p align="center">
  <strong>Native audio metadata editing for macOS and iPadOS.</strong><br>
  Inspect tags, batch edit fields, manage artwork, rename files from metadata, extract metadata from filenames, renumber tracks, and tag releases with MusicBrainz.
</p>

<p align="center">
  <a href="#building">
    <img alt="Build app for macOS" src="https://img.shields.io/badge/Build%20app%20for-macOS-black?style=for-the-badge&logo=apple">
  </a>
</p>

AudioMator is built around a TagLib-powered metadata pipeline, a SwiftUI-first shell, and platform-specific UI where native behavior matters. On macOS the app keeps its desktop workflow, including watched folders and multi-window tools. On iPadOS the app switches to a session-only model that matches the sandbox and touch interaction model.

## Current platform model

### macOS

- Full desktop workflow
- Current Session import
- Persistent watched folders with automatic rescan
- Three-pane main window: sidebar, file list, inspector
- Secondary tools open in dedicated windows
- File-path display and Finder-style reveal/open actions

### iPadOS

- Session-only workflow
- No watched folders
- No left sidebar
- Main layout is content + inspector only
- Secondary tools open as in-page sheets instead of extra windows
- Inspector hides file-path presentation that does not make sense on iPad
- Document picking uses security-scoped imports inside the active session

## What AudioMator can do

### Metadata editing

- Single-file editing in the inspector
- Multi-file batch editing with mixed-value handling
- Artwork replace / remove / keep semantics
- Explicit-content editing
- Raw property-map editing for arbitrary keys
- Best-effort erase-all metadata

### Batch tools

- Track renumbering
- Text-to-field import
- Metadata to filename rename templates
- Filename to metadata extraction templates
- MusicBrainz-assisted batch tagging

### Inspection

- Normalized field view
- Raw TagLib property-map view
- ID3v2 frame inspection where applicable
- Technical audio properties
- Artwork preview

## Track / disc number handling

This project now treats the following four values as first-class fields instead of collapsing them into ad-hoc text:

- `Track Number`
- `Total Tracks`
- `Disc Number`
- `Total Discs`

### What changed

- The inspector now exposes four separate edit fields instead of loosely relying on combined text.
- Multi-file editing can apply these four values independently.
- Filename import/export and MusicBrainz write-back now feed the same structured number model.
- Metadata writes carry both numeric values and text-preservation hints through the pipeline.

### Bridge behavior

- For ID3v2-style formats, AudioMator writes canonical `TRCK` / `TPOS` values and preserves totals.
- For PropertyMap-style formats, AudioMator writes `TRACKNUMBER`, `TRACKTOTAL`, `DISCNUMBER`, `DISCTOTAL` and compatible aliases when needed.
- For MP4/M4A, AudioMator writes standard `trkn` / `disk` numeric pairs and also stores internal freeform text atoms to preserve user-facing formatting such as zero padding.
- Post-write verification compares both numeric values and text forms so the app can distinguish a real mismatch from harmless container normalization.

### Example

If the user enters `02/09`, AudioMator now preserves:

- numeric values: `track = 2`, `totalTracks = 9`
- user-facing text intent: `02/09`

That same round-trip is now verified for MP4/M4A instead of silently losing the total-track count.

## Supported formats

AudioMator discovers readable and writable formats from the `TagLibAudioMetadata` Swift package at runtime. Current supported extensions include:

`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`, `flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`

Format-specific depth still depends on the underlying container and tag implementation. Raw property-map support is the widest common surface across formats.

Some module/tracker formats are treated as metadata-only writable formats for artwork purposes.

## Optional online features

AudioMator is local-first. Network access only happens when you explicitly use online features:

- MusicBrainz lookup and tagging
- iTunes artwork lookup
- GitHub release notes in the About / Settings flow

Your audio files are read and written locally. AudioMator does not upload the files themselves for normal metadata editing.

## Building

Open `AudioMator.xcodeproj` in Xcode and build the `AudioMator` scheme. The project uses Swift Package Manager to resolve `TagLibAudioMetadata` from:

`https://github.com/ChrisLloydME/TagLibAudioMetadata.git`

The macOS target also resolves Sparkle 2 from:

`https://github.com/sparkle-project/Sparkle`

Current deployment targets in the Xcode project are macOS 26.0 and iOS/iPadOS 26.0.

Useful local commands:

```bash
bash scripts/codex-build.sh
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Sparkle updates

Sparkle is wired only for the macOS build, but update checking is currently disabled. The app does not expose a **Check for Updates…** command, does not show an update button in About settings, and does not start the Sparkle updater at launch. The package, appcast metadata, and sandbox support are kept in place so the feature can be enabled later without reworking the core integration.

Before shipping a build, replace the placeholder `SUPublicEDKey` build setting in `AudioMator.xcodeproj` with the public key printed by Sparkle's `generate_keys` tool. Publish the appcast at:

`https://chrislloydme.github.io/AudioMator/appcast.xml`

Sparkle's SPM tools are available under Xcode's package artifacts directory after dependency resolution, typically in `SourcePackages/artifacts/sparkle/Sparkle/bin/`. Use `generate_appcast` on the folder containing signed and notarized update archives, then upload the generated appcast and archives to the update host.

## TagLib bridge smoke testing

The repository includes a lightweight bridge regression tool under `scripts/`. It is intended for local bridge/package debugging and may require the expected TagLib bridge source layout to be available in your checkout.

```bash
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke read path/to/file.m4a
./.tmp/taglib_bridge_smoke raw path/to/file.m4a
./.tmp/taglib_bridge_smoke write-track path/to/file.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke write-roundtrip path/to/file.m4a
```

This tool is intended for bridge-level debugging, especially around:

- track/disc totals
- MP4 `trkn` / `disk` behavior
- text-preservation vs numeric readback
- raw property-map inspection

## Repository layout

- `AudioMator/`
  The app source
- `AudioMator/App/`
  App entry point, commands, notifications, and platform delegates
- `AudioMator/Core/`
  Shared platform and audio-format support
- `AudioMator/Domain/`
  Metadata pipeline models, audio-file models, rename templates, file sources, and UI state
- `AudioMator/Features/`
  SwiftUI feature areas for the main window, iPad workspace, metadata editor, MusicBrainz browser, settings, and welcome flow
- `AudioMator/Infrastructure/`
  File-system, MusicBrainz, iTunes artwork, and GitHub release-note services
- `scripts/`
  Build and smoke-test helpers
- `README.md`
  Product and developer overview
- `ACKNOWLEDGEMENTS_AND_PRIVACY.md`
  Network/privacy notes and third-party acknowledgements
- `THIRD_PARTY_NOTICES.md`
  Third-party license notices

## Current design constraints

- macOS and iPadOS intentionally do not expose identical file-management workflows.
- Watched folders remain macOS-only by design.
- iPadOS keeps the app session-scoped instead of simulating desktop folder persistence.
- Some containers normalize number formatting on save; AudioMator treats that as a warning, not always a failure.
- Erase-all metadata remains best-effort because the available metadata surfaces differ by container.
