# Metadata Architecture Maintenance Progress

Last updated: 2026-09-16

## Scope

This journal tracks AudioMator-side work for the coordinated metadata correctness and architecture review. TagLibAudioMetadata remains an independent product and has its own journal in that repository.

## Current findings

- **Current dependency state:** `AudioMator.xcodeproj` uses the local package reference `../TagLibAudioMetadata`; `Package.resolved` contains no TagLibAudioMetadata pin. This was intentionally changed in `b78c1be` for coordinated maintenance. Before that change, the release configuration used remote TagLibAudioMetadata 0.4.5.
- One inspector Save now constructs one package `MetadataPatch` containing ordinary fields, formatted track/disc intent, artwork, and all four advisory states. AudioMator no longer performs follow-up advisory, alias, or MP4 cleanup transactions.
- Editable metadata is loaded from one `MetadataSnapshot`; its `MetadataFileVersion` remains attached to the `AudioFile` edit snapshot and is supplied at every inspector, raw editor, erase, lyrics, and track-renumber transaction boundary.
- The raw editor's canonical model is `[String: [String]]`. Newlines are only the UI representation for ordered values; duplicates, empty values, whitespace, and literal semicolons are not normalized.
- TagLibAudioMetadata is authoritative for editable semantic tags. AVFoundation remains for technical and display-only enrichment rather than overriding publisher, copyright, artwork, or advisory values.
- Second-pass finding confirmed: the Inspector dirty check was field-by-field, but `MetadataEditPayload` discarded the baseline and the TagLib adapter emitted a full scalar snapshot. This could rewrite untouched multi-value fields through their scalar UI projection.
- Year/release-date diagnosis confirmed. The former adapter collapsed both controls into `.releaseDate`, ignored a Year edit whenever Release Date was nonempty, and converted an explicit Release Date removal back into Year.

## Confirmed hypotheses

- Investigation target 1: confirmed at source level; the current save path has multiple mutation stages.
- Investigation target 2: confirmed at source level; the main compatibility write receives a Boolean advisory projection before the typed state is repaired later.
- Dependency coordination: the historical 0.4.5 remote pin was confirmed, but the earlier journal conclusion that it remained current was false. The active project uses the sibling checkout; release mode must be restored only after the new package API is published.
- Raw editor lossiness: confirmed. The previous `[String: String]` join/trim/split path could not distinguish one semicolon-bearing value from multiple values and rewrote the whole map.
- Stale edit race: confirmed. The app fingerprint check occurred before the package established its transaction baseline; retaining and passing `MetadataFileVersion` closes that window.
- Timeout diagnosis: confirmed. Swift Task cancellation could not stop the synchronous TagLib mutation, so a reported timeout could later commit. The write now waits for its real outcome; only post-commit reload is bounded.
- Competing editable authorities: confirmed for several fields and fixed by using the package snapshot as the editable-tag authority.
- App-side container compatibility: confirmed and removed from the save path. Runtime format discovery through `AudioFormatSupport` remains intentional capability discovery, not container mutation logic.
- Large `AudioViewModel`: reviewed but not mechanically split. Mutation orchestration already has a feature-level executor/coordinator boundary; a broad service extraction was not necessary for the correctness fixes and would expand risk.

## Pending verification

- Publish TagLibAudioMetadata 0.6.0 (or select an explicit release revision), then resolve AudioMator's remote SwiftPM dependency and commit the regenerated pin. Until publication, local integrated tests use the sibling checkout.
- Xcode Beta is not installed. All available validation used stable Xcode 27 / Swift 6.4; rerun the documented build/test gates with the beta toolchain when available.
- Swift 6 language-mode migration remains separate work. The app still declares Swift 5 and the current compiler reports actor-isolation warnings in lock-protected test doubles. Do not flip the language mode until those boundaries are deliberately repaired.
- Raw-editor newline boundary ambiguity remains explicitly deferred: a newline inside one raw value and the UI separator between values are not yet distinguishable.

## Architectural direction

- AudioMator should construct semantic edits and delegate container representation plus atomic commit to TagLibAudioMetadata.
- Do not introduce new container-specific behavior in AudioMator while migrating.
- Preserve user-file compatibility and explicitly distinguish package defects from application workarounds.
- Keep the UI's own file fingerprint for file-management diagnostics, but use the package version token as the metadata transaction concurrency authority.
- Treat multi-file operations as per-file transactions: each file is atomic, while a batch may still report partial success across files.
- Year maps to the package's recording-date semantic field; Release Date maps only to release date. ID3/Xiph-style formats can store both independently. MP4 exposes `©day` as release date and rejects an independent Year edit instead of silently overwriting `©day`.

## Completed tasks

- Established clean `main` baseline and current dependency resolution.
- Created this durable journal before substantive refactoring.
- Replaced the compatibility-object plus follow-up writes with one semantic package patch per Save, including four-state advisory and artwork.
- Removed application-side MP4 atom cleanup, alias cleanup, advisory encoding, and extension-family mutation branches.
- Made raw metadata editing exact-value-array based and delta committed; LRCLIB now changes only `LYRICS` through `RawMetadataPatch`.
- Retained snapshot version tokens through inspector and raw editor lifecycles; erase and track-renumber paths also pass expected versions.
- Removed mutation timeout from non-cancellable writes. Reload timeout is reported as persisted success with a refresh warning and releases the path reservation.
- Updated user and architecture documentation to describe the PropertyMap editing boundary, package-owned container behavior, and amended timeout semantics.
- Changed every `persistMetadataEdit` path to construct a baseline-aware intent delta. Only changed semantic fields enter `MetadataPatch`; unchanged advisory, formatted numbers, and artwork are absent. Empty deltas are handled by the package's existing no-op fast path.
- Added an app-hosted regression that writes multi-value Artist/Genre plus duplicate, whitespace-sensitive, and semicolon-bearing custom values, changes only Title, and compares exact raw arrays before and after.
- Removed the `effectiveReleaseDate` fallback. Baseline-aware payloads now emit `.date` only for Year changes and `.releaseDate` only for Release Date changes/removal.
- Added application integration tests for independent FLAC Year/Release Date edit and removal behavior, plus explicit rejection and byte preservation for an unsupported MP4 Year edit.
- Hardened `AudioMetadataPipeline` so conformers must implement exact raw-value reads, delta patches, and version-aware mutation entry points. Legacy scalar and unversioned conveniences are now one-way adapters built on those strong primitives rather than lossy fallback requirements.
- Added a protocol contract regression proving that whole-map convenience writes preserve exact arrays, compute removals as a delta, and forward the caller's `MetadataFileVersion`.
- Normalized the Xcode local-package reference representation and documented the exact current sibling-checkout mode versus the future remote release mode. The remote switch remains blocked on publishing the coordinated package version.
- Re-evaluated Swift 6 and large-module work after the correctness changes. Swift 6 remains a deliberate follow-up because enabling it now exposes actor-isolation work in test doubles and shared-state boundaries; suppressing those diagnostics would not be a sound migration. `AudioViewModel` already delegates mutation execution/coordinating and metadata adaptation, so no additional size-only split was justified in this pass.

## Tests and validation

- Passed: `TagLibReadWriteIntegrationTests` using the sibling package after resolving semantic number-pair verification (all tests in the class, 0 failures).
- Passed package gate: sibling `swift test` (119 tests, 2 opt-in tests skipped, 0 failures).
- Passed: forced generic macOS build through `bash scripts/codex-build.sh --force`.
- Passed: generic iOS build with `CODE_SIGNING_ALLOWED=NO`; no simulator was launched.
- Passed: `swift test --filter AudioMatorCoreLogicTests` (49 tests, 0 failures).
- Passed: full serial macOS app-hosted suite (335 tests, 0 skips, 0 failures). The result bundle reported one pre-existing SwiftUI test-harness runtime warning about reading `State` outside an installed view.
- Environment note: `/Applications/Xcode-beta.app` is absent; `/Applications/Xcode.app` reports Xcode 27.0 (27A266a).
- Passed after intent-delta change: incremental generic macOS build and focused `TagLibReadWriteIntegrationTests` for patch shape and exact untouched-value preservation.
- Passed after date integration: full serial `TagLibReadWriteIntegrationTests`, including FLAC independent-date behavior and MP4 unsupported Year behavior.
- Passed after protocol hardening: test-target compilation plus `AudioMetadataPipelineContractTests` (0 failures).
- Final package gate: sibling `swift test` passed 122 tests with 2 opt-in skips and 0 failures.
- Final app fast gate: `swift test --filter AudioMatorCoreLogicTests` passed 49 tests with 0 failures.
- Final app-hosted gate: the complete serial macOS suite passed 339 tests with 0 skips and 0 failures. The result retains one known SwiftUI test-harness runtime warning about reading `State` outside an installed view.
- Final build gates: forced generic macOS build and generic iOS build both passed with code signing disabled where applicable; no simulator was launched.
- The first full-suite run exposed one migrated LRCLIB test backend that recorded only a raw delta while its assertion inspected the resulting map. The backend now applies `RawMetadataPatch` to its baseline, its focused regression passes, and the subsequent full suite is green.

## Commits

- `643e8a6` — `docs: start metadata maintenance journal`
- `dba9098` — `refactor: route metadata saves through package patches`
- `d4cde34` — `fix: preserve exact raw metadata value arrays`
- `d953af4` — `fix: do not time out non-cancellable metadata writes`
- `8fac01b` — `fix: build inspector writes from intent deltas`
- `97035c0` — `fix: preserve independent year and release date edits`
- `89110d7` — `refactor: require precise metadata pipeline operations`
- `5ce0996` — `docs: clarify package integration modes`
- `6731089` — `test: apply raw patches in lyrics backend`
