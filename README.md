# AudioMator

AudioMator is a native audio metadata editor for `macOS` and `iPadOS`.

The project is built around a bundled TagLib bridge, a SwiftUI-first shell, and platform-specific UI where native behavior matters. On macOS the app keeps its existing desktop workflow, including watched folders and multi-window tools. On iPadOS the app switches to a session-only model that matches the sandbox and touch interaction model instead of pretending the desktop file workflow still exists.

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

AudioMator currently imports and writes metadata for these extensions through the bundled TagLib bridge:

`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`, `flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`

Format-specific depth still depends on the underlying container and tag implementation. Raw property-map support is the widest common surface across formats.

## Optional online features

AudioMator is local-first. Network access only happens when you explicitly use online features:

- MusicBrainz lookup and tagging
- iTunes artwork lookup
- GitHub release notes in the About / Settings flow

Your audio files are read and written locally. AudioMator does not upload the files themselves for normal metadata editing.

## Building

Open `AudioMator.xcodeproj` in Xcode and build the `AudioMator` scheme.

Useful local commands:

```bash
bash scripts/codex-build.sh
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## TagLib bridge smoke testing

The repository now includes a lightweight bridge regression tool:

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
- `AudioMator/TagLibBridge/`
  Swift wrapper + Objective-C++ bridge + bundled TagLib sources
- `scripts/`
  Build and smoke-test helpers
- `README.md`
  Product and developer overview
- `ACKNOWLEDGEMENTS_AND_PRIVACY.md`
  Network/privacy notes and third-party acknowledgements
- `FORMAT_METADATA_SUPPORT_ANALYSIS.md`
  Format and field support reference

## Current design constraints

- macOS and iPadOS intentionally do not expose identical file-management workflows.
- Watched folders remain macOS-only by design.
- iPadOS keeps the app session-scoped instead of simulating desktop folder persistence.
- Some containers normalize number formatting on save; AudioMator treats that as a warning, not always a failure.
- Erase-all metadata remains best-effort because the available metadata surfaces differ by container.
