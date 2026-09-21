# Development Guide

## General Principles

Keep changes close to the owning feature or layer. Domain logic belongs in `AudioMator/Domain/`, service integrations belong in `AudioMator/Infrastructure/`, and SwiftUI views or feature-owned view models belong under the nearest `AudioMator/Features/*` folder.

Do not introduce broad shared abstractions for a single feature. The project prefers small feature-owned helpers until more than one feature actually needs shared behavior.

## UI Technology

AudioMator is SwiftUI-first, not SwiftUI-only. Use AppKit when it produces a more complete native result, reduces implementation complexity, or improves performance for a specific feature.

## Metadata Writes

Do not write container-specific metadata directly from UI code. Existing write paths are centered around the metadata pipeline, `AudioViewModel` write extensions, and Domain helpers. Start with:

- `AudioMator/Domain/MetadataEditing/`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWrite.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataWriteSupport.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+MetadataPlanWrite.swift`
- `AudioMator/Features/Main/ViewModels/AudioViewModel+ProviderTaggingWrite.swift`

Track and disc fields must remain structured first-class values, not a single loose string.

## Network Features

Network features must be user initiated. Current network boundaries include MusicBrainz, iTunes Search API, LRCLIB, GitHub release notes, and manual update checks.

When adding or modifying network behavior, check:

- Does `NetworkServiceDisclosure` need an update?
- Do `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md` or `README.md` need updates?
- Does `Docs/THIRD_PARTY_NOTICES.md` need a new service or license note?
- Can deterministic helpers be tested for request construction, query normalization, candidate ranking, or error presentation?

## Swift Style

Project conventions:

- 4-space indentation.
- Prefer `guard` and early returns to reduce nesting.
- Use value types unless identity, observation, or platform lifecycle requires a class.
- Use Swift concurrency where it fits surrounding code.
- The Xcode app and app-hosted tests use Swift 5 language mode with complete
  strict-concurrency checking and MainActor default isolation. Treat warnings
  marked as Swift 6 errors as migration work to fix, not diagnostics to suppress.
- Keep UI state ownership in feature view models or domain state.
- Avoid new singletons for feature work.
- Use `String(localized:)` for user-facing strings.
- Do not add diagnostic `print`, `debugPrint`, or `NSLog` calls in app code.

## Adding Files

`AudioMator/` is the Xcode file-system synchronized source root. Add app source files under the appropriate feature or layer folder. Keep target configuration inputs such as `Config/Info.plist` and entitlements outside the synchronized source root.

## Common Verification

Fast logic tests:

```bash
swift test --filter AudioMatorCoreLogicTests
```

Codex/macOS generic build:

```bash
bash scripts/codex-build.sh
```

Forced full validation build:

```bash
bash scripts/codex-build.sh --force
```

Manual Xcode build:

```bash
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
```
