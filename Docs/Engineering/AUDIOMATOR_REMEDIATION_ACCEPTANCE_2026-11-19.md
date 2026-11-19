# AudioMator audit remediation — engineering acceptance and handoff (2026-11-19)

**Status.** Implementation-side record for independent review. The independent reviewer named by the
[acceptance specification](../Development/REMEDIATION_ACCEPTANCE.md) owns the disposition; the
maintainer owns any later release decision. This record covers automated evidence only: no signed,
notarized, installed or interactive UI acceptance is claimed. Per the campaign instruction, the
temporary implementation specification and acceptance checklist are removed **after** reviewer
acceptance; this record is retained.

## Candidate

| Item | Value |
| --- | --- |
| Branch | `remediation/audit-2026-11-18`, created from `518721404cf280befca370abe86a1d8a53721f68` |
| Tested/cold-build source revision | `74466f0a` (42 commits from base; clean tree; disposable-checkout archive identity recorded) |
| Final full-gate revision | `247c8ed6` (44 commits; the later acceptance-record commit is documentation-only) |
| Working tree | clean at the revisions above; no build artifacts or `.tmp` evidence are tracked |
| Toolchain | stable Xcode 27.2 (27B52), Swift 6.4.2, macOS 27.2.1 arm64 (8 CPU), `.deriveddata-codex`, serial app-hosted tests |
| Package | `TagLibAudioMetadata` exact 0.8.1, revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`, normal committed `Package.resolved`; no local checkout, override, or modification was used |

## Automated verification at the handoff candidate

| Gate | Result | Evidence |
| --- | --- | --- |
| Final full gate `bash scripts/validate-release.sh` at `247c8ed6` | policy passed; core `accepted: true, expected 97, executed 97`; app-hosted `accepted: true, expected 1010, executed 1010`, zero missing/unexpected/skips/failures; unsigned Release build passed; artifact validation passed | `.deriveddata-codex/Validation/20261119-215753-46405/` (`source.txt`, `app.log`, `app.xcresult`, `core`, `release`, `artifact` outputs) |
| Earlier full gate at `aaeb9b23` | policy 29/29; core 88/88; app 994/994 exact identity; unsigned Release + artifact passed | `.deriveddata-codex/Validation/20261119-183535-17055/` |
| Cold isolated Debug `build-for-testing` from disposable `git archive` of `74466f0a` | `** TEST BUILD SUCCEEDED **`, 0 errors | `.tmp/t2-evidence/cold-debug.log` (sha256 `06f0c302…`) |
| Cold isolated Release `build-for-testing` (with verification-only `ENABLE_TESTABILITY=YES`) from the same archive | `** TEST BUILD SUCCEEDED **`, 0 errors | `.tmp/t2-evidence/cold-release2.log` (sha256 `a33e7f2e…`) |
| Compile-clean diagnostic extractor over both cold logs | `accepted: true`; zero forbidden diagnostics in **both** targets and **both** configurations (actor-isolation, autoclosure, cross-isolation, implicit-async, implicit-strong-capture, isolated-conformance, override-isolation, Sendable-capture, Swift-6-migration). Package/toolchain/linker diagnostics are reported separately and were not suppressed | `.tmp/t2-evidence/cold-diagnostics.json` (sha256 `6d0ec7af…`), `cold-diagnostics.md`, `cold-candidate-identity.txt`, `cold-evidence-hashes.txt` |
| Core fast suite | `swift test --filter AudioMatorCoreLogicTests` = 97/97; Quick Import filter 24 tests re-verified during fixes | `.deriveddata-codex/Validation/…/core*` |
| Focused package suites | 287/287 app-hosted focused gate for the completion wave (Quick Import budgets/performance, AM-06 draft races, rename/journal/readback, Inspector draft/session, serialization/policy); F5 final 36/36 standalone + core 27/27; AM-04 harness 12 scenarios / 63 assertions | `.tmp/remediation/logs/`, `.tmp/t2-evidence/`, `.tmp/f5-task51-runtime.log` |

Performance bound at the handoff candidate was re-measured on an idle host after a false failure under
external host load: 1000-file batch save 1.75 s, 32 collection/19 progress publications; 4000-file
batch save 72.3 s with 125 collection publications and 669 progress publications, inside the reviewed
120 s/1000-publication bounds. The performance test is deterministic in counts and only the save
deadline is wall-clock; when the host is externally loaded the deadline can fail, which is why the
cold-build and gate evidence above was produced with the machine otherwise idle.

## Dispositions by finding

Evidence names are the current production boundary the tests exercise; see the audit evidence for the
historical baseline reproductions.

| Finding | Package | Disposition and primary evidence |
| --- | --- | --- |
| AM-01 imported removal deletes sibling total | E1 | Implemented. Typed exchange intents, frozen reviewed payloads, profile-scoped codec; real FLAC/MP4 disk matrix shows lone track/disc removal preserves the sibling total and audio identity, MP4 either writes or is rejected, and the old whole-pair negative control still fails. Baseline replay showed `0/0`. |
| AM-02 blank positional records shift values | E1 | Implemented. Positional framing/binder with typed captures; count-mismatch blocks the plan; two-target disk test asserts exact target IDs/counts and unchanged bytes on rejection. |
| AM-03 failed rename readback grants fresh revision | F1 | Implemented. Observations are the only write authority; failed full readback retains the display projection and a named recovery decision; real post-move save proves writing stays blocked, then succeeds after verified reload. Targeted-fault negative control (`.tmp/remediation/evidence/am03-negative-control.diff/.log`: 2-line fault, 13 tests/21 failures) and archived-baseline unsafe control (`.tmp/remediation/evidence/phase0-am03-baseline-control.log`) confirm the oracle catches the defect. |
| AM-04 interruption strands hidden staging names | F2 | Implemented. Durable versioned rename journal, exclusive-move service, startup classification and verified recovery UI. Real child-process termination evidence: `.tmp/remediation/evidence/am04-process-termination.md` — 12 scenarios / 63 assertions, self-`SIGKILL` children (exit 137) at production seams, sha256 oracles, refusal on foreign/stale/unrecognized identity, syscall-seam source-identity injection (`rolledBack`/`sourceChanged`, nothing moved), archived pre-journal baseline replay strands the staged name with no journal, restore is byte-identical and idempotent, committed records never roll back. Power-loss durability is **not** claimed; remaining manual lanes are listed below. |
| AM-05 stale LRCLIB match can write a newer file | N1 | Implemented. Seed-captured reviewed targets/intents, single session/generation owner, cancellation before public file mutation; real FLAC/M4A persisted readback preserves unrelated tags; `LRCLIBLyricsTests` 20, `LRCLIBLyricsSessionTests` 12. |
| AM-06 file/session change discards a live draft | F3 | Implemented. Session-owned draft with generations, pending review, clean-refresh and guarded plan-write completion. `InspectorDraftSessionTests` 13, `InspectorDirtyStateTests`, `InspectorAndMetadataEditorWorkflowTests`, and `DraftRaceExternalMutationTests` 5 gated cross-mutation scenarios (raw commit, rename readback, filename/exchange plan writes during a different live draft, hidden Quick Import rename publication). Residual success-path `updateEditForSelection` seams owned by E1/N1 files are reported, not silently changed. |
| AM-07 monitor reports active on old directory | F4 | Implemented. Descriptor identity captured on open, stale callback suppression by instance, rebind/status/cap/terminal logic; native `DirectoryMonitorIdentityTests` 15 and ViewModel `WatchedFolderMonitoringWiringTests` 11. |
| AM-08 LRCLIB auto-apply begins after close | N1 | Implemented. Close/dismiss/session change cancels outstanding requests and unstarted writes while preserving committed outcomes; gated non-cooperative provider and commit-boundary tests. |
| AM-09 generic Online Metadata queries before provider choice | N2 | Implemented. Explicit provider routing, zero generic calls on open, consume-once Find, search restart, activation-scoped cache, corrected `NetworkServiceDisclosure` values; `OnlineMetadataRoutingTests` 12. |
| AM-10 malformed MusicBrainz success blocks retry | N3 | Implemented. Responses validated before cache admission; typed numeric rejection of malformed/overflow/missing values; invalid responses are not cached and retry; coalesced/cancelled waiters and `Int.min` score-gap runner-up covered; `ProviderNetworkFaultTests` passes in the final suite. |
| AM-11 raw utility preview differs from apply | E2 | Implemented. Per-element raw value model, ordered entry add/remove/duplicate identity, stale-preview rejection, captured apply; `MetadataEditorRawValueArrayTests` 15 plus real fixture persistence readback. |
| AM-12 renumber planned sequence differs from submission | E3 | Implemented with the approved product decisions: shared reviewed plan, start at 1, 1–9999 clamp, no padding, numeric preview, unchanged rows not written; `TrackRenumberTests` 13, `TrackRenumberExecutionTests` 12, real FLAC/MP3/M4A round trips. |
| AM-13 large exchange preview redundant synchronous work | E4 | Implemented. Store-owned active plan and concurrent value planner with debounce/cancellation; controller-instrumented one-plan/zero-inactive dispatch and bounded 10k/100k benchmark without wall-clock thresholds; `MetadataFilenameConverterPlanTests` 19, `MetadataFilenamePlannerBenchmarkTests`. |
| AM-14 progressive Quick Import reindexes collection | F5 | Implemented. Ordered path index and refcounted scope leases in Foundation-only Core; one identity preparation per candidate, zero per-batch path work, original request-token admission/supersession, first-contiguous progressive publication, incremental replace/append, atomic rename/restore migration, stable IDs; owner-safe lease transfer (no over-stop, no fabricated grant, exactly-once stop) and request-identity pruning fixed from independent audits. 18+ core index/lease tests (24/24 Quick Import filter), `QuickImportCancellationTests` 11, `QuickImportProgressiveIndexTests` 21, `QuickImportProgressivePerformanceTests` 2; counters reproduced (audit 17,040/67,680 at 480/960; post-fix identityPreps = n, one parent key, publications ceil(n/batch)). Signed-sandbox scope grants remain a manual gate. |
| AM-15 build helper claims success without compiling | T1 | Implemented. Fail-closed `scripts/codex-build.sh` (discovery/status handling, relevant path coverage, marker only on successful compile, no implicit prune) plus 16 policy tests; archived-baseline negative control fails 25 sub-cases, fixed helper passes the same cases and a forced wrapper build was verified. |
| AM-16 CSV decodes unmarked apostrophes | E1 | Implemented. Profile-scoped CSV decoding, quoted/escaped literals preserved, marked-export codec unaffected; literal disk readback of apostrophes. |
| AM-17 iTunes results shared across storefronts | N3 | Implemented. Storefront-scoped results, detail cache and previews; `iTunesStorefrontScopingTests` 8 (same collection ID in US/JP, A→B→A counts, cancelled search, delayed detail across reopen, per-selection previews). |
| AM-18 artwork retry/destination draft | N4a/N4b | Implemented. Attempt identity/fault channels and same-candidate retry for downloads (`ArtworkLookupResponsivenessTests` 17, `ArtworkPreviewFallbackTests` 6); destination-draft transfer intents captured before every suspension for online and the six local handoffs, guarded commit revalidating session/command/targets/draft, stale-selection outcomes, unrelated edits preserved, clear/keep/newer commands supersede, disk untouched until Inspector Save (`ArtworkHandoffOwnershipTests` 5, real-fixture `ArtworkStagedSaveReadbackTests`). |
| AM-19 warning/isolation debt | T2 | Implemented. Two app-target ownership fixes (rename-recovery count helper, weak HUD captures + generation decision) and app-target isolation/Sendable fixes in eight files; whole app-hosted suite converted to explicit isolation (`nonisolated final` classes, explicit `@MainActor` members, nonisolated URLProtocol/fixture types, locked recorders, hoisted autoclosure reads). Cold Debug and Release builds have **zero** forbidden diagnostics (extractor accepted); `MetadataWriteHUDDismissalDecisionTests` 5 and `RenameRecoveryPresentationTests` 2 added. Named inventory is additive: 1010 app-hosted tests / 115 classes / 122 files vs 994 at the pre-T2 candidate; 0 removed or renamed. |
| C1 strict reviewed-target write boundary | C1/C2 | Implemented. `ReviewedMetadataTarget`/`ReviewedMetadataWrite`/projection/permit; every listed caller family migrated; S13 removed the legacy optional-version forwarding (`persistMetadataEdit`, legacy admission, optional executor overload) with source-policy tests (`LegacyWriteRouteRemovalPolicyTests`) banning them and production `expectedVersion: nil`; ADR 0006 records the boundary. |
| C1 operation lifetime/cancellation/publication | C1/C2 | Implemented. OSAllocatedUnfairLock commit permit, pre-commit revocation, caller-side cancellation handler, admission immediately before the writer, no unstarted-intent consumption, committed outcomes never retried/relabelled; cancellation/admission race and writer-cancel tests. |

## Regression oracles and negative controls

- AM-01: real post-write readback of untouched sibling total plus archived whole-pair control.
- AM-03: targeted fault in a disposable candidate copy; the reviewed oracle fails 21 assertions, while
  the archived baseline passes the unsafe behavior test.
- AM-04: real killed-process scenarios plus archived pre-journal baseline replay.
- AM-06: gated pipelines block external mutations at defined gates while a different live draft exists.
- AM-07: OS-backed directory replacements and stale-callback tests; in-place write limitation kept as a
  control.
- AM-15/T1: archived helper vs fixed helper on the same fail-closed policy cases.
- F5: counting adapters assert linear budgets independent of forced 24/48 batching; performance report
  records host/loader/cumulative+max MainActor batch cost/publications separately from wall clock.
- AM-19: two cold full builds plus the diagnostic extractor, not a grep of one log.

## Independent review trail

- [Phase-1 audit disposition](.tmp/remediation/design/PHASE1-INDEPENDENT-AUDIT.md) and
  [integrated audit](.tmp/remediation/design/INTEGRATED-INDEPENDENT-AUDIT.md) (candidate-derived
  blockers were fixed: AM-01/02/16, AM-11, AM-05/08, AM-10/17, AM-09, AM-13, AM-07, AM-12 accepted;
  AM-04/AM-06/AM-18 gaps closed in the completion wave).
- [Completion-wave audit](.tmp/remediation/design/WAVE-INDEPENDENT-AUDIT.md): found two real F5 defects
  (lease grant transfer, unpublished-key pruning) and documentation defects; all were fixed in
  `6ed11cb1`, `42ae40dd`, `a63a7984`, and the docs corrections commit.
- [Final verification A](.tmp/remediation/design/FINAL-VERIFICATION-A.md): accepted F5 fixes, AM-04
  matrix and docs; flagged R1 (lease double-stop residual), commit-provenance mixing and a stale ADR
  wording. R1 was fixed in `42ae40dd`; the F5 test additions are now committed with the test-target
  conversion; ADR wording was corrected in `f406de52`.
- Auditor checklists (acceptance specification rows) may use their own probes; the implementer's
  assertions and evidence are inputs, not the final disposition.

## Known limitations and remaining manual gates

- **Release/distribution:** unsigned build only. Code signing, sandbox entitlement enforcement on the
  installed app, notarization, Gatekeeper and distribution remain maintainer lanes. The signed
  security-scoped grant behavior of Quick Import/F5 (scope acquisition across relaunch/revocation) is
  simulated with an injected access adapter; the signed scenario is a manual gate.
- **Interactive UI:** no UI automation or manual app launch was performed. Inspector/pending-review
  interaction, Rename Recovery screen and artwork flow visual acceptance are maintainer verification.
- **AM-04:** process-termination is proven for the documented crash gates; power-loss/directory-barrier
  durability is not claimed. Journal metadata-error-after-move, live second-instance lock contention,
  syscall-seam failure injection variants beyond the covered source-identity case, and the explicit
  committed-record acknowledgement UI remain reviewer/manual lanes (also listed in the AM-04 evidence).
- **AM-06:** helper E1/N1 success-path editor refresh seams are reported as residuals; the AM-06
  regression set covers the required raw/rename/plan-write races and hidden-source rename publication.
- **Network:** no live network was used; provider behavior is exercised through URLProtocol and injected
  clients. Real provider availability/rate limits are not claimed.
- **TagLib package:** treated as an external dependency; no package checkout, cache or bridge smoke was
  touched. Package behavior beyond the pinned 0.8.1 contract is out of scope.
- **Diagnostic gate:** the AM-19 metric covers compiler diagnostics on repository sources in the app and
  app-hosted test targets in Debug and Release; package/toolchain/linker diagnostics are reported
  separately, never suppressed, and were zero in the cold builds.
- **Performance:** the batch-save deadline is wall-clock; an externally loaded host can exceed it
  (observed once, re-measured green when idle). Count-based budgets are deterministic.
- **Campaign documents:** `Docs/Development/REMEDIATION_IMPLEMENTATION.md` and
  `Docs/Development/REMEDIATION_ACCEPTANCE.md` remain until independent acceptance, then they and their
  index entries are removed per the specification; this dated record and the existing engineering
  evidence remain.

## Reviewer handoff

1. Read the [interaction acceptance specification](../Development/REMEDIATION_ACCEPTANCE.md), the
   [implementation specification](../Development/REMEDIATION_IMPLEMENTATION.md) and the
   [original audit](AUDIOMATOR_INDEPENDENT_AUDIT_2026-11-18.md) with its evidence companion.
2. Candidate: branch `remediation/audit-2026-11-18`; tested source `74466f0a`; final full gate at
   `247c8ed6` (later commits are documentation-only; confirm with `git log` and the `source.txt` in the
   validation directory). Base `51872140`.
3. Reproduce: `bash scripts/validate-release.sh` (policy, core, app-hosted, unsigned Release, artifact);
   cold builds and diagnostic extraction:
   `git archive HEAD | tar -x -C <disposable>`, then Debug `build-for-testing` and Release
   `build-for-testing` with `ENABLE_TESTABILITY=YES`, then
   `python3 .tmp/t2-tools/extract-diagnostics.py --label Debug --log <debug.log> --label Release --log <release.log>`.
   Evidence commands and intermediate JSONs are under `.tmp/t2-evidence/` and `.tmp/remediation/`.
4. Run the reviewer-owned probes and negative controls from the acceptance specification; the
   implementation record supplies dispositions and evidence, not the verdict.
5. After acceptance: remove the two campaign documents and their index entries; retain this record (or
   the reviewer's dated equivalent) with dispositions, tested revisions and evidence. Release approval
   remains with the maintainer.
