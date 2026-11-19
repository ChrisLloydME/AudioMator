# State and Mutation Model

This document describes how AudioMator models application state and how it serializes, validates, and reports changes to files on disk.

## State Categories

| Category | Meaning | Persistence |
| --- | --- | --- |
| File identity | Session UUID associated with a normalized path. Rename rebinds the path while retaining the ID. | Session |
| Disk snapshot | Immutable `AudioFile` value loaded from file bytes and tags. | Recreated on import, scan, reload, or mutation |
| Selection | Current visible file IDs owned exclusively by `AudioViewModel`. | Session |
| Editing draft | `SingleFileEditModel` or `MultiFileEditModel`, plus the source snapshots it was created from. | Session; never implicit disk truth |
| Presentation | Progress, HUDs, open sheets/windows, issue summaries. | Session |
| Source configuration | Watched-folder and file-access bookmark records. | `UserDefaults` |
| Preferences | Sidebar/sort/columns/toolbar/inspector visibility, conflict policy, welcome state, MuseAmp toggle. | `UserDefaults` |
| Save issue log | Non-success batch summaries. | JSON in Application Support |

`SharedState` owns presentation preferences and sidebar choice. It does **not** own the selected audio IDs.

## File Identity

- A URL key is standardized, symlink-resolved, and Unicode-precomposed. Case folding is applied only on case-insensitive volumes (`FileSystemPathSemantics`).
- Imports and rescans reuse the existing UUID for the same path through `fileIDsByKey`.
- A rename operation carries the file ID, source, destination, and the preview fingerprint. On success the ID is retained and the URL mapping is updated.
- Metadata and provider write plans carry an expected fingerprint and metadata version. They are validated again inside the mutation reservation.

## Immutable Snapshots

`AudioFile` is a `Sendable` value with a unique `snapshotID`. Copies preserve the ID; a reload or transformation creates a new one. The middle list and artwork caches use the ID to decide whether a snapshot is still current.

Refresh publication has several guards:

1. Selected-file reloads compare the current URL and `snapshotID` before publishing.
2. Quick-import observations, immediate reloads, rename readbacks, and watched-folder observations use the same per-file generation acceptance check. Deferred batches retain their accepted generation and flush only while that generation is current. A rename publishes its new URL and a named pending-readback decision, with an authority-free display projection, before the move reservation is released; queued old-URL snapshots and old-URL import tokens are invalidated. Only the matching bounded full readback (same move, same destination entry identity) can restore an observation and clear that decision.
3. Watched-folder scans compare their scan token and captured folder mutation epoch after enumeration and loading. A changed epoch discards that scan and schedules a debounced retry. A scan reuses a previous file only when its fingerprint and package version still match. A failed metadata read retains the latest accepted snapshot, including a pending commit, and does not advance that file’s observation generation.
4. Unknown rename recovery locations discard queued reloads, advance the file publication generation, and invalidate in-flight folder scans before making the model refresh-required.

Recovery decisions are retained independently of snapshots as named reasons (`moveReadbackPending(moveID, destination, entryIdentity)`, `recoveryLocationUnresolved(expectedIdentity)`, and F2's `journalPending`). The shared mutation executor rechecks them after acquiring the reservation, so stale Inspector/Metadata Editor targets and queued writers cannot bypass a newer decision. Automatic observations preserve that state, discard their write revisions, and are published as authority-free projections. A receipt-matched readback clears only its own move decision; an explicit selected-file reload may clear a pending move decision for the same URL and a resolved-path failure only when its full read observed the same device/inode, after resolving any dirty inspector draft. A successor entry cannot be accepted silently. Neither an automatic read nor a successful move readback clears a pre-existing resolved-path or journal decision.

These guards order app-owned mutations and observations. A directory scan is not an atomic filesystem snapshot: an external edit after the last revision probe can remain unseen until a later reload or notification. Write-time revision checks still apply.

## Selection Ownership

`AudioViewModel.setSelectedAudioIDs`:

1. filters requested IDs to the visible collection,
2. stores the normalized set,
3. rebuilds the single-file or multi-file inspector draft in the same main-actor operation.

Rebuilding the visible collection prunes IDs that are no longer present and updates the draft. Views use a guarded binding; selection changes that could discard unsaved edits are confirmed by `ContentView` before calling the owner.

## Mutation Lifecycle

Legacy/conflict-aware lifecycle:

```text
prepare immutable input + expected fingerprint/version
  → reserve every affected normalized path
  → check cancellation
  → validate file identity and expected revision
  → resolve conflicts (semantic/raw writes only)
  → execute the disk mutation
  → reload the persisted snapshot while the reservation is held
  → release the reservation
  → publish the snapshot/result on the main actor
```

Reviewed (strict) lifecycle — see ADR 0006:

```text
reviewed target + frozen intent + adapter projection (plan time)
  → classify staleness/recovery/capability before any prompt
  → reserve the captured path
  → MainActor recheck of membership, URL identity and recovery state
  → register MetadataCommitPermit (pending) for the operation
  → detached worker verifies the captured fingerprint
  → admit() immediately before the synchronous package write
       revoked → precommit rejection, zero package calls
       admitted → commit + bounded reload report the real outcome
  → release the reservation, publish by stable file ID under the operation generation
```

A queued cancellation synchronously revokes the permit. Because the package
commit is synchronous after admission, cancellation cannot interrupt an admitted
commit; the real outcome, warnings included, is reported and never retried.

Conflict groups follow actual native storage: `track`/`trackTotal` share one group, `disc`/`discTotal` share another, and YEAR, DATE, RELEASEDATE and ORIGINALDATE are independent groups. A changed YEAR therefore does not create a blanket date conflict, while a shared native number pair remains protected. Alias/private-number cleanup is an explicit captured plan, not a conflict-resolution side effect.

Metadata batches commit file by file, so partial success is a valid outcome. Provider, filename and CSV/text plans run up to four independent targets concurrently. Cancellation prevents unstarted targets from invoking their writers; up to four already started commits may finish and all actual outcomes are retained. Results and cancelled entries are accounted for in captured plan order. Raw-map and renumber loops retain their sequential cancellation checks. Renumbering inherits caller cancellation; the per-file executor alone detaches the non-interruptible commit lifecycle. Results preserve each file's failure and warning. A file that was written but could not be reloaded is never reported as "not written".

## Reservation Rules

`FileMutationCoordinator` is an actor keyed by normalized path:

- A mutation reserves every source and destination path.
- Reservations are acquired atomically for multi-path operations, avoiding deadlock between overlapping rename and metadata operations.
- Waiters are granted in a way that avoids starvation: a later waiter is granted only if it conflicts with neither active work nor an older blocked waiter.
- Cancellation while waiting removes the waiter and throws `CancellationError`; the mutation must not run later.
- Cancellation after acquisition is checked before irreversible work starts.

Operations that use the coordinator include semantic metadata writes, raw metadata writes, erase-all, track renumbering, rename transactions, and selected file reloads.

## Cancellation and Recovery

| Situation | Result |
| --- | --- |
| Cancelled while waiting for reservation | Operation never executes; reported as cancelled |
| Cancelled after reservation, before write | Write is not attempted; reservation released |
| Write fails | Snapshot and draft remain unchanged; failure reported |
| Write succeeds, reload succeeds | New snapshot published; draft synchronized when appropriate |
| Write succeeds, reload times out or fails | Persisted-with-warning; no fabricated snapshot; user can reload |
| Reviewed write queued, then membership/protection/recovery/scope changes | Pending permit is revoked; zero package calls; a precommit rejection or cancellation is reported structurally |
| Cancelled while queued for a reviewed write | Permit revoked before admission; reported as cancelled, not as a failure |
| Cancelled after a reviewed write was admitted | Commit is not interrupted; its real outcome and warnings are reported |
| Rename succeeds, destination full readback fails, times out or observes a different entry | Moved file stays an authority-free projection with a pending-readback decision; stat/version probes never restore a revision; explicit Reload from Disk is required |
| Rename rollback incomplete | Recovery items list original, intended, and observed locations plus rollback errors; a uniquely verified location is rebound through the same receipt/readback path, others stay blocked |
| File path/object identity changes, or file is deleted | Identity/revision validation refuses writes; no "looks similar" substitution. Changed revisions require equal non-nil package audio identities before rebasing, including same-inode changes; unavailable identity requires explicit reload. See File Revision and Reload. |
| TagLib reports commit committed but durability uncertain | Treated as committed with a warning; retrying as a failure is explicitly discouraged |

## Operation-Specific Guarantees

| Operation | Transaction scope | Reload | Allowed partial success |
| --- | --- | --- | --- |
| Inspector single-file save | One file | Yes, bounded | N/A |
| Inspector multi-file save | Up to four files concurrently, per-file commits | Yes, per file | Yes |
| Metadata Editor apply | Per file | Yes | Yes |
| Raw PropertyMap write | Per file, exact delta | Yes | Yes |
| Erase All Metadata | Per file | Yes | Yes |
| Track renumber | Per file, serial | Yes, verification enabled | Yes |
| Rename | One multi-file transaction under a union reservation; per-destination bounded readback under separate reservations | Per completed move | No; rollback or recovery report |
| LRCLIB lyrics apply | Per file raw patch | Yes | Batch auto-match yes |
| Provider tagging plan | Up to four files concurrently, per-file commits | Yes | Yes |
| Selected-file reload | Per file | Read only | Yes |

## Persistence Boundaries

- Audio files: modified in place at their user-authorized locations.
- Watched folders and file-access grants: security-scoped bookmark data in `UserDefaults` (`watchedFolderRecords`, `fileAccessGrantRecords`).
- Conflict policy: `metadata.conflictPolicy`.
- Save issue log: `Application Support/AudioMator/SaveIssueLog.json`, capped at 200 entries.
- No audio content is copied into application storage.

## Inspector Effective Dirty State

The Inspector keeps captured per-file source baselines. Multi-file modified-field/action sets record intent but do not by themselves establish unsaved changes: the effective draft, excluding intent already completed for a target, must differ from that target's baseline. Batch Save uses the same comparison to avoid enqueuing no-op writes. Mixed-value blank input remains an explicit clear; reverting a common field value becomes clean.

Unchanged Track/Disc component setters preserve stored pair text. Dirty comparison uses the displayed components and numeric values, retaining visible zero-padding intent while ignoring invisible pair-separator normalization on undo. Removing already absent artwork or an empty/absent container value is clean; Boolean false and integer zero remain present. Genuine dirty drafts retain their original conflict baseline across reloads. See [repair evidence](../Engineering/HISTORY/INSPECTOR_DIRTY_STATE_2026-11-10.md).

## Related Documents

- [Metadata Pipeline](METADATA_PIPELINE.md)
- [File Revision and Reload](FILE_REVISION_AND_RELOAD.md)
- [Architecture Overview](OVERVIEW.md)

## Inspector field visibility

`InspectorMetadataField.configurableFields` is the curated quick-edit catalog; `defaultVisibleFields` explicitly lists the original common-field defaults. Neither list is generated from the package registry. Settings and the single/multiple-selection Inspector use this catalog through `SharedState.orderedVisibleInspectorMetadataFields`. Additional container fields are not rendered through a second, uncontrolled Inspector route. Existing visibility preferences remain authoritative, including previously enabled optional fields; unknown preference keys are ignored and an empty configuration falls back to common defaults. Visibility is presentation state, independent of edit intent: hiding fields preserves drafts and on-disk values, and Save applies all pending edits. Format capabilities disable unsupported edits without adding rows.
