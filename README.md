<p align="center">
  <img src="AppIcon-1024x1024@1x.png" alt="AudioMator app icon" width="240">
</p>

<h1 align="center" style="font-size: 36px;">AudioMator</h1>

<p align="center">
  <strong style="font-size: 24px;">Your Audio Library’s Best Mate</strong><br>
  Native Audio Metadata Editor
</p>

<p align="center">
  <a href="#building">
    <img alt="Build for macOS Tahoe" src="https://img.shields.io/badge/Build%20for-macOS-black?style=for-the-badge&logo=apple">
  </a>
</p>


## Overview

AudioMator is a local-first audio metadata editor for macOS and iPadOS. It helps users inspect, organize, and edit music files through common tagging workflows, including metadata editing, artwork replacement, automatic track numbering, filename-based metadata conversion, raw metadata inspection, and online metadata lookup. For more detailed feature information, see [AudioMator Feature Overview](#audiomator-feature-overview).

> [!CAUTION]
>
> #### macOS 27 Golden Gate Compatibility Issues
>
> * Toolbar buttons may appear incorrectly.
> * Tag Inspector: [TagLib Properties] are not displayed correctly.



## Screenshot

<p align="center">
  <img src="Screenshot.png" alt="Screenshot">
</p>

## AudioMator Feature Overview

- ### Metadata Editing

  AudioMator provides two metadata editing interfaces for different levels of control.

  **Inspector** offers a more approachable editing experience for common metadata fields. It is designed for everyday metadata editing, with a simpler interface and a focus on frequently used fields.

  **Metadata Editor** is a more advanced editing interface. It allows users to add, remove, and edit all available metadata fields, making it suitable for more detailed or professional metadata workflows.
 
  <img src="Docs/Images/AudioMator Metadata Editor.png">
 
- ### Automatic Track Number Assignment

  AudioMator allows users to reorder audio files by dragging them into the desired sequence, then automatically regenerate track numbers based on that order. This is useful for organizing albums, live recordings, or any group of files where track order needs to be corrected or standardized.
  
   <img src="Docs/Images/Renumber Track Numbers.png">
 
- ### Metadata and Text Conversion

  AudioMator supports bidirectional conversion between metadata and text-based sources, including filenames, TXT files, and CSV files. Users can extract metadata from filenames or structured text files, and they can also generate filenames or text-based metadata records from existing file metadata.
  

> [!CAUTION]
>
> Metadata and Text Conversion is still under active refinement. Some behavior may require further improvement, especially when working with complex filenames, inconsistent TXT/CSV structures, or unusual metadata values. Please use this feature carefully, and manually review the results after applying changes to ensure that the metadata has been interpreted and written correctly.

- ### Online Metadata Lookup

  AudioMator can search for and apply metadata from online sources, including MusicBrainz, iTunes Search, and LRCLIB. MusicBrainz and iTunes Search are used for general music metadata lookup, while LRCLIB is mainly used for finding and applying lyrics metadata.
  
  <img src="Docs/Images/Online Metadata Lookup.png">

- ### Tag Inspector

  Tag Inspector provides a read-only view of the raw tags and file properties stored in the selected file. It is designed for inspection and troubleshooting, allowing users to review the actual metadata values detected by AudioMator without modifying them.

- ### Metadata Editor Utilities

  The Metadata Editor includes text-processing utilities for both single-file and multi-file workflows. These tools support case conversion, find and replace, prefix and suffix insertion, and trimming leading or trailing whitespace. They are intended to make large-scale metadata cleanup and normalization more efficient.
  
  <img src="Docs/Images/Metadata Editor Utilities.png">

## Platform Model

### macOS

The macOS build is the full desktop workflow:

- Current Session import for one-off work.
- Persistent watched folders with automatic rescans.
- Sidebar, middle list, and inspector in a native three-pane window.
- Dedicated windows for Online Metadata, Filename & Metadata, and Metadata Editor.
- File-path display in the inspector.
- Finder-style actions such as reveal in Finder, open with the default app, and copy path.
- Configurable toolbar buttons.
- Configurable list columns.
- Settings tabs for General, Toolbar, Columns, and About.

### iPadOS

The iPadOS build intentionally avoids pretending to be macOS:

- Session-only document workflow.
- No persistent watched folders.
- No desktop-style sidebar.
- Content + inspector workspace optimized for touch.
- Tools appear as in-page sheets instead of extra windows.
- Document picking uses security-scoped access during the active session.
- File-path presentation is hidden where it does not fit iPadOS.
- Settings focus on iPad-specific list metadata and About information.

> [!IMPORTANT]
>
> #### About iPadOS Support
>
> I do not have an Apple Developer Program membership and there are currently no plans to commercialize AudioMator. The iPadOS version is being developed separately from the macOS release cycle and should be considered more of a personal side project and platform experiment rather than a feature-parity target.

## Track And Disc Number Handling

AudioMator treats track and disc data as structured metadata instead of a single loose string. These fields are first-class throughout the inspector, batch editor, filename tools, MusicBrainz write-back, and write verification path:

- `Track Number`
- `Total Tracks`
- `Disc Number`
- `Total Discs`

This matters because common containers do not all store numbering the same way. A user may enter `02/09`, but the file format may represent that as numeric track `2`, numeric total `9`, and possibly a separate text form. AudioMator preserves both numeric intent and user-facing text intent where the container and bridge support it.

### Write behavior

- ID3v2-style formats use canonical `TRCK` and `TPOS` values.
- PropertyMap-style formats use `TRACKNUMBER`, `TRACKTOTAL`, `DISCNUMBER`, `DISCTOTAL`, and compatible aliases where needed.
- MP4/M4A writes standard `trkn` and `disk` numeric pairs.
- MP4/M4A also uses internal freeform preservation data where available so formatting such as zero padding can survive a round trip.
- Post-write verification compares numeric values and text forms separately so a harmless container normalization is reported differently from a real write mismatch.

## Supported Formats

AudioMator discovers readable and writable extensions from the `TagLibAudioMetadata` package at runtime. Current supported readable extensions include:

`mp3`, `mp2`, `m4a`, `m4b`, `m4p`, `mp4`, `aac`, `ogg`, `opus`, `mpc`, `wma`, `asf`, `spx`, `flac`, `ape`, `wv`, `tta`, `wav`, `aiff`, `aif`, `dsf`, `dff`, `oga`

Format-specific behavior still depends on the underlying container and tag implementation. Raw property-map support is the widest common surface. Some module/tracker formats may be treated as metadata-only writable formats for artwork purposes when the package reports that capability.

## Privacy And Network Use

AudioMator is local-first. Core editing, raw inspection, filename tools, batch editing, renumbering, and local artwork replacement run on the device.

Network access happens only when you explicitly use an online feature:

- MusicBrainz lookup and tagging contacts `musicbrainz.org`.
- iTunes metadata and artwork lookup contacts the Apple iTunes Search API at `itunes.apple.com` and Apple artwork CDN hosts.
- LRCLIB synced lyrics lookup contacts `lrclib.net`.
- Release-note lookup may contact `api.github.com`.
- Manual update checks on macOS contact GitHub Releases through `api.github.com` to read the latest AudioMator release tag and version metadata.

AudioMator does not upload the audio file contents for ordinary metadata editing. Online lookup features may send search terms derived from metadata or user input, such as title, artist, album, album artist, track number, duration, ISRC, barcode/UPC, iTunes album/artist/track IDs, MusicBrainz identifiers, pasted MusicBrainz/Apple Music/iTunes links, storefront country, or manually entered queries.

See `ACKNOWLEDGEMENTS_AND_PRIVACY.md` for the detailed disclosure.

## Manual Update Checks

The macOS app includes a lightweight **Check for Updates...** flow. AudioMator asks the GitHub Releases API for the latest published release, compares the release tag with the app's current version, and opens the GitHub Releases page when you choose to download an update.

AudioMator release tags must use the form `V<version>B<build>`, for example `V2.3B26512`. The update checker compares only the version part before `B`; the build number is ignored. Version parts are compared as integer segments, so `2.10` is newer than `2.9`, and `2.2` is newer than `2.1.20`.

This flow does not install updates, download archives in the background, perform delta updates, or require code signing or notarization. Sparkle infrastructure remains dormant for macOS. The app does not start Sparkle at launch and does not link `Sparkle.framework` unless `ENABLE_SPARKLE_UPDATES` is added and the Sparkle package product is linked back into the app target.

## TagLib Bridge Smoke Testing

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

## Contact

E-mail: AudioMator@lloydME.com

## Repository Layout

- `AudioMator/`
  The app source.
- `AudioMator/App/`
  App entry point, commands, notifications, and platform delegates.
- `AudioMator/Core/`
  Shared platform compatibility, network disclosure, and audio-format support.
- `AudioMator/Domain/`
  Metadata pipeline models, audio-file models, rename templates, file sources, track renumbering, and UI state.
- `AudioMator/Features/`
  SwiftUI feature areas for the main window, iPad workspace, online metadata browser, provider-specific metadata and lyrics browsers, metadata editor, settings, filename tools, metadata inspector, and welcome flow.
- `AudioMator/Infrastructure/`
  File-system monitoring, MusicBrainz, iTunes Search API/artwork, LRCLIB lyrics lookup, GitHub release-note services, and macOS manual update checks.
- `Config/`
  Project configuration inputs, including the app Info.plist.
- `scripts/`
  Build and smoke-test helpers.
- `README.md`
  Product and developer overview.
- `ACKNOWLEDGEMENTS_AND_PRIVACY.md`
  Network/privacy notes and third-party acknowledgements.
- `THIRD_PARTY_NOTICES.md`
  Third-party license notices.
