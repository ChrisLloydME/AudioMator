# Contributing

Use these conventions when preparing changes for AudioMator.

## Keep Changes Scoped

Changes should be small and placed in the owning layer or feature. Do not rewrite unrelated UI, metadata pipeline code, project settings, or dependencies while fixing a specific issue.

If a change affects user-visible behavior, privacy disclosure, or third-party usage, update the relevant documentation:

- `README.md`
- `Docs/ACKNOWLEDGEMENTS_AND_PRIVACY.md`
- `Docs/THIRD_PARTY_NOTICES.md`
- The matching Wiki page under `Docs/wiki/`

## Source Boundaries

- Domain logic belongs in `AudioMator/Domain/`.
- Service integrations belong in `AudioMator/Infrastructure/`.
- SwiftUI views and feature-owned view models belong under the closest `AudioMator/Features/*` folder.
- Target configuration inputs belong under `Config/`, outside the synchronized app source root.
- Do not vendor `TagLibAudioMetadata` or TagLib source unless the maintainer explicitly requests it.

## Metadata and File Writes

Preserve the existing metadata write pipeline. Do not write container-specific metadata directly from UI code. For rename operations, metadata writes, raw property-map writes, or batch file actions, respect the file mutation coordination boundary.

## Platform Differences

macOS and iPadOS intentionally differ. macOS supports watched folders, Finder-style actions, and multiple windows. iPadOS uses session-only document workflows and sheet-based tools. Do not force behavior from one platform onto the other without a clear product and code reason.

## Testing Expectations

Run the smallest relevant check:

```bash
swift test --filter AudioMatorCoreLogicTests
```

If you changed app source, Xcode configuration, or UI-related code, run:

```bash
bash scripts/codex-build.sh
```

For a forced validation build:

```bash
bash scripts/codex-build.sh --force
```

If a change touches TagLib bridge behavior, track/disc writes, raw property maps, or format capabilities, consider running the bridge smoke tool on temporary audio files.

## Privacy and Network Changes

For any new or changed network request, answer:

- What user action starts the request?
- Which fields or identifiers are sent?
- Are audio file contents or embedded artwork ever sent?

Then update `NetworkServiceDisclosure`, privacy documentation, and relevant user-facing docs.

## Third-Party Licensing

AudioMator uses TagLib, TagLibAudioMetadata, Sparkle, and user-triggered services such as Apple iTunes Search API, MusicBrainz, LRCLIB, and GitHub Releases. Before distribution, review upstream license and service obligations as described in `Docs/THIRD_PARTY_NOTICES.md`.

Do not describe commercial or legal compliance as complete unless the project has the required review material.
