# Independent Reassessment and Remediation

Date: 2026-10-18. Baseline: `review/audit-repairs-verification` at `a60f3064`. Remediation branch: `review/reassessment-remediation`. This is a dated engineering record; current contracts live in Architecture, Development, Product and Security documentation. The supplied third-party reassessment was a checklist, not a specification. Earlier reports were preserved.

## A. Executive Summary

**NOT READY TO MERGE.** Recovery/publication, renumber eligibility, cancellation, validation explanations, CSV compatibility and test-host isolation have been repaired and verified. One independently reproduced audio-content identity defect remains. The regression is enabled, asserts rejection and unchanged bytes, and fails; it was not skipped, marked expected-failure or weakened to obtain a green suite.

The report was substantially correct about automatic refresh removing safety state, unguarded deferred/rename publication, refresh-required renumber gaps and inconsistent cancellation. Its non-numeric-number recommendation requires correction: a public-API probe demonstrated that the pinned package rejects non-numeric number-text components before mutation. Allowing those inputs through would not add support. Its whole-map testing claim also missed an existing concrete-adapter complete-map integration test.

The unresolved defect is concrete: a temporary WAV's PCM samples are replaced in place, retaining path/device/inode/size and restoring mtime. Every automatic conflict policy accepts a stale title draft and modifies that replacement audio. Manual reload policy rejects the revision change in the same reproduction. Filesystem object continuity and a fresh metadata revision do not establish audio-content continuity.

## B. Independent Finding Validation

Original severity/confidence below comes from the supplied reassessment. Final classifications describe this investigation; “resolved” means the verified repair is committed, not that every possible environment was tested.

### New production findings

| ID | Report severity / confidence | Independent classification and evidence | Remediation / final status |
| --- | --- | --- | --- |
| N-01 | High / confirmed source-path | **CONFIRMED**, production safety-state bypass. Activation and rescan accepted new writable snapshots over recovery decisions. Stale editor targets also retained their old writable flag. | Resolved: independent recovery-ID storage, preserved automatic observations, explicit verified recovery, and shared executor check after reservation acquisition. Tests exercise activation, rescan, explicit reload, stale raw targets and queued typed writes. |
| N-02 | Medium / confirmed source-path | **CONFIRMED**, persisted numbering defect. Capability filtering omitted recovery eligibility; the inner guard consumed preassigned numbers. | Resolved: one eligible assignment set; recovery failures accounted before directory authorization. First/middle blocked-target tests assert actual `01`, `02` writes. Runtime write failures still consume their planned number, deliberately avoiding timing-dependent reassignment. |
| N-03 | Medium / high confidence | **CONFIRMED**, inconsistent publication architecture. Deferred values lost generation; rename directly replaced arrays. Related quick-import observations and failed scan fallbacks also needed consistent ordering. | Resolved: common acceptance gate, generation-bearing pending values, guarded flush, scan generations/token/epoch, immediate move-path publication, captured readback generations and ordered imports. Failed reads retain the latest accepted pending commit without claiming a new metadata observation. |
| N-04 | Medium / high confidence | **PARTIALLY VALID**, misleading diagnosis; support is **DEPENDENCY-LIMITED**. The concrete adapter rejected `A1/13` with extractor code 245, requiring unsigned decimal components at most 2147483647. No mutation occurred. | Resolved actionable app defect: dedicated unsupported-text explanation, separate from missing-number totals. Real FLAC tests cover `A1/12`, `A1` plus total and `B2` plus disc total, rejection bytes and unrelated title preservation. Non-numeric semantic writes remain unsupported. |
| N-05 | High impact / potential consequence, high confidence | **CONFIRMED**, demonstrated integration safety defect. `StableInodeContentReplacementTests` replaces the RIFF data chunk with different valid PCM samples and proves the complete fingerprint is unchanged. All three automatic policies write the stale draft; byte preservation assertions fail. | **UNRESOLVED BLOCKER.** External audio-identity contract is absent; dependency work or a separately designed app payload-identity implementation is required. The package version remains opaque. See G for alternatives and next steps. |
| N-06 | Medium / confirmed source-path | **CONFIRMED**, inconsistent batch cancellation. Detached renumbering ignored parent cancellation; other loops continued invoking per-file execution. | Resolved: cancellation inherited by renumber loop; provider/filename/CSV/raw loops account for all remaining entries before stopping. The per-file commit lifecycle remains detached and reserved until outcome/readback is known. Real-file tests exercise six workflows after commit and while queued. |
| N-07 | Low / high confidence | **PARTIALLY VALID**, compatibility gap rather than incorrect strict schema validation. Common external labels were absent; arbitrary cross-locale translation is not an established contract. | Added explicit `Name`, `Comments`, `Track #`, `Disc #`, `Disk Number` and related English aliases. Order/field identity remains strict. Tests verify external headers and rejection of reordered aliases. Other export-language labels remain a documented limitation. |

### New test findings

| ID | Report severity / confidence | Classification, evidence and final disposition |
| --- | --- | --- |
| TF-01 | High / confirmed | **CONFIRMED missing tests**, now supplemented with activation, watched scan, explicit recovery, stale target and queued-writer tests. The earlier queued-reload test remains useful. |
| TF-02 | Medium / confirmed | **CONFIRMED missing eligibility case**, now first/middle refresh-required targets with recorded number text and complete result accounting. |
| TF-03 | Medium / high confidence | **CONFIRMED coverage gap**, corrected using concrete public-API rejection/unchanged-byte checks and complete raw-map comparison after unrelated edits. The expected unsupported grammar is established by observed behavior, not package source. |
| TF-04 | Medium / confirmed gap | **CONFIRMED**, now gated late rename/readback, deferred-vs-rescan, stale import-vs-commit and failed-scan-vs-pending tests. |
| TF-05 | Medium / confirmed | **PARTIALLY VALID**. An identical-byte replacement is a legitimate test of filesystem-object replacement, not a vacuous test. It does not prove audio-content continuity. Retained it and added an independently constructed different-PCM, same-inode reproduction. The stronger test remains red. |
| TF-06 | Medium / confirmed gap | **CONFIRMED**, now inspect weak references to actual app-owned models, not just factories. Views and About commands share isolated test preferences. Debug custom-runner flag and Release exclusion are covered by policy tests; the Release binary also compiles. No UI interaction was performed. Preview construction remains outside the test-host guarantee. |
| TF-07 | Low / confirmed | **CONFIRMED weak oracle**, replaced self-derived expected hosts with a separate literal inventory checked against current request-builder constants and navigation policy. Existing URLProtocol client tests remain independent execution evidence. Arbitrary Apple-returned artwork and WebKit subresource hosts are explicitly outside an exhaustive static inventory. |
| TF-08 | Medium / confirmed claim | **PARTIALLY VALID**. `testLosslessRawValueMapPreservesArraysDuplicatesWhitespaceAndLiteralSemicolons` already exercised concrete `writeRawMetadataValueMap` with complete-map equality at baseline. This review adds deletion, title replacement and native artwork preservation. Concrete invocation interception is still absent; externally observable adapter behavior is tested. |
| TF-09 | Low / confirmed | **CONFIRMED missing scenarios**, supplemented with queued cancellation for both providers and four other batches, zero actual write calls, complete unchanged raw maps, and correct failed-target/log accounting. Executor tests cover cancellation after reservation and reservation lifetime. |
| TF-10 | Low / confirmed | **CONFIRMED limitation**, source-policy tests retained as supplemental checks. Behavioral publication/recovery/cancellation coverage now supports critical policies. New commit/readback ordering uses explicit gates with bounded entry waits; some older polling/sleep tests remain. No wholesale rewrite was justified. |

### Previous production concerns included by the reassessment

The supplied report did not restate original severities/confidence for these IDs. They are not invented here. Current source and the fresh complete suite were checked; prior test counts are not reused as evidence.

| ID | Independent classification / final state |
| --- | --- |
| P-01 | **CONFIRMED incomplete repair**, resolved by N-03 acceptance/epoch/generation work, including imports and failure fallback. External scans remain non-atomic observations. |
| P-02 | **PARTIALLY VALID**. LRCLIB store uses `isHighConfidenceAutoMatch`; low-confidence auto-selection defect is already resolved. Replacing existing lyrics after explicit Auto Apply is a product policy; no unsolicited policy change. |
| P-03 | **PARTIALLY VALID**. Silent total-only loss is already prevented by shared semantic/transfer validation. N-04 explanation corrected; support remains dependency-limited. |
| P-04 | **PARTIALLY VALID performance concern**. Scanner reuses fingerprint AND package-version matches, but enumerates the whole folder. No representative network-volume benchmark; safe to defer measured optimization. |
| P-05 | **ALREADY RESOLVED** ordered header identity validation. N-07 adds compatibility without positional reinterpretation. |
| P-06 | **DEPENDENCY-LIMITED**. MP3 untouched-track and AAC total-clearing fixture failures are rejected with original bytes preserved. No package workaround or pin change. |
| P-07 | **ALREADY RESOLVED** missing advisory is absent intent, not a clear. Provider-plan and seeded advisory tests remain. |
| P-08 | **CONFIRMED incomplete recovery repair**, resolved by N-01/N-03 and shared reservation-boundary checks. Real permission/volume rollback behavior remains unverified. |
| P-09 | **ALREADY RESOLVED** shared pair parser splits slash-containing input instead of concatenating malformed pairs. |
| P-10 | **UNVERIFIED practical performance impact**. Plan/path work exists; no broad cache refactor without representative evidence. |
| P-11 | **UNVERIFIED practical performance impact**. Unvirtualized preview stacks exist; workload/UI measurements are needed before prioritizing redesign. |
| P-12 | **ALREADY RESOLVED** separate skipped bucket/HUD/log. An all-skipped direct apply returns nil; the UI disables apply when no entries are ready. This internal edge is not demonstrated silent user-data loss. |
| P-13 | **PARTIALLY VALID**. Conservative missing-device/inode revision continuity already works; stronger audio-content continuity is still blocked by N-05. Neither guarantee is substituted for the other. |
| P-14 | **ALREADY RESOLVED** MusicBrainz stale-ID fallback and retained candidate list; mocked real client paths tested. |
| P-15 | **ALREADY RESOLVED** iTunes stored-ID fallback and supported link forms. Duplicate/dead parsing code is maintenance debt, not a reproduced blocker. |
| P-16 | **UNVERIFIED desired entity contract / product decision**. Workbench mapping is inspectable, but intended recording-versus-release-track identity requires a documented integration contract; IDs were not guessed. |
| P-17 | **ALREADY RESOLVED** nullable release body and nil-safe consumption; decoding test passes. |
| P-18 | **ALREADY RESOLVED** HTTPS provider-page allow-list/non-persistent storage/disclosure. Subresources are not restricted and Apple artwork URLs may name additional hosts; documented, not claimed as a firewall. |
| P-19 | **UNVERIFIED environmental hang; dependency limitation**. Synchronous commit is not safely cancellable. A timer must not release its mutation reservation while the writer may remain active. Readback alone is bounded. |
| P-20 | **ALREADY RESOLVED reported failed-index stall**. Resolved indices advance the contiguous cursor after failures. An earlier genuinely pending load still gates later contiguous publication, an intentional ordering tradeoff. |
| P-21 | **CONFIRMED incomplete repair**, resolved N-02 refresh eligibility. Existing start normalization remains established product behavior. |
| P-22 | **ALREADY RESOLVED** unique corrupt-log quarantine and disabled persistence after preservation failure; in-memory history continues. Deliberate preservation tradeoff, not an overwrite defect. |
| P-23 | **CONFIRMED incomplete cancellation consistency**, resolved N-06 for the named writers. Dead code cleanup remains non-blocking maintenance. |
| P-24 | **PARTIALLY VALID**. Apostrophe protection round-trips. UTF-8 CSV without BOM is valid. BOM-aware UTF-8/UTF-16 and legacy fallbacks exist on import; silent fallback selection remains a usability concern. No unsupported claim that a BOM is required. |
| P-25 | **NOT A DEFECT** under current documented path-derived MuseAmp identity. Move-stable product identity would be a different contract. |
| Undo | **NOT A DEFECT under the present feature contract**, but no pre-write snapshots or application undo is a material product limitation. Issue logs are not backups. |

### Previous test concerns included by the reassessment

| ID | Independent classification / final state |
| --- | --- |
| T-01 | **ALREADY RESOLVED**, edited title is asserted with full raw-map expectations. |
| T-02 | **ALREADY RESOLVED**, seeded clear/erase values and named-field readback; does not establish removal of every native structure. |
| T-03 | **ALREADY RESOLVED**, advisory seeded, cleared, and raw removal verified. |
| T-04 | **ALREADY RESOLVED**, actual write-boundary preflight and no-writer assertion. |
| T-05 | **ALREADY RESOLVED** app patch mapping and supported artwork fixture round trips; multi-role/other-format limitations remain. |
| T-06 | **PARTIALLY VALID**, many orchestration fakes intentionally use synthetic revisions. New persistence/cancellation/number/identity coverage uses real temporary fixture copies; synthetic tests are not claimed as persistence proof. |
| T-07 | **CONFIRMED incomplete lifecycle coverage**, strengthened by actual app-owned model diagnostics and view/command preference isolation. Previews are not included. |
| T-08 | **ALREADY RESOLVED**, desynchronized owner guard is reached and no write occurs. |
| T-09 | **ALREADY RESOLVED**, patch/version/removal and no-op write-attempt assertions remain. |
| T-10 | **PARTIALLY VALID instrumentation gap**, complete concrete-map behavior already tested and strengthened; protocol recording is not described as concrete interception. |
| T-11 | **ALREADY RESOLVED**, explicit six writable and three artwork fixture membership/count expectations. |
| T-12 | **CONFIRMED test coupling**, corrected named integration checks to typed `TagLibManagerError.verificationFailed` plus byte preservation instead of English substrings. Success unexpectedly replacing a known failure still fails the contract test for review. |
| T-13 | **PARTIALLY VALID**, stress/source assertions remain limited sensors; actual write counts/maps/gates supplement them. No claim of representative large-library performance. |
| T-14 | **PARTIALLY VALID**, source-policy tests retained; critical runtime invariants now have behavioral coverage. |
| T-15 | **CONFIRMED missing cases**, substantially improved by N/TF coverage; audio identity remains a failing test, and UI/real-volume scenarios are unverified. |
| T-16 | **PARTIALLY VALID**, new gates bound the start wait and control ordering; older bounded polling, locale-pinned assertions and some unbounded historical latches remain technical debt. |

Prior R-01 missing-identity rejection remains intact, but is not audio identity. R-02 cancellation is extended to the named batches. R-03 recovery/publication and R-04 actual host/view isolation are strengthened. R-05 skipped summaries, R-06 durability warnings, R-07 corrupt-log preservation and R-08 browsing disclosure remain intact. R-09/R-10 constructor isolation/prior verification were rechecked through fresh tests; old results were not treated as this review's results.

## C. Root Causes and Architectural Conclusions

The systemic weakness was real: snapshots carried both observed metadata and recovery authority, while immediate refresh, deferred refresh, rename, scans and imports used different publication rules. The implementation now separates sticky session recovery decisions from snapshots and shares generation acceptance across observations. Pending commits retain their accepted generation. Folder token/epoch checks still guard both asynchronous scan stages. Failed reads do not manufacture newer authority. Move paths are published before awaiting readback; old pending URLs cannot return afterward.

The mutation executor checks session recovery authority after acquiring a reservation. This closes stale Inspector/raw-target and queued-writer bypasses. There is no await between the detached synchronous writer's validation and write; cancellation is checked after asynchronous preflight and before starting that writer. Once the writer starts, the reservation remains held through the actual outcome and bounded readback. No failed commit is retried or stripped of its expected version.

This is not a transactional filesystem snapshot, a continuous watcher or a proof against external writes after the last check. External processes do not participate in the app coordinator. Audio-content identity remains separate and unresolved; generations cannot repair it.

## D. Implemented Repairs and Commits

| Commit | Change, source and verification |
| --- | --- |
| `f0f86fb4` | `AudioViewModel.swift` / `+FileReload.swift`: sticky recovery, common observation acceptance, pending generations, scan/rename ordering. Activation/explicit reload/scan/pending-move tests; 30 focused tests passed. |
| `f0f58a81` | `+TrackRenumbering.swift`, plan/raw/provider writers and `BatchMetadataOperationSummary`: eligible numbering, inherited cancellation, remaining-file accounting. Real-file batch and renumber checks; 12 focused tests passed after correcting a test-only zero-success wording expectation. |
| `89109eb5` | `AudioMetadataPipeline.swift`, `NumberTextDependencyContractTests`: accurate non-numeric limitation, preserved unrelated values; included in 84 passing contract tests. The initial unsupported-input probe failed with extractor validation before the safe limitation was codified. |
| `a580b29a` | `AudioMatorApp`, `AudioMatorTestHost`, Content/Settings views and About commands: process-consistent isolated preferences, actual host diagnostics, custom Debug runner detection, Release exclusion. Included in 84 passing tests. |
| `5708cd0e` | Explicit external CSV aliases; independent literal host inventory; concrete-map deletion/title/artwork checks. Included in 84 passing tests. |
| `f2be0a77` | Imports capture observation generation; scan failure fallback keeps accepted commit; gated late rename/import tests; typed dependency-error checks. 61 focused tests passed. |
| `b5add47f` | Shared executor recovery validation after reservation, stale editor/queued writer test, caller cancellation check before detached work; new test-class isolation annotations corrected. 31 focused tests passed before final full verification. |
| `7e494046` | Strengthened the concrete whole-map test with an explicitly seeded JPEG, nonempty artwork/data assertions, and preservation through both map writes. One focused test passed after the full run; no production code changed. |

The final evidence commit retains the failing audio-identity regression, updates current limitation/security guidance and this record. No dependency source, pin, main branch or previous commit was altered.

## E. Test Suite Improvements and Limits

New tests exercise actual production paths: selected-file refresh, watched scans, shared rename publication, typed/raw mutation dispatch, plan loops and renumbering. Cancellation tests gate readback after a real commit, assert one write and complete first/untouched-second raw maps; queued cases assert zero writes across six workflows. They account for successes, failures and unprocessed entries. Recovery tests separately verify explicit recovery can exit the blocked state. The new WAV test edits the actual RIFF audio-data chunk, not metadata or an identical copy.

Native structure verification is bounded: whole-map FLAC checks include artwork; it is not a proof of every container-native structure. The same package's read/write APIs can conceal symmetric defects. Source tests remain supplemental. No UI acceptance, real sandbox bookmark grants, network volumes, live providers, malformed-container matrix, AIFF/Opus fixtures or broad multi-role artwork matrix was added or claimed.

## F. Verification Results

All results below were executed in this assignment using Xcode 27.1 (27A9275) at `/Applications/Xcode.app`. App deployment remains macOS 15.0; Swift 5 language mode, complete strict concurrency and MainActor default isolation are unchanged. `TagLibAudioMetadata` remains exactly 0.5.3 / `03473c9ae199026b806a5f75c387ca036e325284`. The SwiftPM target is the selected Foundation-only subset, not the app module.

| Verification | Fresh result |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AudioMatorCoreLogicTests` | Final run: **62 passed**, zero failures. Repeated after the shared recovery-error change. |
| Recovery/publication focused groups | 30 passed initially; later 61 passed including import/failure fallback, late rename and integration checks. |
| Batch/renumber/semantic focused group | **12 passed** after a test-only correction: zero successes are summarized as “No files were saved”, not “0 of 2”. |
| Number-text/host/CSV/disclosure/concrete integration group | **84 passed**. Initial number-text support probe failed with extractor code 245 before codifying safe rejection; no production check was weakened. |
| Reservation-boundary recovery/cancellation/renumber/number-text group | **31 passed**, including the stale-target and queued-writer recovery test. |
| Final full serial Debug app-hosted suite | **488 tests executed: 487 passed, one failed with six assertion failures.** All six are in the enabled different-PCM automatic-policy regression (three policies × expected rejection and unchanged bytes). Manual-reload control passes. |
| Final identity-only rerun after moving baseline/version unwraps outside the expected-error assertion | **2 executed: one passed, one failed with six assertions**, confirming the test cannot pass merely because a baseline is absent. Log: `.deriveddata-codex/reassessment-identity-final.log`. |
| Whole-map test tightened after full run, without changing production code | **1 passed**. Explicit JPEG seeding, nonempty artwork/data preconditions, addition, deletion, exact full-map and artwork readback. |
| Direct unsigned generic Debug build | **BUILD SUCCEEDED**. |
| Direct unsigned generic Release build | **BUILD SUCCEEDED**. |
| macOS artifact validation and executable architectures | **Passed**: bundle/app minimum 15.0; bundled TagLib framework minimum 13.0; both Mach-O files are macOS. Release executable is universal `x86_64 arm64`. |

Final full-suite command (no skipped test or expected-failure annotation):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  CODE_SIGNING_ALLOWED=NO test
```

Focused runs used the same command with `-only-testing:AudioMatorTests/<Suite>` for the suites described above. The full suite included every suite and the unresolved reproduction. The final full result bundle is `.deriveddata-codex/Logs/Test/Test-AudioMator-2026.10.18_16-07-22-+0800.xcresult`; final logs use `.deriveddata-codex/reassessment-full-final.log` and `reassessment-core-final.log`. These local build/test outputs are ignored and not committed.

Build commands, both configurations executed separately:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex CODE_SIGNING_ALLOWED=NO build

bash scripts/validate-macos-artifact.sh \
  .deriveddata-codex/Build/Products/Release/AudioMator.app 15.0
lipo -archs .deriveddata-codex/Build/Products/Release/AudioMator.app/Contents/MacOS/AudioMator
```

The first sandboxed Xcode/SwiftPM attempts could not write user compiler/manifest caches; reruns with appropriate access succeeded. No cache relocation, package patch, dependency upgrade or beta toolchain was used. Existing repository test-isolation/deprecation warnings remain; newly added XCTest classes use nonisolated class identity with MainActor test methods rather than suppressing warnings. Unsigned builds do not verify signing, notarization or macOS 15 runtime compatibility. No tests were claimed solely from another agent's results.

## G. Remaining Issues

### Must fix before merge

**N-05: audio-content continuity for automatic conflict resolution.** The enabled automatic-policy regression is red. The same identity validation and fresh-version adoption pattern is shared by typed and raw conflict resolution; the executed different-PCM reproduction directly establishes typed-write impact. The manual-reload-policy control passes. This is not classified as merely theoretical or automatically acceptable because the package is external.

Required next engineering work:

1. Establish a metadata-independent audio-payload identity contract. A package-owned token in `MetadataSnapshot` is a suitable boundary because it understands the containers; an app-owned implementation would need equivalent format and normalization coverage.
2. Capture original payload identity at the baseline; compare it with a coherent current snapshot before any automatic rebase. Keep the final exact expected-version commit guard. When payload identity is unavailable, require explicit user reload instead of treating a successful read as continuity.
3. Add same-payload/changed-metadata positive tests and different-payload/same-inode negative tests for typed and raw policies, with format coverage and measured I/O costs.

No speculative digest was added. A whole-file hash includes legitimate metadata updates and would make the existing metadata merge policies reject their intended use. Size/mtime rejection has the same false-rejection problem and can be defeated by restoring mtime, as this reproduction does. Decoding/hashing all audio during every import would add unmeasured large-file/network-volume cost and codec-coverage dependencies. Silently disabling all automatic conflict policies would be a substantial product-contract change rather than a narrow repair. A deliberate conservative reload-only release policy could be chosen and implemented as an alternative, but is not claimed here as already authorized product behavior or a completed identity fix.

This is an integration contract requirement, not a diagnosed package-internal defect. The package owner should add a public audio-content token and tests that preserve it across metadata-only edits, change it across in-place payload replacement, and bind its computation to snapshot/transaction revision checks. AudioMator's minimal runnable reproduction is committed in `StableInodeContentReplacementTests.swift`; no package checkout access is needed.

### Safe to defer

Representative large-library/network-volume benchmarks, preview virtualization, path/plan optimization, duplicate/dead code cleanup, broader behavioral replacements for source-policy tests, and the all-skipped internal apply edge. None has a demonstrated new data-loss consequence in this review.

### External dependency limitations

Total-only and non-numeric semantic number-text support, MP3 untouched-track normalization, AAC total clearing and multi-artwork role replacement remain restricted or safely rejected. Synchronous commit cancellation needs a cancellable/isolated writer before a hard timeout can safely release reservations. These limitations do not justify clearing versions or retrying commits.

### Product decisions

Lyrics overwrite review after explicit high-confidence auto-apply, MuseAmp move-stable identity, MusicBrainz entity semantics, automatic legacy-encoding disclosure, undo/pre-write backups, and a possible temporary reload-only conflict policy. No unrelated feature was added.

### Unverified environments

Signed/notarized distribution, actual macOS 15 runtime, CI runner provisioning, live services, real file-provider/SMB/NFS/FUSE behavior, sandbox bookmark restoration and interactive UI acceptance. Automated tests launch only their host; the app was never launched manually or inspected interactively.

## H. Git Summary

- Main/base: `78d5f5e3`; main had zero commits beyond the reviewed branch's merge base.
- Prior branch/HEAD: `review/audit-repairs-verification`, `a60f3064` (43 commits ahead of main; original repair HEAD `02810a2b` and all 11 subsequent review commits present).
- Initial working tree: clean. Local `audit-repairs-2026-10` / saved `origin/audit-repairs` were `02810a2b`; review / saved `origin/audit-repairs-verification` were `a60f3064`; main / saved `origin/main` were `78d5f5e3`. These are local/tracking observations, not a claim of a fresh server fetch. No fetch, merge or remote mutation was needed.
- New branch: `review/reassessment-remediation`, created from that exact HEAD. Existing history was preserved without amend/reset/squash/reorder.
- New implementation commits: listed in D. The final evidence commit adds this report and the unresolved regression.
- Final HEAD: the evidence commit containing this report; resolve with `git log -1 --format=%H -- Docs/Engineering/REASSESSMENT_REMEDIATION_2026-10-18.md` (avoids embedding an impossible self-referential commit hash).
- Final worktree/main/ancestry check: Clean after committing intended changes; main remains `78d5f5e33e7a10669088bc93d487661ac6505a7c`; `a60f3064` remains an ancestor; branch is 52 commits ahead of main (43 preserved + 9 new), zero behind. Verified with status, rev-parse, merge-base and rev-list commands.
- No merge, push, force-push, dependency-pin change or package-source inspection/modification. All Xcode builds used `.deriveddata-codex` and stable `/Applications/Xcode.app`.

## I. Final Merge Decision

**NOT READY TO MERGE**

The repaired recovery, ordering and cancellation paths have fresh positive evidence. The independent audio replacement reproduction establishes a remaining high-consequence write to different audio under automatic conflict policies. Its failing regression remains in the suite. Integration should wait for a payload-identity guarantee or an explicitly designed conservative conflict-policy change, followed by green meaningful negative and positive tests. Successful compilation and other passing tests do not override that demonstrated blocker. No merge was performed.
