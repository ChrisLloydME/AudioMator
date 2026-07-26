# Online Metadata Responsiveness Progress

## Goal

Make every reachable MusicBrainz and iTunes browser page recover to an interactive state after success, failure, timeout, cancellation, navigation, source changes, and window closure without changing search semantics, matching rules, or the visible workflow.

## Baseline and runtime evidence

Date: 2026-07-25

- A forced baseline macOS build completed successfully with `bash scripts/codex-build.sh --force`.
- Real macOS traversal used ten files from `AudioMatorTests/Fixtures/MetadataExchange/Audio` and exercised MusicBrainz file search, release detail/preload, source switching, iTunes file search, iTunes album search, and iTunes album detail.
- A 15-second sample during the ten-file MusicBrainz search found the main thread idle in `mach_msg` for 6,313 of 6,356 samples. The successful search still took approximately 30–40 seconds, identifying sequential network fan-out without an overall deadline rather than a continuously blocked main thread.
- A 20-second sample during MusicBrainz release detail preload found the main thread idle for 8,487 of 8,575 samples. The preload performs sequential recording-detail requests and can keep the page loading indefinitely when a request never completes.
- A 10-second sample while opening an iTunes album detail captured 160 samples in `iTunesAlbumDetailView.loadDetail`, including 158 in `iTunesBrowserStore.detailByResolvingSelectionPreview` and 113 in `iTunesAlbumMatcher.match`. The stack continues through fuzzy similarity and Levenshtein distance on the main thread.
- A post-fix real macOS traversal opened MusicBrainz file search, recording detail, relationship preload, and the Review & Apply workbench. An 8-second sample while changing workbench field selections found the main thread idle for 6,874 of 6,879 samples, with no sustained comparison or plan-building block.

The raw `sample` reports are intentionally kept outside the repository under `/private/tmp/audiomator-*.sample.txt`; this document records the durable findings without committing machine-specific traces.

## Confirmed root causes

### RC1 — iTunes album matching blocks the main actor

`iTunesBrowserStore.albumDetail(for:)` calls `detailByResolvingSelectionPreview` from the main-actor store. For uncached previews, the synchronous album matcher and fuzzy string/edit-distance work therefore run on the UI thread. Runtime sampling confirms this stack.

Required fix and regression sensor:

- Compute the immutable selection preview away from the main actor, then publish/cache only the completed value on the main actor.
- Add a test that proves the main actor remains schedulable while a deliberately expensive album match is being resolved.

### RC2 — provider request fan-out has no bounded completion

MusicBrainz file search, MusicBrainz recording-detail preload, and iTunes file-album enrichment perform sequential network fan-out. Provider requests use URLSession defaults without an explicit request deadline, and release preload has no overall budget. A slow or non-returning request can leave a page in loading state indefinitely.

Required fix and regression sensors:

- Give provider requests an explicit finite timeout.
- Bound detail preload as a whole and expose partial detail rather than holding the entire release page hostage.
- Preserve current request ordering, matching, and result rules.
- Test timeout, cancellation, and partial-preload completion.

### RC3 — tasks outlive their page/session and can retain UI state

Browser search tasks, detail preparation tasks, and MusicBrainz workbench recording-load tasks do not consistently use operation identities or weak post-await publication. Several closures promote a weak reference to a strong one before an unbounded await. Closing, navigating back, switching source, or starting a replacement operation can therefore leave old work alive and able to retain or overwrite state.

Required fix and regression sensors:

- Every long-lived operation receives an identity and has one cancellation/invalidating owner.
- Never retain a view/store across an external await solely through a task it owns.
- Old operations cannot clear or replace newer state.
- Test non-cooperative clients, not only cancellation-aware sleeps.

### RC4 — apply/write/reload can leave global progress permanently active

Provider apply functions clear `metadataSaveProgress` only on their normal tail path. `MetadataFileMutationExecutor` awaits a detached write/reload task whose value wait is not cancellation-responsive. A stuck synchronous write or reload can therefore keep both the caller and global progress state active indefinitely.

Required fix and regression sensors:

- Progress cleanup must be guaranteed for success, failure, and cancellation.
- Cancellation must release the UI caller without releasing the file reservation while the underlying write still runs.
- A cancelled queued mutation must still never execute.
- Test cancellation during a non-cooperative reload/write gate and verify a later mutation remains serialized correctly.

### RC5 — MusicBrainz decoding and ranking inherit main-actor isolation

The app target's default actor isolation causes the MusicBrainz client, JSON DTO decoding, Lucene query construction, link parsing, and result reranking to execute on the main actor unless each pure-data boundary is explicitly nonisolated. Wrapping the client call in a detached timeout task is insufficient when the called protocol and concrete methods hop back to the main actor.

Required fix and regression sensors:

- Make the complete MusicBrainz request/parse/query/ranking pipeline nonisolated and Sendable where values cross task boundaries.
- Keep only observable UI-state publication in `MusicBrainzBrowserStore` on the main actor.
- Add a structural compile-time regression sensor for the nonisolated boundaries plus existing successful/invalid-payload client tests.

### RC6 — release matching and comparison are rebuilt inside SwiftUI body

MusicBrainz release detail previously resolved a fallback file-to-track preview and built every metadata comparison row directly in `releaseSections`. Optional recording-detail preload publishes progress repeatedly, so each update could retrigger the full matching/comparison workload on the main actor. The preload's best-effort error handler also swallowed `CancellationError` and published progress after cancellation.

Required fix and regression sensors:

- Build the immutable release presentation once in a detached, bounded, cancellable operation while keeping the base release detail interactive.
- Do not publish preload progress that is not visible and only causes broad view invalidation.
- Propagate preload cancellation and invalidate the MusicBrainz session when switching back to Sources.
- Test fallback preview/comparison equivalence, preservation of provider previews, cancellation progress, and the absence of body-time matching.

## Page-chain audit checklist

- [x] Provider source picker and source switching
- [x] MusicBrainz track search and recording detail
- [x] MusicBrainz multi-file search and release detail/preload
- [x] MusicBrainz recording and release tagging workbenches
- [x] iTunes file, album, and track search result paths
- [x] iTunes album detail and match preview
- [x] iTunes track and album tagging workbench implementation/test audit
- [x] Metadata comparison and assignment page implementation audit
- [x] Apply/write/reload success, failure, timeout, and cancellation

## Delivery gates

- [x] Regression tests for every confirmed permanent-unresponsive root cause
- [x] SwiftPM core-logic tests
- [x] Serial macOS app-hosted test suite
- [x] macOS build
- [x] Generic iOS build
- [x] Deterministic macOS app-hosted success/failure/timeout/cancel page traversal with a selected audio fixture
- [x] Clean working tree and release-ready review

## Completed batches

### Batch 1 — browser task ownership and iTunes album matching

- Browser searches now use operation identities, invalidate state on every reset/source/mode change, and publish through a weak post-await reference. A cancelled provider that ignores cancellation no longer retains either browser store or leaves `isSearching` active.
- iTunes album preview matching now runs in a detached user-initiated task; only the resolved immutable preview returns to the main-actor cache.
- Added three regression sensors: non-cooperative MusicBrainz search teardown, non-cooperative iTunes search teardown, and main-actor schedulability while iTunes album matching is deliberately blocked.
- Targeted result: `ProviderSearchRestartTests`, 5 tests passed serially on macOS.

### Batch 2 — bounded provider operations and partial detail recovery

- Added a one-shot async deadline primitive whose caller completes on success, failure, timeout, or cancellation even when the wrapped operation ignores cancellation. Late results are discarded.
- MusicBrainz and iTunes searches, detail requests, and off-main iTunes matching now have operation deadlines; every provider URL request carries an explicit 15-second timeout.
- MusicBrainz release detail is published before optional recording-detail preload. Individual preload requests and the overall preload have finite budgets, so unavailable relationship data can no longer hold the page in a loading state.
- Sequential provider fan-out now checks cancellation between requests and does not swallow cancellation in best-effort fallback branches.
- Added regression sensors for both non-cooperative search timeouts, non-cooperative MusicBrainz preload timeout, finite URL request timeouts, and replacement-search stale-result suppression.
- Targeted result: `ProviderSearchRestartTests` and `ProviderNetworkFaultTests`, 13 tests passed serially on macOS; incremental macOS build succeeded.

### Batch 3 — page-owned work and metadata mutation recovery

- MusicBrainz/iTunes detail preparation, workbench apply, and MusicBrainz recording-detail tasks now have explicit owners and are cancelled when their page disappears. Cancelled recording loads return to an idle state without publishing late data.
- Provider apply functions clear the shared metadata progress overlay with `defer`, including early cancellation exits between files and after writes.
- Metadata write/reload now has a finite UI-facing deadline. Timeout or cancellation releases the caller while the underlying non-cancellable transaction retains its per-file reservation until it actually finishes, preventing overlapping TagLib writes.
- Added regression sensors for cancellation during a non-cooperative provider reload and timeout during reload with a queued same-file mutation.
- Targeted result: `FileMutationSerializationTests` plus the provider apply cancellation regression, 7 tests passed serially on macOS.

### Batch 4 — artwork processing and comparison refresh isolation

- iTunes artwork search/download requests now use explicit 15-second request timeouts and a 30-second UI-facing deadline. A provider that ignores cancellation can no longer retain the lookup session or leave search/apply state active indefinitely.
- Artwork decode and PNG normalization now happen inside the detached, bounded service operation. Only construction of the already-normalized platform preview image and publication of edit state occur on the main actor.
- The artwork sheet remains dismissible while a download is active on both macOS and iPadOS; dismissal invalidates the session and releases the view model even if the service continues running.
- iTunes album comparison groups are no longer rebuilt inside SwiftUI `body`. They are prepared once per detail/file fingerprint in a detached, 10-second bounded operation, and file lookup is indexed once by ID instead of repeated for every assignment and field.
- Added regression sensors for non-cooperative artwork search/download timeouts, cancellation-state cleanup, dismissal during search/download, and explicit artwork request timeout configuration.
- Targeted result: `ArtworkLookupResponsivenessTests`, `iTunesMetadataComparisonBuilderTests`, and `ProviderNetworkFaultTests` passed serially on macOS; incremental macOS build succeeded.

### Batch 5 — MusicBrainz parsing and release-presentation isolation

- The complete MusicBrainz client pipeline—query/link construction, request processing, JSON DTO decoding, result mapping/ranking, and relationship construction—is explicitly nonisolated. Detached deadline tasks no longer hop heavy parse/rank work back to the main actor.
- Release fallback matching and comparison-row construction moved out of SwiftUI `body` into a pure Sendable presentation builder with a 10-second caller deadline. The overview is published first and stays scrollable/dismissible during preparation or after timeout/failure.
- Invisible recording-preload progress no longer invalidates the entire release view. Cancellation is propagated instead of being swallowed, and switching from MusicBrainz to Sources closes the provider session before changing the selected source.
- Added regression sensors for presentation equivalence, provider-preview preservation, off-main structural boundaries, body-time matching removal, and cancellation without late preload progress.
- Targeted macOS tests and incremental generic macOS build succeeded; full delivery gates are being rerun after this audit batch.

### Batch 6 — deterministic app-hosted stress harness

- Replaced coordinate-driven GUI performance automation with deterministic app-hosted stress fixtures. A 10,000-record MusicBrainz JSON response exercises request completion, JSON decoding, result mapping, and ranking under a five-second caller deadline while a main-actor heartbeat remains schedulable.
- A 200-file/200-track MusicBrainz release fixture exercises fallback matching plus 1,800 comparison-row decisions through the same detached, five-second bounded presentation path used by the detail page. The test asserts the operation is not on the main thread and that every assignment/comparison group completes.
- The attempted GUI search without a valid AudioMator file-selection setup is explicitly discarded as invalid evidence. Its follow-up 5-second sample found the main thread idle in `mach_msg` for 4,328 of 4,335 samples, so it did not show a main-thread hang, but it is not counted as a successful page traversal.
- Targeted `OnlineMetadataStressTests` and `ProviderNetworkFaultTests` passed serially without new compiler warnings.

### Batch 7 — selected-file macOS page and recovery traversal

- Added an app-hosted traversal harness that first creates and selects a real `AudioFile` fixture in `AudioViewModel`; provider searches therefore exercise the same selected-file precondition as the application instead of attempting a resultless GUI search.
- The harness mounts the actual SwiftUI source picker, MusicBrainz/iTunes search roots, recording/release/track and album detail pages, comparison surfaces, both tagging workbenches, and artwork loading/failure/success states in an `NSHostingView`/`NSWindow` host.
- MusicBrainz and iTunes roots are each driven through success, provider failure, a 30-millisecond deadline, and explicit session cancellation. Every case asserts loading-state recovery before rendering, then requires layout to finish within two seconds and a queued main-event-loop pulse to complete.
- Production entry points retain their existing behavior; the view initializers only accept injected stores/source state so app-hosted tests can traverse provider roots deterministically.
- Targeted `OnlineMetadataPageTraversalTests` passed serially on macOS (2 tests). The earlier coordinate-driven run remains discarded and is not used as evidence.

## Final validation status

Date: 2026-07-26

- SwiftPM core logic: 47 tests passed with no failures. `Core/Concurrency` is explicitly excluded from the selective fast-test target, removing the unhandled-file warning without adding UI/network code to that target.
- Serial macOS app-hosted suite: 287 tests passed with no failures or skips using `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`, including the deterministic stress sensors and the two selected-file page traversal tests.
- Forced generic macOS build: succeeded with repository-local `.deriveddata-codex`.
- Generic iOS build: succeeded against the installed iPhoneOS 27.0 SDK using Xcode 27 beta and the same `.deriveddata-codex`. The default Xcode 26.5 installation did not include an iOS platform SDK.
- The release traversal gate is satisfied by the macOS app-hosted harness: it starts with an explicitly selected audio fixture and mounts every MusicBrainz/iTunes root, detail, comparison, tagging-workbench, and artwork state while exercising timeout, failure, cancellation, stale results, large-payload parsing, large comparison construction, apply/reload recovery, and non-cooperative providers.
- Coordinate-driven GUI automation was stopped after it proved unable to establish AudioMator's required file-selection state reliably. Its result and sample are retained only as discarded diagnostic history and are not counted as release evidence.
- Final forced generic macOS and generic iOS builds passed. The worktree was clean after the validation record was committed.
