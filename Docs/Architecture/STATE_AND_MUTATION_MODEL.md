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
| Online artwork lookup | `ArtworkLookupSession`: one search attempt (`searching`/`results`/`failed`/`cancelled`), one candidate download attempt owned by session and attempt IDs, a candidate-scoped retryable download fault, the selected candidate ID, and the captured destination transfer intent (or preview-only). | Session; results, candidate faults and the transfer intent are discarded when the sheet closes |
| Source configuration | Watched-folder and file-access bookmark records. | `UserDefaults` |
| Preferences | Sidebar/sort/columns/toolbar/inspector visibility, conflict policy, welcome state, MuseAmp toggle. | `UserDefaults` |
| Save issue log | Non-success batch summaries. | JSON in Application Support |
| Rename recovery journal | Durable `prepared`/`committed` rename records, path-keyed mutation blocks and read-only recovery presentation. | Versioned JSON manifests + stable lock file in Application Support |

`SharedState` owns presentation preferences and sidebar choice. It does **not** own the selected audio IDs.

## File Identity

- A URL key is standardized, symlink-resolved, and Unicode-precomposed. Case folding is applied only on case-insensitive volumes (`FileSystemPathSemantics`).
- Imports and rescans reuse the existing UUID for the same path through `fileIDsByKey`.
- A rename operation carries the file ID, source, destination, and the preview fingerprint. On success the ID is retained and the URL mapping is updated.
- Metadata and provider write plans carry a captured reviewed target: the logical
  ID, operational URL, fingerprint and nonoptional package metadata version. They
  are validated again inside the mutation reservation. There is no optional
  expected-version forwarding path: every production metadata write is either
  reviewed or draft-aware, and a source without both tokens cannot authorize a
  write.

## Immutable Snapshots

`AudioFile` is a `Sendable` value with a unique `snapshotID`. Copies preserve the ID; a reload or transformation creates a new one. The middle list and artwork caches use the ID to decide whether a snapshot is still current.

Refresh publication has several guards:

1. Selected-file reloads compare the current URL and `snapshotID` before publishing.
2. Quick-import observations, immediate reloads, rename readbacks, and watched-folder observations use the same per-file generation acceptance check. Deferred batches retain their accepted generation and flush only while that generation is current. A rename publishes its new URL and a named pending-readback decision, with an authority-free display projection, before the move reservation is released; queued old-URL snapshots and old-URL import tokens are invalidated. Only the matching bounded full readback (same move, same destination entry identity) can restore an observation and clear that decision.
3. Watched-folder scans compare their scan token and captured folder mutation epoch after enumeration and loading. A changed epoch discards that scan and schedules a debounced retry. A scan reuses a previous file only when its fingerprint and package version still match. A failed metadata read retains the latest accepted snapshot, including a pending commit, and does not advance that file’s observation generation.
4. Unknown rename recovery locations discard queued reloads, advance the file publication generation, and invalidate in-flight folder scans before making the model refresh-required.

Recovery decisions are retained independently of snapshots as named reasons (`moveReadbackPending(moveID, destination, entryIdentity)`, `recoveryLocationUnresolved(expectedIdentity)`, and `journalPending(operationID)`). The shared writer guard rechecks the decisions and the journal's path-keyed blocks after acquiring the reservation, so stale Inspector/Metadata Editor targets and queued writers cannot bypass a newer decision, even when no session file ID is loaded. Automatic observations preserve that state, discard their write revisions, and are published as authority-free projections. A receipt-matched readback clears only its own move decision; an explicit selected-file reload may clear a pending move decision for the same URL and a resolved-path failure only when its full read observed the same device/inode, after resolving any dirty inspector draft. A successor entry cannot be accepted silently. Neither an automatic read nor a successful move readback clears a pre-existing resolved-path or journal decision. A `.journalPending` decision is attached when an observation is accepted at a recorded path and is cleared only by a verified restore or explicit acknowledgement of that operation.

These guards order app-owned mutations and observations. A directory scan is not an atomic filesystem snapshot: an external edit after the last revision probe can remain unseen until a later reload or notification. Write-time revision checks still apply.

### Watched-folder directory monitoring

Each watched folder owns one `DirectoryMonitorController` with a capped set of `O_EVTONLY` descriptors (128 per folder; the root is always first). A directory is active only while the identity captured from its opened descriptor (`fstat` device/inode/kind) matches the current authorized path. Reconciliation compares retained and planned identities even when the path key is unchanged, closes stale descriptors, reopens them, and verifies the newly opened inode against its path before installing it. `.rename`, `.delete` and `.revoke` make an instance terminal and close its descriptor exactly once; a terminal event schedules a debounced rescan and never degrades a replacement. A newly installed or rebound descriptor requests exactly one follow-up scan for the scan-before-attach interval; a scan whose attachments are unchanged requests none. Late callbacks are dropped by instance token, and status publication is guarded by the folder lifetime, the scan token and a monotonic reconciliation generation, so an older result cannot overwrite a newer published status. Descriptor and path I/O run off the main actor while the folder scope is held.

Status separates cap omissions, open failures (missing, inaccessible or revoked folders), identity mismatches (the path now refers to a different directory), scan failures and metadata read failures; only identity-verified descriptors count as actively monitored. In-place edits to an already indexed file are not directory-entry events: that refresh remains best effort and explicit Refresh/Reload or activation covers it.

### Quick Import indexing and scope leases

Quick Import keeps the published `quickImportFiles` array plus a parallel ordered `QuickImportPathIndex`, both in Foundation-only `Core/FileSystem`. The index is the bookkeeping source of truth: row order (`orderedIDs`), stable row IDs per canonical file key, per-URL replacement tokens, admission sequences, and file/parent reference counts. Replacing a row keeps its original position and stable ID; removing one compacts the order. The published array is updated by applying one index delta per accepted batch, never by re-scanning the whole collection.

An `importQuickFiles(from:)` request:

1. dedupes exact standardized URLs and sorts lexically with no path-key work, registers one request/token sequence, and starts the job's URL-level scope leases so the worker may observe the selected entries;
2. prepares Sendable candidate identities off the main actor, one canonical/volume resolution for the file and one for its lexical parent plus entry device/inode evidence, reusing the parent evidence of a sibling. Candidates carry their operational URL, canonical path, file/parent keys and versioned request token; no path key is computed per batch later;
3. admits candidates on the main actor: a newer request sequence supersedes an older one for the same file key, an alias in the same request keeps the later candidate, and the stable ID is looked up (or assigned) in the session-wide `fileIDsByKey` map;
4. loads with the shared keyed loader, which flushes only a contiguous resolved prefix at the production cadence or the injected forced batch size, and publishes the batch once: stale token/sequence batches and empty batches never publish and never rebuild the visible collection;
5. verifies the observation's canonical location and, when captured, device/inode identity against the candidate before accepting it. A symlink retarget or a parent entry replacement between preparation and load is declined and reported as "select again" instead of retried, so a different file never receives the selected row;
6. terminates exactly once: releases the job's leases (stale batch publication cannot restore a removed row), prunes tokens for keys that never published, and reports only failures whose original request token is still current. There is no end-of-job merge of already-published results and no per-callback token re-key pass.

Scope access is refcounted per file and parent key by `QuickImportScopeLeases`. The first owner starts one security scope; later owners only join. Releasing the last owner stops it exactly once. A start that reports no scope required is tracked as `notRequired` and is never retried by passive batch sync; a scope that was granted before and fails later becomes `revoked` and is retried only at an explicit authorization event (a new user import or relaunch). A forced start/stop pair is therefore balanced, and a removal or clear cannot stop a scope another job, watched folder or rename read still holds. Clearing Quick Import releases every lease at once.

Rename and recovery migration is atomic under the existing rename reservation: `publishMovePlaceholders` migrates the ID map, replacement tokens, index identity, file/parent leases and the membership URL in one main-actor step before the single visible rebuild, and the destination identity is computed once and checked against the move receipt's device/inode evidence. A journal restore migrates a membership back to its original URL only when the restored entry's device/inode matches the captured membership; ambiguous evidence skips migration and keeps the recovery decision. `fileIDsByKey` remains session-wide so re-selecting a path reuses its identity even after removal or clear.

## Selection Ownership

`AudioViewModel.setSelectedAudioIDs`:

1. filters requested IDs to the visible collection,
2. stores the normalized set,
3. rebuilds the single-file or multi-file inspector draft in the same main-actor operation.

Rebuilding the visible collection prunes IDs that are no longer present and updates the draft. Views use a guarded binding; selection changes that could discard unsaved edits are confirmed by `ContentView` before calling the owner.

### Inspector draft sessions

The Inspector draft has a store-owned session identity independent of the current selection and of any single disk observation: a session ID, the captured target IDs and source baselines, a monotonic edit generation, and an independent artwork command generation. `AudioViewModel` rebuilds the published `edit`/`multiEdit` payload only through named operations: explicit selection transition, session-scoped clean refresh, and own-save completion. A dirty draft keeps its payload and original expected version across passive refresh and watch/scan publication; a clean draft follows the newest accepted observation.

A save captures a receipt (session identity, target baselines, submitted per-target intent) before any suspension. Completion is accepted only for that session/generation, advances the baseline of successful targets from their accepted readback, inherits readback normalization for fields whose live value still equals the submitted value, and reapplies newer typed edits (including an intentional revert to the pre-save value) as still-dirty intent. A commit whose reload failed records no new baseline. Partial batches maintain a completed-target ledger so a retry submits only failed targets or newer changes.

#### Artwork command handoffs

An asynchronous artwork command — online lookup/download and the Finder, photo-library and clipboard single and batch imports — captures one `ArtworkTransferIntent` before its first suspension: the F3 draft session ID, the independent artwork command generation, the ordered captured target IDs, a transfer/attempt identity and the source context. Staging is a guarded commit rather than a setter: it accepts the intent only while the same draft session and artwork command generation are live, the current selection and draft shape still represent the full ordered captured target set, every captured target is still in source membership, writable for artwork, and not blocked by a recovery decision. Otherwise it returns a localized stale-selection or superseded rejection and mutates nothing. It never creates or steals a draft for the captured IDs, never substitutes the current selection, and never stages a surviving subset of a batch. Unrelated text edits advance only the edit generation and preserve the handoff; Clear/Keep and every newer artwork command advance the artwork generation and supersede older handoffs. A deferred picker or transfer completion whose captured intent is already obsolete is silent, and an explicit selection change or pending-review transition cancels the in-flight local preparation. Staged artwork remains draft state until Inspector Save.

When a dirty draft's captured targets become unavailable (passive prune or an intentional removal), the payload, captured values and ledger are retained as a detached pending-review session. Selection is still pruned to the visible collection; Save is suspended until every captured target is available again and the user resumes, or until the user discards the review. Cross-source or new-target transfer of captured values never happens implicitly. Explicit transitions remain the only discard routes and their confirmation is revalidated against the session/generation that displayed it.

### Metadata Editor raw draft

The Metadata Editor draft is `[AudioFile.ID: RawMetadataValueMap]`; every value is an ordered array, never a joined string. A text-utility preview captures per-file/key before/after arrays together with the presentation identity, target set and draft generation. Apply accepts that captured preview only while all of them still match, stages exactly the captured after-arrays, and never inserts or removes a key. Done captures the per-file/key before/after arrays for pending targets and starts the reviewed raw apply from the captured baseline; an unchanged draft produces no request and no write. A completion is accepted only for the presentation/apply that started it. Field entry commits an ordered value list; the last element cannot be removed there, and key removal is the separate Delete Field command.

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

LRCLIB session ownership is explicit: `LRCLIBLyricsBrowserStore` owns one session ID plus a monotonic generation and at most one operation token. Every publication (`searchState`, candidates, applied marks, progress) is gated by the token's generation, and every write handoff carries the reviewed target captured at seed. Close, Back and reseed invalidate the generation first, then cancel the operation; the commit permit remains the only ordering point between a cancelled and an admitted write. Back retains the queued rows/bindings but clears candidates, so a new review is required.

The removed mixed write helper (`persistMetadataEdit`) is no longer a production
route. Inspector and Raw Metadata Editor saves use the draft-aware route with
their captured baseline/conflict policy; every other metadata workflow uses the
strict reviewed route with a captured nonoptional revision.

Metadata batches commit file by file, so partial success is a valid outcome. Provider, filename and CSV/text plans run up to four independent targets concurrently. Cancellation prevents unstarted targets from invoking their writers; up to four already started commits may finish and all actual outcomes are retained. Results and cancelled entries are accounted for in captured plan order. Raw-map and renumber loops retain their sequential cancellation checks. Renumbering inherits caller cancellation; the per-file executor alone detaches the non-interruptible commit lifecycle. Results preserve each file's failure and warning. A file that was written but could not be reloaded is never reported as "not written".

## Reservation Rules

`FileMutationCoordinator` is an actor keyed by normalized path:

- A mutation reserves every source and destination path. Each lexical path contributes both its symlink-resolved comparison key and its directory-entry location key (parent resolved, basename folded with the parent volume's case semantics), so a symlink object and its target cannot be mutated as independent entries.
- Rename reservations also include the deterministic staging URLs, so another rename or writer cannot claim a temporary name for the same operation.
- Reservations are acquired atomically for multi-path operations, avoiding deadlock between overlapping rename and metadata operations.
- Waiters are granted in a way that avoids starvation: a later waiter is granted only if it conflicts with neither active work nor an older blocked waiter.
- Cancellation while waiting removes the waiter and throws `CancellationError`; the mutation must not run later.
- Cancellation after acquisition is checked before irreversible work starts.

Operations that use the coordinator include semantic metadata writes, raw metadata writes, erase-all, track renumbering, rename transactions, explicit rename-journal restores/acknowledgements, and selected file reloads.

### Rename journal and restart recovery

`AudioViewModel` owns authorization, folder scopes, the union reservation, path-keyed blocks and presentation. `RenameTransactionService` (`Infrastructure/FileSystem`) owns durability and exclusive filesystem effects: one versioned manifest per operation UUID under `Application Support/AudioMator/RenameJournal/`, a stable non-blocking journal lock, `prepared`/`committed` transitions, atomic/flushed writes, and `renameatx_np(RENAME_EXCL)` moves on held directory descriptors.

Startup restores authorized folders, loads manifest records read-only, installs path-keyed blocks even when no file IDs are loaded, and classifies in the background. Classification never moves or removes files. A startup warning points at **Settings > Folders > Rename Recovery**, which exposes read-only per-entry roles plus explicit **Restore Original Names** (prepared records; revalidated under the journal lock and union reservation, never overwriting an occupied name, idempotent across repeated interruption) and **Remove Record** (committed or no-move prepared records only, after fresh verification; files are not moved). Missing or revoked folder access is reported as unavailable and a restore requests the exact recorded folder before taking the lock. Volumes without exclusive-rename support are rejected before staging; other programs remain external writers and the external source/destination race limits are documented in [Rename and Renumbering](RENAME_AND_RENUMBERING.md).

## Cancellation and Recovery

| Situation | Result |
| --- | --- |
| Cancelled while waiting for reservation | Operation never executes; reported as cancelled |
| LRCLIB session ended (close, Back, reseed) | Store invalidates the generation and cancels the operation; pending permits are revoked, unstarted files are recorded cancelled once, and an admitted commit completes and reports its real outcome |
| Cancelled after reservation, before write | Write is not attempted; reservation released |
| Write fails | Snapshot and draft remain unchanged; failure reported |
| Write succeeds, reload succeeds | New snapshot published; draft synchronized when appropriate |
| Write succeeds, reload times out or fails | Persisted-with-warning; no fabricated snapshot; user can reload |
| Reviewed write queued, then membership/protection/recovery/scope changes | Pending permit is revoked; zero package calls; a precommit rejection or cancellation is reported structurally |
| Cancelled while queued for a reviewed write | Permit revoked before admission; reported as cancelled, not as a failure |
| Cancelled after a reviewed write was admitted | Commit is not interrupted; its real outcome and warnings are reported |
| Rename succeeds, destination full readback fails, times out or observes a different entry | Moved file stays an authority-free projection with a pending-readback decision; stat/version probes never restore a revision; explicit Reload from Disk is required |
| Rename interrupted before commit | A durable `prepared` journal record survives process termination; startup installs path-keyed blocks and shows the observed roles without moving files. Explicit Restore Original Names (identity-checked, no overwrite, idempotent) is required |
| Rename committed record left by termination | Startup verifies the recorded locations, keeps the new names, and offers explicit record removal only; never an automatic restore or move |
| Rename recovery record unreadable/unsupported | Retained for inspection with a sanitized warning; no file is moved and no path block is derived from unparseable data |
| Rename rollback incomplete | The prepared journal record is retained and reports original, intended, and observed locations; a unique verified location can be restored through the explicit recovery flow, others stay blocked |
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
| Rename | One multi-file durable transaction under a union reservation plus a process-wide journal lock; exclusive `RENAME_EXCL` moves on held directory descriptors; per-destination bounded readback under separate reservations | Per completed move | No; verified rollback, or a retained `prepared`/`committed` journal record for explicit restart recovery |
| LRCLIB lyrics apply | Per file raw patch through the strict reviewed target (captured at seed) | Yes, captured package version | Batch auto-match yes; cancelled unstarted rows recorded once |
| Provider tagging plan | Up to four files concurrently, per-file commits | Yes | Yes |
| Selected-file reload | Per file | Read only | Yes |

## Persistence Boundaries

- Audio files: modified in place at their user-authorized locations.
- Watched folders and file-access grants: security-scoped bookmark data in `UserDefaults` (`watchedFolderRecords`, `fileAccessGrantRecords`).
- Conflict policy: `metadata.conflictPolicy`.
- Save issue log: `Application Support/AudioMator/SaveIssueLog.json`, capped at 200 entries.
- Rename recovery journal: `Application Support/AudioMator/RenameJournal/` — versioned manifests and a stable lock file; recorded paths and local entry identity evidence only, retained until verified restore, explicit acknowledgement, or verified completion. No audio content is copied into application storage.

## Inspector Effective Dirty State

The Inspector keeps captured per-file source baselines. Multi-file modified-field/action sets record intent but do not by themselves establish unsaved changes: the effective draft, excluding intent already completed for a target, must differ from that target's baseline. Batch Save uses the same comparison to avoid enqueuing no-op writes. Mixed-value blank input remains an explicit clear; reverting a common field value becomes clean.

Unchanged Track/Disc component setters preserve stored pair text. Dirty comparison uses the displayed components and numeric values, retaining visible zero-padding intent while ignoring invisible pair-separator normalization on undo. Removing already absent artwork or an empty/absent container value is clean; Boolean false and integer zero remain present. Genuine dirty drafts retain their original conflict baseline across reloads. See [repair evidence](../Engineering/HISTORY/INSPECTOR_DIRTY_STATE_2026-11-10.md).

## Related Documents

- [Metadata Pipeline](METADATA_PIPELINE.md)
- [File Revision and Reload](FILE_REVISION_AND_RELOAD.md)
- [Architecture Overview](OVERVIEW.md)

## Inspector field visibility

`InspectorMetadataField.configurableFields` is the curated quick-edit catalog; `defaultVisibleFields` explicitly lists the original common-field defaults. Neither list is generated from the package registry. Settings and the single/multiple-selection Inspector use this catalog through `SharedState.orderedVisibleInspectorMetadataFields`. Additional container fields are not rendered through a second, uncontrolled Inspector route. Existing visibility preferences remain authoritative, including previously enabled optional fields; unknown preference keys are ignored and an empty configuration falls back to common defaults. Visibility is presentation state, independent of edit intent: hiding fields preserves drafts and on-disk values, and Save applies all pending edits. Format capabilities disable unsupported edits without adding rows.
