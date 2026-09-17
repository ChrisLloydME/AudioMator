# Metadata Architecture Maintenance Progress

Last updated: 2026-09-17

## Scope

This journal tracks AudioMator-side work for the coordinated metadata correctness and architecture review. TagLibAudioMetadata remains an independent product and has its own journal in that repository.

## Current findings

- **Platform state:** iPadOS was deprecated and removed in commit `fe10c62`. The app target now supports only `macosx`; iPad workspace/tool/welcome sources, iOS conditional branches, iPad assets, deployment settings, and plist keys were removed. Shared domain and service code was retained.
- **Current dependency state:** `AudioMator.xcodeproj` resolves the remote `TagLibAudioMetadata` package at exact version `0.5.1`. The former sibling-checkout reference was removed after the matching upstream release became available.
- One inspector Save now constructs one package `MetadataPatch` containing ordinary fields, formatted track/disc intent, artwork, and all four advisory states. AudioMator no longer performs follow-up advisory, alias, or MP4 cleanup transactions.
- Editable metadata is loaded from one `MetadataSnapshot`; its `MetadataFileVersion` remains attached to the `AudioFile` edit snapshot and is supplied at every inspector, raw editor, erase, lyrics, and track-renumber transaction boundary.
- The raw editor's canonical model is `[String: [String]]`. Newlines are only the UI representation for ordered values; duplicates, empty values, whitespace, and literal semicolons are not normalized.
- TagLibAudioMetadata is authoritative for editable semantic tags. AVFoundation remains for technical and display-only enrichment rather than overriding publisher, copyright, artwork, or advisory values.
- Second-pass finding confirmed: the Inspector dirty check was field-by-field, but `MetadataEditPayload` discarded the baseline and the TagLib adapter emitted a full scalar snapshot. This could rewrite untouched multi-value fields through their scalar UI projection.
- Year/release-date diagnosis confirmed. The former adapter collapsed both controls into `.releaseDate`, ignored a Year edit whenever Release Date was nonempty, and converted an explicit Release Date removal back into Year.

## Confirmed hypotheses

- Update comparison lead A is confirmed in the current implementation: `SemanticVersion(releaseTag:)` validates but discards the `B{build}` suffix, and `UpdateChecker` reads only `CFBundleShortVersionString`. The existing equality tests encode the incorrect behavior and must be replaced.
- MusicBrainz rate-limiter lead B is confirmed in the current implementation: the actor reads its last request time, suspends, and only then updates it, allowing reentrant callers to share a wait and release together.
- File-mutation fairness lead D is confirmed: a later reservation could acquire
  inactive keys even when those keys overlapped an older waiter blocked on a
  different active key, allowing the older broad reservation to starve.
- Bookmark persistence lead F is confirmed for both file-access grants and
  watched folders: top-level decode failure returned an ordinary empty array,
  and later saves could overwrite the only copy of unreadable persisted data.
- Privacy disclosure lead G is confirmed: LRCLIB endpoint/data constants existed
  and the documentation mentioned the service, but the Settings Privacy sheet
  manually assembled other services and omitted LRCLIB.
- Filesystem identity lead C is confirmed: rename collision checks and the fast
  import core lowercased every path, while mutation scheduling, security-scope
  caches, watched-folder scans, and selection checks used case-sensitive path
  strings. This produced different identities for the same entry depending on
  the workflow and was wrong for case-sensitive volumes.
- Mutation lifecycle lead E was partly confirmed and partly revised. A timed-out
  reload is detached but its result is resolved through a single-winner completion
  and therefore cannot update UI state later. The remaining real race was after a
  successful reload: two mutation tasks could reach MainActor model replacement
  out of completion order after their reservations had ended.
- Concurrency lead J is confirmed for `AudioFile`: the immutable snapshot stored
  an AppKit `NSImage`, was created on detached/background work, and used
  `@unchecked Sendable` to cross concurrency boundaries.
- Domain-coupling lead H is more nuanced than the audit described. Direct imports
  remain outside the TagLib adapter, but `MetadataFileVersion` is an intentionally
  opaque, hashable, sendable optimistic-concurrency token rather than a container
  implementation detail. Duplicating or type-erasing it would weaken compile-time
  safety without making the current single app target independently buildable.
  Raw patch and field-key ownership remain candidates if a real domain module is
  extracted; they should move with that module instead of gaining mirror types now.
- MusicBrainz maintainability/cache lead K is confirmed in part. The response
  cache retained every successful URL payload until process exit, despite search
  URLs having high cardinality. The client file also owned rate limiting, retry,
  and cache mechanics alongside transport, DTOs, mapping, and fallback logic.
- Investigation target 1: confirmed at source level; the current save path has multiple mutation stages.
- Investigation target 2: confirmed at source level; the main compatibility write receives a Boolean advisory projection before the typed state is repaired later.
- Dependency coordination: the historical 0.4.5 remote pin was superseded by the matching 0.5.1 upstream release, which is now the project dependency.
- Raw editor lossiness: confirmed. The previous `[String: String]` join/trim/split path could not distinguish one semicolon-bearing value from multiple values and rewrote the whole map.
- Stale edit race: confirmed. The app fingerprint check occurred before the package established its transaction baseline; retaining and passing `MetadataFileVersion` closes that window.
- Timeout diagnosis: confirmed. Swift Task cancellation could not stop the synchronous TagLib mutation, so a reported timeout could later commit. The write now waits for its real outcome; only post-commit reload is bounded.
- Competing editable authorities: confirmed for several fields and fixed by using the package snapshot as the editable-tag authority.
- App-side container compatibility: confirmed and removed from the save path. Runtime format discovery through `AudioFormatSupport` remains intentional capability discovery, not container mutation logic.
- Large `AudioViewModel`: reviewed but not mechanically split. Mutation orchestration already has a feature-level executor/coordinator boundary; a broad service extraction was not necessary for the correctness fixes and would expand risk.

## Pending verification

- The broader 2026-09-17 maintenance audit remains active. Entitlements and
  CI/module structure are not yet resolved. Swift 6 migration
  remains a separately tracked follow-up after test-double isolation is repaired.
- Completed: resolved AudioMator's remote SwiftPM dependency and regenerated the pin for `TagLibAudioMetadata` 0.5.1.
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

- Removed the discontinued iPadOS application and configuration as a standalone first commit; updated current product/build/privacy documentation and validated the macOS build plus 49 fast tests.
- Replaced marketing-only update comparison with `ReleaseVersion`, which parses both bundle version fields and compares marketing version before build number. Corrected the old equality regression and added same-marketing-version/newer-build coverage.
- Replaced the reentrant MusicBrainz timestamp check with atomic future-slot reservation. Concurrent callers now reserve distinct globally spaced turns before suspension; cancellation preserves an already-reserved slot so later reservations cannot be pulled forward.
- Added conflict-aware FIFO scheduling to `FileMutationCoordinator`: later work
  may bypass only when it conflicts with neither active reservations nor older
  blocked waiters. Cancelling a blocker immediately reschedules eligible work.
- Added explicit bookmark collection load states (`empty`, `loaded`, `corrupt`),
  quarantined the original corrupt blob, blocked ordinary overwrites (including
  save-before-load), surfaced recovery warnings in File Access settings, and
  rolled back newly added grants/folders when persistence is protected.
- Replaced the hand-built Privacy sheet list with a declarative production
  network-service registry. LRCLIB now appears automatically alongside iTunes,
  MusicBrainz, release notes, and update checks.
- Centralized path identity in `FileSystemPathSemantics`. Existing symlink and
  standardized aliases now converge, while case folding is selected from the
  containing volume and therefore also works for future rename destinations.
  Mutation reservations, quick-import deduplication, security-scope caches,
  watched-folder monitoring, rename collision planning, and descendant checks
  now share that rule.
- Defined the mutation lifecycle explicitly: queued operations are cancellable;
  after reservation acquisition, the synchronous commit's real outcome is always
  observed; reload has an independent deadline; late timed-out reload results are
  discarded. MainActor file-model refresh generations now reject an older reload
  handoff after a newer generation has already been applied, including delayed
  batch track-renumber refreshes.
- Replaced `AudioFile`'s stored `NSImage` and `@unchecked Sendable` conformance
  with immutable artwork `Data` and compiler-checked `Sendable`. AppKit image
  decoding is now a MainActor-only presentation projection.
- Bounded the MusicBrainz response cache to 128 entries and 16 MiB with LRU
  eviction, expired-entry pruning, and oversized-response bypass while retaining
  request coalescing. Moved rate limiting, retry policy, and response caching into
  `MusicBrainzRequestScheduling.swift`; DTO/mapping extraction was deferred because
  it would be a high-churn mechanical split without changing ownership or behavior.
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

- Passed focused `UpdateCheckerTests` after adding release build-number comparison.
- Added concurrency and cancellation coverage for `MusicBrainzRateLimiter`.
- Passed focused `FileMutationSerializationTests`, including an older A+B waiter,
  later B-only traffic, and independent C traffic proving fairness plus concurrency.
- Passed focused `FileAccessGrantStoreTests` and `DirectoryMonitoringPlanTests`
  covering corruption quarantine, save preflight, overwrite prevention, and
  user-visible view-model diagnostics.
- Passed focused `NetworkServiceDisclosureTests`, which require one complete
  registry entry per service and exact coverage of all production client hosts.
- Passed 51 fast core tests after adding real symlink/standardized-alias coverage
  and explicit case-sensitive versus case-insensitive path-key coverage.
- Passed the incremental generic macOS build after centralizing filesystem path
  semantics.
- Passed focused `FileMutationSerializationTests` after adding post-reservation
  cancellation/commit coverage and out-of-order reload-generation coverage.
- Passed the generic macOS build with compiler-checked `AudioFile: Sendable`
  after moving artwork image construction to the presentation layer.
- Passed focused `MusicBrainzResponseCacheTests` covering LRU count eviction,
  byte limits, oversized-response bypass, and concurrent request coalescing.
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

- `fe10c62` — `chore: remove deprecated iPadOS app`
- `643e8a6` — `docs: start metadata maintenance journal`
- `dba9098` — `refactor: route metadata saves through package patches`
- `d4cde34` — `fix: preserve exact raw metadata value arrays`
- `d953af4` — `fix: do not time out non-cancellable metadata writes`
- `8fac01b` — `fix: build inspector writes from intent deltas`
- `97035c0` — `fix: preserve independent year and release date edits`
- `89110d7` — `refactor: require precise metadata pipeline operations`
- `5ce0996` — `docs: clarify package integration modes`
- `6731089` — `test: apply raw patches in lyrics backend`
- `ae78991` — `fix: compare update release build numbers`
- `6697faa` — `fix: reserve MusicBrainz request slots atomically`
- `23ae6f9` — `fix: prevent file mutation waiter starvation`
- `dd95ff8` — `fix: preserve corrupt bookmark collections`
- `6839a0a` — `fix: derive privacy UI from network registry`
- `01636f3` — `fix: unify filesystem path identity`
- `1d75524` — `fix: reject stale mutation reloads`
- `340cbdf` — `refactor: make audio file snapshots sendable`
