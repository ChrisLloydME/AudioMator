# AudioMator Agent Guide

## Project

AudioMator is a native, sandboxed macOS audio metadata editor. It uses `AudioMator.xcodeproj` and the `AudioMator` scheme. Container metadata I/O is delegated to the external `TagLibAudioMetadata` Swift package through `AudioMetadataPipeline`.

Use the documentation set under `Docs/` as the detailed reference:

- [Documentation index](Docs/README.md)
- [Architecture](Docs/Architecture/OVERVIEW.md)
- [Metadata pipeline](Docs/Architecture/METADATA_PIPELINE.md)
- [State and mutation model](Docs/Architecture/STATE_AND_MUTATION_MODEL.md)
- [Build](Docs/Development/BUILD.md)
- [Testing](Docs/Development/TESTING.md)
- [Security and data integrity](Docs/Security/SECURITY_AND_DATA_INTEGRITY.md)

## Source of Truth

Existing documentation, comments, tests, and commit messages may be stale. Verify behavior against the current implementation, build settings, public interfaces, and reproducible commands. Do not change functional code merely to satisfy old documentation. When documentation contradicts behavior, investigate and document the real behavior.

## Repository Layout

- `AudioMator/App/` — entry point, commands, notifications, delegates.
- `AudioMator/Core/` — shared Foundation/system support, format support, paths, localization, network disclosure, platform adapters.
- `AudioMator/Domain/` — models, metadata contract, conflict policy, mutation coordinator, exchange/rename/renumber rules.
- `AudioMator/Features/` — native UI, feature view models, provider stores.
- `AudioMator/Infrastructure/` — TagLib adapter, file-system/bookmark services, provider clients, update services.
- `AudioMatorTests/` — app-hosted XCTest bundle and fixtures.
- `Tests/AudioMatorCoreLogicTests/` — SwiftPM Foundation-only fast tests.
- `Config/` — `Info.plist` and entitlements; keep outside the synchronized `AudioMator/` source root.
- `Docs/` — engineering documentation.
- `scripts/` — build, validation, bridge smoke helpers.

## Architecture Rules

- Keep domain logic in `Domain`, integrations in `Infrastructure`, and native UI and feature view models under the closest `Features/*`.
- `AudioMator/` is an Xcode file-system synchronized root. New source files under it are included automatically; configuration inputs stay in `Config/`.
- Do not write container metadata or move files directly from UI code. Preserve the existing metadata pipeline.
- All disk mutations must use `FileMutationCoordinator`.
- Respect the documented Domain exception: it reuses `MetadataFieldKey`, `MetadataFileVersion`, `MetadataSnapshot`, and `RawMetadataPatch` from the package. It must not call `TagLibMetadataManager` or own file transactions.
- Keep `AudioViewModel` as the single selection owner.
- Avoid new singletons and broad shared abstractions for a single feature.
- The app is macOS-only. Do not reintroduce iOS/iPadOS deployment code.

## Metadata Rules

- Track Number, Total Tracks, Disc Number, and Total Discs are first-class structured fields. Preserve numeric values and text intent where supported.
- A changed text representation after a write is not necessarily a failure if the numeric values round-trip. Report container normalization instead.
- Semantic writes must preflight the exact requested fields against format capability. The raw editor is the low-level exception.
- Conflict policies must never clear the expected version, retry a failed commit, or substitute a file that merely looks similar.
- Erase-all remains best effort. Do not claim it removes every container-native structure.

## Swift and UI Style

- 4-space indentation; prefer `guard` and early returns.
- Value types unless identity, observation, or lifecycle requires a class.
- Use Swift concurrency where it fits the surrounding code.
- The app target uses Swift 5 language mode with complete strict concurrency and MainActor default isolation. Do not suppress isolation warnings.
- Keep state ownership in view models or domain state, not hidden in views.
- Use `String(localized:)` for user-facing strings.
- Do not add `print`, `debugPrint`, or `NSLog` in app code.
- SwiftUI is common, but no framework is mandated. Choose the native approach that best fits performance and maintainability.

## Build and Test

Use the stable Xcode 27 toolchain at `/Applications/Xcode.app`. Do not add beta toolchain logic.

```bash
swift test --filter AudioMatorCoreLogicTests
bash scripts/codex-build.sh
bash scripts/codex-build.sh --force
```

App-hosted tests must be serial:

```bash
xcodebuild \
  -project AudioMator.xcodeproj \
  -scheme AudioMator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

- Use `.deriveddata-codex` for all Xcode builds. Do not create alternate derived data roots.
- Use `swift test` for fast feedback; the SwiftPM target compiles a selected Foundation-only subset and is not the app module.
- Run the app-hosted suite only when the change requires it. It launches the test host; do not treat that as permission to interact with the UI.
- Read [Testing](Docs/Development/TESTING.md) before claiming coverage. Known gaps include no AIFF/Opus fixtures, artwork writes only for MP3/M4A/FLAC, no live network tests, and no UI automation.

## Verification Boundary

- Verify your own changes through code inspection, compilation, and the smallest relevant automated tests.
- Do not launch `AudioMator.app` manually or through shell, GUI automation, AppleScript, accessibility tooling, or screenshots. Do not open the built app for interactive smoke testing.
- UI acceptance remains the maintainer's responsibility unless the user explicitly requests a different procedure.
- If `xcodebuild` or `swift test` fails because the environment cannot write caches under the user Library, treat it as an environment issue and rerun with appropriate access before diagnosing project code.
- Report exactly what you ran and what passed. Do not claim tests you did not run.

## TagLibAudioMetadata Boundary

- Treat `TagLibAudioMetadata` as an independently maintained external dependency, even if a local checkout exists elsewhere on the machine.
- Do not enter, edit, patch, build from, or commit in any local `TagLibAudioMetadata` checkout, SwiftPM cache, or resolved package source unless the user explicitly grants access for the current task.
- Do not work around the boundary by modifying checkouts, caches, symlinks, or copies outside this repository.
- If a package defect is suspected, stop and report:
  - the affected API or source area,
  - observed versus expected behavior,
  - a minimal AudioMator reproduction,
  - the test or fix the package owner should add.
- Keep any AudioMator-side mitigation narrow and labeled as a workaround.
- Do not run `scripts/build-taglib-bridge-smoke.sh` as an Agent: it compiles from the package checkout. Maintainers may run it manually.

## Dependency Notes

- `TagLibAudioMetadata` is pinned to exact version `0.5.3` (revision `03473c9ae199026b806a5f75c387ca036e325284`).
- App deployment target: macOS 15.0.
- Do not vendor package or TagLib source.
- Do not add network features that are not user initiated. Update `NetworkServiceDisclosure` and the privacy/third-party docs when network behavior changes.

## Repository and Change Hygiene

- The writable scope is this repository. Do not modify files, repositories, tools, or user data outside it without explicit authorization.
- Keep changes narrowly scoped. Do not revert user changes in a dirty worktree.
- Do not commit build output, derived data, `.tmp`, test results, app bundles, archives, or personal IDE state.
- If a generated file is tracked, remove it with `git rm --cached` and keep the local copy ignored.
- Update the matching documentation for any behavior, build, test, privacy, dependency, or release change. See [Documentation Maintenance](Docs/Development/DOCUMENTATION.md).
- Prefer meaningful incremental commits with imperative messages.

## Documentation Updates

A behavior change is incomplete without documentation. Use the [update matrix](Docs/Development/DOCUMENTATION.md#update-matrix). Do not add current guidance under `Docs/Engineering/HISTORY`; those files are dated records and are not authoritative for current behavior.
