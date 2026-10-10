# File revision conflicts and reload strategy

## Step 1 — What the conflict actually detects

Investigation baseline: TagLibAudioMetadata 0.5.3, revision
`03473c9ae199026b806a5f75c387ca036e325284`.

AudioMator has two distinct guards. `AudioFileFingerprint` compares resolved path,
size, modification time, device and inode. The TagLib optimistic version additionally
compares link count and nanosecond-resolution status change time (`ctime`). Neither
guard is a content hash. The reported “The file changed since it was read. No metadata
was committed by this operation; reload before editing.” comes from TagLib's
`fileChanged` error, including its expected-version check before a write.

There are reproducible conflicts with unchanged bytes:

- Changing permissions updates `ctime`. AudioMator's fingerprint remains equal,
  but the package version changes and rejects the write.
- Changing only modification time (`touch`, or restoring filesystem timestamps)
  invalidates AudioMator's fingerprint without changing audio/tag contents.
- Replacing a file with an identical copy changes inode and invalidates both guards.

This is conservative filesystem revision detection, not proof that tags changed.
It can report a conflict that a user reasonably regards as a false positive.
However, simply removing `ctime` is unsafe: a same-size content edit with restored
modification time can pass the app fingerprint while changing the package version.
`FileRevisionConflictTests` covers unchanged bytes after chmod/timestamp changes,
this counterexample, and a successful unchanged-snapshot write. These reproductions
establish possible causes, not the cause of an individual user's incident without
its file/volume and revision observations.

Published implementation references:

- [Opaque version and snapshot](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/03473c9ae199026b806a5f75c387ca036e325284/Sources/TagLibAudioMetadata/MetadataSnapshotPatch.swift)
- [File identity and atomic write](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/03473c9ae199026b806a5f75c387ca036e325284/Sources/TagLibAudioMetadata/TagLibMetadataManager.swift)

## Step 2 — Read/write strategy assessment

Retain expected-version validation and the package's final atomic-commit guard.
Never respond to a conflict by retrying with `expectedVersion: nil`, silently
accepting the current version, or trusting an unchanged basic tag projection.
Those approaches can overwrite concurrent edits or lose opaque native metadata.

Candidate improvements, in order of increasing scope:

1. Read only the Basic snapshot needed for list/inspector loading, and ensure the
   app fingerprint and metadata belong to one stable read. The current loader reads
   a full raw/structured snapshot, then awaits AVFoundation and captures a later
   fingerprint. A file changed during that interval can produce a mixed revision.
2. Always compute inspector deltas against the draft's original snapshot. A watched
   rescan can update the list while preserving a dirty draft; comparing that draft
   against the newer list incorrectly treats external edits as requested changes.
3. For status-only changes, use a package-owned content revision/verified rebase API.
   A full-file digest captured with the original snapshot can prove byte equality
   before accepting a new filesystem version. Stream the digest, validate the file
   before/after hashing, and retain final commit validation. Hashing only metadata
   or sampled audio bytes does not establish equality; hashing every large file on
   import costs I/O. The opaque package version cannot safely be relaxed in the app.
4. For real concurrent edits, offer a three-way merge: original snapshot, user delta,
   current disk snapshot. Auto-merge only disjoint fields, report overlapping edits,
   and submit the resulting patch with the freshly read expected version. Track/disc
   number-total pairs, artwork, multivalue properties, and erase-all need explicit
   conflict rules. Full basic-tag equality is insufficient for raw editor changes.

Dependency-owner follow-up: consider an opt-in verified content revision/rebase API
in `MetadataSnapshotPatch.swift` and the atomic mutation area of
`TagLibMetadataManager.swift`; preserve their strict transaction-time checks.
Add unchanged-byte chmod/xattr/touch cases, changed bytes with restored mtime,
same-path replacement, and a writer racing the rebase/commit. AudioMator does not
patch dependency sources or disable their guard as a workaround.

Implemented at step 2: Basic snapshot loading; before/after validation across
the complete asynchronous load; one bounded retry for a read-time `fileChanged`;
original-snapshot inspector deltas for single and multi-file drafts; and no mutation
when the inspector has no changes. Step 2 did not rebase writes; step 4 below adds explicit conflict policies.
Workflow and format integration tests cover these changes. The existing provider
cancellation test now releases its gated post-commit reload before joining the task,
matching the executor's documented cancellation boundary rather than deadlocking.

## Step 3 — Existing reload behavior and improvements

At the investigation baseline:

- Quick Import reads at import time, including bounded transient-read retry.
  There is no ongoing file monitor, foreground reconciliation, or manual reload.
- Watched Folders observe each directory with DispatchSource, up to 128 directories
  per root, debounce events for 350 ms, enumerate recursively, and reread all audio
  files. Failed scans retain the list; failed reads retain the prior metadata.
  Directory-entry events do not guarantee notification of an in-place child write.
- Successful writes reload the same file while its mutation reservation is held,
  with a separate 60-second reload deadline. Reload failure is a committed save
  warning, not a write failure. Generation checks protect mutation handoff order.
- Clean inspector drafts follow refreshed files; dirty drafts retain their original
  snapshot so a refresh cannot silently discard edits or change the save baseline.

A useful bounded improvement is selected-file reload, available for both sources,
plus selected-file reconciliation on app activation. Explicit reload can ask before
discarding a dirty draft; background reconciliation must preserve it. Reads must
share the write coordinator and generation checks, keep failed file models, and
avoid applying results after a file was removed or moved.

Implemented in this branch:

- **Reload from Disk** in the native list context menu for selected files, with a
  confirmation before discarding an inspector draft. Raw Metadata Editor drafts
  remain independent; reopen that editor to start from a refreshed revision.
- On app activation, compare both the app fingerprint and package version for
  selected files. Skip unchanged files and reread changed/missing revisions. Including
  the package version detects `ctime`-only changes the app fingerprint would miss.
- Serialize these reads with writes, apply results while still reserved, and reject
  results whose original list snapshot was removed, moved or independently replaced.
  A 60-second read deadline discards late results. Duplicate refreshes are suppressed.
  Explicit reload displays progress and holds off new save actions until it finishes.
- Clean drafts follow readback; dirty drafts (including edits typed during the read)
  retain their original baseline. Read failures preserve the old model; explicit
  reload reports them. Automatic reconciliation runs on activation rather than a
  timer, and checks only the selected files.

`FileReloadWorkflowTests` exercises clean/dirty refreshes, unchanged-revision skips,
permission-only detection, failure retention, shared reservations, removed files,
independently refreshed snapshots, and edits made while loading.

Further options: incremental watched rescans using stable revision checks,
recursive FSEvents with dropped-event recovery, and a modest periodic reconciliation
for active files on volumes with unreliable notifications. These require separate
performance/volume testing. Watching alone does not replace validation at save time.

## Step 4 — Settings and draft conflict policies

**Settings → Conflicts** persists the policy under `metadata.conflictPolicy`.
Missing or unknown values select **Merge non-conflicting changes**. The choice is
read at the start of each file save, so an open draft can be retried after choosing
a different strategy without losing its original baseline.

| Policy | Different fields changed | Same edited group changed on disk |
| --- | --- | --- |
| Merge non-conflicting changes (default) | Merge silently | Preserve draft and stop; accept exact single-field convergence |
| Prefer my changes | Merge silently | Apply the user's intended edits; may overwrite conflicting external values |
| Prefer disk changes | Merge silently | Keep disk group; list discarded draft fields in the save report |
| Require manual reload | Stop if revision changed | Preserve draft and require reload |

These policies apply to **Inspector and Metadata Editor drafts**. Preview-based
imports, online plans, renumbering, lyrics application and destructive clear-all
retain their strict revision guards. No strategy bypasses the dependency's final
expected-version validation or retries a failed commit.

Each loaded file now retains a full raw/structured semantic baseline from the same
verified snapshot as its editable fields. This supersedes step 2's Basic-only read:
value arrays, roles, aliases and secondary artwork are needed to detect conflicts
that the Basic projection hides. It increases read work and baseline memory compared
to Basic-only loading. Large-library import optimization can later capture coherent
baselines only for active editors; it must not mix revisions to save this cost.

Inside the existing per-file mutation reservation, the resolver verifies identity,
reads a stable current snapshot, compares edited groups and commits against that
snapshot's version. Same-inode permission/timestamp changes can therefore rebase
without assuming unchanged audio bytes: the patch is applied to the latest valid
file and changes only intended metadata. This is semantic merging, not proof of
byte equality or an app-side weakening of the package's version guard.

Raw editor saves submit an exact original-to-draft delta, preserving unrelated
external additions, arrays and deletions. Opening Metadata Editor also reads a
coherent fresh baseline before showing its editable values. Track/total and
disc/total pairs, year/release date, shared musician credits and the entire artwork
set are grouped conservatively. A disc-only text patch carries the latest unedited
track pair because the package's number-text API always includes track text.
Unknown raw keys with changed native structures and ASF native changes use
conservative conflict detection because the registry does not map every native
alias or role. Some non-overlapping changes may still require a policy choice.
Already-converged or wholly disk-preferred changes perform no redundant write.

All policies refuse same-path replacement (including an external editor's atomic
replacement), unavailable identity, unstable reads and a change racing the final
commit. A semantic metadata snapshot cannot prove that a replacement is the same
audio recording. Automatic reload preserves drafts and their original baselines;
explicit reload requires a deliberate discard. A raw editor draft remains open on
failure. Continuous monitoring of every open file is not added by this setting:
selected-file activation checks and existing watched-folder events still apply.

`MetadataConflictStrategyTests` uses real TagLib writes in test-owned temporary
files, simulating external in-place changes while retaining inode identity. It
covers policy persistence/fallback, status-only changes, disjoint/overlapping edits,
convergence, multi-values, additions, deletion, paired numbers, multi-artwork role projections,
coherent editor opening, replacement refusal and a writer racing the final guard.
The artwork-role sensor injects two structured artwork projections while retaining
real filesystem versions, rather than relying on multi-artwork write support.
Folder permission UI is excluded from the test adapter; production transactional
folder access remains unchanged.

### Dependency-owner follow-up from artwork fixture setup

An attempted FLAC fixture setup through the public `applyMetadataPatch` API failed
with `verificationFailed(["Patched artwork differs after save."])` when replacing
artwork with two `StructuredArtwork` entries using identical JPEG payloads,
`pictureTypeCode: 3`/`4`, and a description of `"Before"` on the second entry
(`pictureType` and `container` left at their API defaults). This occurs before the
AudioMator conflict resolver runs. It indicates either an undocumented required
role representation or a package round-trip/verification issue; the cause is not
established. No dependency sources or checkouts were modified.

The TagLibAudioMetadata owner should add this FLAC reproduction to package tests,
compare expected/observed count, order, role code, description and bytes, and inspect
the structured artwork writer and `structuredArtworkMatches` verification path.
Expected: accepted artwork input should round-trip under documented normalization,
or fail validation before mutation with a clear unsupported-role diagnosis.
AudioMator's standard single-cover integration tests still pass. This task does not
claim multi-cover dependency write coverage or introduce a workaround for it.

## Verification

- Step 1: four filesystem-revision reproduction tests passed.
- Step 2: 69 focused app-hosted workflow, pipeline contract, revision and TagLib
  fixture integration tests passed.
- Step 3: 91 tests passed, adding reload workflows, native selection and mutation
  serialization coverage. Reload tests use isolated preferences to avoid restoring
  unrelated watched-folder scans from the test host.
- Step 4: 105 focused app-hosted tests passed. After the final no-write sensor and
  failed-target retention check, all 28 conflict-policy/editor-store tests passed
  (17 policy tests). All 61 selected SwiftPM core tests also passed. The native
  arm64/x86_64 build passed; no interactive UI acceptance was performed.
- Native app compilation uses `scripts/codex-build.sh` and repository-local
  `.deriveddata-codex`. App-hosted tests use one serial runner. Interactive UI
  acceptance remains the maintainer's responsibility.
