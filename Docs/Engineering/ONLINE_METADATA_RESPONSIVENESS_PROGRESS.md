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

## Page-chain audit checklist

- [x] Provider source picker and source switching
- [x] MusicBrainz track search and recording detail
- [x] MusicBrainz multi-file search and release detail/preload
- [ ] MusicBrainz recording and release tagging workbenches
- [x] iTunes file, album, and track search result paths
- [x] iTunes album detail and match preview
- [ ] iTunes track and album tagging workbenches
- [ ] Metadata comparison and assignment pages under both workbenches
- [ ] Apply/write/reload success, failure, timeout, and cancellation

## Delivery gates

- [ ] Regression tests for every confirmed permanent-unresponsive root cause
- [ ] SwiftPM core-logic tests
- [ ] Serial macOS app-hosted test suite
- [ ] macOS build
- [ ] Generic iOS build
- [ ] Real macOS success/failure/timeout/cancel traversal
- [ ] Clean working tree and release-ready review

## Completed batches

### Batch 1 — browser task ownership and iTunes album matching

- Browser searches now use operation identities, invalidate state on every reset/source/mode change, and publish through a weak post-await reference. A cancelled provider that ignores cancellation no longer retains either browser store or leaves `isSearching` active.
- iTunes album preview matching now runs in a detached user-initiated task; only the resolved immutable preview returns to the main-actor cache.
- Added three regression sensors: non-cooperative MusicBrainz search teardown, non-cooperative iTunes search teardown, and main-actor schedulability while iTunes album matching is deliberately blocked.
- Targeted result: `ProviderSearchRestartTests`, 5 tests passed serially on macOS.
