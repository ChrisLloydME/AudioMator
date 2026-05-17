# AudioMator Agent Guide

## Project Overview

AudioMator is a native SwiftUI-first audio metadata editor for macOS and iPadOS. It uses the `AudioMator.xcodeproj` Xcode project and the `AudioMator` scheme.

The app is built around a TagLib-powered metadata pipeline from the `TagLibAudioMetadata` Swift package. It supports inspecting and editing audio tags, artwork, filename/metadata conversion, track renumbering, MusicBrainz-assisted tagging, watched folders on macOS, and a session-scoped iPad workflow.

SwiftUI is used because it makes cross-platform migration convenient, not because the project has a strict preference for SwiftUI over AppKit or UIKit. If AppKit or UIKit can produce a more complete native result, reduce implementation complexity, or improve performance for a specific feature, prefer AppKit or UIKit for that feature.

## Repository Layout

- `AudioMator/App/`: app entry point, commands, notifications, and platform delegates.
- `AudioMator/Core/`: shared platform, network disclosure, and audio-format support.
- `AudioMator/Domain/`: metadata models, audio-file models, rename templates, file sources, and UI state.
- `AudioMator/Features/`: SwiftUI feature areas for the main window, iPad workspace, online metadata browser, metadata editor, settings, and welcome flow.
- `AudioMator/Infrastructure/`: file-system, MusicBrainz, iTunes, and GitHub release-note services.
- `Config/`: project configuration files that should not be compiled or copied from the synchronized app source root.
- `scripts/`: build and smoke-test helpers.

The app source is attached to the target through Xcode's file-system synchronized `AudioMator/` root. Keep feature and infrastructure boundaries clear on disk; Xcode will mirror those folders automatically. Keep target configuration inputs such as `Config/Info.plist` outside that synchronized source root so Xcode processes them as build settings inputs instead of bundle resources.

## Platform Model

- macOS is the full desktop workflow: watched folders, three-pane main window, file paths, Finder-style reveal/open actions, and secondary tool windows.
- iPadOS is session-only: no watched folders, no desktop folder persistence, content + inspector layout, security-scoped imports, and sheet-based tools.
- Do not force feature parity where platform behavior intentionally differs.
- Gate platform-specific code with existing compatibility patterns in `AudioMator/Core/Platform/PlatformCompatibility.swift`.

## Architecture Rules

- Keep domain logic in `AudioMator/Domain/` and service integrations in `AudioMator/Infrastructure/`.
- Keep SwiftUI views and feature-specific view models under the closest `AudioMator/Features/*` folder.
- Keep cross-provider online metadata selection under `AudioMator/Features/OnlineMetadataBrowser/`; provider-specific browser flows stay under `Features/MusicBrainzBrowser/` and `Features/ITunesBrowser/`.
- Keep iTunes Store API clients and iTunes artwork lookup services together under `AudioMator/Infrastructure/ITunes/`.
- Avoid adding new top-level folders unless there is a clear architectural boundary.
- Prefer small feature-owned helpers over broad shared abstractions until more than one feature actually needs the behavior.
- Preserve the existing metadata write pipeline instead of writing container-specific metadata directly from UI code.
- Network-backed features must stay explicit and user initiated: MusicBrainz lookup, iTunes artwork lookup, and GitHub release notes.

## Metadata Rules

- Treat track and disc values as structured first-class fields:
  - `Track Number`
  - `Total Tracks`
  - `Disc Number`
  - `Total Discs`
- Preserve both numeric values and user-facing text intent when the surrounding pipeline supports it.
- Account for container normalization after writes; a changed text representation is not always a write failure if numeric values round-trip correctly.
- Erase-all metadata remains best effort because supported tag surfaces differ by container.

## Swift And SwiftUI Style

- Indentation: 4 spaces.
- Prefer `guard` and early returns to reduce nesting.
- Use value types unless identity, observation, or platform lifecycle requires a class.
- Use Swift concurrency where it fits the surrounding code.
- SwiftUI is not mandatory for every UI surface. Use AppKit on macOS or UIKit on iOS/iPadOS when it is the better engineering choice for fidelity, performance, platform behavior, or implementation simplicity.
- Keep UI state ownership in feature view models or domain state, not hidden inside views.
- Avoid introducing singletons for feature work.
- Use `String(localized:)` for user-facing strings.
- Do not add diagnostic `print`, `debugPrint`, or `NSLog` calls in app code.

## Build And Verification

Useful commands:

```bash
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
```

Prefer `bash scripts/codex-build.sh` for Codex validation. The script uses a two-stage strategy:

- It skips `xcodebuild` entirely when the current working tree has no build-relevant changes.
- When build-relevant files did change, it reuses the repository-local `.deriveddata-codex` directory so `xcodebuild build` can behave incrementally like Xcode instead of forcing a clean build.

Use `bash scripts/codex-build.sh --force` when you want to run a full validation build regardless of the changed-file filter. All Agent-triggered Xcode builds should write derived data to the repository-local `.deriveddata-codex` directory. Do not create alternate local build roots such as `.DerivedData`, `.deriveddata-codex-ios`, `.deriveddata-ios-codex`, or `.deriveddata-macos-codex`; reuse `.deriveddata-codex` and let the existing `.gitignore` keep it out of source control.

For bridge/package debugging:

```bash
bash scripts/build-taglib-bridge-smoke.sh
./.tmp/taglib_bridge_smoke read path/to/file.m4a
./.tmp/taglib_bridge_smoke raw path/to/file.m4a
./.tmp/taglib_bridge_smoke write-track path/to/file.m4a 07/12 2/3
./.tmp/taglib_bridge_smoke write-roundtrip path/to/file.m4a
```

If `xcodebuild` fails in sandboxed environments because it cannot write SwiftPM, Clang, simulator, or Xcode cache files under the user Library, treat that as an environment issue and rerun with appropriate permissions before diagnosing project code.

Do not launch the iPadOS simulator, boot virtual devices, or use simulator-only validation unless the user explicitly asks for it. Prefer generic iOS destination builds for iPadOS compile checks.

## Dependency Notes

- Swift Package Manager resolves `TagLibAudioMetadata` from `https://github.com/ChrisLloydME/TagLibAudioMetadata.git`.
- Current app target deployment settings in the project are macOS 26.0 and iOS/iPadOS 26.0; project-level macOS build settings may be newer for local Xcode tooling.
- Do not vendor package source into this repository unless explicitly requested.

## Repository Hygiene

- Do not commit generated Xcode build output, local package build products, scratch audio fixtures, or personal IDE state.
- Keep `DerivedData/`, `.DerivedData/`, `.deriveddata*/`, `.build/`, `.tmp/`, `*.xcresult`, `*.xcuserstate`, `xcuserdata/`, archives, debug symbols, and app bundles out of source control.
- If a generated file was already tracked, remove it with `git rm --cached` and keep the local copy ignored.
- Do not rewrite published Git history casually. If large generated artifacts have already reached GitHub, document the need for a coordinated history rewrite and force push rather than treating it as a normal cleanup commit.

## Change Hygiene

- Keep changes narrowly scoped to the requested feature or fix.
- Do not rewrite unrelated UI or metadata pipeline code while touching nearby files.
- Do not revert user changes in a dirty worktree.
- When adding files, make sure they are included in the Xcode project target.
- Update `README.md`, `ACKNOWLEDGEMENTS_AND_PRIVACY.md`, or `THIRD_PARTY_NOTICES.md` when behavior, privacy disclosures, or third-party usage changes.
