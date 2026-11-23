# Testing

AudioMator has two test targets and no UI automation suite. This document describes what exists, what it validates, and what remains unverified.

The required metadata coverage and unified release gate are specified in [Metadata test strategy](METADATA_TEST_STRATEGY.md). Use `bash scripts/validate-release.sh` for release acceptance; individual successful suites are not full Mapping conformance.

Counts and paths below were re-verified by source inspection on 2026-11-23. The current source declares **1073 app-hosted tests across 117 `XCTestCase` classes**, **126 SwiftPM core tests across 8 classes**, and **32 policy and crash-recovery tests** under `scripts/tests`. They drift; re-count before quoting them in a release. The dated 2026-11-18 cleanup acceptance (code-complete revision `28fe62a6`, tested source revision `19e1ac23`) ran with 629 app-hosted tests and remains historical evidence for that revision.

## Test Targets

| Target | Kind | Root | Framework | Test functions | XCTestCase classes |
| --- | --- | --- | --- | ---: | ---: |
| `AudioMatorCoreLogicTests` | SwiftPM test target | `Tests/AudioMatorCoreLogicTests` | XCTest | 126 | 8 |
| `AudioMatorTests` | App-hosted Xcode unit-test bundle | `AudioMatorTests` | XCTest | 1073 | 117 |

- There is no Swift Testing (`import Testing`, `@Test`) usage.
- There are 125 `XCTestCase` classes across both targets (117 app-hosted, 8 core); no custom base class. Every app-hosted class is declared `nonisolated` and opts its app-model members into `@MainActor` explicitly (see the isolation convention below).
- The app-hosted test-support helpers are `AudioMatorTests/TestSupport/AudioFileTestFactory.swift` and `AudioViewModelTestFactory.swift`. The latter injects isolated defaults and a temporary save-issue log. The scheme also sets `AUDIOMATOR_TEST_HOST=1` for the Test action: Debug app startup uses an empty view, isolated stores, and no first-launch preference write. This prevents the host itself from restoring the developer's watched folders before tests start. Release builds ignore the flag. `SharedState` accepts injected defaults, including in presentation tests. Tests that construct watched-folder models directly also supply isolated grant stores, conflict preferences, and temporary issue logs. The test factory never falls back to standard defaults. The online-workbench performance fixture is a separate shared factory; other fakes are private to their files.
- F4 directory-monitor coverage lives in `AudioMatorTests/Application/WatchedFolders/DirectoryMonitorIdentityTests.swift` (15 native tests over disposable real directories: descriptor device/inode/kind capture, same-key move-aside/recreate rebinding, removal/reappearance, cap/root priority, open-vs-identity failure split, terminal event and balanced close, in-place-write platform limit) and `WatchedFolderMonitoringWiringTests.swift` (11 ViewModel-driven tests: attach-before-scan with no redundant follow-up, exactly one follow-up scan for a newly attached nested directory, cap omission status, same-key root replacement rebinding, stale-callback suppression, removed-nested-directory terminal rescan, missing/permission-denied root degraded status and manual refresh recovery, removal/reappearance with a fresh controller, cancelled scan after folder removal, user-requested refresh of all watched folders).
- F3 Inspector draft-session coverage lives in `AudioMatorTests/Application/MetadataEditing/InspectorDraftSessionTests.swift` (session identity/generations, dirty and original-revision retention across passive refresh, clean refresh, detached pending review and resume/discard, per-field save-delta completion including an intentional pre-save revert, partial-batch ledger, unverified readback, and independent artwork command generations), plus extended cases in `InspectorDirtyStateTests`, `InspectorAndMetadataEditorWorkflowTests`, `WatchedFolderRefreshOrderingTests` and `RenameRefreshSafetyTests`.
- The scheme includes one testable, `skipped = "NO"`, `parallelizable = "NO"`, with an auto-created test plan. No `.xctestplan` file exists.
- There are no skipped, disabled, or expected-failure tests, and no environment-variable gating of individual tests. The Test action environment flag isolates app startup. The action pins English/US presentation and ignores saved window restoration state.
- Source-policy tests read repository files through `#filePath`; moving the test or its target file breaks them.

## Commands

Fast core logic:

```bash
swift test
swift test --filter AudioMatorCoreLogicTests
```

App-hosted suite:

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

Focused app-hosted run:

```bash
xcodebuild ... \
  -only-testing:AudioMatorTests/TagLibReadWriteIntegrationTests \
  test
```

Always keep the serial flags for Agent-driven runs. The test bundle is app-hosted and each parallel runner launches another app instance.

The unified release gate is:

```bash
bash scripts/validate-release.sh
```

Performance tests are part of the same scheme and run in CI. See [Performance tests](#performance-tests).

## SwiftPM Fast Target

`Package.swift` compiles exactly 35 Foundation-only production files:

- Core: numeric conversion, tag-number text, format-support core, async deadline, path semantics, Quick Import path index and refcounted scope leases, fuzzy similarity, date serialization, picker drafts and viewport bounds.
- Domain: metadata model core, fingerprint, file-source models, watched-folder hierarchy, mutation directory plan, conflict policy, text edit pipeline, mutation coordinator, CSV and template syntax, MuseAmp IDs, rename plan/template/sanitizer, filename extraction, track renumber.
- Infrastructure pure cores: iTunes artwork/provider, LRCLIB models/ranker/request builder, MusicBrainz provider core/Lucene builder/request scheduling, online selection core.

It intentionally excludes:

- all UI, AppKit, SwiftUI, Combine, and platform code,
- TagLib adapters and `AudioFile` loading,
- network clients and services,
- app models (`AudioFile`, edit models, pipeline contract, conflict baseline),
- the app metadata exchange planner and template models.

A file in this target must stay Foundation-only and deterministic. It may use a temporary directory for path-semantics tests, but it must not contact the network, invoke TagLib, or depend on app-hosted types.

## App-Hosted Suite Map

| Directory | Files | Tests | Validates |
| --- | ---: | ---: | --- |
| `Application/MetadataEditing` | 26 | 299 | pipeline contract, batch summaries, reload workflow, revision conflicts, view-model orchestration, conflict strategies, editor store, text pipeline, renumber execution |
| `Application/MetadataExchange` | 6 | 112 | fixture parsing, profile v2, planner import/export/matching/limits, field transfer |
| `Application/Rename` | 10 | 80 | durable rename journal and exclusive-move service, journal fault/cleanup/failure controls, startup recovery bootstrap and path blocks, transaction rollback, template parsing, filename extraction, refresh safety |
| `Application/WatchedFolders` | 7 | 59 | hierarchical subfolder browsing, scoping, untagged FLAC batch-edit isolation and fallback when a subfolder disappears during browsing or a pending Inspector discard confirmation; identity-aware descriptor reconciliation (same-key rebinding, terminal events, stale-callback suppression), cap omission, permission loss, cancelled scan, removal/reappearance, ViewModel follow-up-scan single-fire, monitor plan/cap, bookmark persistence/corruption, security-scope balancing |
| `Concurrency` | 4 | 52 | reservation ordering/cancellation/starvation, quick-import cancellation and progressive index/lease budgets, 200-track presentation stress |
| `Integration/Network` | 8 | 115 | mocked HTTP faults, MusicBrainz response-shape validation/cache admission/numeric decoding, iTunes storefront-scoped publication/detail cache, LRCLIB reviewed binding/session cancellation, artwork search/download fault separation, retry/cancel and attempt identity, page traversal, search restart |
| `Integration/TagLib` | 14 | 133 | real TagLib reads/writes on temporary fixture copies, date state matrices, provider save journeys, staged-artwork save/readback |
| `Performance` | 5 | 22 | batch concurrency, publication bounds, IO stages, online workbench work bounds, progressive Quick Import counters (decode excluded/included) |
| `Unit/Core` | 20 | 102 | tag numbers, formatters, fuzzy matching, MuseAmp, provider helpers, version/update, network and license disclosure registries, issue log, markdown |
| `Unit/Presentation` | 15 | 83 | artwork preview cache, editor rows, status text, list selection (including track-list Command-A scoping), comparison builders, folder selection |
| `Root` | 2 | 16 | source-policy checks for write-plan routing and sensitive logging |
| `TestSupport` | 7 | 0 | shared test factories, Quick Import counting/synthetic adapters, and the ID3v2.3 fixture builder (no test functions) |
| **Total** | **124** | **1073** | |

Notable coverage:

- Core date picker tests verify partial dates, DST handling, UTC conversion and narrow-window viewport bounds. The app-hosted date picker suite covers known raw routes and the Metadata Editor Add Field path from filling the initially selected value through exact FLAC `DATE` readback. Viewport logic tests do not measure a macOS sheet presented in a window.
- Xcode Canvas previews in `MetadataDatePickerPanel.swift` use sample data to show the expanded calendar, grouped date and time rows with an in-group UTC preview, the searchable time-zone dropdown, a narrow window, and a daylight saving choice. Inspect the sheet and the shared AppKit dropdown from the picker and Metadata Editor during manual UI acceptance.

- `LicenseDisclosureTests` verifies that every acknowledged component has a non-empty bundled license text and that the TagLib dual-license paths and copyright markers are present.
- Real TagLib writes use temporary copies of the six committed audio fixtures. Rename tests verify that a replacement changed in place and a superseded confirmation both keep the file protected. Reviewed-write tests also invalidate a later target during the first folder request and verify that no request is made for the blocked target’s folder.
- Metadata Editor raw value arrays (`MetadataEditorRawValueArrayTests`, `MetadataFieldValueDraftTests`, `MetadataRawValuePresentationTests`, `MetadataEditorRawValueArrayPersistenceTests`) use the real store with an array-backed pipeline fake for per-element utility preview/apply (whole-value, prefix/suffix, case/trim, empty/duplicate/multiline elements, missing keys, reordering), stale-preview rejection, ordered field-entry add/remove/duplicate identity, no-op confirmations with zero writes, and captured Done before/after arrays. The persistence lane seeds temporary FLAC copies and asserts exact multiline/duplicate array readback with unrelated keys preserved, or an atomic failure with unchanged bytes.

- Conflict-strategy tests drive the real adapter on a temporary FLAC copy, including rejection of changed revisions and replacements when original inode identity is absent.
- Provider cancellation and semantic-write tests use real FLAC copies to verify committed outcomes, exact preservation, and total-only persistence through MusicBrainz, iTunes, and CSV execution.
- LRCLIB lyrics tests drive the real browser store and `AudioViewModel` write handoff with a gated non-cooperative fake provider and a recording real-package pipeline: seed-captured reviewed targets, same-ID/same-path reload and replacement rejection, equal-observation refresh control, equal-fingerprint/different-version control, mixed-bulk accounting, close/back/reseed cancellation at the provider/reservation/commit-boundary checkpoints, and real FLAC/M4A raw-map readback of `LYRICS` with unrelated tags and audio identity preserved.
- Rename journal and exclusive-move tests use disposable temporary directories and injected filesystem/journal fakes. Native probes exercise `renameatx_np(RENAME_EXCL)`, case-only renames and directory flushing only in those disposable directories; no test opens a real audio library or launches the app UI.
- Provider URLProtocol tests cover stale-ID fallback and MusicBrainz results beyond the detail-verification cap.
- MusicBrainz cache-admission tests use an ephemeral cache-free `URLProtocol` script: each of the four request shapes returns one invalid 200 and then a valid body for the identical URL and must recover on the same client with two transport calls and a later cache hit; wrong-schema valid JSON, HTTP failure, timeout and transport cancellation leave no cached entry; two coalesced waiters share one fetch (including when one is cancelled and the other must succeed and populate the cache); and the DTO score/count/votes/rating fields accept JSON-integer, numeric-string, absent and null forms while malformed, overflowing, non-integer and nonfinite forms fail with a field-level error. An `Int.min` runner-up drives the release-detail score-gap check without overflow, with 7-point continue and 8-point stop controls.
- iTunes storefront tests use one fake catalog that returns distinct albums and tracks for the same collection ID in the US and Japan: both album-result and track-result entry paths must request the submitted country and show that region's data; an A→B→A storefront/detail sequence fetches once per storefront; a delayed search after a storefront switch never publishes; a delayed detail completing after close/reopen cannot repopulate the cache; and two local selections sharing one remote album receive their own match previews while the raw detail is fetched once.
- `ArtworkLookupResponsivenessTests` drives the real online artwork lookup sheet state through a scripted in-process service: search failure/cancellation/timeout stay on the search channel while per-candidate download failure, timeout and cancellation stay on the candidate channel with the result grid and selection retained; same-candidate retry and alternate-candidate apply work without a repeated search; duplicate Apply starts one download; Stop Download keeps the sheet and grid; a superseded attempt and a completion arriving after dismissal/new session cannot publish a fault, staged draft or close the newer session; and button enablement is asserted through the same `ArtworkLookupSession` predicates the sheet binds. Staging is asserted against expected PNG bytes in the Inspector draft with unrelated draft fields preserved and file bytes plus the metadata pipeline untouched until Inspector Save. `ArtworkPreviewFallbackTests` covers the candidate-scoped preview URL fallback (A→B reset, delayed previous-candidate failure ignored, no successor at the last URL, preferred URL order preserved).
- `ArtworkHandoffOwnershipTests` covers the destination-draft ownership boundary for the six local handoffs (Finder, photo library and clipboard, single and batch): staging into exactly the captured Inspector draft with unrelated text edits preserved and no disk writes, plus gated rejections when the selection changes, the same file IDs are reopened in a new draft, a captured batch target is removed (no surviving-subset staging), a newer Clear supersedes the pending image, and a deferred obsolete completion stays silent. `ArtworkStagedSaveReadbackTests` stages downloaded PNG bytes through the guarded boundary on real MP3/M4A/FLAC fixture copies, proves the file bytes are unchanged until the separate Inspector Save, then asserts exact artwork byte readback with unrelated fields preserved and a clear-artwork round trip. Online destination rejection is covered in `ArtworkLookupResponsivenessTests`: a gated download whose selection/draft/target set changes before completion, a newer Clear command, and a preview-only lookup without an Inspector draft all leave no staged draft and disable further application.
- Provider-activation routing tests use counting fake MusicBrainz/LRCLIB clients and the real stores, routing controller and consume-once session model: generic open and source-tile selection make zero provider calls, explicit Find in MusicBrainz submits the captured query exactly once in a new window and when retargeting an open window, a consumed intent cannot replay after window recreation, generic open returns to the picker without resending, empty selection is inert, a replacement Find cancels and supersedes the previous search, back-to-Sources cancels tracked work while retaining the seed, LRCLIB Previous/Next cancels the departing row without a search, synthetic-path/tagged LRCLIB query values are asserted, and the disclosure constants name the actual fields and folder-derived terms.
- Network tests never open a socket: they use `URLProtocol` fakes or injected protocol clients.
- `NetworkServiceDisclosureTests` checks registry completeness and compares disclosed request hosts and embedded provider page domain suffixes with an independent inventory. `MetadataFieldGuideTests` checks that the guide’s external browser links match the field guide disclosure entry.
- Presentation tests include `NSHostingView` traversal of online metadata pages with a 2-second layout budget.
- `MetadataBoundaryMatrixTests` and `MetadataSaveJourneyTests` exercise sparse date-presence states, CSV/profile behavior, provider field selection, Inspector/Editor drafts, and real disk reloads.

## Fixtures

Committed fixtures live in `AudioMatorTests/Fixtures` and are copied to temporary directories before any write:

- Audio: `testAudioFile.mp3`, `.m4a`, `.flac`, `.aac`, `.ogg`, `.wav`.
- Artwork: `testCover.jpg`.
- Metadata exchange: ten `aurora-*.flac` files (byte-identical copies of the FLAC fixture, verified by SHA-256) plus pipe/tab/comma/semicolon text fixtures and an expected-output file.

There are no committed AIFF or Opus fixtures. Artwork write/clear coverage is limited to MP3, M4A, and FLAC.

## Network Tests

There are no live-network tests and no environment gating.

- `MockURLProtocol` (LRCLIB), `ProviderFaultURLProtocol`, and `UpdateMockURLProtocol` intercept requests in ephemeral sessions.
- Other tests inject non-cooperative or traversal client fakes.
- LRCLIB session tests use an injected non-cooperative provider gate that ignores task cancellation; closing/back/reseeding must still stop later requests and writes, and a gated real-package reload proves an admitted commit reports its actual outcome while later files remain untouched.
- Production request timeouts are asserted to be 15 seconds where applicable.
- Provider stores are tested for cancellation, restart races, timeout clearing, and bounded fan-out.

What this does **not** prove: live service availability, remote rate limits, API drift, Apple-provided artwork hosts, or WebKit subresource behavior.

## Performance Tests

- No `XCTMetric` and no `measure {}` API.
- Timing uses `ContinuousClock`/`Duration`; the online workbench reports warm medians as attachments.
- Most wall-clock numbers are informational. Hard assertions mostly check work bounds: four concurrent batch writes, publication counts below a fraction of file count, virtualized rows ≤ 40, recording fan-out ≤ 1, menu deferral.
- The 1,000- and 4,000-file synthetic Inspector saves use a 120-second stall timeout that resets when the reported completion count advances. The test checks collection publications against file count and progress publications against the 100 ms throttle and lifecycle updates.
- One traversal test asserts a 2-second layout budget.
- All performance tests run unconditionally in CI and in the scheme.
- `QuickImportProgressivePerformanceTests` is the AM-14 sensor: 480/960/4,000 synthetic candidates through the real progressive import path (decode excluded) and 480/960 real MP3 fixture copies through the real TagLib adapter (decode included). It asserts deterministic work counters (one identity preparation per candidate, one parent per directory, zero per-batch path-key work, forced 24/48 publication counts, unique rows, no terminal merge), records host/fixture/loader-mode, cumulative and maximum main-actor batch publication cost, and publication counts as a report and attachment. It has no wall-clock threshold and no `measure` block. `WatchedFolderRefreshOrderingTests` also checks that a late Quick Import result retains its admitted membership without replacing a newer watched observation, that a disjoint progressive import makes one membership lookup and updates zero watched rows, and that folder removal prunes the index. The audit-measured path-work harness and the source-derived pre-F5 production model are archived as `.tmp` probe output, not as test thresholds.

They are regression sensors for algorithmic blowups, not benchmarks for a specific Mac or volume.

## CI

Only one workflow exists: `.github/workflows/core-logic.yml` (`Validation`).

- Triggers: pull requests and pushes to `main`.
- Runner label: `xcode-27`; `DEVELOPER_DIR` points at `/Applications/Xcode.app/Contents/Developer`.
- `swift-test`: 15-minute timeout, runs `swift test`.
- `xcode-test`: 45-minute timeout, runs `bash scripts/validate-release.sh`.
- The gate disables signing, records evidence under `.deriveddata-codex/Validation/`, and uploads that directory with `actions/upload-artifact` even when the gate fails.
- Workflow permissions are read-only.

The `xcode-27` runner provision is external to the repository and was not verified. There is no test sharding, live-service test, or signing secret.

## Release Gate Evidence

`bash scripts/validate-release.sh` is the current acceptance path. It:

1. runs the policy and crash-recovery tests with `python3 -m unittest discover -s scripts/tests` (currently 32: 13 evidence-gate tests, 16 build-helper shell policy tests, and 3 real child-process `SIGKILL` rename crash-recovery tests covering 7 crash gates),
2. runs the full core suite and checks complete named execution with `scripts/check-core-evidence.py`,
3. runs the complete serial app-hosted suite and requires exact source-to-`xcresult` identity equality via `scripts/check-test-evidence.py`, plus every frozen critical identity and zero failures/skips/expected failures (the gate also enforces a 579-test reviewed floor and the 62-core floor; the inventory at the 2026-11-19 `878e2fc6` gate was 949 app-hosted and 70 core tests; the F5 wave reached 1010 app-hosted and 97 core tests; the 2026-11-20 independent-review remediation wave brings the named inventory to 1042 app-hosted, 97 core, and 32 policy/crash-gate tests),
4. builds an unsigned Release app and runs the artifact validator,
5. records source identity, logs, `.xcresult`, summary, test tree, and acceptance JSON under `.deriveddata-codex/Validation/`.

`bash scripts/validate-release.sh --tests-only` runs steps 1-3 and skips the Release build and artifact checks; it is not full release acceptance. A local package candidate may be evaluated with `--local-package`; that result is not published-tag acceptance.

The dated 2026-11-18 cleanup gate (code-complete revision `28fe62a6`, tested source revision `19e1ac23`) passed 13 policy tests, 62 core tests, and 629 serial app-hosted tests with zero failures, skips, or expected failures, plus the unsigned Release build and artifact validation. See the [cleanup acceptance record](../Engineering/AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md) for commands and evidence paths, and the [audit remediation acceptance record](../Engineering/AUDIOMATOR_REMEDIATION_ACCEPTANCE_2026-11-19.md) for the current 1042-test remediation gate and 2026-11-20 follow-up addendum.

The historical published 0.8.0 gate (2026-11-16) passed 13 policy tests, 62 core tests and 580 serial app-hosted tests, Release build and artifact validation. An additional unsigned Archive passed structure, architecture, license, and dependency-path checks. See [release readiness](../Engineering/HISTORY/TAGLIB_080_RELEASE_READINESS_2026-11-16.md) for evidence paths and the manual distribution boundary.

### Compile-clean isolation diagnostics gate (AM-19)

The integrated remediation candidate keeps the original concurrency settings: Swift 5 language
mode, complete strict concurrency, MainActor default actor isolation, and Approachable Concurrency
for both `AudioMator` and the app-hosted test target. The campaign adds no warning suppressions,
no `@preconcurrency` imports, no `nonisolated(unsafe)` escapes, and no language or default-isolation
changes. It does add a small number of justified `@unchecked Sendable` conformances on lock-guarded
classes that must cross isolation domains - the Quick Import lease store, the rename-journal lock,
the rename cancellation flag and the directory-monitor wrappers - while pre-existing declarations
remain. Each is backed by internal locking, none substitutes for the isolation corrections above,
and the AM-19 gate counts compiler diagnostics rather than hiding them.

Isolation ownership convention:

- App-hosted `XCTestCase` subclasses are declared `nonisolated`; methods, helpers and fixtures that
  own app models, stores, view models or AppKit objects are explicitly `@MainActor`. `URLProtocol`
  subclasses and protocol-witness fixtures are `nonisolated`, with locked recorders for mutable
  state.
- Pure value types and count/localization helpers stay `nonisolated`; synchronous move/rollback and
  other I/O work is never moved onto the main actor to silence a diagnostic.
- Headless coverage exists for the two former production warnings: the rename-recovery localized
  file count (`RenameRecoveryPresentationTests`, injected committed-marker journal failure through
  the real detached transaction and `AudioViewModel.renameFiles(using:)`) and the Metadata Write HUD
  dismissal generation barrier (`MetadataWriteHUDDismissalDecisionTests`: current/stale generation,
  replacement HUD, deallocated owner).

The compile-clean gate is a separate cold-build check from `validate-release.sh`: it compiles the app
and app-hosted test target from a disposable checkout in **both** configurations and searches the
full compiler logs for actor-isolation, Swift 6 migration, `Sendable` and implicit-capture
diagnostics. Diagnostics are keyed by target, file, line and category and de-duplicated by
`(target, file, line, message)`; the current source must produce zero such diagnostics in both
targets and both configurations. Package, toolchain/system, linker, asset and unrelated
`#NoUsage`/`#UnnecessaryEffectMarker` diagnostics are reported separately by owner and are never
suppressed.

Cold-build commands (run from a disposable copy of the exact candidate; Debug also runs the serial
named suite, Release only compiles both targets):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# 1. Debug: app + app-hosted test target compile, then the full serial suite
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  CODE_SIGNING_ALLOWED=NO test
# 2. Release: app + app-hosted test target compile in Release.
#    Release disables Enable Testability for the app target, so the app-hosted test target cannot
#    link against it without a verification-only command-line override. This does not change any
#    project build setting; it exists only to make the Release diagnostic lane compilable.
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  build-for-testing
```

A plain Release `build` is not sufficient for this check because it does not compile the test
target. The Release lane must pass `ENABLE_TESTABILITY=YES` on the `xcodebuild` command line: the Release
configuration disables Enable Testability for the app target, so the app-hosted test target cannot be
built against it otherwise. This is a verification-only override and no project build setting changes.
Both the Debug and the Release diagnostic lanes must finish clean. Incremental builds are not valid evidence: the candidate must be a clean checkout with no
prior products, and the logs must be shown to contain full app and test-target compilation. The
dated campaign evidence records the exact source revision, Xcode version, commands, log paths and
per-category counts.

## Known Coverage Gaps

1. **No committed AIFF/Opus fixtures.** `StoreIdentifierWriteTests` generates a temporary AIFF to cover store-ID set/replace/clear, reload and invalid-input atomicity. Other AIFF metadata surfaces and Opus remain outside this fixture coverage.
2. **Artwork writes only for MP3/M4A/FLAC.** Other artwork-capable formats are untested.
3. **No live-network coverage.** Provider integration is mocked.
4. **No UI automation.** Full SwiftUI/AppKit interaction, file panels, drag-and-drop, accessibility, and visual behavior are manual.
5. **Watched-folder OS integration is partially native.** Monitor tests open real `O_EVTONLY` descriptors with disposable temporary directories through the production controller, but real sandbox bookmark grants, external volumes, file providers and volume-revocation notifications are not exercised; app-hosted tests use isolated `UserDefaults` suites.
6. **Quick Import security-scope leases are tested through an injected access adapter.** The refcounted start/stop balance, `notRequired`/`revoked` tracking and explicit-authorization retry are deterministic unit/work-counter tests. Real signed-sandbox bookmark grants, revocation by the system and reauthorization remain a manual gate on a signed sandboxed build; do not treat the injected adapter as proof of real scope behavior.
7. **Full `AudioViewModel` watched-folder scanning and long-running batch UI** are only partially covered by synthesized orchestration tests.
8. **App-side container-normalization warning rendering was removed.** The legacy number-text write route that produced the normalized-warning branch was deleted in the 2026-11-18 cleanup (ledger candidate INF-04, commit `97016668`); typed semantic number-component writes surface package warnings directly. Positive coverage for a package-emitted normalization warning remains absent.
9. **No archived-binary security scan.** `validate-macos-artifact.sh` checks minimum OS and Mach-O platform only. Historical claims about scanning a release binary are not backed by a committed script.
10. **Source-policy tests depend on repository layout.** Tests read files via `#filePath`; moving those files breaks the tests.
11. **Dated test documents are stale by design.** Counts in this file drift; counts in `Docs/Engineering/` records describe the revision they name.

## Manual Verification Boundary

Automated tests and builds are the Agent verification boundary. Interactive acceptance remains the maintainer's responsibility. When manual verification is required, use temporary fixture copies and check:

- import, single and batch edit, save, reload,
- rename and renumber previews and failure reporting,
- text/CSV import and export, including profile v2 and `<remove>` handling,
- online metadata apply and cancellation,
- watched-folder restore, identity-aware monitor rebinding/terminal events/degraded status,
- settings persistence and conflict policies.

Do not run destructive smoke tests against a real music library.

## Recommended Additions (Not Implemented)

These are proposals, not current coverage:

1. Add redistributable AIFF and Opus fixtures to the integration matrix.
2. Add a fixture that forces a package container-normalization warning on a typed write and assert the resulting presentation (the old app-side normalization branch no longer exists).
3. Replace source-text policy tests with behavioral tests where practical, or assert paths through a small manifest.
4. Add a live-network opt-in test target that is skipped by default; never run it in CI.
5. Add a UI test host with stable accessibility identifiers for selection, save, and window flows.
6. Add real bookmark/security-scope integration tests on a signed sandboxed build.

## Historical Verification

These dated records are evidence for the revision they name, not current inventories:

- [0.6.0 integration](../Engineering/HISTORY/TAGLIB_060_INTEGRATION_2026-10-25.md) — historical migration record; its FLAC semantic-comment blocker is fixed in later releases.
- [0.7.0 implementation ledger](../Engineering/HISTORY/AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md) and [acceptance](../Engineering/HISTORY/AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md) — superseded 0.7.0 evidence.
- [0.7.1 joint acceptance](../Engineering/HISTORY/MAPPING_071_JOINT_ACCEPTANCE.md) — local-candidate acceptance, superseded by published dependencies.
- [0.7.2 adoption](../Engineering/HISTORY/TAGLIB_072_ADOPTION_2026-11-11.md) — failed on the absent-Year/present-Date MP4 Comment/Lyrics case; retained as a mandatory regression.
- [0.7.3 readiness](../Engineering/HISTORY/TAGLIB_073_RELEASE_READINESS_2026-11-12.md) — 13 policy tests, 62 core tests, 579 serial app tests.
- [0.8.0 readiness](../Engineering/HISTORY/TAGLIB_080_RELEASE_READINESS_2026-11-16.md) — 13 policy tests, 62 core tests, 580 serial app tests, plus an unsigned Archive.
- [Inspector field visibility](../Engineering/INSPECTOR_FIELD_VISIBILITY_2026-11-16.md) — 586 app-hosted tests at that baseline.
- [Internal numbering recovery](../Engineering/INTERNAL_NUMBERING_RECOVERY_2026-11-16.md) — 593 app-hosted tests at the local-candidate gate, followed by a 596-test joint run.
- [Metadata Field Guide](../Engineering/METADATA_FIELD_GUIDE_2026-11-17.md) — 599 app-hosted tests at the first Debug-only gate, then 602 at the naming follow-up.
- [Published 0.8.1 Debug adoption](../Engineering/TAGLIB_081_DEBUG_ADOPTION_2026-11-17.md) — 13 policy tests, 62 core tests, 596 serial app tests on the normal project, tests-only lane.
- [2026-11-18 cleanup acceptance](../Engineering/AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md) — 13 policy tests, 62 core tests, 629 app tests (code-complete revision `28fe62a6`, tested source `19e1ac23`), full Release/artifact gate.

Earlier local-candidate and write-concurrency evidence ([state coverage](../Engineering/HISTORY/METADATA_STATE_COVERAGE_2026-11-11.md), [write concurrency](../Engineering/HISTORY/WRITE_CONCURRENCY_2026-11-12.md), [package review repair](../Engineering/HISTORY/TAGLIB_REVIEW_REPAIR_2026-11-14.md), [API performance candidate](../Engineering/HISTORY/TAGLIB_API_PERFORMANCE_CANDIDATE_2026-11-12.md)) remains archived and is not published-tag acceptance.

## Related Documents

- [Build](BUILD.md)
- [Metadata test strategy](METADATA_TEST_STRATEGY.md)
- [Debugging](DEBUGGING.md)
- [Release Engineering](RELEASE.md)
- [2026-11-18 cleanup acceptance record](../Engineering/AUDIOMATOR_LEGACY_CLEANUP_ACCEPTANCE_2026-11-18.md)
- [2026-11-18 cleanup ledger](../Engineering/AUDIOMATOR_LEGACY_CLEANUP_LEDGER_2026-11-18.md)
