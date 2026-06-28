# Repository Layout

The main repository layout is:

```text
AudioMator/
  App/
  Core/
  Domain/
  Features/
  Infrastructure/
Config/
AudioMatorTests/
Tests/
scripts/
AudioMator.xcodeproj/
Docs/
  Images/
  ACKNOWLEDGEMENTS_AND_PRIVACY.md
  THIRD_PARTY_NOTICES.md
Docs/wiki/
```

## AudioMator

`AudioMator/` is the app source root and is attached to the target through Xcode file-system synchronization. New app source files should usually go under an existing feature or layer folder.

## App

`AudioMator/App/` contains the app entry point, macOS app delegate, commands, notifications, and platform scene declarations. `AudioMatorApp.swift` creates the shared metadata pipeline, main view model, shared state, and feature stores.

## Core

`AudioMator/Core/` contains shared foundation code:

- `Audio`: track/disc parsing, audio format policy, and TagLib format support core.
- `Localization`: localization access.
- `Network`: network service disclosure and GitHub API request helpers.
- `Platform`: platform compatibility helpers.
- `Text`: fuzzy string similarity.

## Domain

`AudioMator/Domain/` contains business logic and models. Current subdirectories include `AudioFiles`, `FileSources`, `MetadataEditing`, `MetadataExchange`, `MuseAmp`, `Rename`, `TrackRenumber`, and `UIState`.

## Features

`AudioMator/Features/` groups SwiftUI views and feature-owned view models by workflow. Current directories include `Main`, `MetadataEditor`, `MetadataFilenameTool`, `OnlineMetadataBrowser`, `MusicBrainzBrowser`, `iTunesBrowser`, `LRCLIBLyricsBrowser`, `MetadataInspector`, `Settings`, `Welcome`, and `iPad`.

`OnlineMetadataBrowser` owns the shared Online Metadata window shell and source picker. Provider-specific flows stay in their own browser folders so MusicBrainz, iTunes, and LRCLIB concerns do not become hidden dependencies of the shared entry point.

## Infrastructure

`AudioMator/Infrastructure/` contains file-system, online service, and update-check integrations. Current directories include `FileSystem`, `GitHub`, `iTunes`, `LRCLIB`, `MusicBrainz`, `OnlineMetadata`, and `Updates`.

## Config

`Config/` contains target configuration inputs. `Info.plist` defines bundle display name, category, copyright, and version-field references. `AudioMator.entitlements` enables sandboxing, user-selected file read/write access, network client access, and Sparkle-related temporary mach lookup exceptions.

These configuration inputs stay outside the synchronized source root so Xcode treats them as build settings inputs rather than bundle resources.

## Tests and AudioMatorTests

`Tests/AudioMatorCoreLogicTests/` contains the SwiftPM fast core-logic tests.

`AudioMatorTests/` contains app-hosted Xcode tests for TagLib integration, metadata editor workflows, MusicBrainz/iTunes/LRCLIB helpers, directory monitoring plans, rename transactions, update checking, and related behavior.

## scripts

`scripts/codex-build.sh` is the validation build helper. `scripts/build-taglib-bridge-smoke.sh` and `scripts/taglib_bridge_smoke.mm` support TagLib bridge smoke debugging.

## Docs

`Docs/Images/` contains images used by the README. `Docs/wiki/` contains the Wiki Markdown pages, with `Home.md` as the landing page. Privacy acknowledgements and third-party notices also live under `Docs/` so the repository root stays focused on source, configuration, tests, and project entry points.
