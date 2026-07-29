# AudioMator Agent Guide

## Project Overview

AudioMator is a native audio metadata editor for macOS and iPadOS. It uses the `AudioMator.xcodeproj` Xcode project and the `AudioMator` scheme.

The app is built around a TagLib-powered metadata pipeline from the `TagLibAudioMetadata` Swift package. It supports inspecting and editing audio tags, artwork, filename/metadata conversion, track renumbering, MusicBrainz-assisted tagging, watched folders on macOS, and a session-scoped iPad workflow.

Use native Apple platform technologies. The project has no preferred native UI framework; choose the implementation that delivers the best performance, platform behavior, and code simplicity for the feature.

## Repository Layout

- `AudioMator/App/`: app entry point, commands, notifications, and platform delegates.
- `AudioMator/Core/`: shared platform, network disclosure, and audio-format support.
- `AudioMator/Domain/`: metadata models, audio-file models, metadata editing, metadata exchange, rename templates, file sources, track renumbering, and UI state.
- `AudioMator/Features/`: native UI feature areas for the main window, iPad workspace, shared online metadata entry point, provider-specific metadata/lyrics browsers, metadata editor, filename tools, metadata inspector, settings, and welcome flow.
- `AudioMator/Infrastructure/`: file-system, MusicBrainz, iTunes, LRCLIB, shared online metadata, GitHub release-note, and update-check services.
- `Config/`: project configuration files that should not be compiled or copied from the synchronized app source root.
- `Docs/`: maintainer docs, README images, wiki pages, privacy acknowledgements, and third-party notices.
- `Tests/`: SwiftPM fast core-logic tests and coverage notes.
- `AudioMatorTests/`: app-hosted Xcode tests and fixtures.
- `scripts/`: build and smoke-test helpers.

The app source is attached to the target through Xcode's file-system synchronized `AudioMator/` root. Keep feature and infrastructure boundaries clear on disk; Xcode will mirror those folders automatically. Keep target configuration inputs such as `Config/Info.plist` outside that synchronized source root so Xcode processes them as build settings inputs instead of bundle resources.

## Platform Model

- macOS is the full desktop workflow: watched folders, three-pane main window, file paths, Finder-style reveal/open actions, and secondary tool windows.
- iPadOS is session-only: no watched folders, no desktop folder persistence, content + inspector layout, security-scoped imports, and sheet-based tools.

- iPadOS development is currently in maintenance mode. Keep the iPadOS target compiling successfully, but do not implement new iPad-specific features, UI, or platform optimizations unless the user explicitly requests them. New functionality may remain macOS-only until iPadOS development resumes.

- Gate platform-specific code with existing compatibility patterns in `AudioMator/Core/Platform/PlatformCompatibility.swift`.

## Architecture Rules

- Keep domain logic in `AudioMator/Domain/` and service integrations in `AudioMator/Infrastructure/`.
- Keep native UI code and feature-specific view models under the closest `AudioMator/Features/*` folder.
- Keep the shared online metadata window shell and source selection under `AudioMator/Features/OnlineMetadataBrowser/`; provider-specific browser flows stay under `Features/MusicBrainzBrowser/`, `Features/iTunesBrowser/`, and `Features/LRCLIBLyricsBrowser/`.
- Keep iTunes Store API clients and iTunes artwork lookup services together under `AudioMator/Infrastructure/iTunes/`.
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

## Swift And Native UI Style

- Indentation: 4 spaces.
- Prefer `guard` and early returns to reduce nesting.
- Use value types unless identity, observation, or platform lifecycle requires a class.
- Use Swift concurrency where it fits the surrounding code.
- Do not default to the UI framework already used nearby when another native approach would clearly improve performance or substantially simplify the implementation. Replacing an existing UI implementation is acceptable when it is the most direct, maintainable solution and remains within the requested scope.
- Keep UI state ownership in feature view models or domain state, not hidden inside views.
- Avoid introducing singletons for feature work.
- Use `String(localized:)` for user-facing strings.
- Do not add diagnostic `print`, `debugPrint`, or `NSLog` calls in app code.

## Build And Verification

Agents are responsible for verifying that their own changes are technically sound through code inspection, compilation, and the smallest relevant automated tests. UI acceptance remains the maintainer's responsibility.

- Do not launch `AudioMator.app` manually or through shell commands, GUI automation, AppleScript, accessibility tooling, or similar mechanisms to inspect the running UI.
- Do not take screenshots of AudioMator or use command-driven screenshots, image comparison, or visual inspection as proof that UI work is complete.
- Do not open the built app for interactive smoke testing. A successful build and relevant non-interactive tests are the expected Agent verification boundary unless the user explicitly requests a different validation procedure.
- App-hosted automated tests may launch the test host as part of `xcodebuild`; this is test execution, not permission to interact with, automate, or screenshot the app. Run these tests only when the change requires their coverage.

Xcode Configuration:

Development should use the installed Xcode Beta toolchain by default.

- Stable Xcode (App Store): `/Applications/Xcode.app`
- Xcode Beta: `/Applications/Xcode-beta.app`
- Use `Xcode-beta.app` and its corresponding SDKs for all project development, builds, testing, and validation unless the user explicitly requests otherwise.
- If the active developer directory needs to be selected or switched, use the Xcode Beta installation (for example, via `xcode-select`) before invoking Xcode command-line tools.

Useful commands:

```bash
swift test --filter AudioMatorCoreLogicTests
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'platform=macOS' -derivedDataPath .deriveddata-codex -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
```

Use `swift test --filter AudioMatorCoreLogicTests` for the fastest local regression sensors around pure domain logic. This SwiftPM target intentionally includes only selected non-UI source files and should stay free of platform UI frameworks, TagLib, and network-dependent tests. See `Tests/FAST_TEST_GAPS.md` before broad refactors so known app-hosted coverage gaps are not mistaken for covered behavior.

Prefer `bash scripts/codex-build.sh` for Codex validation. The script uses a two-stage strategy:

- It skips `xcodebuild` entirely when the current working tree has no build-relevant changes.
- When build-relevant files did change, it reuses the repository-local `.deriveddata-codex` directory so `xcodebuild build` can behave incrementally like Xcode instead of forcing a clean build.

Use `bash scripts/codex-build.sh --force` when you want to run a full validation build regardless of the changed-file filter. All Agent-triggered Xcode builds should write derived data to the repository-local `.deriveddata-codex` directory. Do not create alternate local build roots such as `.DerivedData`, `.deriveddata-codex-ios`, `.deriveddata-ios-codex`, or `.deriveddata-macos-codex`; reuse `.deriveddata-codex` and let the existing `.gitignore` keep it out of source control.

The macOS `AudioMatorTests` target is app-hosted, so every parallel Xcode test runner launches another `AudioMator.app` instance in the Dock. Keep the scheme test target non-parallel and run all Agent-triggered app-hosted Xcode tests with `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`. Do not override this with parallel-testing flags. This serializes runner processes without skipping tests or reducing coverage; prefer the SwiftPM core-logic tests for fast feedback and reserve the full app-hosted suite for changes that require it.

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

### TagLibAudioMetadata Ownership Boundary

- Treat `TagLibAudioMetadata` as an independently maintained external dependency, including when a local checkout happens to exist elsewhere on the same computer.
- Do not enter, edit, patch, format, build from, commit in, or otherwise mutate any local `TagLibAudioMetadata` repository or package checkout while working as an AudioMator Agent unless the user explicitly grants access to that repository for the current task.
- Do not work around this boundary by modifying SwiftPM checkouts, caches, resolved package sources, symlinks, or other copies outside this repository.
- If investigation indicates a defect in `TagLibAudioMetadata`, stop the dependency-side work and report it to the user. Identify the affected API or source area, the observed and expected behavior, the evidence or minimal reproduction from AudioMator, and the change or tests that the Agent working in the `TagLibAudioMetadata` repository should implement.
- Keep any AudioMator-side mitigation narrowly scoped and clearly label it as a workaround; do not silently compensate for an unreported package defect.

## Repository Hygiene

- The writable scope for AudioMator Agents is this repository only. Do not modify files, repositories, package sources, tools, configuration, or user data outside the AudioMator project unless the user explicitly authorizes the specific external location and work.
- Do not commit generated Xcode build output, local package build products, scratch audio fixtures, or personal IDE state.
- Keep `DerivedData/`, `.DerivedData/`, `.deriveddata*/`, `.build/`, `.tmp/`, `*.xcresult`, `*.xcuserstate`, `xcuserdata/`, archives, debug symbols, and app bundles out of source control.
- If a generated file was already tracked, remove it with `git rm --cached` and keep the local copy ignored.
- Do not rewrite published Git history casually. If large generated artifacts have already reached GitHub, document the need for a coordinated history rewrite and force push rather than treating it as a normal cleanup commit.

## Change Hygiene

- Keep changes narrowly scoped to the requested feature or fix.
- Do not rewrite unrelated UI or metadata pipeline code while touching nearby files.
- Do not revert user changes in a dirty worktree.
- When adding files, make sure they are included in the Xcode project target.
- Update `README.md`, `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`, or `Docs/THIRD_PARTY_NOTICES.md` when behavior, privacy disclosures, or third-party usage changes.
