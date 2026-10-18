# AudioMator independent post-repair review

Date: 2026-10-17. Original base: `78d5f5e3`. Repair HEAD: `02810a2b`. Review branch: `review/audit-repairs-verification`.

This is a dated engineering record. Current contracts remain in the architecture, security, and development documentation. The supplied audit and implementation report were treated as claims, not evidence. Evidence here comes from base/current source comparison, the 32 repair commit diffs, current callers, and fresh automated runs. No external package source was inspected or edited. No application was manually launched or interactively tested.

## A. Executive summary

**READY WITH CAVEATS**, after the additional review commits. The original repair HEAD should not be merged unchanged: its missing-inode fallback allowed a stale draft to adopt a replacement file's version; its cancellation repair still discarded an already committed provider result; and its rename safety marker could be undone by a queued reload.

The original audit was substantially accurate about the important control-flow and test weaknesses. Most repairs were useful and correctly targeted. The strongest corrections were centralized total-only rejection, missing iTunes advisory preservation, CSV header validation, and watched-folder scan epochs. Several “FIXED” classifications were too broad, especially identity safety, cancellation, test isolation, skipped-row wording, and quarantine preservation.

The review corrected those problems, added real-file provider/CSV checks, verified stale-provider-ID fallbacks and the MusicBrainz result cap, strengthened whole-map preservation and fixture participation, and surfaced a previously omitted renumber durability warning. The original 32 commits remain intact. Main was neither changed nor merged.

Fresh verification: **62 core tests and 472 serial app-hosted tests passed**. Final configuration and Release verification are recorded in section H. Passing tests establish the exercised paths, not all formats, volumes, provider behavior, or UI acceptance.

## B. Original audit validation

### Confirmed

Base source confirms P-01/P-03/P-05/P-07/P-08/P-09: folder publication bypassed mutation ordering; total-only intent disappeared at number-text serialization; CSV headers were positional; missing iTunes advisory became writable “Unset”; rename failure did not reconcile models; slash input was concatenated into malformed pairs. Their safety consequences were credible, although stale UI is distinct from demonstrated disk corruption.

Base source also confirms full rescan loads, skipped-target numbering gaps, terminal stored-ID lookup paths, the three-result MusicBrainz truncation, null-body decoding, incomplete cancellation reporting, and debug assertion on issue-log persistence. The important T-01–T-11 assertion/coverage weaknesses are observable in the base tests themselves.

### Significant qualifications and disagreements

- **P-02:** indiscriminate low-confidence lyrics selection was a defect. Overwriting lyrics after the user explicitly selects “Auto Apply Best Matches” is a product policy, not independently proof of an unintended write. The new exact-title/artist/duration gate is meaningful; a review/overwrite opt-in remains a product decision. This review preserves the existing explicit action.
- **P-03:** AudioMator's chosen text-patch path loses standalone totals. This does not prove every public structured API is incapable of representing them in every format. Safe rejection fixes the silent-loss defect; it does not implement independent-total editing. An untouched standalone total must remain editable alongside unrelated changes, and the new real-file test verifies that case.
- **P-04/P-10/P-11:** source confirms the expensive work and unvirtualized views. The original severity is workload-dependent; no representative network-volume or large-library benchmark was supplied or run. These are concrete scaling risks, not measured universal hangs.
- **P-06:** observable integration failures are confirmed by fresh fixture tests. Root cause inside TagLibAudioMetadata is unverified. No package-internal diagnosis or workaround is asserted.
- **P-13:** nil identity caused unconditional rejection in the base. Which real filesystems expose nil or unreliable attributes remains unverified. The repair comment calling the opaque package version “content-derived” was unsupported. A fresh snapshot/version pair proves a stable current read, not continuity with the original recording.
- **P-16:** differing entity IDs are confirmed. The correct field mapping requires a verified external contract/product decision; guessing a replacement value would be inappropriate.
- **P-18:** this was hardening, not demonstrated code execution. Page-navigation restriction is not a WebKit subresource firewall.
- **P-19:** releasing a reservation after a timeout while a synchronous commit still runs would permit overlapping writes. That recommendation is unsafe. Retaining the reservation until actual completion is the correct present safety boundary; a recoverable hard timeout needs a cancellable or isolated writer.
- **P-24:** UTF-8 without BOM is valid CSV, not inherently a defect. Silent legacy decoding remains a usability/data-interpretation risk; the preview and explicit apply remain relevant safeguards.
- **P-25:** path-derived MuseAmp identity is a documented design, not a regression or a violated move-stability guarantee. Do not change an identity algorithm without a product decision.
- The original architectural claim that rich metadata is generally flattened to strings was too broad: advisory and artwork already use typed package patches. The problematic number-text boundary is specific.

Important omissions in the original audit: app-host startup itself bypassed test factories; renumbering ignored committed durability uncertainty; and the repaired fail-closed model needed ordering against queued reloads. These were corrected here.

## C. Review of all 32 repair commits

Each original commit was inspected in context; cumulative caller behavior takes precedence over its message. Grouping below accounts for every original commit exactly once.

| Area / original commits | Independent assessment |
| --- | --- |
| Number safety: `b0833e7e`, `ddf4746c`, `488f8376` | Central rejection covers semantic writers; combined input is split. Unchanged standalone totals are not rejected. Safe, with limited semantic functionality. |
| Advisory: `4061ea98`, `f894caff` | Empty provider advisory is excluded from plans; present advisory still maps normally. Effective. |
| Lyrics: `e9322a95`, `08002d08` | Exact normalized title/artist, duration distance, score, and synced availability are enforced by the store. Effective confidence gate; no overwrite review added. |
| Scans/import: `5aaa6ed0`, `d6b1ae3a`, `afc2c133`, `6e1954ac`, `0a4d90b8` | Final optional epoch defaults to zero at capture and both comparisons. Tokens reject overlapping scans; mutation epochs reject older app-state publication. Fingerprint AND package version gate reuse. Enumeration remains full; failed reads retain old metadata. Early failures now advance the progressive cursor. |
| Rename: `835cbf66` | Identity-bearing recovery locations and model reconciliation are useful. Refresh-required publication omitted queued reload invalidation; corrected here. |
| Identity: `10cd152b` | **Regression introduced.** Missing either original identity component skipped identity continuity checks and permitted rebasing onto replacements. Corrected here for typed/raw writes and Metadata Editor baseline loading. |
| CSV: `0eb9edfe`, `3915d70d` | Ordered header aliases reject reordered schemas; ignore columns remain flexible. Apostrophe/formula protection now round-trips the tested runs. Custom headers must be mapped explicitly or header handling disabled. |
| Summaries: `cf1f8e62`, `2b694c44` | Denominator improved, but skipped rows were called saved-with-warning. Corrected to a separate skipped bucket with log preservation. |
| Renumber: `2dee193d` | Unsupported formats are filtered before ascending/descending assignment. Failures still consume their planned number, appropriately avoiding timing-dependent renumbering. Start clamp remains. |
| Provider/web: `a635b5fe`, `02810a2b` | Stored IDs are best-effort hints; remaining MusicBrainz candidates are retained; canonical links parse; null release bodies decode; navigation delegate matches SDK isolation. Fresh stub tests confirm fallbacks/result count. Web privacy documentation/disclosure was incomplete and is corrected here. |
| Cancellation: `2f05bb15` | **Partially fixed at repair HEAD.** Returning was replaced by breaking, but a post-await cancellation check still discarded the completed result. Corrected; remaining entries are accounted for. |
| Issue history: `fabb3437` | Best-effort persistence removes the debug trap. A single fixed backup and ignored copy failure could still lose later corrupt histories. Corrected here. |
| Test repairs: `c6101190`, `3420e1db`, `b14076ce`, `61699593`, `ee55a3ea`, `43a11579`, `c7d201cd` | Stronger field setup/readback, patch recording, owner-guard tests, artwork mapping, and positive logging controls are useful. Isolation missed direct constructors/host startup. Nonzero fixture counts missed individual support loss. Both strengthened here. Protocol-default delta testing remains distinct from observing concrete adapter calls. |
| Test documentation: `b7b8abf6`, `9b67a802` | 459 repair-HEAD test functions is accurate, but suite-map counts and isolation claims were stale. Final counts and limits are updated. |

## D. Finding-by-finding resolution matrix

Statuses describe the final review implementation. “At repair HEAD” records significant disagreement with the supplied repair status. Verification is limited to source and the automated environments described below.

### Production findings

| ID | Original diagnosis validity | Repair claim | Independently verified status / action / limitation |
| --- | --- | --- | --- |
| P-01 | Valid race | FIXED | **VERIFIED FIXED** for stale scans crossing published app mutations: token/epoch guards at both suspension boundaries. Recovery invalidation strengthened. External edits after probes are not atomic with scans. |
| P-02 | Valid confidence defect; overwrite policy overstated | IMPROVED | **PARTIALLY FIXED**: confidence gate verified; high-confidence replacement of existing lyrics and absence of review remain explicit product behavior. |
| P-03 | Valid serialization loss | FIXED | **VERIFIED FIXED** for silent loss via centralized rejection. Added real provider/CSV track/disc rejection and untouched-total preservation tests. Standalone semantic total writes remain unsupported. |
| P-04 | Valid work amplification; severity workload-dependent | IMPROVED | **PARTIALLY FIXED**: only changed revisions fully load; full enumeration and per-file probes remain. Reuse is not cryptographic identity or continuous monitoring. |
| P-05 | Valid | FIXED | **VERIFIED FIXED**: ordered name/alias validation before row construction. Explicit no-header mode remains positional. |
| P-06 | Valid observed limitation; internal cause unverified | BLOCKED | **DEPENDENCY-BLOCKED**: MP3 untouched-track verification and AAC total clearing still fail safely in the fixture matrix. See section J. |
| P-07 | Valid absent-vs-clear defect | FIXED | **VERIFIED FIXED**: missing advisory is absent from write entries; explicit/clean clearing has separate real-file coverage. |
| P-08 | Valid recovery state defect | FIXED | **VERIFIED FIXED** after additional queued/older reload invalidation. Transaction recovery output now exercises the shared model reconciliation helper. Real volume/permission failures are not simulated end to end. |
| P-09 | Valid | FIXED | **VERIFIED FIXED** for pasted combined pairs: parser splits rather than concatenates. This is not general arbitrary-text validation. |
| P-10 | Valid source concern | PARTIAL | **DEFERRED**: main-actor path-key/preview work remains. No measured regression threshold or speculative cache rewrite introduced. |
| P-11 | Valid source concern | DEFERRED | **DEFERRED**: preview stacks are not virtualized. Large accepted plans can be expensive; no representative UI benchmark run. |
| P-12 | Valid | FIXED | **VERIFIED FIXED** after separate skipped accounting/HUD/log correction. Unchanged rows are excluded from the actionable denominator. |
| P-13 | Valid conditional functional failure | FIXED | At repair HEAD **INCORRECTLY FIXED / REGRESSION INTRODUCED**. Final **VERIFIED FIXED**: unchanged fallback revisions may save; changed fallback revisions require reload; all available identity components remain checked. Real nil-inode volumes untested. |
| P-14 | Valid | FIXED | **VERIFIED FIXED**: stored release 404 falls back; five candidates survive the three-detail cap in new URLProtocol test. Representative lookups use the same catch/cancellation structure; live service not tested. |
| P-15 | Valid | FIXED | **VERIFIED FIXED**: unresolved stored album falls back to text search; canonical, legacy, scheme-less, and track-query forms tested. UPC catch/fallback inspected; no dedicated UPC failure test. Dead duplicate parser remains. |
| P-16 | Confirmed inconsistency; desired mapping uncertain | DEFERRED | **UNVERIFIED** correct entity contract; deferred product/dependency decision. Existing IDs were not guessed or rewritten. |
| P-17 | Valid | FIXED | **VERIFIED FIXED**: nullable body and call-site nil handling; decoding regression passes. |
| P-18 | Valid hardening gap | FIXED | **VERIFIED FIXED** for initial/page-navigation policy and non-persistent storage; shared policy/disclosure/docs aligned. Subresources remain unrestricted; actual provider redirects untested. |
| P-19 | Plausible environmental hang, not reproduced | DEFERRED | **DEFERRED**: synchronous commits remain unbounded. Reservation must remain held while outcome is unknown. Reload timeout is separate and tested. |
| P-20 | Valid failed-index stall; slow-index ordering is a tradeoff | FIXED | **PARTIALLY FIXED**: failed indices no longer block batches, now tested while a final load remains gated. A still-unresolved earlier input continues to hold later contiguous publication. |
| P-21 | Valid skipped-format gap; clamp visible in code | FIXED | **PARTIALLY FIXED**: unsupported targets no longer consume numbers; silent start clamp remains. Added durability-warning correction unrelated to number assignment. |
| P-22 | Valid | FIXED | **VERIFIED FIXED** after preserving each corrupt history and disabling persistence if preservation fails. New repeated-corruption regression; best-effort in-memory logging remains available. |
| P-23 | Valid cancellation defect; dead code is maintenance debt | PARTIAL | **PARTIALLY FIXED**: committed provider outcomes and remaining cancelled rows now reconcile. Production-dead import and differing other batch cancellation policies remain deferred. |
| P-24 | Valid apostrophe loss; BOM recommendation optional | PARTIAL | **PARTIALLY FIXED**: apostrophe corpus round-trips. UTF-8 has no BOM; legacy decoding remains silent. No unsupported claim that BOM is required. |
| P-25 | Accurate implementation description; no violated contract | DEFERRED | **NOT A DEFECT** under current documented path-based identity. Move-stable IDs require a product decision. |
| No undo/backup | Accurate product gap | DEFERRED | **DEFERRED**: committed metadata has no application undo/archive. Issue logs are not backups. |

### Test findings

| ID | Original diagnosis validity | Repair claim | Independently verified status / action / limitation |
| --- | --- | --- | --- |
| T-01 | Valid omitted edited-field assertion | FIXED | **VERIFIED FIXED**; strengthened further to full raw-map equality against baseline plus intended title. |
| T-02 | Valid vacuous setup | FIXED | **VERIFIED FIXED** for the named editable/common fields: setup and clear/erase readbacks now assert those fields. Does not prove erase of every native structure. |
| T-03 | Valid vacuous clear | FIXED | **VERIFIED FIXED**: seed explicit, verify it, clear, inspect raw removal and model nil. |
| T-04 | Valid enforcement blind spot | FIXED | **VERIFIED FIXED**: workflow invokes persist, checks rejection and no writer calls; helper test retained separately. |
| T-05 | Valid mapping blind spot | FIXED | **VERIFIED FIXED**: patch shape plus adapter replace/remove round trips on MP3/M4A/FLAC. UI interaction and multi-artwork roles remain outside coverage. |
| T-06 | Valid overclaim about synthetic workflow fixtures | PARTIAL | **PARTIALLY FIXED**: injectable revision/baseline/refresh state plus more real-file workflows. Many fakes intentionally remain orchestration-only. |
| T-07 | Valid | FIXED | At repair HEAD **PARTIALLY FIXED**. Final **VERIFIED FIXED** for identified stores: direct constructors, host startup, first-launch preference, SharedState preferences, no standard-default fallback, and saved-window restoration addressed. Does not establish real sandbox authorization. |
| T-08 | Valid unreachable owner guard | FIXED | **VERIFIED FIXED**: directly desynchronized draft/selection exercises guard and verifies repaired owner/title plus zero writes. |
| T-09 | Valid missing invocation evidence | FIXED | **VERIFIED FIXED**: exact raw delta/removals/version and no-op/converged call counts; editor retry patch recorded. Real-disk readback retained. |
| T-10 | Valid default-vs-concrete distinction | FIXED (qualified) | **PARTIALLY FIXED**: default exact-delta recording and unchanged key are tested; concrete full-map readback strengthened here. Concrete patch invocation itself is not intercepted. Its identical filter was inspected, not claimed as separately instrumented. |
| T-11 | Valid silent coverage loss | FIXED | **VERIFIED FIXED**: nonzero checks strengthened to require all six pinned writable fixtures and all three artwork fixtures. |
| T-12 | Valid dependency coupling | DEFERRED | **DEFERRED**: known-issue tests retain message substrings. On package upgrade these must be revisited as contract probes, not product guarantees. |
| T-13 | Valid weak performance assertions | PARTIAL | **PARTIALLY FIXED**: completion/concurrency bounds, actual readback, and fallback requests asserted. Some stress/timing tests remain observational or test wrappers. |
| T-14 | Valid weak proxy tests | DEFERRED | **PARTIALLY FIXED**: logging detector fails closed and has positive controls; source greps still do not establish runtime architecture or privacy. |
| T-15 | Valid high-risk missing coverage | MOSTLY FIXED | **PARTIALLY FIXED**: added real provider cancellation, track/disc total-only provider/CSV, fallback/replacement rejection, recovery publication, and progressive import coverage. Complete UI-to-file and real-volume failure scenarios remain absent. |
| T-16 | Valid | PARTIAL | **PARTIALLY FIXED**: new gates are bounded; quick-import start/return waits now fail on deadline; Test action pins locale. Older latches, sleeps/yield drains, and some restart tests remain. |

## E. Newly discovered or materially incomplete problems

All listed problems were corrected on the review branch. Source locations refer to final source; compare the referenced repair commit for the pre-correction behavior.

| Review ID | Severity / confidence | Trigger, consequence, source | Resolution |
| --- | --- | --- | --- |
| R-01 | High / reproduced | Original fingerprint lacks identity; same-path replacement or changed revision; priority/merge writes adopt fresh version and relabel another recording. `MetadataConflictResolver.swift:17`, `:51`, `:88`, `:153`; introduced by `10cd152b`. | `607f6bc3`: compare known components/size/time and require original opaque version without full identity, including editor baseline load. Two new real-file regressions cover typed/raw policies and replacement; they failed on the old fallback. |
| R-02 | Medium / reproduced | Cancel provider task after actual commit while reload is gated. Post-await guard drops success and omits remaining entries. `AudioViewModel+ProviderTaggingWrite.swift:21`, `:111`; incomplete `2f05bb15`. | `aa77e3ec`: account for result first; cancel before next entry; log remaining targets. Both real-file provider tests failed before correction and now compare full maps. |
| R-03 | Medium / reproduced | Queue reload, mark rename recovery refresh-required, then flush/late handoff. Writable old model replaces safety state. `AudioViewModel.swift:716`; introduced with `835cbf66`. | `890cd2f2`: remove queued observation, advance generation, invalidate scans; recovery mapping shares one tested helper. |
| R-04 | Medium / confirmed source and execution | Test factories do not control real `AudioMatorApp` initialization; several direct constructors still use default grant/log stores and SharedState writes real sort preferences. `AudioMatorApp.swift:23`, `AppDelegate.swift:7`, `AudioViewModelTestFactory.swift:15`, `SharedState.swift:95`. | `76a6dbb8`, `1bc1af64`, final test configuration: isolated Debug test host, complete store injection, isolated preferences, fail-closed suite construction, blank root view, ignore restoration. |
| R-05 | Low / reproduced by strengthened assertion | Skipped issue rows enter warning bucket and HUD calls them saved. `BatchMetadataOperationSummary.swift:73`, `:120`; introduced by `cf1f8e62`. | `87430b79`: distinct skipped bucket, accurate text, log includes skipped filenames. |
| R-06 | Medium / confirmed; injected outcome test | Renumber receives `.durabilityUncertain`, counts success but loses the warning and retry guidance. `AudioViewModel+TrackRenumbering.swift:156`; pre-existing omission. | `6b3ada73`: success retained, warning surfaced, one write attempt asserted. |
| R-07 | Low / confirmed; filesystem regression | Second corrupt history finds an existing `.corrupt` and is overwritten on append; failed backup also permits overwrite. `SaveIssueLogStore.swift:152`; incomplete `fabb3437`. | `3f9b83bb`: unique additional quarantine, no persistence when copy fails. Repeated corrupt histories and subsequent valid history tested; backup-permission denial branch inspected rather than fault-injected. |
| R-08 | Low / confirmed | Privacy documentation says persistent unrestricted WebView although repair changes it; in-app registry omits browsing. `NetworkServiceDisclosure.swift`, Web Content section of ONLINE_METADATA. | `127f7c1a` and final localization: shared allowed-host list, explicit browsing disclosure, session/subresource limits stated. No new network feature introduced. |

## F. Additional remediation and contracts

Ten focused implementation/test commits precede the final verification/documentation commit; see section I for exact hashes. Corrections retain the existing metadata pipeline and FileMutationCoordinator boundary. No commit retry, cleared expected version, replacement substitution, package patch, dependency upgrade, or main-branch modification was introduced.

The material contract changes are deliberately narrow: fallback files cannot automatically rebase changed revisions; cancelled provider plans report all their captured targets; skipped rows are not described as saved; corrupt diagnostic history is preserved before replacement; renumber reports a committed durability warning. Debug XCTest startup is isolated by the Test action only, and Release ignores the flag.

The total-only gate remains conditional on changing that pair, so existing unusual data is preserved during an unrelated edit. The new FLAC test proves this with an independent raw-map expectation. A refusal to write a requested standalone total is documented as a limitation, not reported as successful persistence.

## G. Final test-suite assessment

The repaired suite is materially more trustworthy. Edited-field assertions, seeded clear operations, artwork intent mapping, exact conflict patches, and write-attempt counts remove specific false negatives. Full-map expectations now also catch unexpected additions/removals. Fixture matrices fail if any member of the pinned expected set silently loses support.

New real-file tests use temporary FLAC copies, actual adapter writes, independent raw-map/byte comparisons, and a gate placed after commit. They prove cancellation preserves the actual disk outcome, untouched arrays/custom keys survive, unprocessed files remain unchanged, total-only requests do not reach writers, and untouched standalone totals do not block a title update. New URLProtocol tests prove real client fallbacks execute and return expected candidate IDs; no socket is opened.

Remaining risks: permissive orchestration fakes and synthetic fingerprints are still common; the concrete whole-map patch call is not intercepted; some dependency-known-issue assertions match messages; three source architecture tests and the logging scanner are proxies; some waits and yield drains remain nondeterministic. The rename test drives a transaction result into the production reconciliation helper, not a real permission-revocation scenario through the full UI. No claim of full UI acceptance or exhaustive workflow persistence is made.

Coverage gaps remain: AIFF/Opus fixtures, artwork outside MP3/M4A/FLAC, PNG/multiple image roles, malformed containers, real SMB/NFS/FUSE/file providers, sandbox bookmark grants, live networks, large representative libraries, and UI automation. The same package's reader/writer can conceal symmetric container defects; app-side mapping and complete raw expectations reduce that risk without eliminating it.

## H. Verification results

All results below were executed during this review; previous agent results are not counted.

Common Xcode options:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  CODE_SIGNING_ALLOWED=NO test
```

Focused runs add `-only-testing:AudioMatorTests/<class>` before the action. Logs are local ignored files under `.tmp/review/`.

| Run / log | Result |
| --- | --- |
| `swift test --filter AudioMatorCoreLogicTests` / `final-core.log` | 62 passed, zero failures. |
| Initial new identity regressions / `identity-before.log` | 33 selected tests, 21 failed assertions concentrated in the two new negative tests; replacement really wrote. Isolation/presentation tests passed. |
| Identity/editor correction / `identity-after.log` | 40 passed. |
| Initial provider cancellation regressions / `cancellation-before.log` | Two tests failed: no partial issue-log entry after actual disk commit. |
| Provider cancellation plus plan tests / `cancellation-after.log` | 14 passed. |
| Remaining constructor isolation / `isolation-callers.log` | 41 passed. |
| Recovery correction / `recovery-after.log` | 23 passed; the preceding new queued-recovery test failed before correction. |
| Summary/log/workflow / `skipped-summary.log` | 53 passed. |
| Disclosure/policy / `disclosure.log` | Four passed. |
| Provider/TagLib matrix / `provider-persistence.log` | 49 passed. |
| Provider semantic/cancellation, recovery, TagLib, network / `semantic-persistence.log` | 56 passed. |
| Final targeted renumber/import/log / `final-focused.log` | 24 passed. Test authoring corrections included explicit padding intent and checking the real 24-file partial batch threshold; no production behavior was changed to satisfy those assumptions. |
| Full serial suite / `final-full.log` | 472 passed, zero failures, approximately 49 seconds of test execution. |
| Final scheme/localization full suite / `final-config-full.log` | 472 passed, zero failures; English/US and restoration-isolated Test action. |
| Final source, including corrected new test-harness isolation / `final-clean-full.log` | 472 passed, zero failures; approximately 49 seconds. No actor-isolation warnings from the new provider/isolation harness files. |
| Unsigned Release generic build / `release-build.log` | Succeeded; stable Xcode 27.1; universal `x86_64 arm64` executable. |
| `bash scripts/validate-macos-artifact.sh .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0` | Passed: bundle minimum 15.0; executable minimum 15.0 and bundled TagLib framework minimum 13.0, both architectures. |

Release command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build
```

The initial sandboxed Swift and Xcode invocations failed to write user Library/Clang manifest caches. They were rerun with appropriate cache access; this was an environment failure, not diagnosed as a project defect. No HOME/CODEX_HOME substitution, alternate derived-data root, beta toolchain, package checkout edit, manual app launch, or bridge smoke script was used.

Warnings/limits: existing XCTest and test-double actor-isolation diagnostics appeared during recompilation under Swift 5/complete concurrency, and macOS test-host service/AVFoundation diagnostics appeared at runtime. The touched URLProtocol override and the new lock-protected provider test pipeline are nonisolated; new XCTest classes keep MainActor on their methods instead of inheriting actor-isolated initializers. No isolation warning was suppressed. The Release build emitted only the AppIntents extraction notice that no AppIntents.framework dependency was found; it succeeded. Unsigned build success does not establish signing, notarization, actual macOS 15 runtime behavior, or network-volume safety.

## I. Git summary

- Original base/main: `78d5f5e3`.
- Original local repair branch: `audit-repairs-2026-10` at `02810a2b`, tracking `origin/audit-repairs`.
- Exactly 32 original commits reviewed; all remain unchanged and ancestral to this review.
- Review branch: `review/audit-repairs-verification`, created from repair HEAD after confirming the original working tree was clean.
- Eleven additional commits in total: the ten focused commits below and the final verification/report commit.

| Commit | Message |
| --- | --- |
| `76a6dbb8` | test: isolate app-host startup and presentation preferences |
| `607f6bc3` | fix: refuse conflict rebasing without original file identity |
| `aa77e3ec` | fix: account for committed provider writes during cancellation |
| `1bc1af64` | test: isolate remaining direct view-model constructors |
| `890cd2f2` | fix: preserve refresh-required rename recovery against stale reloads |
| `87430b79` | fix: distinguish skipped rows from saved files in batch summaries |
| `127f7c1a` | docs: disclose restricted embedded browsing and session storage |
| `6b3ada73` | fix: surface committed durability warnings when renumbering |
| `3f9b83bb` | fix: preserve each corrupt issue log before replacing history |
| `98e5b7ad` | test: verify provider fallbacks and real-file metadata preservation |

The final commit, `test: finalize audit verification and document results`, records verified documentation, localized browsing disclosure, final Test action configuration, actor-correct test harness declarations, and this report. Its hash is obtained from `git log` after committing; the record intentionally does not contain a self-referential hash. Final intended state is clean, with no merge, history rewrite, push, or main change. These conditions are checked after the final commit.

## J. Remaining issues and merge readiness

### Must fix before merge

None known within the reviewed and exercised AudioMator paths after these corrections. This conclusion applies to the review branch including the additional commits, not the original repair HEAD. Maintainer UI acceptance remains separate.

### Safe to defer with explicit limits

- P-04/P-10/P-11: full enumeration, synchronous path/preview planning, and unvirtualized preview stacks. Measure representative libraries and volumes before selecting a cache/virtualization design; these remain significant scalability work.
- P-19: an indefinitely blocked synchronous commit keeps its reservation. A safe hard timeout requires package/process support; do not release a live writer's lock or claim an unknown outcome was not written.
- P-20/P-21/P-23/P-24: slow earlier import publication, renumber start clamp, dead helpers/inconsistent other batch cancellation policies, optional BOM/legacy encoding disclosure.
- T-06/T-10/T-12–T-16: broader persistence instrumentation, dependency probes, behavioral architecture checks, and remaining bounded-wait cleanup.
- WebKit subresource hosts and Apple artwork hosts are not fully restricted; accurately disclosed. No claim of full browsing-network confinement.

### External dependency action

Pinned package: TagLibAudioMetadata **0.5.3**, revision `03473c9ae199026b806a5f75c387ca036e325284`; exact requirement and resolved pin verified.

1. **MP3 disc-only public `applyMetadataPatch` number-text path:** seed `07/12` and `02/03` on the MP3 fixture, change only disc text, retain expected version. Observed verification rejects an untouched TRACKNUMBER representation change and preserves original bytes. Expected: disc changes while untouched track structure is preserved. Package owner should add a disc-only patch regression asserting complete untouched raw-map preservation and successful round trip.
2. **AAC total clearing through number-text patches:** seed a number and total, request number without total/clear a total. Observed verification retains the old total and rejects safely. Expected: explicit total-clearing intent round-trips or is rejected before mutation with a documented unsupported contract. Package owner should add track/disc clearing tests and byte-preservation assertions on failure.
3. **Standalone totals/multi-artwork:** existing dependency-limitations documentation records observations; comprehensive support was not established in this review. Do not infer internal causes or bypass verification. Package owner should define accepted typed representations and normalization, then add independent-number and multi-role artwork round trips.

Minimal AudioMator reproductions and current safe-failure expectations are in `TagLibReadWriteIntegrationTests.testFieldTransferNumberCombinationsRoundTripOrFailWithoutChangingFile`, `testFieldTransferCutNumberWithoutTotalRoundTripsOrPreservesFileOnFailure`, and [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md). No package work was attempted.

### Product/design decisions

- Whether high-confidence lyrics auto-apply needs an overwrite opt-in or review step.
- MusicBrainz recording-vs-release-track field semantics.
- Independent standalone-total support through a verified package contract.
- Move-stable MuseAmp identity and application undo/pre-write snapshots.

**READY WITH CAVEATS:** the demonstrated review blockers are corrected and the automated checks pass. The remaining items above are bounded limitations or product/dependency work; passing this review does not turn them into verified capabilities.
