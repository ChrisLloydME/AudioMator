# Metadata Architecture Maintenance Progress

Last updated: 2026-09-22

## 2026-09-22 second maintenance pass

### Current status

- Began from clean `main` at `5d58b68` and updated `AGENTS.md` first, as
  required. AudioMator is macOS-only and stable Xcode 27 is the normal
  development environment.
- Current reported CI failures are being revalidated against source. The Xcode
  job's first known failure is missing hosted-runner signing credentials; the
  fast SwiftPM job reaches a MusicBrainz rate-limiter spacing regression.
- Release-version integration remains explicitly deferred: AudioMator stays on
  released TagLibAudioMetadata 0.5.2 until release preparation.

### Immediate order

1. Make hosted Xcode tests explicitly unsigned and verify they reach the full
   application build and serial test suite.
2. Reproduce and correct actual MusicBrainz grant spacing without weakening the
   timing contract.
3. Validate the final Release artifact's macOS minimum version, then audit the
   remaining specialized metadata preflights and rename/reload fallback.

### Commits

- `0fbdea9` — update agent guidance for stable Xcode 27.

### Completed changes

- Made the hosted `xcode-test` invocation explicitly unsigned with command-line
  overrides for signing allowance, requirement, identity, and development team.
  Product signing settings remain unchanged for local and distribution builds.
- Replaced MusicBrainz's independent deadline sleepers with a single FIFO grant
  queue. Every slot is now delayed from the preceding actual grant, so scheduler
  stalls cannot produce a catch-up burst. Cancellation resumes promptly while a
  tombstone retains the reserved slot and prevents later callers moving forward.
- Added a Release-artifact compatibility audit to CI. It requires bundle
  `LSMinimumSystemVersion` to equal 15.0, discovers every Mach-O inside the app,
  requires the macOS platform, and rejects any architecture whose load-command
  minimum exceeds macOS 15.

### Tests and validation

- Reproduced the hosted command locally with a clean derived-data root. It passed
  signing, compiled the real application graph, and completed the serial
  app-hosted suite: 354 tests, 0 failures.
- Expanded the rate-limiter suite with a delayed-first-wake regression. All three
  spacing, cancellation, and delayed-wake tests passed, and the complete fast
  SwiftPM suite passed: 57 tests, 0 failures.
- Incremental universal macOS Debug build passed with the queue implementation.
- An unsigned Release artifact built successfully with Xcode 27. Its generated
  bundle minimum is 15.0; both app slices report `minos 15.0`; both embedded
  TagLib framework slices report `minos 13.0`. The artifact contains no other
  Mach-O files, and the reusable audit script passed all checks.

### Deferred release integration

- After the next independent TagLibAudioMetadata release, update the package
  pin, migrate the adapter to typed commit status, adopt the focused Basic
  snapshot where appropriate, and run cross-repository integration tests.

## 2026-09-21 coordinated reliability pass

### Current status

- Both repository worktrees began clean on `main` at `9d70edc` (AudioMator) and `62dcf9b` (TagLibAudioMetadata).
- Reopened the prior maintenance work against the current source rather than treating the new external audit as authoritative.
- Correctness-critical implementation work is in progress; findings below are source-confirmed unless marked pending.

### Newly confirmed findings

- The package's committed-but-durability-uncertain error currently becomes `MetadataFileMutationResult.failure`, so AudioMator can present a committed write as `Save Failed` and does not reload the committed file.
- `MetadataNumberTextPatch` still requires track text. A disc-only AudioMator edit therefore sends the current track text and requests a track-pair rewrite.
- Artwork identity hashes only complete small payloads; large same-size payloads with equal 64-byte prefix/suffix are deterministic false matches.
- `AudioFile.withUpdatedURL(_:)` and `withUpdatedTrackNumberText(_:)` perform hidden filesystem/TagLib reads with `try?`, conflating a value transformation with revision refresh and silently dropping concurrency state on failure.
- Multi-file metadata save progress still says `Saving Album Artwork` for arbitrary metadata edits.
- Update checking still merges equal and ahead-of-release versions into `.upToDate`, while the presenter claims the installed version matches the latest release.
- The SwiftPM fast target remains a selected-source harness rather than the production Xcode module. This was already documented accurately; replacing it is deferred until a real module extraction is justified.

### Revised or already-addressed findings

- The timeout path already prevents a late detached reload result from updating UI through a single-winner timeout plus refresh generations. The remaining detached stale work is a resource/lifecycle concern, not a stale-state corruption path.
- The package global mutex covers TagLib object access, not the entire filesystem transaction. Per-destination coordination owns transaction serialization.
- Swift and Objective-C++ transaction implementations serve different public layers; consolidation remains unsafe without a generic internal transaction SPI.

### Immediate implementation order

1. Add a non-throwing typed post-commit durability outcome to the package's high-level write results while retaining compatibility behavior where needed.
2. Make formatted track and disc patch intent independently expressible and add preservation regressions.
3. Teach AudioMator's current package adapter/executor to preserve committed outcomes, then fix artwork identity, hidden value-transform I/O, progress copy, and update-state semantics.
4. Continue capability propagation and public API safety review after those corruption/misleading-state risks are protected.

### Completed in this pass

- Added an AudioMator-owned commit status to the metadata pipeline contract.
  The TagLib adapter converts the published package's post-rename
  `committedButDurabilityUncertain` error into committed success, the mutation
  executor still reloads the on-disk result, and presentation adds a warning
  that explicitly tells the user not to retry as though the save failed.
- Added an adapter contract regression for the committed-but-uncertain mapping.
- Corrected stale dependency documentation from TagLibAudioMetadata 0.5.1 to the
  actual exact 0.5.2 project requirement.
- Removed the sampled artwork fingerprint entirely. Multi-file artwork uniformity
  now uses exact `Data` equality, with a regression whose equal-length payloads
  share the first and last 64 bytes but differ in the middle.
- Made URL replacement a deterministic value transform with explicit revision
  inputs and removed the unused track-number copy helper that performed hidden
  best-effort reads. Successful renames now explicitly reload each destination;
  a refresh failure is surfaced in the rename summary and leaves revision tokens
  absent rather than silently pretending they were captured.
- Corrected general batch-save progress from `Saving Album Artwork` to
  `Saving Metadata`.
- Added an explicit `aheadOfLatest` update-check result and presentation so
  development/internal builds newer than GitHub's latest release are not claimed
  to match it.
- Extended the app-owned format capability snapshot with effective writable
  field keys derived from the package registry. Semantic inspector writes now
  compute all requested ordinary, number-pair, advisory, and artwork fields and
  reject unsupported fields before acquiring a mutation reservation or creating
  a staged copy. This closes the late-failure path for restricted formats such
  as tracker modules while retaining AudioMator-owned preflight behavior.
- Enabled complete strict-concurrency checking for both application and
  app-hosted test configurations while retaining Swift 5 language mode. This
  strengthens production/test diagnostics now without disguising the remaining
  actor-isolation work behind an unsafe one-step Swift 6 flip.
- Revised the loading-concurrency finding after tracing the actual stages. Each
  load task performs the package-serialized TagLib snapshot first and then moves
  into AVFoundation enrichment, so the existing bounded task group already
  pipelines the serialized native stage with genuinely concurrent AV work. An
  additional app-owned TagLib queue would duplicate package serialization.
- TagLibAudioMetadata now has a focused Basic snapshot API, but AudioMator remains
  pinned to independently released 0.5.2. Adopting that loading optimization is
  explicitly blocked on a new package release rather than a local checkout.
- Made the custom metadata-field `NSLayoutManager` explicitly nonisolated so its
  AppKit override contract is not accidentally changed by the target's
  MainActor-by-default setting. This removes the production Swift 6 isolation
  warning without weakening strict-concurrency checking for the target.

### Validation in this pass

- Focused serial app-hosted `AudioMetadataPipelineContractTests`: 2 tests, 0 failures.
- Focused serial app-hosted metadata-contract/artwork and update-check suites
  completed successfully after these changes. Existing Swift 5 strict-concurrency
  warnings remain confined to lock-protected test doubles and are unchanged.
- Focused SwiftPM capability snapshot test and serial app-hosted restricted-format
  contract tests completed successfully.
- Incremental universal macOS Debug build passed with complete Swift 5
  strict-concurrency checking enabled. Existing Swift 6 migration warnings are
  now explicit compiler output rather than relying on toolchain defaults.
- Full serial app-hosted suite passed under the same configuration: 354 tests,
  0 failures. SwiftUI state-installation and Swift 6 migration diagnostics remain
  warnings and did not mask any test failures.
- Incremental universal macOS Debug build passed after correcting the AppKit
  layout-manager isolation boundary.

### Commits created in this pass

- `ed8f8fd` — reopen the coordinated reliability journal.
- `16f9327` — handle committed metadata durability uncertainty.
- `5e8e84b` — use exact artwork identity and explicit revision refresh.
- `42c877f` — correct metadata progress and update status semantics.
- `df5893f` — preserve field-level metadata write capabilities.
- `7a07812` — enable complete Swift 5 concurrency checking.

## Scope

This journal tracks AudioMator-side work for the coordinated metadata correctness and architecture review. TagLibAudioMetadata remains an independent product and has its own journal in that repository.

## Current findings

- **Platform state:** iPadOS was deprecated and removed in commit `fe10c62`. The app target now supports only `macosx`; iPad workspace/tool/welcome sources, iOS conditional branches, iPad assets, deployment settings, and plist keys were removed. Commit `84ca385` completed the source cleanup by replacing obsolete `Platform*` aliases and always-true platform branches with direct AppKit types and explicitly macOS-owned helpers.
- **Current dependency state:** `AudioMator.xcodeproj` resolves the remote `TagLibAudioMetadata` package at exact version `0.5.2`. The former sibling-checkout reference was removed after the matching upstream release became available.
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
- Entitlement/dependency lead L is confirmed. Sparkle was neither linked nor used
  by the active update flow, but its remote package pin, compile-gated source,
  Info.plist build settings, acknowledgement copy, disabled library validation,
  and temporary Mach lookup exceptions remained. These inactive surfaces were
  removed; the app now keeps only sandbox, user-selected file, and outbound
  network entitlements required by current behavior.
- Build/test-world lead I is confirmed for CI but revised for module structure.
  The root Swift package deliberately compiles a selected set of the same
  production source files as a fast deterministic sensor; it is not consumed by
  the app and must not be described as its production Core module. A broad module
  extraction would mix a risky ownership migration into correctness maintenance.
  The actionable gap was that CI never exercised the authoritative Xcode graph.
- Investigation target 1: confirmed at source level; the current save path has multiple mutation stages.
- Investigation target 2: confirmed at source level; the main compatibility write receives a Boolean advisory projection before the typed state is repaired later.
- Dependency coordination: the historical 0.4.5 remote pin was superseded by published package releases; 0.5.2 is now the project dependency.
- Raw editor lossiness: confirmed. The previous `[String: String]` join/trim/split path could not distinguish one semicolon-bearing value from multiple values and rewrote the whole map.
- Stale edit race: confirmed. The app fingerprint check occurred before the package established its transaction baseline; retaining and passing `MetadataFileVersion` closes that window.
- Timeout diagnosis: confirmed. Swift Task cancellation could not stop the synchronous TagLib mutation, so a reported timeout could later commit. The write now waits for its real outcome; only post-commit reload is bounded.
- Competing editable authorities: confirmed for several fields and fixed by using the package snapshot as the editable-tag authority.
- App-side container compatibility: confirmed and removed from the save path. Runtime format discovery through `AudioFormatSupport` remains intentional capability discovery, not container mutation logic.
- Large `AudioViewModel`: reviewed but not mechanically split. Mutation orchestration already has a feature-level executor/coordinator boundary; a broad service extraction was not necessary for the correctness fixes and would expand risk.

## Remaining follow-ups

- The coordinated maintenance audit is complete. Swift 6 migration remains a
  separately tracked follow-up after test-double isolation is repaired.
- Completed: resolved AudioMator's remote SwiftPM dependency and regenerated the pin for `TagLibAudioMetadata` 0.5.2.
- Xcode Beta is not installed. All available validation used stable Xcode 27 / Swift 6.4; rerun the documented build/test gates with the beta toolchain when available.
- Swift 6 language-mode migration remains separate work. The app still declares
  Swift 5 with `SWIFT_STRICT_CONCURRENCY = complete`; the current compiler reports
  actor-isolation warnings in lock-protected test doubles. Do not flip the
  language mode until those test boundaries are deliberately repaired.
- Raw-editor newline boundary ambiguity remains explicitly deferred: a newline inside one raw value and the UI separator between values are not yet distinguishable.
- AudioMator now uses published TagLibAudioMetadata 0.5.2, which includes the status-only read-conflict and optional-read logging fixes.

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
- Removed dormant Sparkle source, package resolution, build settings, user-facing
  acknowledgement text, and Sparkle-only sandbox/hardened-runtime exceptions.
  The supported update flow remains the explicit GitHub Releases check and manual
  download handoff, and its documentation now reflects build-number comparison.
- Expanded CI from the SwiftPM fast lane to two independent jobs. The new Xcode
  lane builds the actual application host and runs the complete app-hosted suite
  serially, while the selected-source SwiftPM package remains an explicitly
  documented fast test harness rather than a claimed production module.
- Added the extracted Foundation-only MusicBrainz scheduler/cache implementation
  to the fast package and moved its five deterministic tests there. This resolves
  an unhandled-source warning and increases the fast lane from 51 to 56 tests.
- Completed the macOS-only source model: renamed the compatibility file to
  `MacPlatformSupport.swift`, removed platform image/font/color aliases and
  always-true watched-folder branching, and made AppKit ownership explicit.
- Stabilized the app-hosted fixture-readability test by reading private temporary
  copies. This is a test-only workaround for the published package's status-time
  read guard and can be reconsidered after AudioMator adopts the package fix.
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
- During integration, normalized the temporary local-package reference used for coordinated validation. The project subsequently returned to the published remote exact dependency, now at 0.5.2; the 2026-09-21 typed durability and independent number-patch changes still require a later package release before direct adoption.
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
- Passed package resolution and a forced generic macOS build after removing
  Sparkle; the resolved graph now contains only `TagLibAudioMetadata`.
- Passed the expanded SwiftPM fast suite: 56 tests, 0 failures, with no unhandled
  source warning.
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
- Passed the forced universal macOS Debug build after the final AppKit/macOS source cleanup.
- Passed the focused app-hosted fixture-readability regression after isolating bundled fixtures in temporary copies. The compiler continues to report the already-tracked Swift 6 actor-isolation warnings in lock-protected test doubles.
- Final current gates on 2026-09-18: the SwiftPM fast harness passed 56 tests;
  the complete serial app-hosted Xcode suite passed 350 tests with no failures or
  skips; and the forced universal macOS Debug build succeeded. The Xcode result
  retains one known SwiftUI test-harness runtime warning about reading `State`
  outside an installed view.
- The independent TagLibAudioMetadata suite passed 128 tests with 2 opt-in skips
  and no failures after its final maintenance commits.

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
- `681dfdc` — `fix: bound MusicBrainz response caching`
- `502162b` — `chore: remove dormant Sparkle configuration`
- `e352b1e` — `ci: validate the real Xcode test graph`
- `84ca385` — `refactor: finish macOS-only platform cleanup`
- `2a296b0` — `test: isolate bundled metadata fixtures`
