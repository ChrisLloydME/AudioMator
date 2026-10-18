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
2. Quick-import observations, immediate reloads, rename readbacks, and watched-folder observations use the same per-file generation acceptance check. Deferred batches retain their accepted generation and flush only while that generation is current. A rename publishes its new URL as refresh-required before awaiting metadata, preventing queued old-URL snapshots from returning.
3. Watched-folder scans compare their scan token and captured folder mutation epoch after enumeration and loading. A changed epoch discards that scan and schedules a debounced retry. A scan reuses a previous file only when its fingerprint and package version still match. A failed metadata read retains the latest accepted snapshot, including a pending commit, and does not advance that file’s observation generation.
4. Unknown rename recovery locations discard queued reloads, advance the file publication generation, and invalidate in-flight folder scans before making the model refresh-required.

Refresh-required IDs are retained independently of snapshots. Automatic observations preserve that state and discard their write revisions. An explicit selected-file reload can clear it only after a successful read with both fingerprint and metadata version; the user must first resolve any dirty inspector draft. A successful rename readback may recover the temporary move state, but cannot clear a pre-existing recovery decision.

These guards order app-owned mutations and observations. A directory scan is not an atomic filesystem snapshot: an external edit after the last revision probe can remain unseen until a later reload or notification. Write-time revision checks still apply.

## Selection Ownership

`AudioViewModel.setSelectedAudioIDs`:

1. filters requested IDs to the visible collection,
2. stores the normalized set,
3. rebuilds the single-file or multi-file inspector draft in the same main-actor operation.

Rebuilding the visible collection prunes IDs that are no longer present and updates the draft. Views use a guarded binding; selection changes that could discard unsaved edits are confirmed by `ContentView` before calling the owner.

## Mutation Lifecycle

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

Metadata batches commit file by file, so partial success is a valid outcome. Provider, filename, CSV/text, raw-map, and renumber loops check cancellation before each next target, retain the current commit outcome, and account for the remaining targets as cancelled without invoking their writers. Renumbering inherits caller cancellation; the per-file executor alone detaches the non-interruptible commit lifecycle. Results preserve each file's failure and warning. A file that was written but could not be reloaded is never reported as "not written".

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
| Rename succeeds, full reload fails | Fingerprint and metadata revision are recovered independently; if either fails, snapshot is refresh-required and writes fail closed |
| Rename rollback incomplete | Recovery items list original, intended, and observed locations plus rollback errors |
| File moved, replaced, or deleted | Identity/revision validation fails; write is refused; no "looks similar" substitution |
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
| Rename | One multi-file two-phase transaction | Per completed move | No; rollback or recovery report |
| LRCLIB lyrics apply | Per file raw patch | Yes | Batch auto-match yes |
| Provider tagging plan | Per file | Yes | Yes |
| Selected-file reload | Per file | Read only | Yes |

## Persistence Boundaries

- Audio files: modified in place at their user-authorized locations.
- Watched folders and file-access grants: security-scoped bookmark data in `UserDefaults` (`watchedFolderRecords`, `fileAccessGrantRecords`).
- Conflict policy: `metadata.conflictPolicy`.
- Save issue log: `Application Support/AudioMator/SaveIssueLog.json`, capped at 200 entries.
- No audio content is copied into application storage.

## Related Documents

- [Metadata Pipeline](METADATA_PIPELINE.md)
- [File Revision and Reload](FILE_REVISION_AND_RELOAD.md)
- [Architecture Overview](OVERVIEW.md)
