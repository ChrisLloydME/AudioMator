# Product Overview

AudioMator is a native macOS application for inspecting, editing, organizing, and enriching audio-file metadata. It is local-first: ordinary editing operates on files the user selects or authorizes, and network access is limited to explicitly started online features.

This document describes the product as implemented at the audited commit. See [Configuration](../Reference/CONFIGURATION.md) for exact build settings and [Architecture Overview](../Architecture/OVERVIEW.md) for how the system is assembled.

## Purpose and Scope

AudioMator is built for local music-library maintenance:

- Inspect the tags and technical properties of audio files.
- Edit common metadata fields in a simple inspector, singly or across a selection.
- Edit the raw TagLib PropertyMap representation for advanced work.
- Convert between metadata and filenames, plain text, or CSV.
- Renumber tracks by the visible list order.
- Replace or clear embedded artwork.
- Look up metadata, artwork, and synced lyrics from opt-in online services.
- Keep folders watched across launches and refresh their contents.

AudioMator is **not** a media player, a cloud library, a tag-format conversion tool, or an automatic bulk renamer that runs without a preview. It does not host or upload the user's audio library. It also does not install application updates automatically.

## Feature Summary

The following features are implemented in the repository. Format-specific capability varies; see [Supported Formats](#supported-formats).

| Feature | What it does | Primary implementation |
| --- | --- | --- |
| Quick Import | Loads selected files into a session-only list. | `AudioViewModel.importQuickFiles`, `AudioViewModel+Import.swift` |
| Watched folders | Persists security-scoped folder access and refreshes contents on directory events and app activation. | `WatchedFolderStore`, `DirectoryMonitor`, `AudioViewModel` |
| Three-pane main window | Sidebar sources, sortable/editable middle list, and inspector. | `Features/Main` |
| Inspector editing | Edits common fields and artwork for one or many selected files. | `InspectorPane`, `SingleFileEditModel`, `MultiFileEditModel` |
| Metadata Editor | Edits the TagLib PropertyMap projection as ordered value lists. | `Features/MetadataEditor` |
| Tag Inspector | Read-only raw tag/property dump, including compatibility notes. | `MetadataDumpSheet`, `rawMetadataDumpText` |
| Filename & Metadata tool | Seven conversion modes: metadata→filename, filename→metadata, metadata→text, text→metadata, metadata→CSV, CSV→metadata, and field copy/cut. | `Features/MetadataFilenameTool`, `Domain/Rename`, `Domain/MetadataExchange` |
| Track renumbering | Rewrites track numbers by list or selection order, optionally zero-padded. | `Domain/TrackRenumber`, `AudioViewModel+TrackRenumbering.swift` |
| Conflict policies | Chooses how dirty Inspector/Metadata Editor drafts interact with on-disk changes. | `MetadataConflictPolicy`, `MetadataConflictResolver` |
| Save issue log | Persists non-success batch save summaries locally. | `SaveIssueLogStore` |
| Online metadata | MusicBrainz, iTunes Search API, and LRCLIB lookup and write-back. | `Features/*Browser`, `Infrastructure/*` |
| MuseAmp compatibility IDs | Optional generation and writing of MuseAmp album/track IDs as JSON comments. | `Domain/MuseAmp`, `AudioViewModel+MuseAmpIDWrite.swift` |
| Manual update check | Compares the GitHub Releases tag with the running version and opens the releases page. | `Infrastructure/Updates` |
| Localization | String catalogs for localizable UI text; the bundle declares English localization. | `Localizable.xcstrings`, `InfoPlist.xcstrings` |

## Metadata Model

AudioMator treats track and disc numbering as structured values rather than a single string. The inspector and conversion tools expose four independent fields:

- `Track Number`
- `Total Tracks`
- `Disc Number`
- `Total Discs`

Number and total are submitted to the metadata pipeline separately, together with optional user-facing number text (for example `02/09`). Containers may normalize the text representation while preserving the numeric values; the write verification path distinguishes that normalization from a real mismatch.

Year and release date are separate edit intents. The app submits them as separate patch fields and leaves container-level storage decisions to `TagLibAudioMetadata`. MP4 has a single standard date slot, so an independent Year edit can be rejected rather than silently overwriting Release Date.

Artwork is handled as an explicit three-state change: unchanged, replaced with bytes plus MIME type, or removed.

Content advisory is represented as unset, not explicit, clean, or explicit.

## Supported Formats

AudioMator does **not** hard-code the master format list. At runtime it asks `TagLibAudioMetadata` for:

- readable extensions,
- metadata-writable extensions,
- artwork-writable extensions, and
- writable-field capabilities per format.

`AudioFormatSupport` converts that into the app's capability snapshot. The app then preflights each requested field against the target format before writing.

At the audited dependency pin (`TagLibAudioMetadata` 0.5.3), the readable extensions reported by the package are expected to include:

`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`, `flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`.

This list is a point-in-time statement about the dependency, not an app-owned contract. The runtime-discovered list is authoritative. Read/write, artwork, and per-field support vary by container and tag implementation; a readable extension is not automatically writable.

## System Requirements

- **Runtime platform:** macOS 15.0 or later. The app target's `MACOSX_DEPLOYMENT_TARGET` is `15.0`.
- **Development toolchain:** stable Xcode 27. This audit built and tested with Xcode 27.1 (build 27A9275) and Apple Swift 6.4.
- **Dependency resolution:** network access to GitHub the first time Swift Package Manager resolves `TagLibAudioMetadata`.

The repository has no verified CI or test evidence for older macOS versions or for prerelease Xcode toolchains. Do not claim support that has not been built and tested.

## Installation and Distribution

Two paths are represented in the repository:

1. **Build from source.** Open `AudioMator.xcodeproj`, select the `AudioMator` scheme, and build. See [Build](../Development/BUILD.md).
2. **Published releases.** The in-app update checker and documentation point to <https://github.com/ChrisLloydME/AudioMator/releases>. The repository contains no release workflow, signing configuration, notarization automation, or installer packaging. A release artifact's signing/notarization status must be verified outside this repository before distribution.

## Dependencies and Responsibilities

| Dependency | Responsibility | AudioMator's side |
| --- | --- | --- |
| [`TagLibAudioMetadata`](https://github.com/ChrisLloydME/TagLibAudioMetadata) 0.5.3 (exact pin) | TagLib-backed snapshot loading, container tag read/write, format capability discovery, raw PropertyMap projection, artwork writes, verification, atomic commit, opaque file versioning. | Supplies semantic edit intent, raw deltas, expected versions, and consumes structured results. |
| TagLib 2.3.1 (through the package) | Low-level audio metadata parsing and writing. | Bundled as a dynamic framework; not called directly by app code. |
| utf8-cpp (utfcpp) | UTF-8 conversion inside TagLib. | Bundled with the TagLib framework; not called directly. |
| Apple frameworks (SwiftUI, AppKit, AVFoundation, CoreMedia, UniformTypeIdentifiers, Foundation) | UI, file panels, technical fallback metadata, thumbnails, content types. | Uses them directly in the appropriate layers. |
| MusicBrainz | Opt-in metadata lookup. | Builds queries, decodes results, maps to local fields. |
| Apple iTunes Search API and artwork CDN | Opt-in catalog metadata and artwork lookup. | Builds requests, ranks/compares results, downloads selected artwork. |
| LRCLIB | Opt-in synced-lyrics lookup. | Builds queries, ranks candidates, writes selected lyrics as a raw patch. |
| GitHub Releases API | Release notes and manual update checks. | Reads release metadata; opens the releases page for manual download. |

The exact boundary and known dependency limitations are documented in [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md), [Dependency Rules](../Architecture/DEPENDENCY_RULES.md), and [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md). License texts and service obligations are recorded in [Third-Party Notices](../THIRD_PARTY_NOTICES.md); the app bundle includes the full texts and Settings → About → Acknowledgements opens them.

## Important Limitations

- **Container behavior is not uniform.** Track/disc text, artwork roles, date fields, and raw PropertyMap keys differ by format. AudioMator verifies writes and reports container normalization, but it cannot make every container store every representation.
- **The raw editor is a PropertyMap view.** Container-native structures that TagLib does not project into PropertyMap are not editable there. Tag Inspector may still display them.
- **Batch operations are per-file, not atomic as a group.** Partial success is possible and is reported per file.
- **Revision checks are conservative.** Permission or timestamp-only changes can invalidate a revision even when tags did not change. Conversely, the app does not continuously monitor every open file.
- **Erase-all is best effort.** Supported tag surfaces differ by container.
- **Network features require explicit user action.** They are not background synchronization.
- **No automated UI test suite exists.** Build checks and focused view-model tests are the automated boundary; interactive acceptance remains manual.
- **No release automation exists in this repository.** See [Release Engineering](../Development/RELEASE.md).

## Current Version and License

The authoritative version, build number, bundle identifiers, and build settings are recorded in [Configuration](../Reference/CONFIGURATION.md). At the audited commit they were marketing version `2.7`, build `2697`, Debug bundle ID `com.TheLloydME.AudioMator.Beta`, and Release bundle ID `com.LloydME.AudioMator`.

The project is licensed under the GNU Affero General Public License v3.0; see [`LICENSE`](../../LICENSE) and the [Third-Party Notices](../THIRD_PARTY_NOTICES.md). The app bundle includes the AGPL-3.0 text plus the TagLib LGPL-2.1/MPL-1.1, TagLibAudioMetadata MIT, and utf8-cpp Boost texts.

## Documentation Navigation

- Users: [User Guide](USER_GUIDE.md), [FAQ](FAQ.md), [Troubleshooting](TROUBLESHOOTING.md).
- Contributors: [Build](../Development/BUILD.md), [Testing](../Development/TESTING.md), [Contributing](../../CONTRIBUTING.md).
- Architects: [Architecture Overview](../Architecture/OVERVIEW.md).
- Release maintainers: [Release Engineering](../Development/RELEASE.md).
- Security reviewers: [Security and Data Integrity](../Security/SECURITY_AND_DATA_INTEGRITY.md).
- AI coding agents: [AGENTS.md](../../AGENTS.md).
