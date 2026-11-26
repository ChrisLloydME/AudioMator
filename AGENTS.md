# AudioMator Agent Guide

## Project

AudioMator is a native, sandboxed macOS audio metadata editor. It uses `AudioMator.xcodeproj` and the `AudioMator` scheme. Container metadata I/O is delegated to the external `TagLibAudioMetadata` Swift package through `AudioMetadataPipeline`.

Use the documentation set under `Docs/` as the detailed reference:

- [Documentation index](Docs/README.md) — start here.
- [Product overview](Docs/Product/OVERVIEW.md) and [User guide](Docs/Product/USER_GUIDE.md) — scope and current workflows.
- [Architecture](Docs/Architecture/OVERVIEW.md), [Metadata pipeline](Docs/Architecture/METADATA_PIPELINE.md), [State and mutation model](Docs/Architecture/STATE_AND_MUTATION_MODEL.md).
- [Metadata mapping specification](Docs/Architecture/METADATA_MAPPING_SPEC.md) — shared contract `AM-TLAM-MAPPING-2.2`, implemented by published package 0.8.3.
- [Build](Docs/Development/BUILD.md), [Testing](Docs/Development/TESTING.md), [Commit messages](Docs/Development/COMMIT_MESSAGES.md), [Documentation maintenance](Docs/Development/DOCUMENTATION.md).
- [Security and data integrity](Docs/Security/SECURITY_AND_DATA_INTEGRITY.md).

Dated evidence lives under `Docs/Engineering/` and superseded records under `Docs/Engineering/HISTORY/`. Those records are not current contracts; never copy a claim out of them without re-verifying it against the implementation.

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
- `Docs/` — current documentation under `Product`, `Architecture`, `Development`, `Reference`, and `Security`; dated evidence under `Engineering` and `Engineering/HISTORY`.
- `scripts/` — build, validation, bridge smoke helpers.

## Architecture Rules

- Keep domain logic in `Domain`, integrations in `Infrastructure`, and native UI and feature view models under the closest `Features/*`.
- `AudioMator/` is an Xcode file-system synchronized root. New source files under it are included automatically; configuration inputs stay in `Config/`.
- Do not write container metadata or move files directly from UI code. Preserve the existing metadata pipeline.
- All disk mutations must use `FileMutationCoordinator`.
- Respect the documented Domain exception: it reuses `MetadataFieldKey`, `MetadataFileVersion`, `MetadataSnapshot`, `MetadataAudioContentIdentity`, `MetadataAudioContentError`, and `RawMetadataPatch` from the package. It must not call `TagLibMetadataManager` or own file transactions.
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

- `TagLibAudioMetadata` is pinned to published exact version `0.8.3`, revision `ebd21c7b1aa9be607133fc4a9de02d2c7890f42f`; [release source](https://github.com/ChrisLloydME/TagLibAudioMetadata/tree/0.8.3) is resolved through the normal Xcode project and committed `Package.resolved`. The TagLib binary remains the checksum-pinned 2.3.1 revision 2 asset.
- The ignored `.tmp/MappingIntegration.xcworkspace` is generated only for an explicitly requested local candidate via `scripts/validate-release.sh --local-package`; it is not part of normal resolution.
- App deployment target: macOS 15.0.
- Do not vendor package or TagLib source.
- Keep `AudioMator/Resources/Licenses`, `Core/Legal/LicenseDisclosure.swift`, the in-app Acknowledgements sheet, and the legal docs in sync when dependency versions or licenses change.
- Do not add network features that are not user initiated. Update `NetworkServiceDisclosure` and the privacy/third-party docs when network behavior changes.

## Repository and Change Hygiene

- The writable scope is this repository. Do not modify files, repositories, tools, or user data outside it without explicit authorization.
- Keep changes narrowly scoped. Do not revert user changes in a dirty worktree.
- Do not commit build output, derived data, `.tmp`, test results, app bundles, archives, or personal IDE state.
- If a generated file is tracked, remove it with `git rm --cached` and keep the local copy ignored.
- Update the matching documentation for any behavior, build, test, privacy, dependency, or release change. See [Documentation Maintenance](Docs/Development/DOCUMENTATION.md).
- Prefer meaningful incremental commits and follow the [commit message contract](Docs/Development/COMMIT_MESSAGES.md).

## Commit Messages

Every commit follows the [commit message contract](Docs/Development/COMMIT_MESSAGES.md). These rules must hold even if that page is not open:

- Subject: `type(scope): imperative summary`, using `feat`, `fix`, `docs`, `test`, `perf`, `build`, `ci`, `chore`, `refactor`, `style`, `revert`, or `merge`.
- Start the summary with a lowercase verb, keep the whole subject to 72 characters or fewer, and do not end it with a period.
- Use the optional lowercase kebab-case scope only when the change is confined to an established area; do not invent scopes.
- Merge commits use `merge: integrate <branch> (PR #N)` or `merge: integrate <source> into <target>`; do not keep GitHub's `Merge pull request #N from …` subject.
- Reverts use `revert: <imperative summary>` and explain the reason in the body.
- Keep one logical change per commit. Add a body only when it explains why, a boundary, or a non-obvious verification step.
- Reword local commits before publishing; do not rewrite commits already on `origin/main` without the maintainer's explicit approval.
- Check before publishing: `python3 scripts/check-commit-messages.py --range origin/main..HEAD`.

## Documentation Maintenance

Documentation is part of every change, not a follow-up task. A behavior, build, test, privacy, dependency, or release change is incomplete until the affected documentation is updated in the same changeset. This applies to implementation, refactoring, bug fixing, and feature development.

Read [Documentation Maintenance](Docs/Development/DOCUMENTATION.md) for the document ownership map, update matrix, examples, uncertainty labels, and verification steps. These mandatory steps apply even if that page is not open:

1. **Identify affected documentation before editing.** Use the ownership map and update matrix; include the canonical owner and every page that links to it.
2. **Verify every claim against the resulting implementation.** Check source, build settings, public interfaces, configuration, tests, and reproducible commands. Treat existing docs, comments, tests, and commit messages as unverified evidence. Never change functional code merely to satisfy old documentation.
3. **Update canonical pages and affected cross-references in the same changeset.** Cover, as applicable: user-facing behavior and workflows; architecture, protocols, and public types; build, test, and CI procedures; dependencies and licenses; privacy, security, and network behavior; and release, version, signing, and distribution steps.
4. **Remove superseded claims.** Delete invalidated descriptions, abandoned plans, obsolete workflows, and duplicated detail instead of layering new text on top. Link to the canonical page rather than copying it.
5. **Separate verified behavior from uncertainty.** Label known limitations, proposals, and unverified behavior explicitly; do not present intentions as features.
6. **Check documentation consistency before declaring work complete.** Run `python3 scripts/check-doc-links.py`, review changed paths, commands, terminology, and cross-references, and state which documents were updated. If a change has no documentation impact, state the brief reason in the handoff.

- **Prefer maintaining existing canonical documents.** Create a new document only when no existing document owns the topic, and register it in `Docs/README.md` and the ownership table with a clear scope.
- **Respect the evidence/authority split.** Current guidance lives in `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `AGENTS.md`, and `Docs/{Product,Architecture,Development,Reference,Security}`. `Docs/Engineering/` is dated evidence. `Docs/Engineering/HISTORY/` is a superseded archive: never add current guidance there, never rewrite dated results, and never present its claims as current.
