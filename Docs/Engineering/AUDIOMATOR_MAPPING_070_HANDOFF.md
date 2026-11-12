> Historical record. Superseded by [published 0.7.3 acceptance](TAGLIB_073_RELEASE_READINESS_2026-11-12.md). The 0.7.0 blocker findings below remain dated evidence; do not read them as current capability claims.

# Mapping 0.7.0 outstanding issues and interrupted-agent handoff

Date: 2026-11-09 (Asia/Shanghai). Application base: `906bbbab`; implementation remains in the uncommitted working tree on `codex/metadata-mapping-spec`. Dependency: exact TagLibAudioMetadata 0.7.0, revision `0f89fbe83c8fb029a9b6d640d57e397686986930`.

## Provenance and stopping state

This record was assembled by the supervising agent from the [implementation ledger](AUDIOMATOR_MAPPING_070_IMPLEMENTATION.md), current application tests/source, test artifacts, and the original dsh session's persisted events. It is not a completed dsh final report or independent merge acceptance.

The maintainer's wrap-up instruction was delivered through the live agent's `steer` API to session `964cd84c-de8c-4dfc-8ca7-e51a80040b0a`, message `b436f924-4adb-4f40-9fa9-fce2a6cbe597`. It authorized canceling current verification, required durable issue records, and prohibited another implementation/testing loop. The temporary loopback Inspector used with explicit approval was closed after delivery. The supervising agent did not terminate the process after delivery.

Persisted events show dsh processed this instruction and copied final test logs to `.tmp/evidence/`. Its final turn then ended with `kind=aborted`, reason `kind=user`, before a handoff document was written. That event does not identify who or what initiated the cancellation; do not infer a voluntary successful handoff. The original process was subsequently absent. Do not restart the agent or infer that outstanding requirements were completed from its exit.

## Completion accounting

The implementation ledger marks 11 of 14 acceptance groups complete; **A02, A08 and A09 remain partial**. Those labels are implementation-agent claims, not independent review approval. The six disclosures below must remain open until their individual closure criteria are met. They are not six necessarily confirmed upstream bugs: fixture construction and invalid-input behavior must be distinguished from defects.

A green safe-rejection test proves rejection/rollback, not that the rejected feature works. Review the changes from successful-write assertions to safe-rejection assertions before accepting the refactor. In particular, FLAC comment editing is still unavailable in the documented route.

## Open issue register

### MAP070-01 — FLAC typed comment writes reject

- Classification: reproduced package-behavior limitation in current app tests; comment feature incomplete. Do not close it merely because the safe-failure canary passes (A14 and comment workflows).
- API: `TagLibMetadataManager.applyMetadataPatch`, field `.comment`; app adapter in `AudioMator/Infrastructure/TagLib/TagLibAudioMetadataPipeline.swift`.
- Minimal reproduction: copy the committed FLAC fixture to a temporary URL; capture its bytes; apply `MetadataPatch(fields: [.comment: .text("Probe Comment")])`; compare bytes after the operation. Existing runnable entry: `TagLibUpgradeContractTests.testFLACSemanticCommentWriteFailsSafelyWithUnchangedBytes` in `AudioMatorTests/Integration/TagLib/TagLibUpgradeContractTests.swift`.
- Expected: comment persists and reloads without changing unrelated fields. Observed by that test: verification error containing `Patched native comment collection differs after save.`, original bytes retained.
- Current handling: surface the failure; no raw fallback. Field-transfer tests also contain explicit FLAC safe-rejection branches; these do not establish successful comment transfer.
- Next action / closure: package owner adds native comment set/replace/clear coverage and repairs verification/storage as appropriate; app adopts a released fix and restores positive app execution/transfer regressions. Independently verify preservation of unrelated comment representations.

### MAP070-02 — ID3v2.3 independent Date behavior incomplete

- Classification: reproducible standalone Date limitation; **A02 partial**. The broader TDRL/release-date claim is in the original ledger and still needs its own isolated reproduction; do not assume the standalone Date test proves every ID3v2.3 date failure.
- Entry: `TagLibDateMappingIntegrationTests.testID3v23DateWriteFailsSafelyWithoutChangingBytes`, with `AudioMatorTests/TestSupport/ID3v23FixtureBuilder.swift`.
- Reproduction: build a v2.3 copy of the MP3 fixture using that helper. Current assertions observe Year `2004-04-03`, standalone Date empty. Attempt `.standaloneDate` values `2008-03-04` and `0403`; both must reject without byte changes. The test separately verifies Year remains writable.
- Expected: version-appropriate independent DATE read/write and separate release/original dates, or accurate unsupported preflight before save. Ledger observation: TYER/TDAT flatten into TDRC and Date writes fail verification.
- Current handling: reject unsupported writes without coercion. This is not positive independent Date support.
- Next action / closure: isolate TYER/TDAT/TDRC and TDRL native behavior in package tests, distinguish supported precision from missing codec behavior, then release the repair or correct capability gating. Add positive app set/clear tests for every newly supported v2.3 field and unchanged-byte rejection for unsupported shapes.

### MAP070-03 — YEAR/DATE alias coexistence requires a workaround

- Classification: reported package alias/preservation defect with an app workaround; not closed by app round-trip success. Relevant to A02/A03/A12/A13.
- App code: `TagLibDateCompanion.augmenting` in `TagLibAudioMetadataPipeline.swift`, and `TagLibDateNativeProjection.swift` in the same directory. Read both before modifying date/conflict code.
- Investigation recipe: seed independent YEAR and DATE on FLAC/Ogg and ID3 temporary fixtures; try a YEAR-only edit and a standalone-Date-only set/remove directly through the package, then through the app adapter. Compare native snapshots and file bytes. The ledger reports `Unedited PropertyMap field DATE changed` rejection or Xiph YEAR writes dropping DATE. Reproduce each format/operation separately; the app's augmented patch can mask the underlying package failure.
- Current workaround: repeat the exact captured sibling value in the package patch; reject multiple/ambiguous sibling values. The standalone-Date path deliberately uses the legacy `.date` YEAR alias for the companion. Do not globally replace that occurrence without understanding the workaround.
- Risks requiring review: the physical write set can exceed user intent; sibling absence, full precision, repeated values, aliases, and concurrent sibling edits must remain protected. A stored value must never be derived from another date. Preserve version checks and native conflict comparisons.
- Existing app evidence: `TagLibDateMappingIntegrationTests`; `TagLibMappingContractIntegrationTests.testIndependentDateConflictDoesNotBlockYearEdit`.
- Next action / closure: add isolated direct-package regressions with the companion removed, fix native alias verification/preservation, adopt a released fix, then remove the workaround with positive field-independence and concurrency tests. Until then, keep it explicitly labeled and independently audit its scope.

### MAP070-04 — MusicBrainz recording ID removal needs a reproducer

- Classification: original dsh ledger disclosure, **not independently reproduced in this handoff**. No dedicated retained reproducer was identified during this check.
- API / route: ID3-backed `.musicBrainzTrackID` removal through `MetadataPatch`, reachable through the app payload/adapter.
- Reported observation: bridge rejects an invalid ID3 frame ID. Expected: remove the correct recording identifier without removing unrelated identifiers or damaging UFID/frame ownership.
- Minimal investigation to retain: copy an MP3 fixture; explicitly seed a recording ID; inspect native identity/owner; attempt only `.musicBrainzTrackID: .remove`; capture exact error, native before/after, and byte preservation on failure. Repeat removal when absent to distinguish invalid input from codec failure.
- Next action / closure: turn that recipe into a focused app/package contract test, determine the actual cause, and repair or accurately gate removal. Do not delete this disclosure or describe it as proven fixed merely because current workflows avoid forced removal.

### MAP070-05 — Formatted number text `7/0` is rejected

- Classification: reported behavior requiring a semantics decision, not automatically a package bug. Native absent-total sentinel zero and literal formatted-text total zero are different inputs.
- Reported API behavior: formatted number write rejects `7/0` with `ambiguousNumberRecovery(..., identities: [])`. App uses typed component intents instead.
- Reproduction recipe: on a temporary MP4/ID3 fixture, invoke the released formatted-number operation with exactly `7/0`, then separately request number 7 / absent total through typed component intent. Record exact arguments, initial native pair, error/result and bytes. Locate the adapter method and existing `NumberTextDependencyContractTests` before implementing a new test; this record does not claim those tests currently isolate `7/0`.
- Expected decision: either document literal zero-total text as invalid and present a precise validation error, or define and test normalization to absence. Do not invent private text storage or silently reinterpret malformed text.
- Next action / closure: retain an isolated regression and document the chosen contract. If it is invalid input, close as a documented validation case rather than claiming a codec fix. Verify typed number-only/total removal still preserves intended native values.

### MAP070-06 — Exact private MP4 provenance coverage missing

- Classification: fixture-construction/coverage gap; **A08 and A09 partial**. Failure of a writer to create a retired private field does not prove reading/preservation/cleanup is broken.
- Required identities in exact `com.apple.iTunes` namespace: `AUDIOMATOR_TRACKNUMBER_TEXT`, `AUDIOMATOR_DISCNUMBER_TEXT`, `TAGLIBAUDIOMETADATA_TRACKNUMBER_TEXT`, `TAGLIBAUDIOMETADATA_DISCNUMBER_TEXT`. Preserve foreign-namespace and similar-name fields.
- Ledger observation: attempted public custom-field seeding fails verification. No exact persistent fixture seed recipe is retained here; do not misrepresent the existing lookalike test as that evidence.
- Current test `TagLibMappingContractIntegrationTests.testTrackCleanupPreservesDiscGroupAndPrivateLookalikes` seeds an MP3 ordinary total plus `DISC-TOTAL-LOOKALIKE`; it is useful but does **not** seed all four MP4 private atoms.
- Next action: add redistributable preseeded MP4 fixtures or a bounded test-only native atom builder inside AudioMator. Do not modify package caches or sibling checkouts and do not add a production private-field writer. Independently verify the fixture's atom namespace/description/value before the app reads it.
- Closure: app execution tests cover both prefixes, private-only `03/12`, total-only `/12`, contradictory/malformed/duplicate values, foreign lookalikes, unrelated-save preservation, track/disc scope, explicit replacement/removal, preview/apply of the same captured plan, and stale-plan rejection. Test absent and removed values distinctly. Only then mark A08/A09 complete.

## Evidence locations and confidence

- Existing ledger above contains implementation details and prior verification claims; preserve it unchanged as evidence of what dsh reported.
- Supervising agent read `.xcresult` summaries for `Test-AudioMator-2026.11.09_23-22-01-+0800.xcresult` and `Test-AudioMator-2026.11.09_23-14-28-+0800.xcresult` under `.deriveddata-codex/Logs/Test`: both report 528 passed, zero failed/skipped/expected failures. A SwiftUI State-access runtime warning was present; green tests are not warning-free UI acceptance.
- `/tmp/audiomator-full-test-final6.log` ends with 528 passed and `TEST SUCCEEDED`; result bundle is `Test-AudioMator-2026.11.09_23-27-55-+0800.xcresult`.
- dsh copied final6/final7 logs to `.tmp/evidence/audiomator-full-test-final6.log` and `audiomator-full-test-final7.log` after the steer. These are ignored local artifacts, not durable Git history. Important issue facts are therefore retained in this document; artifact loss must not erase the register.
- Steering instruction, receipt and pre-steer ledger snapshot are in `.deriveddata-codex/dsh-handoff/` (ignored). The session identity/message identity are recorded above so the original persisted dsh session can be found without exposing its complete private transcript.
- Core test, focused suite, Debug/Release and artifact-validation counts in the original ledger remain dsh-reported unless separately verified. This handoff did not rerun them or review all implementation code.

## Resume checklist and independent acceptance

1. Keep all six IDs and the A02/A08/A09 partial state until closure evidence exists. Give any newly discovered issue a new ID; do not silently replace this record.
2. Independently review the full working-tree implementation against the implementation prompt. Check all-or-nothing preflight, raw/semantic identity separation, touched native conflict sets, cleanup plan/version ownership, multi-value preservation and provider/CSV behavior.
3. Review changed success assertions, negative-only coverage and the date companion's expanded write set. A green suite alone is not merge approval.
4. Preserve current source/untracked tests, fixture builders and records. Do not clean/reset or publish from this state. Do not fix the package inside AudioMator without explicit authorization for a separate package task.
5. For each repair, record exact version/revision, fixture, test name, command, result and remaining limits. Interactive UI acceptance, live services, signing/notarization and macOS 15 runtime remain unperformed.


## Independent acceptance update — 2026-11-10

See [the independent acceptance and repairs](AUDIOMATOR_MAPPING_070_ACCEPTANCE_2026-11-10.md). The private-field seeding gap was narrowed by successful public structured-API fixtures. The original positive FLAC comment release gate has been restored and fails on 0.7.0; earlier green negative tests do not constitute release approval.


## Mapping conformance update

[The latest mapping audit](MAPPING_CONFORMANCE_2026-11-10.md) supersedes earlier companion-workaround guidance and completion claims. Purchase Date/RATE routes and unknown-advisory handling were corrected; positive package probes confirm a YEAR write can erase independent DATE. Overall conformance remains blocked.
