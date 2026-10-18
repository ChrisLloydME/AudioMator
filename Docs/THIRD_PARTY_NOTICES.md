# Third-Party Notices

This file summarizes third-party software, services, and project influences used by AudioMator. It is not a substitute for the upstream license texts.

The app bundle includes the full license texts listed below at the top level of `AudioMator.app/Contents/Resources`. The in-app **Acknowledgements** sheet (Settings → About) lists the same components and opens the bundled texts. The About panel also identifies TagLib and displays its upstream copyright.

## AudioMator

- **Project**: AudioMator
- **Source**: https://github.com/ChrisLloydME/AudioMator
- **License**: GNU Affero General Public License v3.0 (AGPL-3.0); see the repository [`LICENSE`](../LICENSE).
- **App bundle resource**: `AudioMator-AGPL-3.0.txt`.

## TagLib

- **Project**: TagLib audio metadata library
- **Version reported by the bundled framework**: 2.3.1
- **Website**: https://taglib.org/
- **Source**: https://github.com/taglib/taglib/tree/v2.3.1 (tag `v2.3.1`, commit `54ae7d8ac45755e286a5c574280f48d5bef93aef`)
- **Copyright**: Copyright (C) 2002–2008 Scott Wheeler and TagLib contributors.
- **Usage in this repository**: AudioMator uses TagLib through the `TagLibAudioMetadata` Swift package for audio metadata reading, metadata writing, format capability discovery, raw property-map inspection, and artwork operations. The build bundles TagLib in `AudioMator.app/Contents/Frameworks/TagLibAudioMetadataTagLib.framework`.
- **App bundle resources**: `TagLib-LGPL-2.1.txt` and `TagLib-MPL-1.1.txt`.

### Licensing

TagLib is third-party open-source software and is not public domain.

TagLib is dual-licensed. For compliant use, choose and comply with at least one of these license paths:

- GNU Lesser General Public License v2.1 (LGPL-2.1)
- Mozilla Public License 1.1 (MPL-1.1)

### Distribution Obligations

A release that contains TagLib must:

1. Note that the application uses TagLib.
2. Preserve the upstream copyright and attribution notices.
3. Include the applicable license text; the app bundle already contains both texts.
4. Make the corresponding TagLib source available. Record the TagLib version and the pinned `TagLibAudioMetadata` version in the release notes.
5. If TagLib itself is modified, publish those TagLib modifications as required by the chosen license path.

TagLib is linked as a separate dynamic framework. AudioMator's AGPL-3.0 source is public, so recipients can rebuild the app or relink it with a modified TagLib.

Confirm that the pinned package builds TagLib from the unmodified `v2.3.1` source before treating the upstream tag as the corresponding source. If the package applies patches, publish or link to the exact modified TagLib source instead.

### Local Project Status

- This repository uses TagLib through a package dependency instead of checking a full TagLib source tree into the app repository.
- This repository includes usage and licensing notices for TagLib in `README.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`, this file, and the in-app Acknowledgements sheet.
- If future changes vendor TagLib source or modify TagLib itself, maintainers must update these notices and publish required TagLib changes according to the selected license path.

## utf8-cpp (utfcpp)

- **Project**: utf8-cpp (utfcpp)
- **Source**: https://github.com/nemtrif/utfcpp
- **Copyright**: Copyright 2006 Nemanja Trifunovic.
- **Usage in this repository**: UTF-8 conversion library bundled inside the TagLib framework supplied by `TagLibAudioMetadata`.
- **License**: Boost Software License 1.0.
- **App bundle resource**: `utfcpp-Boost-1.0.txt`.

The Boost license permits distribution in machine-executable object form without reproducing the notice, but AudioMator includes the notice and license text so the complete dependency attribution stays discoverable.

## TagLibAudioMetadata

- **Project**: TagLibAudioMetadata
- **Source**: https://github.com/ChrisLloydME/TagLibAudioMetadata.git
- **Current resolution**: exact version `0.5.3`, revision `03473c9ae199026b806a5f75c387ca036e325284`, pinned in `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- **Copyright**: Copyright (c) 2026 Christopher Lloyd.
- **License**: MIT License.
- **Usage in this repository**: Swift Package Manager dependency that exposes the TagLib-backed APIs consumed by AudioMator's metadata pipeline.
- **App bundle resource**: `TagLibAudioMetadata-MIT.txt`.
- **Not vendored**: AudioMator does not include a local copy of this package or of TagLib source in this repository.

The MIT License requires the copyright and permission notice to accompany copies or substantial portions of the Software. Keep the MIT notice in the app bundle even though the package author also maintains AudioMator.

## iTunes Artwork Finder

- **Project**: iTunes Artwork Finder
- **Source**: https://github.com/bendodson/itunes-artwork-finder
- **Usage in this repository**: inspiration for the original album artwork lookup workflow and result transformation approach. AudioMator's current iTunes metadata and artwork implementation is written in Swift in this repository.
- **Upstream license**: Unlicense (public-domain dedication).

No source code from this project is copied into AudioMator. The acknowledgement is retained even though the Unlicense does not require attribution.

## Apple iTunes Search API

- **Service documentation**: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/
- **Usage in this repository**: optional web-service lookup for Apple catalog album and track metadata, UPC/link/store-ID lookup, metadata comparison, selected local tag writing, and artwork candidate discovery.

### Service Notice

The iTunes Search API is an Apple web service, not third-party source code bundled into AudioMator. Keep privacy disclosures current when changing the iTunes lookup flow, because queries may include metadata-derived search terms, storefront country, UPC/barcode values, Apple Music or iTunes links, and Apple/iTunes catalog IDs.

## MusicBrainz

- **Service**: MusicBrainz
- **Website**: https://musicbrainz.org/
- **Usage in this repository**: optional web-service lookup for metadata search, release/recording lookup, relationship lookup, and tag-assist workflows. AudioMator's MusicBrainz client, query builder, and result mapping are written in Swift in this repository.

### Service Notice

MusicBrainz is a public web service, not third-party source code bundled into AudioMator. Keep privacy disclosures current when changing the MusicBrainz lookup flow, because queries may include metadata-derived search terms or identifiers. The app sends a descriptive `User-Agent` and spaces requests at roughly one per 1.1 seconds.

## LRCLIB

- **Project / service**: LRCLIB
- **Source**: https://github.com/tranxuanthang/lrclib
- **Usage in this repository**: optional web-service lookup for synced lyrics candidates. AudioMator's LRCLIB client implementation is written in Swift in this repository.

### Service Notice

LRCLIB is a public lyrics service, not third-party source code bundled into AudioMator. Keep privacy disclosures current when changing the LRCLIB lookup flow, because queries may include metadata-derived title, artist, album, and duration values.

## MuseAmp

- **Project**: MuseAmp
- **Source**: https://github.com/Lakr233/MuseAmp
- **Upstream license**: MIT License, copyright (c) 2026 @Lakr233.
- **Usage in this repository**: optional compatibility feature that writes MuseAmp album/track IDs into the Comment field. AudioMator is an independent project and is not affiliated with, endorsed by, or sponsored by MuseAmp or its developers.
- **Status**: opt-in; the feature runs only when the user enables MuseAmp Compatibility.

No MuseAmp source code is copied into AudioMator. The acknowledgement and license record are retained for completeness because the feature interoperates with MuseAmp data.

## GitHub Releases

- **Service**: GitHub Releases
- **Repository**: https://github.com/ChrisLloydME/AudioMator/releases
- **Usage in this repository**: source of truth for AudioMator release metadata, release notes, and the lightweight macOS manual update check.

### Service Notice

GitHub Releases is a web service, not third-party source code bundled into AudioMator. The macOS update check reads release metadata from GitHub, compares the release tag's version and build with the local app version and build, and opens the GitHub Releases page when the user chooses to download an update manually. AudioMator release tags must use the form `V<version>B<build>`, for example `V2.3B26512`.

## Bundled License Resources

| Component | App bundle resource | License |
| --- | --- | --- |
| AudioMator | `AudioMator-AGPL-3.0.txt` | AGPL-3.0 |
| TagLib | `TagLib-LGPL-2.1.txt`, `TagLib-MPL-1.1.txt` | LGPL-2.1 or MPL-1.1 |
| TagLibAudioMetadata | `TagLibAudioMetadata-MIT.txt` | MIT |
| utf8-cpp (utfcpp) | `utfcpp-Boost-1.0.txt` | Boost Software License 1.0 |

Release validation must confirm those five files are present in the built app's `Contents/Resources` directory. The in-app Acknowledgements sheet loads them by resource name and fails closed with a visible fallback if a text is missing.

At this revision, the bundled TagLib LGPL-2.1 and MPL-1.1 texts correspond to TagLib tag `v2.3.1`, and the TagLibAudioMetadata MIT text matches package revision `03473c9ae199026b806a5f75c387ca036e325284`.
